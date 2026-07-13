#!/usr/bin/env python3
"""
merge_rucc.py  (two-file version)
=================================
Merge USDA ERS Rural-Urban Continuum Codes onto the Arkansas DiD panel,
replacing the ad hoc 20k-population rural/urban cutoff.

ERS ships each vintage separately, so this takes BOTH:
  --rucc-2013 ruralurbancodes2013.xls            (cols: FIPS, RUCC_2013, ...)
  --rucc-2023 Ruralurbancontinuumcodes2023.xlsx  (cols: FIPS, RUCC_2023, ...)
Source: https://www.ers.usda.gov/data-products/rural-urban-continuum-codes
(.xls needs `pip install xlrd>=2.0.1`; .xlsx needs openpyxl.)

VINTAGE: RUCC 2013 = PRIMARY (in force across the 2010-2020 treatment window);
RUCC 2023 carried as a robustness column.

Columns added (time-invariant; merged on fips):
  rucc_2013, rucc_2023           full 1-9 codes
  metro_2013, metro_2023         1 if code in {1,2,3}
  rural_2013                     PRIMARY rural flag = nonmetro = 1-metro_2013
  rucc_adjacent_2013             1 if code in {4,6,8} (nonmetro, metro-adjacent)
  rural_nonadj_2013              1 if code in {5,7,9} (nonmetro, NOT adjacent) --
                                 the isolated-catchment cells where the attractor
                                 mechanism should be strongest

Usage:
  python3 merge_rucc.py --rucc-2013 ruralurbancodes2013.xls \
                        --rucc-2023 Ruralurbancontinuumcodes2023.xlsx \
                        --panel arkansas_panel_annual_border_vmt_nonalc.csv \
                        --out   arkansas_panel_annual_border_vmt_nonalc_rucc.csv
"""
import argparse, sys
import pandas as pd

METRO={1,2,3}; ADJ={4,6,8}; NONADJ={5,7,9}

def load_vintage(path, codecol):
    df = pd.read_excel(path, sheet_name=0, dtype=str)
    if "FIPS" not in df.columns or codecol not in df.columns:
        sys.exit(f"[FATAL] {path}: expected FIPS and {codecol}; saw {list(df.columns)}")
    out = pd.DataFrame()
    out["fips"] = df["FIPS"].str.extract(r"(\d+)")[0].str.zfill(5)
    out[codecol] = pd.to_numeric(df[codecol], errors="coerce").astype("Int64")
    return out.dropna(subset=["fips"]).drop_duplicates("fips")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rucc-2013", dest="rucc_2013", required=True)
    ap.add_argument("--rucc-2023", dest="rucc_2023", required=True)
    ap.add_argument("--panel", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    r13 = load_vintage(a.rucc_2013, "RUCC_2013")
    r23 = load_vintage(a.rucc_2023, "RUCC_2023")
    rucc = r13.merge(r23, on="fips", how="outer")
    rucc = rucc.rename(columns={"RUCC_2013":"rucc_2013", "RUCC_2023":"rucc_2023"})

    c = rucc["rucc_2013"]
    rucc["metro_2013"]        = c.isin(METRO).astype("Int64")
    rucc["rural_2013"]        = (~c.isin(METRO)).astype("Int64")
    rucc["rucc_adjacent_2013"]= c.isin(ADJ).astype("Int64")
    rucc["rural_nonadj_2013"] = c.isin(NONADJ).astype("Int64")
    rucc["metro_2023"]        = rucc["rucc_2023"].isin(METRO).astype("Int64")

    panel = pd.read_csv(a.panel, dtype={"fips": str})
    panel["fips"] = panel["fips"].str.zfill(5)
    before = len(panel)
    merged = panel.merge(rucc, on="fips", how="left", validate="many_to_one")
    assert len(merged) == before

    newcols = ["rucc_2013","rucc_2023","metro_2013","metro_2023",
               "rural_2013","rucc_adjacent_2013","rural_nonadj_2013"]
    front = [x for x in merged.columns if x not in newcols]
    anchor = "neighbor_unit" if "neighbor_unit" in front else front[-1]
    ins = front.index(anchor) + 1
    merged = merged[front[:ins] + newcols + front[ins:]]

    cc = merged.drop_duplicates("fips")
    miss = cc.loc[cc["rucc_2013"].isna(), "fips"].tolist()
    print(f"[merge] {cc['fips'].nunique()} counties; unmatched rucc_2013: {len(miss)} {miss[:10]}")
    if "treated_unit" in cc:
        t = cc[cc["treated_unit"]==1]
        print(f"[split] treated -> RUCC2013 rural={int(t['rural_2013'].sum())} "
              f"urban={int((t['metro_2013']==1).sum())}")
    merged.to_csv(a.out, index=False)
    print(f"[done] {a.out}  ({merged.shape[0]} x {merged.shape[1]})")

if __name__ == "__main__":
    main()
