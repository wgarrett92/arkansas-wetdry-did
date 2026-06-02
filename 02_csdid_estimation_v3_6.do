/*
============================================================
  02_csdid_estimation_v3.do
  Callaway & Sant'Anna (2021) Estimation WITH Covariates
  Arkansas Wet/Dry County DiD Panel
  
  Input:  arkansas_panel_annual_merged_v2.csv
  Output: Event-study CSVs, pre-trend diagnostics, ATT tables
  
  SPECIFICATION STRUCTURE:
    Primary:    DRIPW, NYT, log_pop only
    Primary+:   DRIPW, NYT, log_pop + poverty_rate
    Robust A:   DRIPW, + always-wet comparison, log_pop
    Robust B:   DRIPW, NYT, pre-COVID (2008-2019), log_pop
    Robust C:   method(reg), NYT, full covariates (7 vars)
    Robust D:   DRIPW, NYT, no covariates (v2 baseline)
    Hetero:     Rural vs urban split (pop < 20,000)
  
  Full covariate set (7 vars, Robust C only):
    log_pop, median_hh_income, poverty_rate, pct_white,
    pct_21plus, churches_pc, pct_married
  
  Note on DRIPW covariate limits:
    Single-county cohorts (g2016=Little River, g2018=Randolph)
    are omitted when covariates enter the propensity score.
    This is a mechanical small-sample constraint documented
    in the paper, not a specification error.
============================================================
*/

clear all
capture log close
log using "csdid_v3_results.log", replace text
set more off
set matsize 5000

* ── Set paths (EDIT THESE) ──────────────────────────────────
* cd "/path/to/your/project"

local datafile "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas/arkansas_panel_annual_merged_v2.csv"
local outdir   "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas/output_v3"
capture mkdir "`outdir'"


* ============================================================
* SECTION 1: DATA IMPORT AND PANEL SETUP
* ============================================================

import delimited "`datafile'", clear varnames(1) case(lower)

egen county_id = group(fips)

gen gvar_nyt = .
replace gvar_nyt = cohort if treated_unit == 1

gen gvar = .
replace gvar = cohort if treated_unit == 1
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

gen event_time = year - cohort if treated_unit == 1

xtset county_id year


* ============================================================
* SECTION 2: CONSTRUCT COVARIATES
* ============================================================

gen log_pop = ln(total_pop)

* Rural indicator for heterogeneity split (median ~19k, cutoff 20k)
gen rural = (total_pop < 20000)
label define rural_lbl 0 "Urban (pop >= 20k)" 1 "Rural (pop < 20k)"
label values rural rural_lbl

* Base-period rural status (time-invariant)
bysort county_id (year): gen rural_base = rural[1]

* Covariate sets
local xvars1 log_pop
local xvars2 log_pop poverty_rate
local xvars_full log_pop median_hh_income poverty_rate pct_white pct_21plus churches_pc pct_married

* Check for missing
foreach v in `xvars_full' {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "WARNING: `v' has `r(N)' missing values"
    }
}

di _n "============================================================"
di "COVARIATE SUMMARY STATISTICS"
di "============================================================"
tabstat `xvars_full', stats(mean sd min max n) columns(statistics) format(%9.3f)

di _n "RURAL/URBAN SPLIT (cutoff: pop < 20,000)"
tab rural treated_unit


* ============================================================
* HELPER: Export event-study coefficients to CSV
* ============================================================

capture program drop export_es
program define export_es
    args estname filename
    
    estimates restore `estname'
    quietly estat event
    
    mat RT = r(table)
    local ncols = colsof(RT)
    local cnames : colfullnames RT
    
    tempname fh
    file open `fh' using "`filename'", write replace
    file write `fh' "parameter,event_time,coef,se,z,pvalue,ci_lower,ci_upper" _n
    
    forvalues j = 1/`ncols' {
        local cn : word `j' of `cnames'
        
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


* ============================================================
* HELPER: Run estat simple/event/pretrend with capture
* ============================================================

capture program drop run_spec
program define run_spec
    args estname
    
    * estat simple
    estimates restore `estname'
    capture noisily estat simple
    if _rc == 0 {
        mat S_`estname' = r(table)
    }
    else {
        di as error "  estat simple FAILED for `estname' (rc=" _rc ")"
    }
    
    * estat event
    estimates restore `estname'
    capture noisily estat event
    if _rc == 0 {
        mat ES_`estname' = r(table)
    }
    else {
        di as error "  estat event FAILED for `estname' (rc=" _rc ")"
    }
    
    * estat pretrend
    estimates restore `estname'
    capture noisily estat pretrend
    if _rc == 0 {
        di "  Pre-trend p-value: " r(p)
    }
    else {
        di as error "  estat pretrend FAILED for `estname' (rc=" _rc ")"
    }
end


* ============================================================
* SECTION 3: PRIMARY — DRIPW, NYT, log_pop
* ============================================================

di _n "============================================================"
di "PRIMARY: DRIPW + NYT + log_pop"
di "============================================================"

di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store pri_fatal
run_spec pri_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store pri_alc
run_spec pri_alc

di _n "--- Fatal Crashes Per Capita ---"
csdid fatal_crashes_pc `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store pri_fatal_pc
run_spec pri_fatal_pc

di _n "--- Alcohol Crashes Per Capita ---"
csdid alcohol_crashes_pc `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store pri_alc_pc
run_spec pri_alc_pc


* ============================================================
* SECTION 4: PRIMARY+ — DRIPW, NYT, log_pop + poverty_rate
* ============================================================

di _n "============================================================"
di "PRIMARY+: DRIPW + NYT + log_pop + poverty_rate"
di "============================================================"

di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars2', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store prip_fatal
run_spec prip_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars2', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store prip_alc
run_spec prip_alc


* ============================================================
* SECTION 5: ROBUSTNESS A — + Always-Wet, DRIPW, log_pop
* ============================================================

di _n "============================================================"
di "ROBUST A: + Always-Wet Comparison + DRIPW + log_pop"
di "============================================================"

di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar) ///
    method(dripw) long2
estimates store robA_fatal
run_spec robA_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar) ///
    method(dripw) long2
estimates store robA_alc
run_spec robA_alc


* ============================================================
* SECTION 6: ROBUSTNESS B — Pre-COVID (2008-2019), NYT, log_pop
* ============================================================

di _n "============================================================"
di "ROBUST B: Pre-COVID (2008-2019) + DRIPW + NYT + log_pop"
di "============================================================"
di "NOTE: g2020 and g2022 have no post-treatment obs in this sample."
di "      g2018 has only 1 post-treatment year (2019)."

preserve
keep if year <= 2019

di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store robB_fatal
run_spec robB_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars1', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store robB_alc
run_spec robB_alc

restore


* ============================================================
* SECTION 7: ROBUSTNESS C — Regression, NYT, full covariates
* ============================================================

di _n "============================================================"
di "ROBUST C: method(reg) + NYT + FULL covariates (7 vars)"
di "============================================================"
di "Covariates: `xvars_full'"
di "NOTE: Single-county cohorts may show near-zero SEs (numerical singularity)."

di _n "--- Fatal Crashes ---"
csdid fatal_crashes `xvars_full', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(reg) notyet long2
estimates store robC_fatal
run_spec robC_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars_full', ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(reg) notyet long2
estimates store robC_alc
run_spec robC_alc


* ============================================================
* SECTION 8: ROBUSTNESS D — No covariates (v2 baseline)
* ============================================================

di _n "============================================================"
di "ROBUST D: DRIPW + NYT + NO covariates"
di "============================================================"

di _n "--- Fatal Crashes ---"
csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store robD_fatal
run_spec robD_fatal

di _n "--- Alcohol Crashes ---"
csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store robD_alc
run_spec robD_alc


* ============================================================
* SECTION 9: HETEROGENEITY — Rural vs Urban split
* ============================================================

di _n "============================================================"
di "HETEROGENEITY: Rural (pop < 20k) vs Urban (pop >= 20k)"
di "============================================================"
di "Rural treated:  Little River, Van Buren, Sharp, Sevier, Randolph"
di "Urban treated:  Clark, Columbia, Polk, Boone, Hot Spring, Saline, Benton"

* ── Rural subsample ─────────────────────────────────────────
di _n "--- RURAL: Fatal Crashes ---"
csdid fatal_crashes `xvars1' if rural_base == 1, ///
    ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store het_rural_fatal
run_spec het_rural_fatal

di _n "--- RURAL: Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars1' if rural_base == 1, ///
    ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store het_rural_alc
run_spec het_rural_alc

* ── Urban subsample ─────────────────────────────────────────
di _n "--- URBAN: Fatal Crashes ---"
csdid fatal_crashes `xvars1' if rural_base == 0, ///
    ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store het_urban_fatal
run_spec het_urban_fatal

di _n "--- URBAN: Alcohol Crashes ---"
csdid alcohol_fatal_crashes `xvars1' if rural_base == 0, ///
    ivar(county_id) time(year) gvar(gvar_nyt) ///
    method(dripw) notyet long2
estimates store het_urban_alc
run_spec het_urban_alc


* ============================================================
* SECTION 10: EXPORT ALL EVENT-STUDY CSVs
* ============================================================

di _n "============================================================"
di "EXPORTING EVENT-STUDY COEFFICIENTS"
di "============================================================"

* Primary
capture export_es pri_fatal       "`outdir'/es_fatal_primary.csv"
capture export_es pri_alc         "`outdir'/es_alcohol_primary.csv"
capture export_es pri_fatal_pc    "`outdir'/es_fatal_pc_primary.csv"
capture export_es pri_alc_pc      "`outdir'/es_alcohol_pc_primary.csv"

* Primary+
capture export_es prip_fatal      "`outdir'/es_fatal_primaryplus.csv"
capture export_es prip_alc        "`outdir'/es_alcohol_primaryplus.csv"

* Robustness A–D
capture export_es robA_fatal      "`outdir'/es_fatal_robA.csv"
capture export_es robA_alc        "`outdir'/es_alcohol_robA.csv"
capture export_es robB_fatal      "`outdir'/es_fatal_robB.csv"
capture export_es robB_alc        "`outdir'/es_alcohol_robB.csv"
capture export_es robC_fatal      "`outdir'/es_fatal_robC.csv"
capture export_es robC_alc        "`outdir'/es_alcohol_robC.csv"
capture export_es robD_fatal      "`outdir'/es_fatal_robD.csv"
capture export_es robD_alc        "`outdir'/es_alcohol_robD.csv"

* Heterogeneity
capture export_es het_rural_fatal "`outdir'/es_fatal_rural.csv"
capture export_es het_rural_alc   "`outdir'/es_alcohol_rural.csv"
capture export_es het_urban_fatal "`outdir'/es_fatal_urban.csv"
capture export_es het_urban_alc   "`outdir'/es_alcohol_urban.csv"


* ============================================================
* SECTION 11: SUMMARY TABLES
* ============================================================

di _n "============================================================"
di "SUMMARY: SIMPLE ATTs"
di "============================================================"
di ""
di "Spec                      | Fatal (SE)         | Alcohol (SE)"
di "--------------------------|--------------------|-----------------"

* Re-extract simple ATTs for display (some may have failed above)
foreach est in pri prip robA robB robC robD {
    foreach out in fatal alc {
        local nm = "`est'_`out'"
        capture {
            estimates restore `nm'
            quietly estat simple
            mat S_`nm' = r(table)
        }
    }
}

* Display with capture for any that failed
capture di "Primary (log_pop)         |" %7.2f S_pri_fatal[1,1]  " (" %4.2f S_pri_fatal[2,1]  ") |" %7.2f S_pri_alc[1,1]  " (" %4.2f S_pri_alc[2,1]  ")"
capture di "Primary+ (+ poverty)      |" %7.2f S_prip_fatal[1,1] " (" %4.2f S_prip_fatal[2,1] ") |" %7.2f S_prip_alc[1,1] " (" %4.2f S_prip_alc[2,1] ")"
capture di "Robust A (+ wet comp)     |" %7.2f S_robA_fatal[1,1] " (" %4.2f S_robA_fatal[2,1] ") |" %7.2f S_robA_alc[1,1] " (" %4.2f S_robA_alc[2,1] ")"
capture di "Robust B (pre-COVID)      |" %7.2f S_robB_fatal[1,1] " (" %4.2f S_robB_fatal[2,1] ") |" %7.2f S_robB_alc[1,1] " (" %4.2f S_robB_alc[2,1] ")"
capture di "Robust C (reg, full cov)  |" %7.2f S_robC_fatal[1,1] " (" %4.2f S_robC_fatal[2,1] ") |" %7.2f S_robC_alc[1,1] " (" %4.2f S_robC_alc[2,1] ")"
capture di "Robust D (no covariates)  |" %7.2f S_robD_fatal[1,1] " (" %4.2f S_robD_fatal[2,1] ") |" %7.2f S_robD_alc[1,1] " (" %4.2f S_robD_alc[2,1] ")"

di ""
di "HETEROGENEITY (DRIPW, NYT, log_pop):"
di "--------------------------|--------------------|-----------------"

foreach est in het_rural het_urban {
    foreach out in fatal alc {
        local nm = "`est'_`out'"
        capture {
            estimates restore `nm'
            quietly estat simple
            mat S_`nm' = r(table)
        }
    }
}

capture di "Rural (pop < 20k)         |" %7.2f S_het_rural_fatal[1,1] " (" %4.2f S_het_rural_fatal[2,1] ") |" %7.2f S_het_rural_alc[1,1] " (" %4.2f S_het_rural_alc[2,1] ")"
capture di "Urban (pop >= 20k)        |" %7.2f S_het_urban_fatal[1,1] " (" %4.2f S_het_urban_fatal[2,1] ") |" %7.2f S_het_urban_alc[1,1] " (" %4.2f S_het_urban_alc[2,1] ")"


* ============================================================
* SECTION 12: EVENT-STUDY DYNAMICS (PRIMARY SPEC)
* ============================================================

di _n "============================================================"
di "EVENT-STUDY DYNAMICS: PRIMARY (DRIPW + log_pop)"
di "============================================================"

estimates restore pri_fatal
estat event
mat ES_F = r(table)

estimates restore pri_alc
estat event
mat ES_A = r(table)

di ""
di "Event Time | Fatal Coef (SE)     p     | Alcohol Coef (SE)     p"
di "-----------|---------------------------|---------------------------"

local ncols_f = colsof(ES_F)
local cnames_f : colfullnames ES_F

forvalues j = 1/`ncols_f' {
    local cn : word `j' of `cnames_f'
    
    if regexm("`cn'", "^T[mp][0-9]+$") {
        local b_f  = ES_F[1, `j']
        local se_f = ES_F[2, `j']
        local p_f  = ES_F[4, `j']
        
        capture local b_a  = ES_A[1, `j']
        capture local se_a = ES_A[2, `j']
        capture local p_a  = ES_A[4, `j']
        
        di "   `cn'     |" %8.2f `b_f' " (" %5.2f `se_f' ")" %8.3f `p_f' " |" %8.2f `b_a' " (" %5.2f `se_a' ")" %8.3f `p_a'
    }
}


di _n "============================================================"
di "ESTIMATION COMPLETE"
di "============================================================"
di "Output: `outdir'/"
di "  Up to 20 event-study CSVs for Python plotting pipeline"
di ""
di "Specs:"
di "  Primary:    DRIPW, NYT, log_pop"
di "  Primary+:   DRIPW, NYT, log_pop + poverty_rate"
di "  Robust A:   DRIPW, + always-wet, log_pop"
di "  Robust B:   DRIPW, NYT, pre-COVID, log_pop"
di "  Robust C:   Regression, NYT, full (7 vars)"
di "  Robust D:   DRIPW, NYT, no covariates"
di "  Hetero:     Rural (pop<20k) vs Urban, DRIPW, NYT, log_pop"
di ""
di "Full covariate set (Robust C):"
di "  `xvars_full'"
di ""
di "Next: event_study_plots_v3.py"
log close
