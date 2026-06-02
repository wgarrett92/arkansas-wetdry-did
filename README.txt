================================================================
CONTEXT TRANSFER: Arkansas Wet/Dry DiD Project
Transfer date: 2026-04-19
Purpose: Monthly panel build, DOW data, churches merge, ACS setup
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


WHAT CHANGED THIS SESSION (2026-04-19)
=======================================
1. Rebuilt FARS crash-level extract from raw ACCIDENT files (2008-2023)
   with vehicle-level alcohol joins for 2021-2023 (DR_DRINK).
   Validated: 0 mismatches against existing county-year panel.

2. Created county x year x month panel (14,400 rows = 75 x 16 x 12)
   with day-of-week crash counts per cell. This enables:
   - Monthly-level estimation
   - Day-of-week fixed effects or controls

3. Created county x year day-of-week distribution file (1,200 rows)
   with per-day counts and shares for DOW FE at annual level.

4. Processed CBP churches data (NAICS 813110) for religiosity proxy.
   75 counties x 2010-2023 from raw .dta, backfilled 2008-2009 
   with 2010 values. Key variable: church_establishments (est).

5. Confirmed IPUMS ACS microdata identifies only 4 AR counties 
   (Benton, Pulaski, Saline, Washington). Wrote Census API pull 
   script for full 75-county ACS summary tables. Must be run locally 
   (Census API domain not in sandbox network allowlist).

6. IPUMS microdata (usa_00006.csv) is NOT useful for county-level 
   controls. 329,365 of 446,415 AR observations have COUNTYFIP=0.
   Use the Census API script instead.


PANEL DATASET: arkansas_did_panel.csv (UNCHANGED)
==================================================
- 1,200 rows: 75 Arkansas counties x 16 years (2008-2023)
- 20 columns (see prior context transfer for full list)
- This remains the primary estimation dataset at annual level


NEW DATA FILES
==============

fars_crash_level_arkansas_2008_2023.csv
  - 8,287 rows: individual fatal crashes in Arkansas
  - Columns: st_case, fips, county_fips_3, year, month, day, day_week,
    hour, drunk_dr, alcohol_flag_source, fatals, persons, is_alcohol,
    is_weekend, is_night
  - day_week: FARS coding (1=Sun, 2=Mon, ..., 7=Sat, 9=Unknown)
  - alcohol_flag_source: "DRUNK_DR" (2008-2020) or "DR_DRINK" (2021-2023)
  - is_weekend: 1 if Sat or Sun
  - is_night: 1 if hour 20-23 or 0-5

arkansas_county_year_month.csv
  - 14,400 rows: 75 counties x 16 years x 12 months
  - Columns: fips, county, year, month, fatal_crashes, total_fatalities,
    alcohol_fatal_crashes, weekend_crashes, night_crashes,
    crashes_sun through crashes_sat, alcohol_flag_source
  - Balanced panel including zero-crash months (9,015 of 14,400)
  - Ready for monthly-level estimation once merged with treatment vars

arkansas_county_year_dow.csv
  - 1,200 rows: 75 counties x 16 years
  - Columns: fips, county, year, total_crashes,
    crashes_sun/share_sun through crashes_sat/share_sat
  - DOW shares sum to 1.0 within each county-year (when total > 0)
  - For DOW FE at county-year level, merge into annual panel

arkansas_churches_2008_2023.csv
  - 1,200 rows: 75 counties x 16 years
  - Columns: fips, year, church_establishments, church_employees
  - Source: County Business Patterns, NAICS 813110
  - 2008-2009 values backfilled from 2010 (CBP coverage starts 2010)
  - church_establishments range: 2-400

pull_acs_controls.py
  - Script to pull ACS 5-year summary tables from Census Bureau API
  - Covers all 75 AR counties, vintages 2009-2023
  - Variables: total_pop, median_hh_income, median_age, poverty_rate,
    pct_white, pct_black, pct_under_18, pct_21plus
  - Usage: python3 pull_acs_controls.py [API_KEY]
  - Get API key: https://api.census.gov/data/key_signup.html
  - Output: arkansas_acs_controls_2009_2023.csv
  - MUST BE RUN LOCALLY (Census API not accessible from sandbox)

build_full_panel.py
  - Complete FARS extraction pipeline that produced the above files
  - Documents file-by-file column mapping and encoding handling
  - Vehicle-level join logic for 2021-2023 alcohol flags


SAMPLE COMPOSITION (UNCHANGED)
==============================
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


ESTIMATION STRATEGY (UNCHANGED)
================================
See prior context transfer for full detail. Summary:
  PRIMARY: Not-yet-treated only, DRIPW, passes pre-trend for alcohol
  ROBUST A: + always-wet neighbors (fails pre-trend)
  ROBUST B: Pre-COVID (2008-2019)
  ROBUST C: Regression estimator


DIRECT EFFECT RESULTS (as of 2026-03-20, UNCHANGED)
====================================================
See prior context transfer. Key findings:
  - Overall ATT negative but insignificant
  - Tp1-Tp2 significant reductions in fatal and alcohol crashes
  - Effects attenuate by Tp3+


DAY-OF-WEEK SUMMARY STATISTICS (2008-2023)
===========================================
All AR fatal crashes:
  Day   Count    %    Alcohol  Alc%
  Sun   1,203  14.5%    465   38.7%
  Mon   1,091  13.2%    255   23.4%
  Tue   1,058  12.8%    216   20.4%
  Wed   1,058  12.8%    238   22.5%
  Thu   1,165  14.1%    292   25.1%
  Fri   1,273  15.4%    351   27.6%
  Sat   1,439  17.4%    516   35.9%

Key pattern: Sat-Sun have highest crash counts AND highest alcohol
share (35.9% and 38.7% vs 20-27% on weekdays). This supports 
including DOW FE or weekend/night controls in estimation.


MONTHLY DISTRIBUTION (2008-2023)
=================================
  Jan:   575 (6.9%)    Jul:   716 (8.6%)
  Feb:   513 (6.2%)    Aug:   760 (9.2%)
  Mar:   625 (7.5%)    Sep:   757 (9.1%)
  Apr:   713 (8.6%)    Oct:   774 (9.3%)
  May:   715 (8.6%)    Nov:   686 (8.3%)
  Jun:   823 (9.9%)    Dec:   630 (7.6%)

Summer months (Jun-Oct) account for 46.2% of crashes. Strong 
seasonality supports month FE in monthly estimation.


NEXT STEPS
==========
1. RUN pull_acs_controls.py LOCALLY to get ACS controls
   - Then merge into monthly panel and annual panel
   - ACS vintage T maps to panel year T (2009 -> 2008-2009)

2. MERGE all controls into estimation-ready panels:
   - Churches (arkansas_churches_2008_2023.csv)
   - ACS demographics (once pulled)
   - Treatment/cohort variables (from arkansas_did_panel.csv)
   - For monthly panel: replicate annual treatment vars across months

3. RE-ESTIMATE with controls:
   - 02_csdid_estimation_v2.do with covariates in DRIPW
   - DOW controls: use share_sat, share_sun as county-year controls
     (or estimate at monthly level with month FE + DOW crash counts)
   - Churches as religiosity control in propensity score

4. MONTHLY ESTIMATION:
   - County x year x month panel enables month FE
   - Many zero-crash months (62.6%) -- consider Poisson/NB
   - Monthly treatment timing more precise than annual

5. Still needed:
   - HPMS VMT data (behavioral mechanism test)
   - On/off-premise license coding for 12 treated counties
   - 2008-2009 FARS ACCIDENT files if crash-level needed for those years
     (existing annual aggregates are already in the panel)


KEY DATA NOTES
==============
1. FARS alcohol flag: DRUNK_DR in ACCIDENT.CSV (2008-2020), DR_DRINK 
   in VEHICLE.CSV joined on ST_CASE (2021-2023). Tracked via 
   alcohol_flag_source column in all files.

2. CBP churches 2008-2009: backfilled from 2010. CBP annual data 
   starts 2010; 2008-2009 are not available.

3. IPUMS ACS microdata (usa_00006.csv): identifies only 4 AR counties
   (Benton FIPS 05007, Pulaski 05119, Saline 05125, Washington 05143).
   71 counties have COUNTYFIP=0. NOT useful for county-level controls.
   Use Census API summary tables via pull_acs_controls.py instead.

4. Monthly panel zero-inflation: 62.6% of county-months have zero 
   fatal crashes. Modeling choices for monthly estimation should 
   account for this (Poisson, NB, or zero-inflated models).

5. 2023 FARS: original upload was .numbers format (Apple iWork), 
   re-uploaded as CSV. Vehicle-level alcohol join completed via
   vehicle_arkansas_2023.csv.


WORKFLOW CONVENTIONS (UNCHANGED)
================================
- Stata for all estimation (csdid package, .do files run locally)
- Python (matplotlib) for custom publication-quality plots
- Navy/gold color palette: NAVY=#1A2744, GOLD=#C9A84C
- All code provided alongside outputs
- README as .txt, not .md
- Targeted fixes over full rewrites
================================================================
