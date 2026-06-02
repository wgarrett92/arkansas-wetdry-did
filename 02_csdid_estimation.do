/*==============================================================
  02_csdid_estimation.do
  Arkansas Wet/Dry DiD Panel — Callaway & Sant'Anna Estimation
  
  PURPOSE:
    1. Construct the C&S-A group variable (gvar)
    2. Estimate group-time ATTs for fatal & alcohol crashes
    3. Pre-trend / pre-test diagnostics
    4. Aggregate to event-study, simple, calendar, and group ATTs
    5. Robustness: not-yet-treated only comparison group
    6. Robustness: restricted sample window (2008–2019, drops COVID)
  
  COMPARISON GROUP FRAMING:
    - Main spec: not-yet-treated + never-treated (32 always-wet counties)
    - 31 always-dry neighbor counties EXCLUDED (spillover-contaminated)
    - Robustness: not-yet-treated only
  
  REQUIREMENTS:
    - Stata 16+
    - csdid, drdid packages (ssc install csdid; ssc install drdid)
    - Run 01_descriptives.do first (or this file re-imports from CSV)
    
  AUTHOR: [Your Name]
  DATE:   2026-03-20
==============================================================*/

clear all
set more off
set scheme s2color

* ── USER: Set paths ──────────────────────────────────────────
global datadir "."
global outdir  "$datadir/output"
cap mkdir "$outdir"

* ── Install packages if needed (uncomment on first run) ──────
* ssc install csdid, replace
* ssc install drdid, replace
* ssc install event_plot, replace   // optional: Stata event-study plots

* ══════════════════════════════════════════════════════════════
* 1. DATA PREPARATION
* ══════════════════════════════════════════════════════════════

import delimited "$datadir/arkansas_did_panel.csv", clear varnames(1)

destring fips year fatal_crashes total_fatalities alcohol_fatal_crashes ///
         countywide_wet first_treated_year cohort years_since_treatment ///
         any_wet_neighbor n_wet_neighbors share_wet_neighbors ///
         any_wet_area_neighbor n_neighbors partial_county ///
         treated_unit neighbor_unit clean_control, replace force

egen county_id = group(fips)
xtset county_id year

* ── Construct C&S-A group variable ───────────────────────────
*
*   gvar = cohort year   for treated counties (12 counties)
*   gvar = 0             for never-treated comparison (32 always-wet neighbors)
*   gvar = .             for always-dry neighbors (EXCLUDED from main sample)
*
*   Rationale: always-dry neighbors are spillover-contaminated
*   (they border transitioning counties) and would bias the
*   direct treatment effect toward zero if used as controls.

gen gvar = .

* Treated counties: cohort year
replace gvar = cohort if treated_unit == 1 & cohort != .

* Always-wet neighbors: never-treated (gvar = 0)
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

* Always-dry neighbors: excluded (gvar stays missing)
* These are: neighbor_unit==1 & countywide_wet==0

label var gvar "C&S-A group variable (0=never-treated, .=excluded)"

* ── Verify sample composition ────────────────────────────────
di _n "{hline 60}"
di "SAMPLE COMPOSITION"
di "{hline 60}"

count if gvar != .
di "Main estimation sample (county-years): `r(N)'"

distinct county_id if gvar != .
di "Main estimation sample (counties): `r(ndistinct)'"

tab gvar if year == 2008, mi
di _n "Treated cohorts:"
tab gvar if gvar > 0 & gvar != . & year == 2008

distinct county_id if gvar == 0
di "Never-treated (always-wet) counties: `r(ndistinct)'"

distinct county_id if gvar > 0 & gvar != .
di "Treated counties: `r(ndistinct)'"

count if gvar == .
di "Excluded county-years (always-dry neighbors): `r(N)'"

* ── Rate outcome: crashes per 10,000 pop (optional) ──────────
* NOTE: population data not yet in the panel. If/when ACS data
* are merged, uncomment and use rate outcomes.
* gen fatal_rate = (fatal_crashes / population) * 10000
* gen alc_rate   = (alcohol_fatal_crashes / population) * 10000

* ══════════════════════════════════════════════════════════════
* 2. MAIN SPECIFICATION: FATAL CRASHES
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "MAIN SPEC: FATAL CRASHES"
di "Comparison group: not-yet-treated + never-treated (always-wet)"
di "{'='*60}" _n

preserve
    keep if gvar != .

    * ── 2a. Group-time ATTs ──────────────────────────────────
    * method(dripw) = doubly-robust IPW (default and recommended)
    * notyet = use not-yet-treated in addition to never-treated
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatal_main
    
    * ── 2b. Pre-trend test ───────────────────────────────────
    * Tests H0: all pre-treatment ATTs = 0
    
    di _n "{hline 40}"
    di "PRE-TREND TEST: Fatal Crashes"
    di "{hline 40}"
    estat pretrend
    
    * ── 2c. Event-study aggregation ──────────────────────────
    * Aggregates group-time ATTs by event time (years since treatment)
    
    di _n "{hline 40}"
    di "EVENT-STUDY AGGREGATION: Fatal Crashes"
    di "{hline 40}"
    estat event, estore(es_fatal_main)
    
    * Plot
    csdid_plot, name(es_fatal_main, replace) ///
        title("C&S-A Event Study: Fatal Crashes") ///
        subtitle("Treated vs. not-yet-treated + always-wet")
    graph export "$outdir/csdid_event_fatal_main.png", replace width(2000)
    
    * ── 2d. Simple (overall) ATT ─────────────────────────────
    di _n "{hline 40}"
    di "SIMPLE ATT: Fatal Crashes"
    di "{hline 40}"
    estat simple
    
    * ── 2e. Group-level ATTs ─────────────────────────────────
    di _n "{hline 40}"
    di "GROUP ATTs: Fatal Crashes"
    di "{hline 40}"
    estat group
    
    * ── 2f. Calendar-time ATTs ───────────────────────────────
    di _n "{hline 40}"
    di "CALENDAR-TIME ATTs: Fatal Crashes"
    di "{hline 40}"
    estat calendar
    
restore

* ══════════════════════════════════════════════════════════════
* 3. MAIN SPECIFICATION: ALCOHOL-INVOLVED FATAL CRASHES
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "MAIN SPEC: ALCOHOL-INVOLVED FATAL CRASHES"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    * ── 3a. Group-time ATTs ──────────────────────────────────
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_alc_main
    
    * ── 3b. Pre-trend test ───────────────────────────────────
    di _n "{hline 40}"
    di "PRE-TREND TEST: Alcohol Crashes"
    di "{hline 40}"
    estat pretrend
    
    * ── 3c. Event-study aggregation ──────────────────────────
    di _n "{hline 40}"
    di "EVENT-STUDY AGGREGATION: Alcohol Crashes"
    di "{hline 40}"
    estat event, estore(es_alc_main)
    
    csdid_plot, name(es_alc_main, replace) ///
        title("C&S-A Event Study: Alcohol-Involved Fatal Crashes") ///
        subtitle("Treated vs. not-yet-treated + always-wet")
    graph export "$outdir/csdid_event_alcohol_main.png", replace width(2000)
    
    * ── 3d. Simple ATT ───────────────────────────────────────
    di _n "{hline 40}"
    di "SIMPLE ATT: Alcohol Crashes"
    di "{hline 40}"
    estat simple
    
    * ── 3e. Group-level ATTs ─────────────────────────────────
    di _n "{hline 40}"
    di "GROUP ATTs: Alcohol Crashes"
    di "{hline 40}"
    estat group
    
    * ── 3f. Calendar-time ATTs ───────────────────────────────
    di _n "{hline 40}"
    di "CALENDAR-TIME ATTs: Alcohol Crashes"
    di "{hline 40}"
    estat calendar

restore

* ══════════════════════════════════════════════════════════════
* 4. MAIN SPECIFICATION: TOTAL FATALITIES
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "MAIN SPEC: TOTAL FATALITIES"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatalities_main
    
    estat pretrend
    
    estat event, estore(es_fatalities_main)
    
    csdid_plot, name(es_fatalities_main, replace) ///
        title("C&S-A Event Study: Total Fatalities") ///
        subtitle("Treated vs. not-yet-treated + always-wet")
    graph export "$outdir/csdid_event_fatalities_main.png", replace width(2000)
    
    estat simple
    estat group

restore

* ══════════════════════════════════════════════════════════════
* 5. ROBUSTNESS A: NOT-YET-TREATED ONLY
*    (drops the 32 always-wet counties from comparison group)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS A: NOT-YET-TREATED ONLY"
di "Comparison group: only treated counties not yet treated"
di "{'='*60}" _n

preserve
    * Keep only treated counties (gvar > 0)
    keep if gvar > 0 & gvar != .
    
    di "Sample: `c(N)' county-years, all treated counties"
    distinct county_id
    di "Counties: `r(ndistinct)'"
    
    * ── Fatal crashes ────────────────────────────────────────
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatal_nyt
    
    estat pretrend
    estat event, estore(es_fatal_nyt)
    
    csdid_plot, name(es_fatal_nyt, replace) ///
        title("Robustness: Fatal Crashes (not-yet-treated only)")
    graph export "$outdir/csdid_event_fatal_nyt.png", replace width(2000)
    
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_alc_nyt
    
    estat pretrend
    estat event, estore(es_alc_nyt)
    
    csdid_plot, name(es_alc_nyt, replace) ///
        title("Robustness: Alcohol Crashes (not-yet-treated only)")
    graph export "$outdir/csdid_event_alcohol_nyt.png", replace width(2000)
    
    estat simple

restore

* ══════════════════════════════════════════════════════════════
* 6. ROBUSTNESS B: PRE-COVID SAMPLE (2008–2019)
*    Drops 2020–2023 to avoid COVID driving surge confound
*    and FARS alcohol-flag discontinuity
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS B: PRE-COVID SAMPLE (2008-2019)"
di "{'='*60}" _n

preserve
    keep if gvar != .
    keep if year <= 2019
    
    * Drop cohorts that have no pre-treatment data in this window
    * 2020 and 2022 cohorts: treatment year is outside window
    drop if gvar == 2020 | gvar == 2022
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    tab gvar if year == 2008
    
    * ── Fatal crashes ────────────────────────────────────────
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatal_pre2020
    
    estat pretrend
    estat event, estore(es_fatal_pre2020)
    
    csdid_plot, name(es_fatal_pre2020, replace) ///
        title("Robustness: Fatal Crashes (2008–2019)")
    graph export "$outdir/csdid_event_fatal_pre2020.png", replace width(2000)
    
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_alc_pre2020
    
    estat pretrend
    estat event, estore(es_alc_pre2020)
    
    csdid_plot, name(es_alc_pre2020, replace) ///
        title("Robustness: Alcohol Crashes (2008–2019)")
    graph export "$outdir/csdid_event_alcohol_pre2020.png", replace width(2000)
    
    estat simple

restore

* ══════════════════════════════════════════════════════════════
* 7. ROBUSTNESS C: ALTERNATIVE ESTIMATOR (reg)
*    Uses regression-based outcome model instead of DRIPW
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS C: REGRESSION-BASED ESTIMATOR"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(reg) notyet
    
    estimates store cs_fatal_reg
    
    estat pretrend
    estat event, estore(es_fatal_reg)
    estat simple
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(reg) notyet
    
    estimates store cs_alc_reg
    
    estat pretrend
    estat event, estore(es_alc_reg)
    estat simple

restore

* ══════════════════════════════════════════════════════════════
* 8. SUMMARY TABLE: COLLECT SIMPLE ATTs ACROSS SPECIFICATIONS
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SUMMARY: SIMPLE ATTs ACROSS SPECIFICATIONS"
di "{'='*60}" _n
di "Run each 'estat simple' output above and compile into a table."
di "Suggested format:"
di ""
di "Spec                      | Fatal Crashes | Alcohol Crashes"
di "─────────────────────────────────────────────────────────────"
di "Main (DRIPW, full panel)  |     [coef]    |     [coef]"
di "Not-yet-treated only      |     [coef]    |     [coef]"
di "Pre-COVID (2008–2019)     |     [coef]    |     [coef]"
di "Regression estimator      |     [coef]    |     [coef]"
di ""
di "Fill in from output above. A future version of this .do file"
di "will automate this table using esttab/estout."

* ══════════════════════════════════════════════════════════════
* 9. EXPORT ESTIMATES FOR PYTHON PLOTTING (optional)
*    If you want to plot event studies in matplotlib instead
* ══════════════════════════════════════════════════════════════

/*
* Uncomment this block to export event-study coefficients as CSV

preserve
    keep if gvar != .
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    estat event
    
    * Matrix of results
    matrix b = e(b)
    matrix V = e(V)
    
    * Manual export (adjust based on number of event-time coefficients)
    * Alternatively, use the parmest/estout approach:
    * estat event, estore(es)
    * esttab es using "$outdir/event_study_fatal.csv", csv se replace
restore
*/

di _n "Done. All output saved to: $outdir"
di "Review event-study plots and pre-trend test p-values."
di "Key diagnostic: if pre-trend test rejects, investigate which"
di "group-time ATTs are driving the rejection."
