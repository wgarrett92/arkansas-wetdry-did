"""
build_panel.py
==============
Merges FARS fatal crash data (2008–2020) with the Arkansas county-level
wet/dry panel to produce an analysis-ready county × year dataset for
spatial difference-in-differences estimation.

Outputs
-------
  arkansas_did_panel.csv   — main analysis file (county × year)
  transition_summary.csv   — treated cohorts with timing info
  merge_log.txt            — data quality notes

Key variables in output
-----------------------
  fips                     — 5-digit county FIPS
  county                   — county name
  year
  --- Outcomes (from FARS) ---
  fatal_crashes            — total fatal crashes in county-year
  alcohol_fatal_crashes    — crashes where DRUNK_DR > 0
  total_fatalities         — sum of FATALS
  alcohol_share            — alcohol_fatal_crashes / fatal_crashes
  --- Treatment (from wet/dry panel) ---
  countywide_wet           — 1 if county fully wet that year (end-of-year)
  first_treated_year       — year of first countywide wet vote (NA if never)
  cohort                   — same as first_treated_year; "never" = 0 (for C&S-A)
  years_since_treatment    — year - first_treated_year (negative = pre)
  --- Spillover variables ---
  any_wet_neighbor         — 1 if any contiguous county is wet
  n_wet_neighbors          — count of wet contiguous neighbors
  share_wet_neighbors      — fraction of neighbors that are wet
  --- Sample flags ---
  treated_unit             — 1 if county ever goes wet 2010–2020
  neighbor_unit            — 1 if county is contiguous to a treated unit
  clean_control            — 1 if never-treated and never a neighbor
"""

import os
import io
import csv
import zipfile
import pandas as pd
from pathlib import Path

UPLOADS = Path("/mnt/user-data/uploads")
OUTDIR  = Path("/mnt/user-data/outputs")
OUTDIR.mkdir(parents=True, exist_ok=True)

LOG = []

def log(msg):
    print(msg)
    LOG.append(msg)

# ─────────────────────────────────────────────────────────────
# 1.  LOAD FARS DATA (2008–2020), filter to Arkansas
# ─────────────────────────────────────────────────────────────
log("=" * 60)
log("STEP 1: Extracting FARS accident records for Arkansas")
log("=" * 60)

AR_STATE = "5"      # FARS uses numeric state code
AR_FIPS_PREFIX = "05"

fars_years = list(range(2008, 2021))
records = []

for yr in fars_years:
    zpath = UPLOADS / f"FARS{yr}NationalCSV.zip"
    if not zpath.exists():
        log(f"  MISSING: {zpath.name} — skipping year {yr}")
        continue

    with zipfile.ZipFile(zpath, "r") as zf:
        # Filename casing varies across years — find it dynamically
        csv_name = next(
            n for n in zf.namelist()
            if n.lower().endswith("accident.csv")
        )
        with zf.open(csv_name) as f:
            reader = csv.DictReader(io.TextIOWrapper(f, encoding="latin-1"))
            yr_count = 0
            for row in reader:
                if row.get("STATE", "").strip() == AR_STATE:
                    county_raw = row.get("COUNTY", "0").strip()
                    try:
                        county_int = int(county_raw)
                    except ValueError:
                        continue
                    # Skip county=0 (unknown) or 999 (unknown)
                    if county_int in (0, 999):
                        continue

                    fips = f"{AR_FIPS_PREFIX}{county_int:03d}"
                    fatals    = int(row.get("FATALS", 0))
                    drunk_dr  = int(row.get("DRUNK_DR", 0))
                    records.append({
                        "fips":      fips,
                        "year":      yr,
                        "fatals":    fatals,
                        "drunk_dr":  drunk_dr,   # number of drunk drivers involved
                    })
                    yr_count += 1
    log(f"  {yr}: {yr_count} Arkansas fatal crash records extracted")

fars_raw = pd.DataFrame(records)
log(f"\n  Total crash-level records: {len(fars_raw):,}")

# ─────────────────────────────────────────────────────────────
# 2.  AGGREGATE TO COUNTY × YEAR
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 2: Aggregating to county × year")
log("=" * 60)

# Each row is one fatal crash; drunk_dr > 0 means ≥1 drunk driver
fars_raw["alcohol_crash"] = (fars_raw["drunk_dr"] > 0).astype(int)

fars = (
    fars_raw
    .groupby(["fips", "year"])
    .agg(
        fatal_crashes         = ("fatals",       "count"),   # crash count
        total_fatalities      = ("fatals",       "sum"),     # person deaths
        alcohol_fatal_crashes = ("alcohol_crash","sum"),     # alcohol-flagged crashes
    )
    .reset_index()
)

fars["alcohol_share"] = (
    fars["alcohol_fatal_crashes"] / fars["fatal_crashes"].replace(0, pd.NA)
)

log(f"  County-year observations: {len(fars):,}")
log(f"  Year range: {fars['year'].min()}–{fars['year'].max()}")
log(f"  Unique counties: {fars['fips'].nunique()}")

# ─────────────────────────────────────────────────────────────
# 3.  LOAD WET/DRY PANEL
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 3: Loading wet/dry panel")
log("=" * 60)

panel_file = UPLOADS / "arkansas_county_adjacency_wetdry_panel_2010_2024.xlsx"

wetdry = pd.read_excel(panel_file, sheet_name="WetDry_Panel_2010_2024")
transitions = pd.read_excel(panel_file, sheet_name="Transition_Events")

# Standardize FIPS dtype
wetdry["fips"] = wetdry["fips"].astype(str).str.zfill(5)
transitions["fips"] = transitions["fips"].astype(str).str.zfill(5)

log(f"  Wet/dry panel rows: {len(wetdry):,}")
log(f"  Transition events: {len(transitions)}")
log(f"  Panel years: {wetdry['year'].min()}–{wetdry['year'].max()}")

# Keep only columns we need
wetdry_slim = wetdry[[
    "year", "county", "fips",
    "countywide_wet_eoy",
    "borders_countywide_wet_eoy",
    "n_countywide_wet_neighbors_eoy",
    "share_countywide_wet_neighbors_eoy",
    "borders_any_wet_area_eoy",
    "partial_county",
    "n_neighbors",
]].rename(columns={
    "countywide_wet_eoy":                "countywide_wet",
    "borders_countywide_wet_eoy":        "any_wet_neighbor",
    "n_countywide_wet_neighbors_eoy":    "n_wet_neighbors",
    "share_countywide_wet_neighbors_eoy":"share_wet_neighbors",
    "borders_any_wet_area_eoy":          "any_wet_area_neighbor",
})

# ─────────────────────────────────────────────────────────────
# 4.  BUILD TREATMENT COHORT VARIABLES
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 4: Constructing C&S-A cohort identifiers")
log("=" * 60)

# first_treated_year from Transition_Events
transitions["event_year"] = transitions["event_year"].astype(int)
first_treat = (
    transitions
    .sort_values("event_year")
    .groupby("fips")["event_year"]
    .first()
    .reset_index()
    .rename(columns={"event_year": "first_treated_year"})
)

# Merge first_treated_year onto panel
wetdry_slim = wetdry_slim.merge(first_treat, on="fips", how="left")

# cohort: year of first treatment; 0 = never-treated (for csdid / did2s)
wetdry_slim["cohort"] = wetdry_slim["first_treated_year"].fillna(0).astype(int)

# years_since_treatment (negative = pre-period; missing if never treated)
wetdry_slim["years_since_treatment"] = (
    wetdry_slim["year"] - wetdry_slim["first_treated_year"]
)

# Sample-role flags
ever_treated_fips = set(first_treat["fips"])

all_fips = set(wetdry_slim["fips"].unique())

# neighbor_unit: contiguous to at least one treated unit at any point
neighbor_fips = set(
    wetdry_slim.loc[wetdry_slim["any_wet_neighbor"] == 1, "fips"].unique()
) - ever_treated_fips

clean_control_fips = all_fips - ever_treated_fips - neighbor_fips

wetdry_slim["treated_unit"]  = wetdry_slim["fips"].isin(ever_treated_fips).astype(int)
wetdry_slim["neighbor_unit"] = wetdry_slim["fips"].isin(neighbor_fips).astype(int)
wetdry_slim["clean_control"] = wetdry_slim["fips"].isin(clean_control_fips).astype(int)

log(f"  Ever-treated counties (2010–2024): {len(ever_treated_fips)}")
log(f"  Neighbor (spillover) counties: {len(neighbor_fips)}")
log(f"  Clean never-treated controls: {len(clean_control_fips)}")

# Show treated cohorts
log("\n  Treated cohorts within FARS window (2008–2020):")
for _, row in transitions[transitions["event_year"] <= 2020].iterrows():
    log(f"    {row['county']:15s}  FIPS={row['fips']}  year={row['event_year']}  ({row['policy_scope']})")

# ─────────────────────────────────────────────────────────────
# 5.  EXTEND PANEL BACK TO 2008–2009 (pre-treatment years)
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 5: Extending panel back to 2008–2009")
log("=" * 60)

# The wet/dry panel starts at 2010. For 2008–2009 we carry 2010 values
# backward (status was stable — no transitions before 2010).
base_2010 = wetdry_slim[wetdry_slim["year"] == 2010].copy()

pre_rows = []
for yr in [2008, 2009]:
    temp = base_2010.copy()
    temp["year"] = yr
    # No transitions before 2010, so wet status same as 2010
    # years_since_treatment update
    temp["years_since_treatment"] = yr - temp["first_treated_year"]
    pre_rows.append(temp)

wetdry_full = pd.concat([pd.concat(pre_rows), wetdry_slim], ignore_index=True)
wetdry_full = wetdry_full.sort_values(["fips", "year"]).reset_index(drop=True)

log(f"  Panel rows after extension: {len(wetdry_full):,}  ({wetdry_full['year'].min()}–{wetdry_full['year'].max()})")

# ─────────────────────────────────────────────────────────────
# 6.  MERGE FARS → WET/DRY PANEL
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 6: Merging FARS outcomes onto wet/dry panel")
log("=" * 60)

# Restrict FARS to 2008–2020 (FARS files available)
fars_window = fars[fars["year"] <= 2020].copy()

# Left join: keep all panel rows; attach FARS outcomes where available
merged = wetdry_full[wetdry_full["year"] <= 2020].merge(
    fars_window,
    on=["fips", "year"],
    how="left"
)

# Counties with 0 fatal crashes in a year: FARS simply has no row.
# Fill with zeros (they were crash-free, not missing).
for col in ["fatal_crashes", "total_fatalities", "alcohol_fatal_crashes"]:
    merged[col] = merged[col].fillna(0).astype(int)

merged["alcohol_share"] = merged["alcohol_share"]  # keep NA if 0 crashes

log(f"  Merged rows: {len(merged):,}")
log(f"  County-years with 0 fatal crashes: {(merged['fatal_crashes'] == 0).sum()}")
log(f"  County-years with FARS data: {(merged['fatal_crashes'] > 0).sum()}")

# Quick merge quality check
unmatched = set(fars_window["fips"].unique()) - set(wetdry_full["fips"].unique())
log(f"  FARS FIPS not in wet/dry panel: {unmatched if unmatched else 'none — clean merge'}")

# ─────────────────────────────────────────────────────────────
# 7.  FINAL COLUMN ORDERING & EXPORT
# ─────────────────────────────────────────────────────────────
log("\n" + "=" * 60)
log("STEP 7: Finalizing and exporting")
log("=" * 60)

col_order = [
    # Identifiers
    "fips", "county", "year",
    # Outcomes
    "fatal_crashes", "total_fatalities",
    "alcohol_fatal_crashes", "alcohol_share",
    # Treatment
    "countywide_wet", "first_treated_year", "cohort", "years_since_treatment",
    # Spillover
    "any_wet_neighbor", "n_wet_neighbors", "share_wet_neighbors",
    "any_wet_area_neighbor",
    # County structure
    "n_neighbors", "partial_county",
    # Sample flags
    "treated_unit", "neighbor_unit", "clean_control",
]

final = merged[col_order].sort_values(["fips", "year"]).reset_index(drop=True)

# ── Export main panel ──
out_panel = OUTDIR / "arkansas_did_panel.csv"
final.to_csv(out_panel, index=False)
log(f"\n  ✓ Main panel saved: {out_panel.name}")
log(f"    Rows: {len(final):,}  |  Columns: {len(final.columns)}")

# ── Export transition summary ──
trans_summary = transitions.copy()
trans_summary["in_fars_window"] = (trans_summary["event_year"] <= 2020).astype(int)
trans_summary["pre_periods_available"] = (
    (2008 - trans_summary["event_year"]).abs()
    .clip(upper=trans_summary["event_year"] - 2008)
)
trans_summary.to_csv(OUTDIR / "transition_summary.csv", index=False)
log(f"  ✓ Transition summary saved: transition_summary.csv")

# ── Descriptive summary ──
log("\n" + "=" * 60)
log("DESCRIPTIVE SUMMARY (2010–2020 estimation window)")
log("=" * 60)
est = final[(final["year"] >= 2010) & (final["year"] <= 2020)]
log(f"  Obs: {len(est):,}  ({est['fips'].nunique()} counties × up to 11 years)")
log(f"  Treated units:       {est[est['treated_unit']==1]['fips'].nunique()} counties")
log(f"  Neighbor units:      {est[est['neighbor_unit']==1]['fips'].nunique()} counties")
log(f"  Clean controls:      {est[est['clean_control']==1]['fips'].nunique()} counties")
log(f"\n  Fatal crashes (mean per county-year):  {est['fatal_crashes'].mean():.2f}")
log(f"  Alcohol crashes (mean per county-year): {est['alcohol_fatal_crashes'].mean():.2f}")
log(f"  Avg alcohol share: {est['alcohol_share'].mean():.3f}")

log("\n  Treated cohorts in FARS window (event_year ≤ 2020):")
for _, r in transitions[transitions["event_year"] <= 2020].iterrows():
    post_yrs  = 2020 - r["event_year"]
    pre_yrs   = r["event_year"] - 2008
    log(f"    {r['county']:15s}  cohort={r['event_year']}  pre={pre_yrs}yr  post={post_yrs}yr")

# ── Write log ──
with open(OUTDIR / "merge_log.txt", "w") as f:
    f.write("\n".join(LOG))
log("\n  ✓ merge_log.txt saved")
log("\nDone.")
