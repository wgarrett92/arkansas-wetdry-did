/*
============================================================
  02_csdid_estimation_v3.do
  Callaway & Sant'Anna (2021) Estimation WITH Covariates
  Arkansas Wet/Dry County DiD Panel
  
  Input:  arkansas_panel_annual_merged_v2.csv
  Output: Event-study CSVs, pre-trend diagnostics, ATT tables
  
  Changes from v2 (no-covariate):
    - Covariates enter both outcome model and propensity score
      via csdid's xvar() option under method(dripw)
    - Covariate set: log_pop, median_hh_income, poverty_rate,
      pct_white, pct_21plus, churches_pc, pct_married
    - Per-capita outcomes as alternative DVs
    - Robustness C (regression) now meaningfully distinct
============================================================
*/

clear all
set more off
set matsize 5000

* ── Set paths (EDIT THESE) ──────────────────────────────────
* Change to your local project directory
* cd "/path/to/your/project"

local datafile "arkansas_panel_annual_merged_v2.csv"
local outdir   "output_v3"
capture mkdir "`outdir'"


* ============================================================
* SECTION 1: DATA IMPORT AND PANEL SETUP
* ============================================================

import delimited "`datafile'", clear varnames(1) case(lower)

* Numeric panel identifier
egen county_id = group(fips)

* Treatment group variables
* gvar_nyt: cohort year for treated, missing for all others (not-yet-treated)
* gvar:     cohort year for treated, 0 for always-wet, missing for always-dry
gen gvar_nyt = .
replace gvar_nyt = cohort if treated_unit == 1

gen gvar = .
replace gvar = cohort if treated_unit == 1
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

* Event time (for reference; csdid computes internally)
gen event_time = year - cohort if treated_unit == 1

* Declare panel
xtset county_id year


* ============================================================
* SECTION 2: CONSTRUCT COVARIATES
* ============================================================

* Log population (avoids scale issues with raw pop in propensity score)
gen log_pop = ln(total_pop)

* Verify no missing covariates in estimation sample
local xvars log_pop median_hh_income poverty_rate pct_white pct_21plus churches_pc pct_married

foreach v of local xvars {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has `r(N)' missing values"
    }
    else {
        di as text "`v': no missing values ✓"
    }
}

* Summary stats for covariates
di _n "============================================================"
di "COVARIATE SUMMARY STATISTICS"
di "============================================================"
tabstat `xvars', stats(mean sd min max n) columns(statistics) format(%9.3f)


* ============================================================
* SECTION 3: PRIMARY SPECIFICATION (Not-Yet-Treated, DRIPW)
* ============================================================

di _n "============================================================"
di "PRIMARY SPEC: NYT + DRIPW + COVARIATES"
di "============================================================"

* ── Fatal crashes ───────────────────────────────────────────
di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

* Store results
estimates store primary_fatal_cov

* Simple ATT
estat simple
mat simple_fatal_primary = r(table)

* Event-study aggregation
estat event
mat es_fatal_primary = r(table)

* Pre-trend test
estat pretrend
local pretrend_fatal_p = r(p)
di "Pre-trend p-value (fatal, primary): `pretrend_fatal_p'"

* Event-study plot (Stata native)
csdid_plot, title("Primary: Fatal Crashes (w/ Controls)") ///
    style(rspike) ///
    name(primary_cov_fatal, replace)
graph export "`outdir'/primary_cov_event_fatal.png", replace width(1200)

* ── Alcohol crashes ─────────────────────────────────────────
di _n "--- Alcohol-Involved Fatal Crashes ---"
csdid alcohol_fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

estimates store primary_alc_cov

estat simple
mat simple_alc_primary = r(table)

estat event
mat es_alc_primary = r(table)

estat pretrend
local pretrend_alc_p = r(p)
di "Pre-trend p-value (alcohol, primary): `pretrend_alc_p'"

csdid_plot, title("Primary: Alcohol Crashes (w/ Controls)") ///
    style(rspike) ///
    name(primary_cov_alc, replace)
graph export "`outdir'/primary_cov_event_alcohol.png", replace width(1200)

* ── Per-capita fatal crashes ────────────────────────────────
di _n "--- Fatal Crashes Per Capita ---"
csdid fatal_crashes_pc `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

estimates store primary_fatal_pc

estat simple
estat event
estat pretrend
local pretrend_fatal_pc_p = r(p)
di "Pre-trend p-value (fatal pc, primary): `pretrend_fatal_pc_p'"

* ── Per-capita alcohol crashes ──────────────────────────────
di _n "--- Alcohol Crashes Per Capita ---"
csdid alcohol_crashes_pc `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

estimates store primary_alc_pc

estat simple
estat event
estat pretrend
local pretrend_alc_pc_p = r(p)
di "Pre-trend p-value (alcohol pc, primary): `pretrend_alc_pc_p'"


* ============================================================
* SECTION 4: ROBUSTNESS A — Add Always-Wet as Never-Treated
* ============================================================

di _n "============================================================"
di "ROBUSTNESS A: + Always-Wet Neighbors (DRIPW + Covariates)"
di "============================================================"

* ── Fatal crashes ───────────────────────────────────────────
di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar) ///
    method(dripw) long2

estimates store robA_fatal_cov

estat simple
mat simple_fatal_robA = r(table)

estat event
mat es_fatal_robA = r(table)

estat pretrend
local pretrend_fatal_robA = r(p)
di "Pre-trend p-value (fatal, robA): `pretrend_fatal_robA'"

csdid_plot, title("Robust A: Fatal Crashes (w/ Controls)") ///
    style(rspike) ///
    name(robA_cov_fatal, replace)
graph export "`outdir'/robA_cov_event_fatal.png", replace width(1200)

* ── Alcohol crashes ─────────────────────────────────────────
di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar) ///
    method(dripw) long2

estimates store robA_alc_cov

estat simple
mat simple_alc_robA = r(table)

estat event
mat es_alc_robA = r(table)

estat pretrend
local pretrend_alc_robA = r(p)
di "Pre-trend p-value (alcohol, robA): `pretrend_alc_robA'"

csdid_plot, title("Robust A: Alcohol Crashes (w/ Controls)") ///
    style(rspike) ///
    name(robA_cov_alc, replace)
graph export "`outdir'/robA_cov_event_alcohol.png", replace width(1200)


* ============================================================
* SECTION 5: ROBUSTNESS B — Pre-COVID (2008–2019), NYT
* ============================================================

di _n "============================================================"
di "ROBUSTNESS B: Pre-COVID (2008-2019), NYT + DRIPW + Covariates"
di "============================================================"

preserve
keep if year <= 2019

* ── Fatal crashes ───────────────────────────────────────────
di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

estimates store robB_fatal_cov

estat simple
mat simple_fatal_robB = r(table)

estat event
mat es_fatal_robB = r(table)

estat pretrend
local pretrend_fatal_robB = r(p)
di "Pre-trend p-value (fatal, robB): `pretrend_fatal_robB'"

csdid_plot, title("Robust B: Fatal Crashes, Pre-COVID (w/ Controls)") ///
    style(rspike) ///
    name(robB_cov_fatal, replace)
graph export "`outdir'/robB_cov_event_fatal.png", replace width(1200)

* ── Alcohol crashes ─────────────────────────────────────────
di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2

estimates store robB_alc_cov

estat simple
mat simple_alc_robB = r(table)

estat event
mat es_alc_robB = r(table)

estat pretrend
local pretrend_alc_robB = r(p)
di "Pre-trend p-value (alcohol, robB): `pretrend_alc_robB'"

csdid_plot, title("Robust B: Alcohol Crashes, Pre-COVID (w/ Controls)") ///
    style(rspike) ///
    name(robB_cov_alc, replace)
graph export "`outdir'/robB_cov_event_alcohol.png", replace width(1200)

restore


* ============================================================
* SECTION 6: ROBUSTNESS C — Regression Estimator, NYT
* ============================================================

di _n "============================================================"
di "ROBUSTNESS C: NYT + Regression Estimator + Covariates"
di "============================================================"
di "NOTE: With covariates, this differs from primary (DRIPW)."

* ── Fatal crashes ───────────────────────────────────────────
di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(reg) notyet long2

estimates store robC_fatal_cov

estat simple
mat simple_fatal_robC = r(table)

estat event
mat es_fatal_robC = r(table)

estat pretrend
local pretrend_fatal_robC = r(p)
di "Pre-trend p-value (fatal, robC): `pretrend_fatal_robC'"

csdid_plot, title("Robust C: Fatal Crashes, Regression (w/ Controls)") ///
    style(rspike) ///
    name(robC_cov_fatal, replace)
graph export "`outdir'/robC_cov_event_fatal.png", replace width(1200)

* ── Alcohol crashes ─────────────────────────────────────────
di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(reg) notyet long2

estimates store robC_alc_cov

estat simple
mat simple_alc_robC = r(table)

estat event
mat es_alc_robC = r(table)

estat pretrend
local pretrend_alc_robC = r(p)
di "Pre-trend p-value (alcohol, robC): `pretrend_alc_robC'"

csdid_plot, title("Robust C: Alcohol Crashes, Regression (w/ Controls)") ///
    style(rspike) ///
    name(robC_cov_alc, replace)
graph export "`outdir'/robC_cov_event_alcohol.png", replace width(1200)


* ============================================================
* SECTION 7: EXPORT EVENT-STUDY COEFFICIENTS TO CSV
* ============================================================

di _n "============================================================"
di "EXPORTING EVENT-STUDY COEFFICIENTS"
di "============================================================"

* Macro to export event-study matrix to CSV
capture program drop export_event_study
program define export_event_study
    args matname filename
    
    * Get matrix dimensions
    local nrows = rowsof(`matname')
    local ncols = colsof(`matname')
    
    * Open file
    tempname fh
    file open `fh' using "`filename'", write replace
    file write `fh' "event_time,coef,se,z,pvalue,ci_lower,ci_upper" _n
    
    * Row names contain event time info
    local rnames : rowfullnames `matname'
    
    forvalues i = 1/`nrows' {
        local rn : word `i' of `rnames'
        
        * Extract event time from row name (e.g., "Tp1" -> 1, "Tm2" -> -2)
        local et = ""
        if regexm("`rn'", "Tp([0-9]+)") {
            local et = regexs(1)
        }
        else if regexm("`rn'", "Tm([0-9]+)") {
            local et = "-" + regexs(1)
        }
        else if regexm("`rn'", "Pre_avg") {
            local et = "Pre_avg"
        }
        else if regexm("`rn'", "Post_avg") {
            local et = "Post_avg"
        }
        else {
            local et = "`rn'"
        }
        
        * b, se, z, p, ll, ul are rows 1-6 of r(table) transposed
        * Actually estat event stores in e(b) and r(table) format
        * r(table) has rows: b se t pvalue ll ul ...
        local b  = `matname'[1, `i']
        local se = `matname'[2, `i']
        local z  = `matname'[3, `i']
        local p  = `matname'[4, `i']
        local ll = `matname'[5, `i']
        local ul = `matname'[6, `i']
        
        file write `fh' "`et',`b',`se',`z',`p',`ll',`ul'" _n
    }
    
    file close `fh'
    di "  Saved: `filename'"
end

* Note: r(table) from estat event has COLUMNS as parameters, ROWS as stats
* So we need to work with the transposed structure. Let's use a simpler approach.

capture program drop export_es_v2
program define export_es_v2
    args estname outcome_label filename
    
    * Restore estimates and re-run estat event
    estimates restore `estname'
    estat event
    
    * r(table) has rows = stats (b, se, t, p, ll, ul), cols = parameters
    mat RT = r(table)
    local ncols = colsof(RT)
    local cnames : colfullnames RT
    
    tempname fh
    file open `fh' using "`filename'", write replace
    file write `fh' "parameter,event_time,coef,se,z,pvalue,ci_lower,ci_upper" _n
    
    forvalues j = 1/`ncols' {
        local cn : word `j' of `cnames'
        
        * Parse event time
        local et = ""
        if regexm("`cn'", "Tp([0-9]+)") {
            local et = regexs(1)
        }
        else if regexm("`cn'", "Tm([0-9]+)") {
            local et = "-" + regexs(1)
        }
        else if regexm("`cn'", "Pre_avg") {
            local et = "Pre_avg"
        }
        else if regexm("`cn'", "Post_avg") {
            local et = "Post_avg"
        }
        else {
            local et = "`cn'"
        }
        
        local b  = RT[1, `j']
        local se = RT[2, `j']
        local z  = RT[3, `j']
        local p  = RT[4, `j']
        local ll = RT[5, `j']
        local ul = RT[6, `j']
        
        file write `fh' "`cn',`et',`b',`se',`z',`p',`ll',`ul'" _n
    }
    
    file close `fh'
    di "  Saved: `filename'"
end

* Export all event-study CSVs
export_es_v2 primary_fatal_cov "fatal" "`outdir'/es_fatal_nyt_cov.csv"
export_es_v2 primary_alc_cov   "alcohol" "`outdir'/es_alcohol_nyt_cov.csv"
export_es_v2 robA_fatal_cov    "fatal" "`outdir'/es_fatal_robA_cov.csv"
export_es_v2 robA_alc_cov      "alcohol" "`outdir'/es_alcohol_robA_cov.csv"
export_es_v2 robB_fatal_cov    "fatal" "`outdir'/es_fatal_robB_cov.csv"
export_es_v2 robB_alc_cov      "alcohol" "`outdir'/es_alcohol_robB_cov.csv"
export_es_v2 robC_fatal_cov    "fatal" "`outdir'/es_fatal_robC_cov.csv"
export_es_v2 robC_alc_cov      "alcohol" "`outdir'/es_alcohol_robC_cov.csv"


* ============================================================
* SECTION 8: SUMMARY TABLE
* ============================================================

di _n "============================================================"
di "SUMMARY: SIMPLE ATTs (WITH COVARIATES)"
di "============================================================"
di ""
di "Spec                    | Fatal (SE)       | Alcohol (SE)"
di "------------------------|------------------|------------------"

* Retrieve simple ATTs from stored matrices
* simple ATT is the first column of the r(table) from estat simple
* We need to re-run estat simple for each

foreach spec in primary robA robB robC {
    foreach outcome in fatal alc {
        local estname = "`spec'_`outcome'_cov"
        capture estimates restore `estname'
        if _rc == 0 {
            quietly estat simple
            mat S_`spec'_`outcome' = r(table)
        }
    }
}

* Display
di "Primary (NYT, DRIPW)   |" %7.2f S_primary_fatal[1,1] " (" %4.2f S_primary_fatal[2,1] ") |" %7.2f S_primary_alc[1,1] " (" %4.2f S_primary_alc[2,1] ")"
di "Robust A (+ wet)       |" %7.2f S_robA_fatal[1,1] " (" %4.2f S_robA_fatal[2,1] ") |" %7.2f S_robA_alc[1,1] " (" %4.2f S_robA_alc[2,1] ")"
di "Robust B (pre-COVID)   |" %7.2f S_robB_fatal[1,1] " (" %4.2f S_robB_fatal[2,1] ") |" %7.2f S_robB_alc[1,1] " (" %4.2f S_robB_alc[2,1] ")"
di "Robust C (regression)  |" %7.2f S_robC_fatal[1,1] " (" %4.2f S_robC_fatal[2,1] ") |" %7.2f S_robC_alc[1,1] " (" %4.2f S_robC_alc[2,1] ")"


di _n "============================================================"
di "PRE-TREND P-VALUES (WITH COVARIATES)"
di "============================================================"
di ""
di "Spec                    | Fatal      | Alcohol"
di "------------------------|------------|--------"

* Re-run pretrend for each to get p-values
foreach spec in primary robA robC {
    foreach outcome in fatal alc {
        local estname = "`spec'_`outcome'_cov"
        capture estimates restore `estname'
        if _rc == 0 {
            quietly estat pretrend
            local pt_`spec'_`outcome' = r(p)
        }
    }
}

* Robustness B needs the restricted sample
preserve
keep if year <= 2019
foreach outcome in fatal alc {
    local estname = "robB_`outcome'_cov"
    capture estimates restore `estname'
    if _rc == 0 {
        quietly estat pretrend
        local pt_robB_`outcome' = r(p)
    }
}
restore

di "Primary (NYT, DRIPW)   |" %10.3f `pt_primary_fatal' " |" %8.3f `pt_primary_alc'
di "Robust A (+ wet)       |" %10.3f `pt_robA_fatal' " |" %8.3f `pt_robA_alc'
di "Robust B (pre-COVID)   |" %10.3f `pt_robB_fatal' " |" %8.3f `pt_robB_alc'
di "Robust C (regression)  |" %10.3f `pt_robC_fatal' " |" %8.3f `pt_robC_alc'


* ============================================================
* SECTION 9: EVENT-STUDY DYNAMICS TABLE (PRIMARY SPEC)
* ============================================================

di _n "============================================================"
di "EVENT-STUDY DYNAMICS: PRIMARY SPEC (NYT + DRIPW + Covariates)"
di "============================================================"

estimates restore primary_fatal_cov
estat event
mat ES_F = r(table)

estimates restore primary_alc_cov
estat event
mat ES_A = r(table)

di ""
di "Event Time | Fatal Coef (SE)     p     | Alcohol Coef (SE)     p"
di "-----------|-------------------------- |---------------------------"

local ncols_f = colsof(ES_F)
local cnames_f : colfullnames ES_F

forvalues j = 1/`ncols_f' {
    local cn : word `j' of `cnames_f'
    
    * Only display Tm and Tp rows
    if regexm("`cn'", "^T[mp][0-9]+$") {
        local b_f  = ES_F[1, `j']
        local se_f = ES_F[2, `j']
        local p_f  = ES_F[4, `j']
        
        * Find matching column in alcohol
        capture local b_a  = ES_A[1, `j']
        capture local se_a = ES_A[2, `j']
        capture local p_a  = ES_A[4, `j']
        
        di "   `cn'     |" %8.2f `b_f' " (" %5.2f `se_f' ")" %8.3f `p_f' " |" %8.2f `b_a' " (" %5.2f `se_a' ")" %8.3f `p_a'
    }
}


di _n "============================================================"
di "ESTIMATION COMPLETE"
di "============================================================"
di "Output directory: `outdir'/"
di "  Event-study CSVs for Python plotting pipeline"
di "  Stata event-study PNGs"
di ""
di "Covariates used:"
di "  `xvars'"
di ""
di "Next: Run event_study_plots_v3.py on exported CSVs"

log close _all
