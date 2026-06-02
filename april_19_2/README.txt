================================================================
CONTEXT TRANSFER: Arkansas Wet/Dry DiD Project
Transfer date: 2026-04-20
Purpose: Re-estimation with controls, monthly panel, DOW FE
================================================================

PROJECT OVERVIEW
================
Empirical study of how county-level wet/dry alcohol policy transitions 
in Arkansas affect fatal traffic crashes. Uses Callaway & Sant'Anna 
(2021) staggered difference-in-differences. Dissertation research.

Theoretical framework: Becker (1968) rational crime/behavior model.
Two offsetting channels:
  - Consumption channel (+): going wet increases local drinking
  - Travel-distance channel (-): going wet eliminates long impaired 
    driving trips to reach distant retailers
Net effect is theoretically ambiguous -- the empirical design resolves it.


WHAT WAS COMPLETED (2026-04-20 session)
========================================
1. Rebuilt FARS crash-level extract from raw ACCIDENT files (2008-2023)
   with vehicle-level alcohol joins for 2021-2023 (DR_DRINK from 
   VEHICLE.CSV joined on ST_CASE). Validated: 0 mismatches against 
   the existing county-year panel.

2. Created county x year x month panel (14,400 rows = 75 x 16 x 12)
   with day-of-week crash counts per cell.

3. Created county x year day-of-week distribution file (1,200 rows)
   with per-day counts and shares.

4. Processed CBP churches data (NAICS 813110) for religiosity proxy.
   75 counties x 2010-2023 from raw .dta, backfilled 2008-2009 
   with 2010 values.

5. Pulled ACS 5-year summary tables from Census Bureau API for all 
   75 AR counties, vintages 2009-2023. Variables: total_pop, 
   median_hh_income, median_age, poverty_rate, pct_white, pct_black,
   pct_under_18, pct_21plus.

6. MERGED EVERYTHING into two estimation-ready panels:
   - arkansas_panel_annual_merged.csv  (1,200 rows, 50 cols)
   - arkansas_panel_monthly_merged.csv (14,400 rows, 38 cols)
   Zero merge misses on all joins.

7. Confirmed IPUMS ACS microdata (usa_00006.csv) identifies only 
   4 AR counties (Benton, Pulaski, Saline, Washington). Not useful 
   for county-level controls. ACS summary tables used instead.


ESTIMATION-READY PANELS
========================

arkansas_panel_annual_merged.csv (PRIMARY — for csdid estimation)
  1,200 rows: 75 counties x 16 years (2008-2023)
  50 columns:
  
  From base panel:
    fips, county, year
    fatal_crashes, total_fatalities, alcohol_fatal_crashes, alcohol_share
    alcohol_flag_source
    countywide_wet, first_treated_year, cohort, years_since_treatment
    any_wet_neighbor, n_wet_neighbors, share_wet_neighbors
    any_wet_area_neighbor, n_neighbors, partial_county
    treated_unit, neighbor_unit, clean_control
  
  ACS controls (merged via fips x acs_vintage):
    acs_vintage — maps panel year to ACS vintage (2008-2009 -> 2009)
    total_pop, median_hh_income, median_age
    poverty_rate, pct_white, pct_black, pct_under_18, pct_21plus, pop_21plus
  
  Derived per-capita outcomes:
    fatal_crashes_pc    — fatal crashes per 100,000 pop
    alcohol_crashes_pc  — alcohol crashes per 100,000 pop
  
  CBP churches:
    church_establishments, church_employees
    churches_pc — establishments per 10,000 pop
  
  DOW distributions (from crash-level aggregation):
    share_sun through share_sat — fraction of crashes on each day
    crashes_sun through crashes_sat — raw counts by day


arkansas_panel_monthly_merged.csv (for monthly estimation)
  14,400 rows: 75 counties x 16 years x 12 months
  38 columns:
  
    fips, county, year, month
    fatal_crashes, total_fatalities, alcohol_fatal_crashes
    weekend_crashes, night_crashes
    crashes_sun through crashes_sat
    alcohol_flag_source
    countywide_wet, cohort, treated_unit, neighbor_unit, clean_control
    n_wet_neighbors, share_wet_neighbors, n_neighbors
    total_pop, median_hh_income, median_age
    poverty_rate, pct_white, pct_black, pct_under_18, pct_21plus, pop_21plus
    fatal_crashes_pc, alcohol_crashes_pc — monthly rates (annualized per 100k)
    church_establishments, church_employees
  
  Notes:
    - 9,015 of 14,400 county-months have zero fatal crashes (62.6%)
    - Per-capita rates are annualized: (crashes / (pop/12)) * 100,000
    - Treatment vars replicated across months within county-year


SUPPORTING FILES
================
fars_crash_level_arkansas_2008_2023.csv
  8,287 rows: individual fatal crashes
  Columns: st_case, fips, county_fips_3, year, month, day, day_week,
    hour, drunk_dr, alcohol_flag_source, fatals, persons, is_alcohol,
    is_weekend, is_night
  day_week: FARS coding (1=Sun, 2=Mon, ..., 7=Sat)

arkansas_acs_controls_2009_2023.csv
  1,125 rows: 75 counties x 15 ACS vintages (2009-2023)
  Raw ACS pull; merged into panels via vintage mapping

arkansas_churches_2008_2023.csv
  1,200 rows: 75 counties x 16 years
  2008-2009 backfilled from 2010

arkansas_county_year_month.csv
  14,400 rows: pre-merge monthly crash aggregation

arkansas_county_year_dow.csv
  1,200 rows: DOW crash distributions at county-year level

build_full_panel.py
  FARS extraction pipeline (all 16 years, vehicle joins)

pull_acs_controls.py
  Census API script (run locally with API key)


SAMPLE COMPOSITION
==================
75 counties total:
  12 treated (transition dry -> wet)
  32 always-wet neighbors
  31 always-dry neighbors
  0  clean never-treated controls

Treated cohorts:
  2010: Boone (05009), Clark (05019)
  2012: Benton (05007), Sharp (05135)
  2014: Columbia (05027), Saline (05125)
  2016: Little River (05081)
  2018: Randolph (05121)
  2020: Sevier (05133), Van Buren (05141)
  2022: Hot Spring (05059), Polk (05113)

g2022 cohort mechanically omitted from NYT estimation (no comparators).
Effective estimation: 10 counties / 6 cohorts.


ESTIMATION STRATEGY
===================
Estimator: Callaway & Sant'Anna (2021), Stata csdid package
  method(dripw), notyet option

PRIMARY: Not-yet-treated only (12 treated counties)
  gvar_nyt = cohort year for treated, missing for all others
  Passes pre-trend test for alcohol crashes (p = 0.289)

ROBUST A: + always-wet neighbors as never-treated
  gvar = cohort for treated, 0 for 32 always-wet, . for always-dry
  Fails pre-trend (p ~ 0.000)

ROBUST B: Pre-COVID (2008-2019), NYT only
  Passes pre-trend for alcohol (p = 0.295)

ROBUST C: Regression estimator, NYT only
  method(reg) instead of method(dripw)

Stata constructed variables (built in .do files, not in CSV):
  county_id     — egen group(fips), panel identifier
  gvar          — cohort for treated, 0 for always-wet, . for always-dry
  gvar_nyt      — cohort for treated, . for all others
  event_time    — year - cohort for treated counties


PRIOR RESULTS (no covariates, from 2026-03-20)
===============================================
Simple ATTs (none significant at 5%):
  Spec                    | Fatal    | Alcohol
  Primary (NYT, DRIPW)   | -0.52    | -0.66
  Robust A (+ wet)        | -1.13    | -0.41
  Robust B (pre-COVID)    | -2.11    | -0.82
  Robust C (reg)          | -0.52    | -0.66
  (SEs: ~0.9-1.5 range)

Event-study dynamics (PRIMARY SPEC):
  Tp0:  +0.46 (p=0.701)   |  +0.43 (p=0.664)
  Tp1:  -2.71 (p=0.000)*  |  -1.50 (p=0.024)*
  Tp2:  -3.37 (p=0.016)*  |  -1.36 (p=0.043)*
  Tp3:  -2.20 (p=0.242)   |  -0.54 (p=0.583)

Interpretation: Travel-distance channel dominates short-run (Tp1-Tp2),
then consumption channel catches up, producing near-zero overall ATT.

Spillover ATTs (insignificant overall, some group-level significance).


CONTROL VARIABLE SUMMARY (annual panel)
========================================
  Variable                    Mean        Min        Max
  total_pop                39,338     4,717    398,949
  median_hh_income         39,602    20,543     89,879
  poverty_rate               0.20      0.08       0.38
  pct_white                  0.78      0.34       0.99
  median_age                40.85     30.60      52.30
  pct_21plus                 0.77      0.70       0.85
  church_establishments     34.88      2.00     400.00
  churches_pc (per 10k)      9.78      2.46      20.49


DAY-OF-WEEK PATTERNS (2008-2023)
=================================
  Day   All crashes   Alcohol share
  Sun   1,203 (14.5%)    38.7%
  Mon   1,091 (13.2%)    23.4%
  Tue   1,058 (12.8%)    20.4%
  Wed   1,058 (12.8%)    22.5%
  Thu   1,165 (14.1%)    25.1%
  Fri   1,273 (15.4%)    27.6%
  Sat   1,439 (17.4%)    35.9%

Strong weekend/alcohol pattern supports DOW controls.


WHAT COMES NEXT
===============
1. WRITE UPDATED .do FILES with covariates:
   - 02_csdid_estimation_v3.do: re-run all specs with ACS + churches
     controls entering both outcome model and propensity score
   - Covariates for csdid: total_pop (or log), median_hh_income, 
     poverty_rate, pct_white, pct_21plus, churches_pc
   - Per-capita outcomes as alternative dependent variables
   - DOW shares (share_sat, share_sun) as additional controls
   - Robustness C (regression) becomes meaningfully distinct with controls

2. UPDATED SPILLOVER ESTIMATION:
   - 03_spillovers_v2.do with same covariate set

3. MONTHLY ESTIMATION (new):
   - New .do file for county x month panel
   - Month FE + county FE
   - Treatment defined at monthly level (need to determine treatment month)
   - Zero-inflated count model considerations (62.6% zeros)
   - csdid may not handle monthly — consider ppmlhdfe or nbreg with FE

4. PUBLICATION PLOTS:
   - Updated event-study figures with covariate-adjusted estimates
   - DOW pattern figures for descriptive section

5. BEAMER UPDATE:
   - Add results slides to alcohol_road_safety_beamer.tex
   - Include control variable summary table
   - Updated event-study plots

6. STILL NEEDED:
   - HPMS VMT data (behavioral mechanism test)
   - On/off-premise license coding for 12 treated counties
   - Welfare/policy discussion section


KEY DATA NOTES TO PRESERVE
===========================
1. FARS alcohol flag: DRUNK_DR (2008-2020), DR_DRINK via vehicle 
   join (2021-2023). Tracked in alcohol_flag_source column.

2. ACS vintage mapping: panel year 2008-2009 use ACS 2009 vintage;
   2010+ use same-year vintage. ACS 5-year estimates are labeled 
   by end-year of survey window.

3. CBP churches 2008-2009 backfilled from 2010.

4. Monthly panel: 62.6% zero-crash months. Per-capita rates 
   annualized: (crashes / (pop/12)) * 100,000.

5. g2022 cohort (Hot Spring, Polk) mechanically omitted from NYT 
   estimation. Effective sample: 10 counties / 6 cohorts.

6. Always-wet comparison fails pre-trend — demoted to robustness.

7. IPUMS microdata NOT used (only 4 counties identified). ACS 
   summary tables from Census API cover all 75 counties.


WORKFLOW CONVENTIONS
====================
- Stata for estimation (csdid package, .do files run locally)
- Python (matplotlib) for custom publication-quality plots
- Navy/gold palette: NAVY=#1A2744, GOLD=#C9A84C, MUTED=#8C9BB5
- All code provided alongside outputs
- README as .txt, not .md
- Targeted fixes over full rewrites
================================================================
