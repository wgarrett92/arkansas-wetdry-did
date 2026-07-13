#!/usr/bin/env python3
"""
build_driver_origin.py  (v2)
============================
Direct test of the ATTRACTOR hypothesis from FARS, keyed on DR_ZIP (driver's
home ZIP), not REG_STAT. For each fatal crash IN ARKANSAS, classify every
present driver by where they live, then collapse to crash-county x year
(and, optionally, crash-county x year x month), and MERGE the county-year
origin shares back onto the analysis panel.

WHY DR_ZIP (not REG_STAT): DR_ZIP is the *driver's residence* at ZIP resolution
-> maps to a home COUNTY. REG_STAT is the *vehicle's* registration at state
resolution only. The attractor claim is about where the DRIVER came from.

------------------------------------------------------------------------------
WHAT'S NEW IN v2
------------------------------------------------------------------------------
1. CROSSWALK: now accepts EITHER a ZIP->COUNTY file OR a ZIP->TRACT file
   (e.g. HUD ZIP-TRACT_032017.xlsx). County is derived as the first 5 digits
   of the 11-digit tract GEOID, and residential ratios are SUMMED to ZIP x
   county BEFORE choosing the dominant county. (Picking the single max-ratio
   tract is wrong: a ZIP can fragment across many small tracts in one county
   that together outweigh one large tract in another. In AR-2017 this fixes 4
   ZIPs.) .xlsx/.xls and .csv are both read.

2. MERGE: after building the county-year origin file, this left-merges the
   origin columns onto the annual panel you pass via --merge-onto (defaults to
   --panel) and writes a NEW file (--out-merged), leaving the panel untouched.
   Panel rows with no involved drivers that county-year get NaN origin shares
   (correct: the share is undefined when no drivers were present).

3. MONTHLY (optional, --monthly): also emits a crash-county x year x MONTH
   origin file by pulling MONTH from the ACCIDENT file. NOTE: home_dry is still
   annual (countywide_wet is an annual flag); within a transition year the home
   county's dry status does not vary by month here. No monthly merge is done
   (there is no monthly panel yet); the file is produced so it's ready when the
   monthly panel exists.

------------------------------------------------------------------------------
INPUTS YOU SUPPLY
------------------------------------------------------------------------------
  1. FARS yearly files in one dir: vehicle_YY.csv AND accident_YY.csv (2008-2023).
  2. A ZIP->COUNTY or ZIP->TRACT crosswalk (HUD ZIP_COUNTY or ZIP_TRACT, or the
     Census ZCTA-county file). HUD ZIP files start 2010Q1; for a single static
     map a stable mid-panel quarter is fine since the attractor signal is a
     POST-treatment SHIFT in sh_home_dry, not its absolute level.
  3. The analysis panel (fips,year,countywide_wet) -- used to tag whether each
     driver's HOME county was DRY that year, and (by default) as the merge target.

  --selftest runs the VEHICLE-side extraction only (DR_ZIP populatedness),
  runnable immediately on vehicle_*.csv with no accident/crosswalk needed.

------------------------------------------------------------------------------
EXAMPLE
------------------------------------------------------------------------------
  python3 build_driver_origin.py \
      --fars-dir   "/path/to/FARS" \
      --zip-xwalk  "ZIP-TRACT_032017.xlsx" \
      --panel      "arkansas_panel_annual_border_vmt_nonalc_rucc.csv" \
      --merge-onto "arkansas_panel_annual_border_vmt_nonalc_rucc.csv" \
      --out-merged "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv" \
      --monthly
"""
import argparse, glob, os, re, sys
import pandas as pd

AR_STATE = 5
BAD_ZIP  = {"00000", "99999", "88888", "77777"}

def yr_from_name(p):
    b = os.path.splitext(os.path.basename(p))[0].strip()   # drop ext (any case), trim spaces
    m = re.search(r"(19|20)\d{2}", b)                       # full 4-digit year if present
    if m:
        return int(m.group(0))
    m = re.search(r"(\d{2})(?!.*\d)", b)                    # else last 2-digit run
    if not m:
        return None
    y = int(m.group(1))
    return y if y > 2000 else 2000 + y

def clean_zip(z):
    if z is None: return None
    s = re.sub(r"\D", "", str(z))
    if len(s) == 9: s = s[:5]            # ZIP+4 -> 5
    if len(s) != 5 or s in BAD_ZIP: return None
    return s

def full_fips(state, county):
    try:
        st, co = int(float(state)), int(float(county))
    except (TypeError, ValueError):
        return None
    if co in (0, 997, 998, 999): return None     # FARS unknown/not-applicable
    return f"{st:02d}{co:03d}"

def geo_to_county(g):
    """First 5 digits of a county FIPS (5-digit) or a tract GEOID (11-digit)."""
    s = re.sub(r"\D", "", str(g))
    if not s: return None
    return s.zfill(11)[:5] if len(s) >= 10 else s.zfill(5)[:5]

def load_zip_xwalk(path, zip_col, county_col, ratio_col):
    """ZIP -> dominant county. Accepts ZIP-COUNTY or ZIP-TRACT (county = GEOID[:5]).
    Ratios are summed to ZIP x county before the dominant county is chosen."""
    if path.lower().endswith((".xlsx", ".xls")):
        x = pd.read_excel(path, dtype=str)
    else:
        x = pd.read_csv(path, dtype=str)
    cols = {c.lower(): c for c in x.columns}
    zc = zip_col or cols.get("zip")
    gc = county_col or cols.get("county") or cols.get("geoid") or cols.get("tract")
    rc = ratio_col or cols.get("res_ratio") or cols.get("tot_ratio")
    if not (zc and gc):
        sys.exit(f"[FATAL] crosswalk needs a ZIP column and a COUNTY/TRACT(GEOID) "
                 f"column; saw {list(x.columns)}")
    x = x.rename(columns={zc: "ZIP", gc: "GEO"})
    x["ZIP"]   = x["ZIP"].map(clean_zip)
    x["CFIPS"] = x["GEO"].map(geo_to_county)
    x = x.dropna(subset=["ZIP", "CFIPS"])
    x["R"] = (pd.to_numeric(x[rc], errors="coerce").fillna(0)
              if (rc and rc in x.columns) else 1.0)
    agg  = x.groupby(["ZIP", "CFIPS"], as_index=False)["R"].sum()
    best = agg.sort_values("R").drop_duplicates("ZIP", keep="last")   # dominant county
    kind = "ZIP-TRACT" if (x["GEO"].str.replace(r"\D", "", regex=True)
                            .str.len().max() or 0) >= 10 else "ZIP-COUNTY"
    print(f"[xwalk] parsed as {kind}: {len(best)} ZIPs -> county "
          f"({best['CFIPS'].str.startswith('05').sum()} AR-dominant)")
    return dict(zip(best["ZIP"], best["CFIPS"]))

VEH_COLS = ["ST_CASE", "VEH_NO", "DR_PRES", "DR_ZIP", "DR_DRINK", "REG_STAT"]
ACC_COLS = ["ST_CASE", "STATE", "COUNTY", "YEAR", "MONTH"]

def read_csv_safe(path, cols):
    try:                                   # FARS files are often Windows-1252/Latin-1
        df = pd.read_csv(path, dtype=str, low_memory=False)
    except UnicodeDecodeError:
        df = pd.read_csv(path, dtype=str, low_memory=False, encoding="latin-1")
    keep = [c for c in cols if c in df.columns]
    return df[keep].copy()

def selftest(vfiles):
    print("=== SELFTEST: DR_ZIP populatedness on vehicle files ===")
    for vf in vfiles:
        y = yr_from_name(vf)
        v = read_csv_safe(vf, VEH_COLS)
        ar = v[(pd.to_numeric(v["ST_CASE"], errors="coerce") // 10000) == AR_STATE]
        pres = ar[ar.get("DR_PRES", "0") == "1"]
        good = pres["DR_ZIP"].map(clean_zip).notna().sum() if "DR_ZIP" in pres else 0
        print(f"  {os.path.basename(vf)} (y={y}): AR veh={len(ar)} present={len(pres)} "
              f"usable DR_ZIP={good} ({good/max(len(pres),1):.1%})")

def share(g, col):  # mean over rows where the flag is defined
    s = g[col].dropna()
    return s.mean() if len(s) else float("nan")

def collapse(long, keys):
    recs = []
    for kv, g in long.groupby(keys):
        gd = g[g["dr_drink"] == 1]
        rec = dict(zip(keys, kv if isinstance(kv, tuple) else (kv,)))
        rec.update(dict(
            n_drivers=len(g), n_drink=len(gd),
            sh_nonresident=1 - share(g, "resident"),
            sh_out_of_state=share(g, "out_of_state"),
            sh_home_dry=share(g, "home_dry"),
            sh_nonresident_drink=(1 - share(gd, "resident")) if len(gd) else float("nan"),
            sh_home_dry_drink=share(gd, "home_dry") if len(gd) else float("nan"),
        ))
        recs.append(rec)
    return pd.DataFrame(recs).sort_values(keys)

def merge_onto_panel(cy, panel_path, out_path):
    P = pd.read_csv(panel_path, dtype={"fips": str})
    P["fips"] = P["fips"].str.zfill(5)
    P["year"] = pd.to_numeric(P["year"], errors="coerce").astype("Int64")
    o = cy.rename(columns={"crash_fips": "fips"}).copy()
    o["fips"] = o["fips"].astype(str).str.zfill(5)
    o["year"] = pd.to_numeric(o["year"], errors="coerce").astype("Int64")
    origin_cols = [c for c in o.columns if c not in ("fips", "year")]
    o = o.rename(columns={c: f"orig_{c}" for c in origin_cols})  # namespace to avoid clashes
    if P.duplicated(["fips", "year"]).any():
        print("[merge][warn] panel has duplicate fips-year keys; not validating 1:1")
    merged = P.merge(o, on=["fips", "year"], how="left")
    matched = merged[[c for c in merged.columns if c.startswith("orig_")][0]].notna().sum()
    merged.to_csv(out_path, index=False)
    print(f"[merge] {out_path}: {len(merged)} panel rows, "
          f"{matched} got origin data ({matched/len(merged):.1%}); "
          f"added cols: {', '.join('orig_'+c for c in origin_cols)}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fars-dir", help="dir with vehicle_*.csv and accident_*.csv")
    ap.add_argument("--zip-xwalk", help="ZIP->county OR ZIP->tract crosswalk (csv/xlsx)")
    ap.add_argument("--panel", help="panel csv with fips,year,countywide_wet (for home_dry)")
    ap.add_argument("--zip-col"); ap.add_argument("--county-col"); ap.add_argument("--ratio-col")
    ap.add_argument("--out-long", default="driver_origin_long.csv")
    ap.add_argument("--out-cy", default="driver_origin_county_year.csv")
    ap.add_argument("--monthly", action="store_true",
                    help="also emit crash-county x year x MONTH origin file")
    ap.add_argument("--out-cym", default="driver_origin_county_year_month.csv")
    ap.add_argument("--merge-onto", default=None,
                    help="annual panel to left-merge county-year origin onto "
                         "(default: same file as --panel)")
    ap.add_argument("--out-merged", default=None,
                    help="output path for the merged panel "
                         "(default: <merge-onto stem>_origin.csv)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    src = a.fars_dir or "."
    def _csv(stem):                       # case-insensitive on name AND extension
        if not os.path.isdir(src):
            return []
        return sorted(os.path.join(src, f) for f in os.listdir(src)
                      if re.match(stem, f, re.I) and f.lower().endswith(".csv"))
    vfiles = _csv("vehicle")
    if a.selftest or not (a.zip_xwalk and a.panel):
        if not vfiles: sys.exit("[FATAL] no vehicle_*.csv found")
        selftest(vfiles)
        if a.selftest: return
        sys.exit("[STOP] provide --zip-xwalk and --panel to build origin shares.")

    z2c = load_zip_xwalk(a.zip_xwalk, a.zip_col, a.county_col, a.ratio_col)

    wet = pd.read_csv(a.panel, dtype={"fips": str})[["fips", "year", "countywide_wet"]]
    wet["fips"] = wet["fips"].str.zfill(5)
    wet_lookup = {(r.fips, int(r.year)): int(r.countywide_wet) for r in wet.itertuples()}

    afiles = {yr_from_name(p): p for p in _csv("accident")}
    rows = []
    for vf in vfiles:
        y = yr_from_name(vf)
        if y not in afiles:
            print(f"[skip] {os.path.basename(vf)}: no matching accident file for {y} "
                  f"(accident years found: {sorted(k for k in afiles if k)})")
            continue
        acc = read_csv_safe(afiles[y], ACC_COLS)
        acc = acc[pd.to_numeric(acc["STATE"], errors="coerce") == AR_STATE]
        acc["crash_fips"] = [full_fips(s, c) for s, c in zip(acc["STATE"], acc["COUNTY"])]
        acc = acc.dropna(subset=["crash_fips"])
        c_by_case = dict(zip(acc["ST_CASE"], acc["crash_fips"]))
        m_by_case = (dict(zip(acc["ST_CASE"], pd.to_numeric(acc["MONTH"], errors="coerce")))
                     if "MONTH" in acc.columns else {})

        veh = read_csv_safe(vf, VEH_COLS)
        veh = veh[veh["ST_CASE"].isin(c_by_case)]
        veh = veh[veh.get("DR_PRES", "1") == "1"]
        for r in veh.itertuples():
            crash = c_by_case.get(r.ST_CASE)
            home  = z2c.get(clean_zip(getattr(r, "DR_ZIP", None)))
            drink = 1 if getattr(r, "DR_DRINK", "0") == "1" else 0
            in_state = (home[:2] == "05") if home else None
            home_dry = (wet_lookup.get((home, y)) == 0
                        if (home and home.startswith("05")) else None)
            mo = m_by_case.get(r.ST_CASE)
            rows.append(dict(year=y, month=(int(mo) if pd.notna(mo) else None),
                             crash_fips=crash, home_fips=home, dr_drink=drink,
                             resident=(home == crash) if home else None,
                             in_state=in_state,
                             out_of_state=(in_state is False) if home else None,
                             home_dry=home_dry))
    long = pd.DataFrame(rows)
    long.to_csv(a.out_long, index=False)
    print(f"[long] {len(long)} present-driver rows -> {a.out_long}")

    cy = collapse(long, ["crash_fips", "year"])
    cy.to_csv(a.out_cy, index=False)
    print(f"[county-year] {len(cy)} rows -> {a.out_cy}")

    if a.monthly:
        cym = collapse(long.dropna(subset=["month"]), ["crash_fips", "year", "month"])
        cym["month"] = cym["month"].astype(int)
        cym.to_csv(a.out_cym, index=False)
        print(f"[county-year-month] {len(cym)} rows -> {a.out_cym}")

    merge_onto = a.merge_onto or a.panel
    if merge_onto:
        out_merged = a.out_merged or (os.path.splitext(merge_onto)[0] + "_origin.csv")
        merge_onto_panel(cy, merge_onto, out_merged)

    print("\nAttractor read: in newly-wet RURAL counties, watch orig_sh_home_dry / "
          "orig_sh_home_dry_drink RISE post-treatment -- inbound drivers from still-dry "
          "neighbors. The merged panel is keyed fips x year, ready for csdid.")

if __name__ == "__main__":
    main()
