*==============================================================
*  03_spillovers_v3.do
*  Arkansas Wet/Dry DiD -- Spillover Analysis, v3
*
*  PURPOSE:
*    Estimate the effect of neighbor counties' wet transitions
*    on fatal and alcohol-involved crashes in dry counties.
*    Tests the "attractor hypothesis" motivated by the rural
*    positive ATT in the direct-effect analysis (v3 run): are
*    dry counties with transitioning neighbors seeing crash
*    changes consistent with cross-border impaired-trip
*    redistribution?
*
*  DESIGN:
*    PATH A (primary): Staggered C&S-A with spillover cohorts
*      defined from the county adjacency workbook. Each dry
*      county's cohort = year of its FIRST treated-neighbor
*      transition. Clean never-spillover-treated dry counties
*      (9 of them) serve as never-treated controls -- a
*      comparison group that was unavailable in the direct-
*      effect analysis.
*
*    PATH B (robustness): Continuous spillover intensity.
*      TWFE with lagged share_wet_neighbors_main as a dose-
*      response regressor. Uses all 29 dry counties.
*
*  COVARIATE SPEC (matches direct-effect Primary+):
*    method(reg), xvars = log_pop poverty_rate
*
*  INPUTS:
*    arkansas_panel_annual_merged_v2.csv   (outcomes + ACS)
*    arkansas_alcohol_adjacency_and_panel.xlsx
*        -- sheet "adjacency_edges"          (pairwise edges)
*        -- sheet "neighbor_exposure"        (share_wet_neighbors)
*        -- sheet "county_summary"           (transition years)
*
*  OUTPUTS:
*    output_v3/spillover_v3_<spec>_<outcome>_event.csv  (18 files)
*    csdid_v3_spillover.log                             (full log)
*
*  NAMING CONVENTION (matches direct-effect v3):
*    spillover_v3_fatal_primaryplus_reg_event.csv
*    spillover_v3_alcohol_primaryplus_reg_event.csv
*    spillover_v3_<outcome>_dripw_event.csv
*    spillover_v3_<outcome>_nocov_event.csv
*    spillover_v3_<outcome>_rural_event.csv
*    spillover_v3_<outcome>_urban_event.csv
*    spillover_v3_<outcome>_pathb_continuous.csv
*==============================================================

clear all
set more off
capture log close
log using "csdid_v3_spillover.log", replace text

* --- Configure paths -----------------------------------------
* Adjust these to match your local setup.
local panel_csv  "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas/arkansas_panel_annual_merged_v2.csv"
local adj_xlsx   "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas/arkansas_alcohol_adjacency_and_panel.xlsx"
local outdir     "output_v3"

capture mkdir "`outdir'"

*==============================================================
* STEP 1: BUILD ADJACENCY + TRANSITION MAP -> SPILLOVER COHORTS
*==============================================================
* Produces a county-level lookup file (tempfile) with:
*   fips, first_treated_neighbor_year (0 if never)
*==============================================================

display _newline(2) "============================================"
display "STEP 1: Build spillover cohort lookup"
display "============================================"

* -- 1a. Import transition-year table from county_summary ---
import excel using "`adj_xlsx'", sheet("county_summary") firstrow clear

* Keep only counties with a confirmed countywide transition year.
* wet_start_year_main is either numeric (2010/2012/.../2022) or
* string "<=2009" for pre-sample wet counties.
capture confirm string variable wet_start_year_main
if _rc == 0 {
    gen long transition_year = real(wet_start_year_main)
}
else {
    gen long transition_year = wet_start_year_main
}

keep if current_status_main == "wet" & !missing(transition_year)
keep county_fips county transition_year
rename county_fips fips_str
rename county treated_neighbor_name

* fips stored as string "05007" etc in the xlsx; convert to numeric
gen long fips = real(fips_str)
drop fips_str
rename fips treated_fips
rename transition_year treated_year

tempfile transitions
save `transitions'

display as text "Transition counties loaded: "
count
list treated_neighbor_name treated_fips treated_year, clean noobs

* -- 1b. Import adjacency edges -----------------------------
import excel using "`adj_xlsx'", sheet("adjacency_edges") firstrow clear
rename county_fips fips_str
rename neighbor_fips nfips_str
gen long fips = real(fips_str)
gen long neighbor_fips = real(nfips_str)
keep fips neighbor_fips county neighbor_county

* -- 1c. Join transitions onto neighbor side ----------------
rename neighbor_fips treated_fips
merge m:1 treated_fips using `transitions', keep(match) nogenerate
rename treated_fips neighbor_fips

* At this point: one row per (dry-candidate fips, treated neighbor, year)
* Collapse to first treated-neighbor shock per dry candidate.
bysort fips (treated_year): keep if _n == 1
keep fips treated_year
rename treated_year first_treated_neighbor_year

tempfile spillover_cohorts
save `spillover_cohorts'

count
display as text "Counties with at least one treated neighbor: " r(N)

*==============================================================
* STEP 2: LOAD OUTCOME PANEL AND MERGE SPILLOVER COHORTS
*==============================================================

display _newline(2) "============================================"
display "STEP 2: Load outcome panel and merge cohort lookup"
display "============================================"

import delimited "`panel_csv'", clear varnames(1) case(lower)

* Confirm key variables exist
foreach v in fips year county fatal_crashes alcohol_fatal_crashes ///
             treated_unit countywide_wet total_pop poverty_rate {
    capture confirm variable `v'
    if _rc {
        display as error "MISSING VARIABLE: `v'"
        exit 111
    }
}

gen log_pop = log(total_pop)
label variable log_pop "Log total population (ACS)"

* Identify baseline wet/dry status from 2008 (or earliest year)
bysort fips (year): gen baseline_wet = countywide_wet[1]

* Restrict to always-dry counties: baseline dry AND never treated
keep if baseline_wet == 0 & treated_unit == 0
quietly levelsof fips, local(ndry)
display as text "Always-dry counties in sample: " `: word count `ndry''

* Merge cohort lookup
merge m:1 fips using `spillover_cohorts', keep(master match) nogenerate

* Spillover cohort = first-treated-neighbor year, or 0 if never
gen spillover_cohort = first_treated_neighbor_year
replace spillover_cohort = 0 if missing(first_treated_neighbor_year)

* Cohort diagnostic
display _newline "=== Spillover cohort distribution ==="
preserve
    keep fips county spillover_cohort
    duplicates drop
    tab spillover_cohort, missing
    list county spillover_cohort, sepby(spillover_cohort) noobs
restore

drop baseline_wet first_treated_neighbor_year

*==============================================================
* STEP 3: MERGE CONTINUOUS SPILLOVER INTENSITY (for Path B)
*==============================================================

preserve
    import excel using "`adj_xlsx'", sheet("neighbor_exposure") firstrow clear
    rename county_fips fips_str
    gen long fips = real(fips_str)
    keep fips year share_wet_neighbors_main wet_neighbors_main num_neighbors
    rename share_wet_neighbors_main share_wet_nbr
    rename wet_neighbors_main n_wet_nbr
    rename num_neighbors n_nbr
    tempfile exposure
    save `exposure'
restore

merge 1:1 fips year using `exposure', keep(master match) nogenerate

* Backfill 2008-2009 with 2010 values (no transitions pre-2010,
* so share_wet_nbr is identical)
bysort fips (year): replace share_wet_nbr = share_wet_nbr[_n+1] if missing(share_wet_nbr) & year < 2010
bysort fips (year): replace share_wet_nbr = share_wet_nbr[_n+1] if missing(share_wet_nbr) & year < 2010
bysort fips (year): replace n_wet_nbr = n_wet_nbr[_n+1] if missing(n_wet_nbr) & year < 2010
bysort fips (year): replace n_wet_nbr = n_wet_nbr[_n+1] if missing(n_wet_nbr) & year < 2010
bysort fips (year): replace n_nbr = n_nbr[_n+1] if missing(n_nbr) & year < 2010
bysort fips (year): replace n_nbr = n_nbr[_n+1] if missing(n_nbr) & year < 2010

* Lagged share_wet_neighbors for dose-response
xtset fips year
gen L_share_wet_nbr = L.share_wet_nbr
gen D_share_wet_nbr = D.share_wet_nbr

* Baseline population for rural/urban stratification
bysort fips (year): gen pop_baseline = total_pop[1]
gen rural = pop_baseline < 20000
label define ruralurb 0 "Urban (pop>=20k)" 1 "Rural (pop<20k)"
label values rural ruralurb

save spillover_analysis_panel.dta, replace

*==============================================================
* STEP 4: PATH A -- C&S-A SPILLOVER ESTIMATION
*==============================================================
*
* Reusable helper. Exports event-study coefficients to a CSV.
*==============================================================

capture program drop run_cs_spillover
program define run_cs_spillover
    syntax, OUTcome(varname) METHod(string) TAG(string) ///
        [ COVars(string) SUBsample(string) ]

    display _newline(2) "=============================================="
    display "SPEC: `tag' | outcome=`outcome' | method=`method'"
    display "      covars=[`covars']  subsample=[`subsample']"
    display "=============================================="

    * Single preserve at the top handles both subsample restriction
    * and the export-dataset build, avoiding nested preserve/restore
    * (Stata supports only one level of preserve).
    preserve

    if "`subsample'" != "" {
        keep if `subsample'
    }

    capture noisily csdid `outcome' `covars', ///
        ivar(fips) time(year) gvar(spillover_cohort) ///
        method(`method') notyet
    local rc = _rc
    if `rc' != 0 {
        display as error "csdid failed with rc=`rc' for `tag'"
        restore
        exit
    }

    capture noisily estat simple
    capture noisily estat pretrend
    capture noisily estat event, window(-5 5)

    * Export event-study coefs
    capture noisily estat event, window(-5 5) post
    if _rc != 0 {
        display as error "estat event failed for `tag'; skipping export"
        restore
        exit
    }

    matrix b = e(b)
    matrix V = e(V)

    * Build export dataset in-place (we're already inside preserve,
    * so clearing data here is safe -- restore at the end recovers).
    clear
    local colnames : colnames b
    local ncoef : word count `colnames'
    set obs `ncoef'
    gen coef_name = ""
    gen coef = .
    gen se = .
    forvalues i = 1/`ncoef' {
        local nm : word `i' of `colnames'
        replace coef_name = "`nm'" in `i'
        replace coef = b[1,`i'] in `i'
        replace se = sqrt(V[`i',`i']) in `i'
    }
    export delimited using "output_v3/spillover_v3_`tag'_event.csv", replace

    * ------------------------------------------------------
    * Build event-study plot from the exported coefs.
    * csdid_plot does not support event-study aggregation
    * (only group-specific plots), so we build it manually.
    * ------------------------------------------------------
    *
    * Filter to event-time coefs only (Tm* and Tp*), extract
    * the event-time integer, compute CIs, and plot.
    gen byte keep_row = regexm(coef_name, "^Tm[0-9]+$") | regexm(coef_name, "^Tp[0-9]+$")
    keep if keep_row == 1
    gen event_time = real(regexr(coef_name, "^T[mp]", ""))
    replace event_time = -event_time if regexm(coef_name, "^Tm")
    gen ci_lo = coef - 1.96*se
    gen ci_hi = coef + 1.96*se
    sort event_time

    * Navy/gold palette via RGB tuples. Requires Stata 15+ for
    * direct RGB color specification; falls back to named colors
    * if the twoway call fails.
    capture noisily twoway ///
        (rarea ci_lo ci_hi event_time, color("140 155 181") fintensity(30) lwidth(none)) ///
        (line coef event_time, lcolor("26 39 68") lwidth(medthick)) ///
        (scatter coef event_time, mcolor("201 168 76") msize(medium) msymbol(O)) ///
        , ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(-0.5, lcolor("201 168 76") lpattern(dash) lwidth(medthin)) ///
        xlabel(-5(1)5, nogrid) ///
        ylabel(, nogrid angle(0)) ///
        xtitle("Event time (years since first wet neighbor)") ///
        ytitle("ATT: `outcome'") ///
        title("Spillover event study: `tag'", size(medsmall)) ///
        subtitle("95% CI; C&S-A with never-treated controls", size(small)) ///
        legend(off) ///
        graphregion(color(white)) plotregion(color(white)) ///
        name(es_`tag', replace)

    if _rc != 0 {
        * RGB failed (older Stata); retry with named colors
        capture noisily twoway ///
            (rarea ci_lo ci_hi event_time, color(gs12) lwidth(none)) ///
            (line coef event_time, lcolor(navy) lwidth(medthick)) ///
            (scatter coef event_time, mcolor(gold) msize(medium) msymbol(O)) ///
            , ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(-0.5, lcolor(gold) lpattern(dash) lwidth(medthin)) ///
            xlabel(-5(1)5, nogrid) ///
            ylabel(, nogrid angle(0)) ///
            xtitle("Event time (years since first wet neighbor)") ///
            ytitle("ATT: `outcome'") ///
            title("Spillover event study: `tag'", size(medsmall)) ///
            subtitle("95% CI; C&S-A with never-treated controls", size(small)) ///
            legend(off) ///
            graphregion(color(white)) plotregion(color(white)) ///
            name(es_`tag', replace)
    }

    capture noisily graph export "output_v3/spillover_v3_`tag'_event.png", ///
        name(es_`tag') replace width(1800)

    restore
end

* -- 4a. PRIMARY+ REG (two outcomes) ------------------------
run_cs_spillover, outcome(fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(fatal_primaryplus_reg)

run_cs_spillover, outcome(alcohol_fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(alcohol_primaryplus_reg)

* -- 4b. DRIPW with log_pop only (robustness) ---------------
run_cs_spillover, outcome(fatal_crashes) method(dripw) ///
    covars(log_pop) tag(fatal_dripw)

run_cs_spillover, outcome(alcohol_fatal_crashes) method(dripw) ///
    covars(log_pop) tag(alcohol_dripw)

* -- 4c. No-covariate baseline ------------------------------
run_cs_spillover, outcome(fatal_crashes) method(dripw) ///
    tag(fatal_nocov)

run_cs_spillover, outcome(alcohol_fatal_crashes) method(dripw) ///
    tag(alcohol_nocov)

* -- 4d. Rural/urban stratification (Primary+ REG) ----------
run_cs_spillover, outcome(fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(fatal_rural) ///
    subsample(rural == 1)

run_cs_spillover, outcome(alcohol_fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(alcohol_rural) ///
    subsample(rural == 1)

run_cs_spillover, outcome(fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(fatal_urban) ///
    subsample(rural == 0)

run_cs_spillover, outcome(alcohol_fatal_crashes) method(reg) ///
    covars(log_pop poverty_rate) tag(alcohol_urban) ///
    subsample(rural == 0)

*==============================================================
* STEP 5: PATH B -- CONTINUOUS SPILLOVER INTENSITY (TWFE)
*==============================================================
*
* Dose-response specification: outcomes on lagged share of wet
* neighbors, with county + year fixed effects and clustered SEs.
* Uses all 29 always-dry counties (no cohort restriction).
*==============================================================

display _newline(2) "============================================"
display "PATH B: Continuous spillover intensity (TWFE)"
display "============================================"

* -- 5a. Contemporaneous + lagged share -----------------------
foreach outcome in fatal_crashes alcohol_fatal_crashes {
    display _newline "--- TWFE: `outcome' on share_wet_nbr ---"

    * Contemporaneous share
    capture noisily reghdfe `outcome' share_wet_nbr log_pop poverty_rate, ///
        absorb(fips year) vce(cluster fips)
    if _rc == 199 {
        display as error "reghdfe not installed. Install with: ssc install reghdfe"
        display as text "Falling back to xtreg, fe"
        capture noisily xtreg `outcome' share_wet_nbr log_pop poverty_rate i.year, ///
            fe vce(cluster fips)
    }

    * Lagged share (dose-response avoiding simultaneity)
    display _newline "--- TWFE: `outcome' on L.share_wet_nbr ---"
    capture noisily reghdfe `outcome' L_share_wet_nbr log_pop poverty_rate, ///
        absorb(fips year) vce(cluster fips)
    if _rc == 199 {
        capture noisily xtreg `outcome' L_share_wet_nbr log_pop poverty_rate i.year, ///
            fe vce(cluster fips)
    }

    * Change in share (first-difference / dynamic)
    display _newline "--- TWFE: `outcome' on D.share_wet_nbr ---"
    capture noisily reghdfe `outcome' D_share_wet_nbr log_pop poverty_rate, ///
        absorb(fips year) vce(cluster fips)
    if _rc == 199 {
        capture noisily xtreg `outcome' D_share_wet_nbr log_pop poverty_rate i.year, ///
            fe vce(cluster fips)
    }
}

* -- 5b. Export continuous-spec coefficients ----------------
* Collect the three specs per outcome into one CSV each.

foreach outcome in fatal_crashes alcohol_fatal_crashes {
    tempname results
    postfile `results' str20 spec double(coef se t pval) using ///
        "output_v3/spillover_v3_`outcome'_pathb_continuous.csv", replace

    foreach regressor in share_wet_nbr L_share_wet_nbr D_share_wet_nbr {
        capture noisily reghdfe `outcome' `regressor' log_pop poverty_rate, ///
            absorb(fips year) vce(cluster fips)
        if _rc == 0 {
            local b = _b[`regressor']
            local se = _se[`regressor']
            local t = `b' / `se'
            local p = 2*(1 - normal(abs(`t')))
            post `results' ("`regressor'") (`b') (`se') (`t') (`p')
        }
    }
    postclose `results'
}

* Convert .dta exports to CSV so all outputs use CSV format
foreach outcome in fatal_crashes alcohol_fatal_crashes {
    preserve
        use "output_v3/spillover_v3_`outcome'_pathb_continuous.csv", clear
        export delimited "output_v3/spillover_v3_`outcome'_pathb_continuous.csv", replace
    restore
}

*==============================================================
* STEP 6: RURAL/URBAN PATH B
*==============================================================
*
* Dose-response split by baseline population.
*==============================================================

display _newline(2) "============================================"
display "PATH B: Rural/urban stratification"
display "============================================"

foreach outcome in fatal_crashes alcohol_fatal_crashes {
    foreach r in 1 0 {
        local label = cond(`r' == 1, "rural", "urban")
        display _newline "--- TWFE: `outcome' | `label' | L.share_wet_nbr ---"
        capture noisily reghdfe `outcome' L_share_wet_nbr log_pop poverty_rate ///
            if rural == `r', absorb(fips year) vce(cluster fips)
        if _rc == 199 {
            capture noisily xtreg `outcome' L_share_wet_nbr log_pop poverty_rate i.year ///
                if rural == `r', fe vce(cluster fips)
        }
    }
}

*==============================================================
* STEP 7: CLEAN UP
*==============================================================

capture erase spillover_analysis_panel.dta

log close
display _newline "=== 03_spillovers_v3.do complete ==="
display "Outputs in output_v3/: 12 C&S-A event CSVs + 2 Path B CSVs"
display "Log: csdid_v3_spillover.log"
