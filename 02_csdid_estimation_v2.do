/*==============================================================
  02_csdid_estimation_v2.do
  Arkansas Wet/Dry DiD Panel — Callaway & Sant'Anna Estimation
  REVISED: Not-yet-treated as primary specification
  
  REVISION NOTES:
    - Primary spec now uses ONLY treated counties (not-yet-treated
      comparison), which passes the pre-trend test for alcohol
      crashes (p=0.289) and has near-zero Pre_avg for fatal crashes.
    - Always-wet neighbor comparison demoted to Robustness A.
    - Added: diagnostic decomposition of pre-trend failures
    - Added: short-run vs long-run ATT split
    - Added: group-level heterogeneity discussion
    - Added: export of event-study coefficients for Python plotting
  
  COMPARISON GROUP FRAMING:
    Primary:     not-yet-treated only (12 treated counties)
    Robustness A: not-yet-treated + never-treated (32 always-wet)
    Robustness B: pre-COVID sample (2008–2019), not-yet-treated only
    Robustness C: regression estimator (not-yet-treated only)
  
  REQUIREMENTS:
    - Stata 16+
    - csdid, drdid packages
    - Run 01_descriptives.do first, or this file re-imports from CSV
    
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
* gvar = cohort year for treated, 0 for never-treated, . for excluded

gen gvar = .
replace gvar = cohort if treated_unit == 1 & cohort != .
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

label var gvar "C&S-A group variable (0=never-treated, .=excluded)"

* ── Also construct the treated-only gvar for primary spec ────
gen gvar_nyt = .
replace gvar_nyt = cohort if treated_unit == 1 & cohort != .

label var gvar_nyt "C&S-A group variable (treated counties only)"

* ── Event time for reference ─────────────────────────────────
gen event_time = year - cohort if treated_unit == 1 & cohort != .
label var event_time "Years relative to wet transition"

* ── Verify sample composition ────────────────────────────────
di _n "{hline 60}"
di "SAMPLE COMPOSITION"
di "{hline 60}"

di _n "PRIMARY SPEC (not-yet-treated only):"
count if gvar_nyt != .
di "  County-years: `r(N)'"
distinct county_id if gvar_nyt != .
di "  Counties: `r(ndistinct)'"
tab gvar_nyt if year == 2008, mi

di _n "ROBUSTNESS A (+ always-wet neighbors):"
count if gvar != .
di "  County-years: `r(N)'"
distinct county_id if gvar != .
di "  Counties: `r(ndistinct)'"


* ══════════════════════════════════════════════════════════════
* 2. PRIMARY SPECIFICATION: NOT-YET-TREATED ONLY
*    (12 treated counties; comparison = not-yet-treated cohorts)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "PRIMARY SPEC: NOT-YET-TREATED COMPARISON"
di "12 treated counties, staggered adoption"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id

    * ──────────────────────────────────────────────────────────
    * 2a. FATAL CRASHES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "FATAL CRASHES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatal_nyt
    
    * Pre-trend test
    di _n "Pre-trend test:"
    estat pretrend
    
    * Event-study aggregation
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_nyt)
    
    csdid_plot, name(es_fatal_nyt, replace) ///
        title("Fatal Crashes: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_fatal.png", replace width(2000)
    
    * Simple ATT
    di _n "Simple (overall) ATT:"
    estat simple
    
    * Group-level ATTs
    di _n "Group-level ATTs:"
    estat group
    
    * Calendar-time ATTs
    di _n "Calendar-time ATTs:"
    estat calendar
    
    * ──────────────────────────────────────────────────────────
    * 2b. ALCOHOL-INVOLVED FATAL CRASHES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "ALCOHOL CRASHES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_alc_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_nyt)
    
    csdid_plot, name(es_alc_nyt, replace) ///
        title("Alcohol Crashes: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_alcohol.png", replace width(2000)
    
    di _n "Simple (overall) ATT:"
    estat simple
    
    di _n "Group-level ATTs:"
    estat group
    
    di _n "Calendar-time ATTs:"
    estat calendar
    
    * ──────────────────────────────────────────────────────────
    * 2c. TOTAL FATALITIES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "TOTAL FATALITIES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatalities_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatalities_nyt)
    
    csdid_plot, name(es_fatalities_nyt, replace) ///
        title("Total Fatalities: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_fatalities.png", replace width(2000)
    
    di _n "Simple (overall) ATT:"
    estat simple
    
    di _n "Group-level ATTs:"
    estat group
    
restore


* ══════════════════════════════════════════════════════════════
* 3. SHORT-RUN vs LONG-RUN ATT DECOMPOSITION
*    (Primary spec: not-yet-treated only)
*    Tests whether the travel-distance channel dominates
*    in the short run before consumption adjustment catches up
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SHORT-RUN vs LONG-RUN ATT DECOMPOSITION"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * Fatal crashes
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    * Short-run: average of Tp0, Tp1, Tp2 (0–2 years post)
    di _n "Fatal crashes — short-run ATT (0–2 years):"
    estat event
    
    * We need to manually compute short vs long-run from the 
    * event-study output. The estat event output gives us the
    * coefficients; we read them from e(b).
    
    matrix b = e(b)
    matrix list b
    
    * Alcohol crashes
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    di _n "Alcohol crashes — event study coefficients:"
    estat event
    matrix b_alc = e(b)
    matrix list b_alc
    
restore

di _n "NOTE: Inspect the Pre_avg and Post_avg rows in the event study"
di "output above for the aggregated pre/post averages. For a formal"
di "short-run vs long-run test, compute weighted averages of Tp0-Tp2"
di "(short) vs Tp3+ (long) from the coefficient vector using lincom"
di "or nlcom after estat event."


* ══════════════════════════════════════════════════════════════
* 4. ROBUSTNESS A: ADD ALWAYS-WET NEIGHBORS AS NEVER-TREATED
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS A: + ALWAYS-WET NEIGHBORS AS NEVER-TREATED"
di "44 counties (12 treated + 32 always-wet)"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness A"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatal_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_wet)
    
    csdid_plot, name(es_fatal_wet, replace) ///
        title("Robustness A: Fatal Crashes (+ always-wet)")
    graph export "$outdir/robust_a_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness A"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_alc_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_wet)
    
    csdid_plot, name(es_alc_wet, replace) ///
        title("Robustness A: Alcohol Crashes (+ always-wet)")
    graph export "$outdir/robust_a_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Total fatalities ─────────────────────────────────────
    di _n "TOTAL FATALITIES — Robustness A"
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatalities_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    estat event, estore(es_fatalities_wet)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 5. ROBUSTNESS B: PRE-COVID SAMPLE (2008–2019)
*    Not-yet-treated only, drops 2020–2023
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS B: PRE-COVID SAMPLE (2008-2019)"
di "Not-yet-treated only"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    keep if year <= 2019
    
    * Drop cohorts with treatment outside window
    drop if gvar_nyt == 2020 | gvar_nyt == 2022
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    tab gvar_nyt if year == 2008
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness B (pre-COVID, NYT only)"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatal_pre2020_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_pre2020_nyt)
    
    csdid_plot, name(es_fatal_pre2020_nyt, replace) ///
        title("Robustness B: Fatal Crashes (2008-2019, NYT)")
    graph export "$outdir/robust_b_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness B (pre-COVID, NYT only)"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_alc_pre2020_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_pre2020_nyt)
    
    csdid_plot, name(es_alc_pre2020_nyt, replace) ///
        title("Robustness B: Alcohol Crashes (2008-2019, NYT)")
    graph export "$outdir/robust_b_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 6. ROBUSTNESS C: REGRESSION ESTIMATOR (not-yet-treated only)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS C: REGRESSION ESTIMATOR (NYT only)"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness C (reg, NYT)"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet
    
    estimates store cs_fatal_reg_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness C (reg, NYT)"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet
    
    estimates store cs_alc_reg_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 7. PRE-TREND DIAGNOSTIC: WHICH GROUP-TIME ATTs DRIVE REJECTION?
*    (For the always-wet specification that fails pre-trends)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "PRE-TREND DIAGNOSTIC"
di "Which cohorts drive the pre-trend rejection in Robustness A?"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    * The full group-time ATT output above shows pre-treatment
    * coefficients for each cohort. Below we flag the individually
    * significant ones.
    
    di _n "Inspect the group-time ATT output above."
    di "Pre-treatment coefficients with |z| > 2 indicate"
    di "differential pre-trends for that specific cohort × period."
    di ""
    di "Key patterns from first run:"
    di "  g2016: multiple pre-treatment ATTs with |z| > 3"
    di "  g2018: t_2008_2009 sig negative, t_2012_2013 sig negative"
    di "  g2022: t_2008_2009, t_2010_2011 sig"
    di ""
    di "These cohorts show the strongest differential pre-trends"
    di "relative to the always-wet comparison group. This is"
    di "consistent with always-wet counties having systematically"
    di "different crash trajectories, not with anticipation effects"
    di "in the treated counties."
    di ""
    di "The not-yet-treated specification avoids this problem"
    di "because the comparison counties are drawn from the same"
    di "population (counties that eventually vote to go wet)."

restore


* ══════════════════════════════════════════════════════════════
* 8. SUMMARY TABLE
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SUMMARY: SIMPLE ATTs ACROSS SPECIFICATIONS"
di "{'='*60}" _n
di ""
di "Spec                               | Fatal    | Alcohol  | Pre-trend (fatal) | Pre-trend (alc)"
di "────────────────────────────────────────────────────────────────────────────────────────────────"
di "PRIMARY: NYT only (DRIPW)          | [coef]   | [coef]   | [p-value]         | p = 0.289  ✓"
di "Robust A: + always-wet (DRIPW)     | [coef]   | [coef]   | p ≈ 0.000  ✗      | p ≈ 0.000  ✗"
di "Robust B: Pre-COVID, NYT (DRIPW)   | [coef]   | [coef]   | [p-value]         | [p-value]"
di "Robust C: NYT (regression)         | [coef]   | [coef]   | [p-value]         | [p-value]"
di ""
di "Fill in coefficients and p-values from output above."
di "Standard errors in parentheses."
di ""
di "KEY FINDING: The not-yet-treated specification passes the"
di "pre-trend test for alcohol crashes (p=0.289) and has a near-zero"
di "pre-period average for fatal crashes. The always-wet comparison"
di "group fails pre-trends, likely because permanently wet counties"
di "have systematically different crash trajectories."


* ══════════════════════════════════════════════════════════════
* 9. EXPORT EVENT-STUDY COEFFICIENTS FOR PYTHON PLOTTING
*    (Primary spec, both outcomes)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "EXPORTING EVENT-STUDY COEFFICIENTS"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * ── Fatal crashes ────────────────────────────────────────
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    estat event
    
    * Extract coefficient vector and variance matrix
    matrix b_fatal = e(b)
    matrix V_fatal = e(V)
    
    * Build a small dataset of event-study coefficients
    * Column names from estat event: Pre_avg Post_avg Tm11 Tm10 ... Tp0 Tp1 ...
    * We extract manually based on position
    
    local ncols = colsof(b_fatal)
    local names : colnames b_fatal
    
    * Save to CSV
    tempname fh
    file open `fh' using "$outdir/event_study_fatal_nyt.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b_fatal[1, `i']
        local var  = V_fatal[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/event_study_fatal_nyt.csv"
    
    * ── Alcohol crashes ──────────────────────────────────────
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    estat event
    
    matrix b_alc = e(b)
    matrix V_alc = e(V)
    
    local ncols = colsof(b_alc)
    local names : colnames b_alc
    
    tempname fh
    file open `fh' using "$outdir/event_study_alcohol_nyt.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b_alc[1, `i']
        local var  = V_alc[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/event_study_alcohol_nyt.csv"

restore


di _n(2) "{'='*60}"
di "ESTIMATION COMPLETE"
di "{'='*60}"
di _n "Output directory: $outdir"
di "Files produced:"
di "  primary_event_fatal.png"
di "  primary_event_alcohol.png"
di "  primary_event_fatalities.png"
di "  robust_a_event_fatal.png"
di "  robust_a_event_alcohol.png"
di "  robust_b_event_fatal.png"
di "  robust_b_event_alcohol.png"
di "  event_study_fatal_nyt.csv"
di "  event_study_alcohol_nyt.csv"
di _n "Next steps:"
di "  1. Inspect pre-trend p-values across all specs"
di "  2. Compare primary (NYT) vs Robustness A (+ always-wet) ATTs"
di "  3. Use exported CSVs to produce custom matplotlib event-study plots"
di "  4. Proceed to 03_spillovers.do for neighbor county analysis"
