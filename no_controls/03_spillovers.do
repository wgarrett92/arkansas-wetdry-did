/*==============================================================
  03_spillovers.do
  Arkansas Wet/Dry DiD Panel — Spillover Analysis
  
  PURPOSE:
    Estimate the effect of a neighboring county going wet on
    traffic outcomes in always-dry counties that did NOT
    themselves change status.
    
    This tests the travel-distance channel directly: if residents
    of dry counties were driving to wet counties for alcohol,
    a newly-wet neighbor should reduce that cross-county traffic
    and lower crashes in the dry county.
    
  DESIGN:
    "Treatment": a dry county gains a NEW wet neighbor during
    the panel (n_wet_neighbors increases relative to baseline)
    
    "Comparison": dry counties whose n_wet_neighbors does NOT
    change during the panel (stable exposure, no new spillover)
    
    Optionally: include the 32 always-wet counties as additional
    never-treated comparison units.
    
  SAMPLE:
    19 newly-exposed dry counties (spillover-treated)
    12 always-exposed dry counties (comparison — no change)
    32 always-wet counties (optional additional comparison)
    
    Excludes: 12 directly-treated counties (analyzed in main spec)
    
  SPILLOVER COHORTS:
    2012: 4 counties
    2014: 4 counties
    2016: 2 counties
    2018: 1 county
    2020: 5 counties
    2022: 3 counties
    
  NOTE ON CONTROLS:
    This specification currently runs without covariates.
    Once ACS demographics and VMT data are merged into the
    panel, re-run with controls by adding covariates after
    the outcome variable in the csdid command.
    
  REQUIREMENTS:
    - Stata 16+
    - csdid, drdid packages
    
  AUTHOR: [Your Name]
  DATE:   2026-03-20
==============================================================*/

clear all
set more off
set scheme s2color

global datadir "/Users/willgarrett/Desktop/Research/Mirror/Research/Crime/General Crime /Data/Arkansas"
global outdir  "$datadir/output"
cap mkdir "$outdir"


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

* ── Classify counties for spillover analysis ─────────────────

* Step 1: Identify baseline (2008) n_wet_neighbors for each county
bysort county_id (year): gen nw_baseline = n_wet_neighbors[1]
label var nw_baseline "n_wet_neighbors at baseline (2008)"

* Step 2: Find the max n_wet_neighbors during the panel
bysort county_id: egen nw_max = max(n_wet_neighbors)

* Step 3: Flag counties where n_wet_neighbors increased
gen spillover_exposed = (nw_max > nw_baseline) & ///
                        (treated_unit == 0) & ///
                        (neighbor_unit == 1) & ///
                        (countywide_wet == 0)
label var spillover_exposed "Dry neighbor with NEW wet neighbor during panel"

* Step 4: Flag comparison dry counties (n_wet_neighbors stable, > 0)
gen spillover_comparison = (nw_max == nw_baseline) & ///
                           (nw_baseline > 0) & ///
                           (treated_unit == 0) & ///
                           (neighbor_unit == 1) & ///
                           (countywide_wet == 0)
label var spillover_comparison "Dry neighbor with stable wet neighbor exposure"

* Step 5: Find the spillover cohort year (first year n_wet increases)
* For each exposed county, find the first year n_wet > baseline
gen spill_year = .
bysort county_id (year): replace spill_year = year ///
    if n_wet_neighbors > nw_baseline & ///
       (n_wet_neighbors[_n-1] == nw_baseline | _n == 1) & ///
       spillover_exposed == 1

* Carry the spillover year forward within county
bysort county_id (year): egen spillover_cohort = min(spill_year)
drop spill_year
label var spillover_cohort "Year dry county first gains a new wet neighbor"

* ── Construct the spillover gvar ─────────────────────────────

* Primary: newly-exposed dry + always-exposed dry comparison
gen gvar_spill = .
replace gvar_spill = spillover_cohort if spillover_exposed == 1 & spillover_cohort != .
replace gvar_spill = 0 if spillover_comparison == 1

label var gvar_spill "Spillover group var (0=never-exposed comparison)"

* Extended: add 32 always-wet counties as additional comparison
gen gvar_spill_ext = gvar_spill
replace gvar_spill_ext = 0 if neighbor_unit == 1 & countywide_wet == 1

label var gvar_spill_ext "Spillover group var, extended (+ always-wet comparison)"

* ── Verify sample composition ────────────────────────────────

di _n "{hline 60}"
di "SPILLOVER SAMPLE COMPOSITION"
di "{hline 60}"

di _n "PRIMARY SPILLOVER SAMPLE (dry counties only):"
distinct county_id if gvar_spill != .
tab gvar_spill if year == 2008, mi

di _n "EXTENDED SPILLOVER SAMPLE (+ always-wet):"
distinct county_id if gvar_spill_ext != .
tab gvar_spill_ext if year == 2008, mi

* Verify cohort composition
di _n "SPILLOVER COHORT DETAIL:"
tab spillover_cohort if spillover_exposed == 1 & year == 2008


* ══════════════════════════════════════════════════════════════
* 2. DESCRIPTIVE: SPILLOVER EXPOSURE OVER TIME
* ══════════════════════════════════════════════════════════════

di _n "{hline 60}"
di "DESCRIPTIVE: MEAN OUTCOMES BY SPILLOVER STATUS"
di "{hline 60}"

* Mean outcomes by year for exposed vs comparison
preserve
    keep if gvar_spill != .
    
    gen group_spill = cond(gvar_spill > 0, 1, 0)
    label define spill_lbl 0 "Comparison (stable)" 1 "Newly exposed"
    label values group_spill spill_lbl
    
    tabstat fatal_crashes alcohol_fatal_crashes, ///
        by(group_spill) stats(mean sd n) format(%9.2f) columns(statistics)
restore


* ══════════════════════════════════════════════════════════════
* 3. PRIMARY SPILLOVER SPECIFICATION
*    Treated: 19 newly-exposed dry counties
*    Comparison: 12 always-exposed dry counties (not-yet-treated + never-treated)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SPILLOVER: PRIMARY SPEC (dry counties only)"
di "19 newly-exposed + 12 always-exposed comparison"
di "{'='*60}" _n

preserve
    keep if gvar_spill != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "{hline 50}"
    di "SPILLOVER — FATAL CRASHES"
    di "{hline 50}"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill) ///
        method(dripw) notyet
    
    estimates store spill_fatal
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(spill_es_fatal)
    
    csdid_plot, name(spill_es_fatal, replace) ///
        title("Spillover Event Study: Fatal Crashes") ///
        subtitle("Dry neighbors gaining a newly-wet neighbor")
    graph export "$outdir/spillover_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    di _n "Group ATTs:"
    estat group
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "{hline 50}"
    di "SPILLOVER — ALCOHOL CRASHES"
    di "{hline 50}"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill) ///
        method(dripw) notyet
    
    estimates store spill_alc
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(spill_es_alc)
    
    csdid_plot, name(spill_es_alc, replace) ///
        title("Spillover Event Study: Alcohol Crashes") ///
        subtitle("Dry neighbors gaining a newly-wet neighbor")
    graph export "$outdir/spillover_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    di _n "Group ATTs:"
    estat group
    
    * ── Total fatalities ─────────────────────────────────────
    di _n "{hline 50}"
    di "SPILLOVER — TOTAL FATALITIES"
    di "{hline 50}"
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar_spill) ///
        method(dripw) notyet
    
    estimates store spill_fatalities
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(spill_es_fatalities)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 4. ROBUSTNESS: EXTENDED COMPARISON GROUP (+ always-wet)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SPILLOVER ROBUSTNESS: EXTENDED COMPARISON (+ always-wet)"
di "19 newly-exposed + 12 always-exposed dry + 32 always-wet"
di "{'='*60}" _n

preserve
    keep if gvar_spill_ext != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "SPILLOVER (extended) — FATAL CRASHES"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill_ext) ///
        method(dripw) notyet
    
    estimates store spill_fatal_ext
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(spill_es_fatal_ext)
    
    csdid_plot, name(spill_es_fatal_ext, replace) ///
        title("Spillover (extended): Fatal Crashes")
    graph export "$outdir/spillover_ext_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "SPILLOVER (extended) — ALCOHOL CRASHES"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill_ext) ///
        method(dripw) notyet
    
    estimates store spill_alc_ext
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(spill_es_alc_ext)
    
    csdid_plot, name(spill_es_alc_ext, replace) ///
        title("Spillover (extended): Alcohol Crashes")
    graph export "$outdir/spillover_ext_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 5. DOSE-RESPONSE: SHARE OF NEIGHBORS THAT ARE WET
*    (Exploratory — not C&S-A, uses continuous treatment intensity)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "DOSE-RESPONSE: SHARE WET NEIGHBORS (exploratory)"
di "{'='*60}" _n

* This is a standard TWFE regression (not C&S-A) using the
* continuous share_wet_neighbors as the treatment intensity.
* Included for descriptive purposes; interpret with caution
* given TWFE bias concerns.

preserve
    * Include all non-treated counties (both dry and wet neighbors)
    keep if treated_unit == 0
    
    di "Sample: `c(N)' county-years (all non-treated counties)"
    distinct county_id
    
    * Change in share relative to baseline
    bysort county_id (year): gen share_change = share_wet_neighbors - share_wet_neighbors[1]
    label var share_change "Change in share of wet neighbors since 2008"
    
    * TWFE with continuous intensity
    xtreg fatal_crashes share_wet_neighbors i.year, fe cluster(county_id)
    estimates store dose_fatal
    
    xtreg alcohol_fatal_crashes share_wet_neighbors i.year, fe cluster(county_id)
    estimates store dose_alc
    
    di _n "NOTE: TWFE dose-response is exploratory. The continuous"
    di "treatment intensity does not map cleanly to C&S-A, and"
    di "standard TWFE bias applies. Use for suggestive evidence only."

restore


* ══════════════════════════════════════════════════════════════
* 6. EXPORT SPILLOVER EVENT-STUDY COEFFICIENTS
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "EXPORTING SPILLOVER EVENT-STUDY COEFFICIENTS"
di "{'='*60}" _n

preserve
    keep if gvar_spill != .
    
    * Fatal crashes
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill) ///
        method(dripw) notyet
    estat event
    
    matrix b = e(b)
    matrix V = e(V)
    local names : colnames b
    
    tempname fh
    file open `fh' using "$outdir/spillover_event_fatal.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b[1, `i']
        local var  = V[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/spillover_event_fatal.csv"
    
    * Alcohol crashes
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_spill) ///
        method(dripw) notyet
    estat event
    
    matrix b = e(b)
    matrix V = e(V)
    local names : colnames b
    
    tempname fh
    file open `fh' using "$outdir/spillover_event_alcohol.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b[1, `i']
        local var  = V[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/spillover_event_alcohol.csv"

restore


* ══════════════════════════════════════════════════════════════
* 7. SUMMARY
* ══════════════════════════════════════════════════════════════

di _n(2) "{'='*60}"
di "SPILLOVER ANALYSIS COMPLETE"
di "{'='*60}"
di _n "Output files:"
di "  spillover_event_fatal.png"
di "  spillover_event_alcohol.png"
di "  spillover_ext_event_fatal.png"
di "  spillover_ext_event_alcohol.png"
di "  spillover_event_fatal.csv"
di "  spillover_event_alcohol.csv"
di _n "Key questions for interpretation:"
di "  1. Do the spillover pre-trend tests pass?"
di "  2. Is the spillover ATT negative (consistent with"
di "     fewer cross-county drunk driving trips)?"
di "  3. Does the spillover effect mirror the direct effect"
di "     timing (short-run reduction that attenuates)?"
di "  4. Does the dose-response show a gradient (higher"
di "     share_wet_neighbors → larger crash reduction)?"
di _n "Next: re-run after merging ACS controls into panel."
