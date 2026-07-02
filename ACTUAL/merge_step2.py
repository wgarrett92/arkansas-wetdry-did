#!/usr/bin/env python3
# =====================================================================
# merge_step2.py  --  RERUN_RUNBOOK Step 2
# ---------------------------------------------------------------------
# Re-merge the refreshed (post Madison/Sebastian recode) border-distance
# augment, and the VMT panel, onto the 50-col annual analysis panel.
#
#   arkansas_panel_annual_merged.csv   (spine: 75 x 16 = 1200 rows, fips x year)
#     + distance_neighbor_augment_v2.csv   (POST recode; 1200 rows, fips x year)
#     + vmt_county_year.csv                (825 rows, 2013-2023, partial coverage)
#   -> arkansas_panel_annual_border_vmt.csv
#
# WHAT THIS DOES *NOT* DO (by design):
#   - It does NOT recode treatment (cohort / first_treated_year / treated_unit
#     stay PLACE 2, the Stata patch_madison_sebastian.do, applied at estimation).
#
# R15 PORT (2026-07-01, ANALYSIS_LOG #25) -- one deliberate exception to the
# "purely additive" rule above: countywide_wet and the plain neighbor columns
# (n_wet_neighbors / share_wet_neighbors / any_wet_neighbor) are now REWRITTEN
# to the authoritative Section-2 wet-SOURCE timeline (wet_source_timeline.py)
# and the corrected in-state counts carried by the augment. Leaving the old
# defective values at rest is how R15 happened (Boone/Clark wet-all-window
# despite g2010). Disable with --no-r15-correct only to reproduce the archived
# pre-v2 panels. REQUIRES the augment to be a PLACE-1-PATCH-v2 output (the
# script verifies the 2010/2012 increment signature and refuses otherwise).
#   - It does NOT touch the OOS ring, centroids, or VMT contents (VMT is
#     unchanged; we re-merge it only so the combined panel is current).
#
# DESIGN NOTES
#   - fips is forced to 5-char zero-padded STRING in every file before the
#     join (the #1 merge bug: '05001' silently read as int 5001 won't match).
#   - year forced to int.
#   - Joins are LEFT, panel = spine, validated 1:1, with merge indicators so
#     unmatched keys surface instead of vanishing.
#   - Column collisions are detected and reported, never silently clobbered.
#   - VMT is optional: if the file is absent the script warns and writes the
#     panel+augment merge, so the pipeline isn't blocked.
#
# Usage (defaults assume you run from the project dir):
#   python merge_step2.py
#   python merge_step2.py --panel arkansas_panel_annual_merged.csv \
#       --augment distance_neighbor_augment_v2.csv \
#       --vmt vmt_county_year.csv \
#       --out arkansas_panel_annual_border_vmt.csv
# =====================================================================

import argparse, os, sys
import pandas as pd

KEYS = ["fips", "year"]
# FIPS-like reference columns: keep as zero-padded 5-char strings so they
# stay consistent with the fips convention and are safe for any later join.
FIPSLIKE = {"nearest_wet_fips_aug"}


def _read(path, label, required=True):
    if not os.path.exists(path):
        if required:
            sys.exit(f"[FATAL] {label}: file not found: {path}")
        print(f"[WARN] {label}: file not found ({path}) -- skipping.")
        return None
    # read fips as string to preserve the leading zero; everything else inferred
    df = pd.read_csv(path, dtype={"fips": str})
    miss = [k for k in KEYS if k not in df.columns]
    if miss:
        sys.exit(f"[FATAL] {label}: missing key column(s) {miss}. Has: {list(df.columns)[:12]}...")
    df["fips"] = df["fips"].astype(str).str.strip().str.replace(r"\.0$", "", regex=True).str.zfill(5)
    df["year"] = df["year"].astype(int)
    for col in FIPSLIKE & set(df.columns):
        s = df[col].astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
        s = s.where(~s.isin(["", "nan", "None"]), "")
        df[col] = s.apply(lambda x: x.zfill(5) if x else "")
    dup = df.duplicated(KEYS).sum()
    if dup:
        sys.exit(f"[FATAL] {label}: {dup} duplicate fips x year keys -- not a clean 1:1 spine.")
    print(f"  [{label}] {len(df):>5} rows | {df['fips'].nunique()} fips | "
          f"years {df['year'].min()}-{df['year'].max()} | {len(df.columns)} cols")
    return df


def _collisions(spine, incoming, label):
    overlap = (set(spine.columns) & set(incoming.columns)) - set(KEYS)
    if overlap:
        print(f"  [WARN] {label}: {len(overlap)} column name(s) collide with the panel and "
              f"will be suffixed '__{label}' so nothing is clobbered: {sorted(overlap)}")
    return overlap


def _merge(spine, incoming, label):
    suffix = f"__{label}"
    out = spine.merge(incoming, on=KEYS, how="left", validate="1:1",
                      indicator=f"_m_{label}", suffixes=("", suffix))
    vc = out[f"_m_{label}"].value_counts()
    both = int(vc.get("both", 0)); left = int(vc.get("left_only", 0))
    print(f"  [{label} merge] matched {both}/{len(out)}  (unmatched panel rows: {left})")
    # any incoming keys that did NOT land on the panel? (would mean a spine gap)
    landed = set(map(tuple, out.loc[out[f"_m_{label}"] == "both", KEYS].values.tolist()))
    orphan = set(map(tuple, incoming[KEYS].values.tolist())) - landed
    if orphan:
        ex = sorted(orphan)[:8]
        print(f"  [WARN] {label}: {len(orphan)} key(s) in the {label} file are NOT in the panel "
              f"spine (dropped by the left join). e.g. {ex}")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--panel",   default="arkansas_panel_annual_merged.csv",
                    help="50-col annual analysis panel (spine).")
    ap.add_argument("--augment", default="distance_neighbor_augment_v2.csv",
                    help="POST-recode distance/neighbor augment (fips x year).")
    ap.add_argument("--vmt",     default="vmt_county_year.csv",
                    help="VMT panel (fips x year, 2013-2023). Optional.")
    ap.add_argument("--out",     default="arkansas_panel_annual_border_vmt.csv")
    ap.add_argument("--no-vmt",  action="store_true", help="Skip the VMT merge entirely.")
    ap.add_argument("--no-r15-correct", action="store_true",
                    help="Skip the R15-port correct-at-rest rewrite of "
                         "countywide_wet + plain neighbor columns (only for "
                         "reproducing the archived pre-v2 panels).")
    args = ap.parse_args()

    print("=" * 60); print("STEP 2 RE-MERGE"); print("=" * 60)
    print("Loading inputs:")
    panel = _read(args.panel,   "panel",   required=True)
    aug   = _read(args.augment, "augment", required=True)
    vmt   = None if args.no_vmt else _read(args.vmt, "vmt", required=False)

    n0 = len(panel)

    # ---- merge 1: distance/neighbor augment (expect full 1:1 coverage) ----
    print("\nMerging distance augment onto panel:")
    _collisions(panel, aug, "augment")
    merged = _merge(panel, aug, "augment")
    aug_unmatched = int((merged["_m_augment"] != "both").sum())
    if aug_unmatched:
        print(f"  [WARN] {aug_unmatched} panel rows got NO distance columns -- investigate fips/year "
              f"formatting before trusting downstream distance results.")
    else:
        print("  [OK] every panel row received distance columns (full coverage).")

    # ---- merge 2: VMT (partial coverage by construction: 2013-2023) ----
    if vmt is not None:
        print("\nMerging VMT onto panel:")
        _collisions(merged.drop(columns=[c for c in merged.columns if c.startswith("_m_")]),
                    vmt, "vmt")
        merged = _merge(merged, vmt, "vmt")
        merged["vmt_present"] = (merged["_m_vmt"] == "both").astype(int)
        print("\n  VMT coverage by year (rows with VMT / total):")
        cov = merged.groupby("year")["vmt_present"].agg(["sum", "count"])
        for yr, r in cov.iterrows():
            bar = "#" * int(r["sum"] / max(cov["count"]) * 20)
            print(f"    {yr}  {int(r['sum']):>3}/{int(r['count']):>3}  {bar}")
    else:
        print("\n[INFO] VMT not merged; 'vmt_present' flag not added.")

    # ---- drop indicator helper columns ----
    merged = merged.drop(columns=[c for c in merged.columns if c.startswith("_m_")])

    # ---- R15 PORT: correct-at-rest wet timeline + plain neighbor columns ----
    if not args.no_r15_correct:
        print("\nR15-port correction (ANALYSIS_LOG #25): rewriting countywide_wet")
        print("+ n_wet_neighbors / share_wet_neighbors / any_wet_neighbor at rest.")
        from wet_source_timeline import build_timelines, hard_asserts
        need = {"cohort", "countywide_wet", "n_wet_neighbors_instate_chk",
                "n_neighbors"}
        miss = need - set(merged.columns)
        if miss:
            sys.exit(f"[FATAL] R15 correction needs columns {sorted(miss)}; "
                     "pass --no-r15-correct only to reproduce archived panels.")
        # guard: the augment must be a PLACE-1-PATCH-v2 output. The pre-port
        # _chk series has NO 2010 increments (that is the R15 signature).
        chk = merged.sort_values(KEYS).set_index(KEYS)["n_wet_neighbors_instate_chk"]
        inc = chk.groupby(level=0).diff()
        inc_years = sorted({y for (_, y), d in inc.items() if d and d > 0})
        if (inc < 0).any():
            sys.exit("[FATAL] n_wet_neighbors_instate_chk DECREASES within a "
                     "county -- augment is broken; refusing to write.")
        if 2010 not in inc_years or 2012 not in inc_years:
            sys.exit(f"[FATAL] augment _chk increments at {inc_years}: missing "
                     "the 2010 (Boone/Clark) and/or 2012 (Madison) events -- "
                     "this looks like a PRE-R15-port augment; rebuild it with "
                     "build_border_augment_v2_patched.py first.")
        cohort_csv = {}
        cw = {}
        for f, y, c, w in zip(merged["fips"], merged["year"],
                              merged["cohort"], merged["countywide_wet"]):
            try:
                cohort_csv[f] = int(float(c)) if str(c) not in ("", "nan") else 0
            except ValueError:
                cohort_csv[f] = 0
            cw[(f, int(y))] = int(w)
        years = sorted(merged["year"].unique().tolist())
        wet_nbr, _, tl = build_timelines(cohort_csv, cw, years)
        hard_asserts(wet_nbr, years, neighbors_variant=True)
        merged["countywide_wet"] = [wet_nbr(f, int(y)) for f, y
                                    in zip(merged["fips"], merged["year"])]
        n_in = merged["n_wet_neighbors_instate_chk"].astype(int)
        merged["n_wet_neighbors"] = n_in
        merged["share_wet_neighbors"] = n_in / merged["n_neighbors"].astype(int)
        merged["any_wet_neighbor"] = (n_in > 0).astype(int)
        print(f"  [OK] timeline: {tl.get('n_sources_2008', '?')} wet sources in "
              f"2008; plain neighbor columns now equal the corrected _chk "
              f"series (increment years: {inc_years}).")
    else:
        print("\n[WARN] --no-r15-correct: countywide_wet + plain neighbor "
              "columns keep the DEFECTIVE archived coding (R15).")

    # ---- spot checks: confirm the recode carried through the merge ----
    print("\nSpot checks (post-merge distance values should reflect the recode):")
    def _peek(fips, yr, cols=("dist_border_aug", "nearest_wet_fips_aug", "n_wet_neighbors_aug")):
        row = merged[(merged["fips"] == fips) & (merged["year"] == yr)]
        if row.empty:
            print(f"    {fips} {yr}: NOT IN PANEL"); return
        vals = {c: (row.iloc[0][c].item() if hasattr(row.iloc[0][c], "item") else row.iloc[0][c])
                for c in cols if c in merged.columns}
        print(f"    {fips} {yr}: {vals}")
    _peek("05087", 2011)   # Madison pre-treatment: nearest should be in-state Washington
    _peek("05087", 2012)   # Madison now a source itself
    _peek("05131", 2010)   # Sebastian: wet source all window
    _peek("05033", 2015)   # Crawford: should point at Fort Smith (05131)

    # ---- NaN audit on the new distance columns (should be ~0) ----
    distcols = [c for c in ["dist_popcen_instate", "dist_popcen_aug",
                            "dist_border_instate", "dist_border_aug"] if c in merged.columns]
    print("\nNaN audit on distance columns (expect 0 unless a county truly has no wet source):")
    for c in distcols:
        print(f"    {c}: {merged[c].isna().sum()} NaN")

    # ---- write ----
    merged.to_csv(args.out, index=False)
    print("\n" + "=" * 60)
    print(f"WROTE {args.out}")
    print(f"  rows: {len(merged)} (panel spine was {n0}; should be unchanged)")
    print(f"  cols: {len(merged.columns)}")
    print("=" * 60)
    if len(merged) != n0:
        print("[WARN] row count changed vs the panel spine -- a merge inflated rows. "
              "Check for duplicate keys in the augment/VMT files.")


if __name__ == "__main__":
    main()
