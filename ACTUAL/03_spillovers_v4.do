*==============================================================
*  03_spillovers_v4.do
*  Arkansas Wet/Dry DiD -- Spillover Analysis, v4 (post-recode)
*
*  PURPOSE: unchanged from v3 -- effect of neighbor wet transitions
*  on crashes in always-dry counties (attractor redistribution test).
*  The paper's symmetry check: rural spillover ATT vs rural direct ATT
*  (pre-recode: -1.19 vs +1.38; THIS RUN re-tests that under the
*  corrected coding -- treat the old numbers as unverified until then).
*
*  v4 CHANGES vs 03_spillovers_v3_3.do (2026-07-01):
*   1. INPUT = canonical 84-col rucc_origin panel. The Excel adjacency
*      workbook is RETIRED: it predates the Madison/Sebastian recode
*      (Madison absent as a 2012 transitioner; Sebastian coded dry).
*   2. SPILLOVER COHORTS rebuilt from the panel's post-recode neighbor
*      counts (PLACE-1 output, runbook Steps 1-2): cohort = first year
*      n_wet_neighbors INCREMENTS. Always-wet neighbors sit in the 2008
*      baseline level; partial-wet units (Sebastian/Logan/Woodruff) are
*      wet all-window -> neither creates spurious events; an in-sample
*      increment can only be a NEWLY-transitioning in-state neighbor
*      (the R2-corrected definition). Madison's 2012 vote now generates
*      2012 events for its dry neighbors. OOS changes (TX 2013) touch
*      only the _aug columns and are deliberately NOT events here --
*      different policy margin; noted as a possible extension.
*   3. SAMPLE = always_dry==1 from patch_madison_sebastian.do. v3's
*      baseline_wet filter would wrongly keep Sebastian/Logan/Woodruff
*      in the dry spillover pool.
*   4. CLASSIFIER = RUCC rural_2013 (log #9); 20k cutoff retired.
*   5. OUTCOMES add nonalc_fatal_crashes (mechanism decomposition #8):
*      if the attractor relocates traffic, dry neighbors shed exposure
*      too -- nonalc spillover should share the sign.
*   6. csdid DISCIPLINE: estimates store/restore before EACH estat (#2);
*      Pre_avg + p from estat event; joint pretrend reported via r(pchi2)
*      but NOT judged (#15).
*   7. Consolidated collector -> spillover_v4_results.csv (att, p,
*      Pre_avg, n per spec) alongside the per-spec event CSVs + plots.
*   8. v4.1 (2026-07-01, R14 FIX): the panel's OWN neighbor columns are
*      defective -- countywide_wet is wet-all-window for Boone/Clark (g2010),
*      so n_wet_neighbors misses ALL 2010 events (and, pre-recode, Madison's
*      2012 events). Spillover cohorts + Path B shares now come from
*      neighbor_counts_corrected.csv (rebuild_neighbor_counts.py: Plotly
*      geojson adjacency x the PLACE-2 wet timeline; STAGE-A validated by
*      reproducing n_wet_neighbors_instate_chk 1200/1200 under the PLACE-1
*      timeline). Do NOT revert to the ARCHIVED panel's columns.
*      See ANALYSIS_LOG R15/#24.
*   9. v4.2 (2026-07-01, R15 PORT, ANALYSIS_LOG #25): the v2 panel
*      (..._rucc_origin_v2.csv) carries CORRECTED neighbor columns at rest
*      (gates G1-G7 in R15_PORT_GATELOG.txt). When it is present we ASSERT
*      its columns equal neighbor_counts_corrected.csv on all 1200 cells and
*      then PREFER the panel columns; the runtime merge stays as the
*      verification path (and as the fallback for the archived panel).
*      Estimation design unchanged -- v4.1 results are final per #24.
*
*  INPUTS (run from ACTUAL/):
*    arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv   (preferred)
*    (fallback: arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv)
*    patch_madison_sebastian.do
*  OUTPUTS:
*    output/spillover_v4_<tag>_event.csv + .png   (per spec)
*    spillover_v4_results.csv                     (summary table)
*    csdid_v4_spillover.log
*  When done: append ANALYSIS_LOG PART-A entry #19; compare the rural
*  spillover ATT against the rural direct ATT from het_rucc_results.csv.
*==============================================================

clear all
set more off
capture log close
log using "csdid_v4_spillover.log", replace text

* R15 PORT (v4.2): prefer the corrected-at-rest v2 panel (#25); fall back to
* the archived panel + runtime neighbor merge if the v2 file is absent.
local panel_csv "arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv"
local panel_v2  1
capture confirm file "`panel_csv'"
if _rc {
    local panel_csv "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv"
    local panel_v2  0
    display as error "WARN: v2 panel not found -- using the ARCHIVED panel; " ///
        "neighbor columns come from neighbor_counts_corrected.csv at run time."
}
local outdir    "output"
capture mkdir "`outdir'"

*==============================================================
* STEP 1: LOAD PANEL + RECODE (treatment coding owned by the patch)
*==============================================================
import delimited "`panel_csv'", clear varnames(1)
destring fips year fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
    countywide_wet first_treated_year cohort treated_unit neighbor_unit ///
    total_pop poverty_rate rural_2013 n_wet_neighbors n_neighbors ///
    share_wet_neighbors n_wet_neighbors_aug share_wet_neighbors_aug, ///
    replace force
do patch_madison_sebastian.do    // Madison g2012; est_sample; always_dry; log_pop

* R14 FIX: corrected neighbor counts/shares (rebuild_neighbor_counts.py)
preserve
    import delimited "neighbor_counts_corrected.csv", varnames(1) clear
    destring fips year n_wet_corr share_wet_corr n_aug_corr share_aug_corr, ///
        replace force
    tempfile nbrcorr
    save `nbrcorr'
restore
merge 1:1 fips year using `nbrcorr', assert(match) nogen

* R15 PORT (v4.2): with the v2 panel, ASSERT its at-rest neighbor columns
* equal the certified artifact on all 1200 cells, then PREFER the panel
* columns (the corrected file stays merged purely as the verification path).
if `panel_v2' {
    display as text "R15-port assert: v2 panel columns vs neighbor_counts_corrected.csv"
    quietly count if n_wet_neighbors != n_wet_corr
    if r(N) {
        display as error "FATAL: n_wet_neighbors != n_wet_corr in " r(N) ///
            " cells -- v2 panel and certified artifact disagree."
        error 459
    }
    quietly count if abs(share_wet_neighbors - share_wet_corr) > 1e-4
    if r(N) {
        display as error "FATAL: share_wet_neighbors off the certified " ///
            "artifact in " r(N) " cells."
        error 459
    }
    quietly count if abs(share_wet_neighbors_aug - share_aug_corr) > 1e-4
    if r(N) {
        display as error "FATAL: share_wet_neighbors_aug off the certified " ///
            "artifact in " r(N) " cells."
        error 459
    }
    display as text "  1200/1200 cells agree -- using the v2 panel columns."
    replace n_wet_corr     = n_wet_neighbors
    replace share_wet_corr = share_wet_neighbors
    replace share_aug_corr = share_wet_neighbors_aug
}

xtset fips year

*==============================================================
* STEP 2: SPILLOVER COHORTS FROM POST-RECODE NEIGHBOR COUNTS
*==============================================================
display _newline(2) "============================================"
display "STEP 2: Spillover cohorts from CORRECTED neighbor-count increments"
display "============================================"

sort fips year
by fips: gen d_nbr = n_wet_corr - n_wet_corr[_n-1]

* QC: counties never go dry in-window; a decrease means the neighbor
* build is broken -- stop rather than estimate on bad cohorts.
quietly count if d_nbr < 0 & !missing(d_nbr)
if r(N) > 0 {
    display as error "FATAL: n_wet_neighbors DECREASES in `r(N)' cells -- " ///
        "panel neighbor build suspect; do not proceed."
    error 459
}

by fips: gen incr_year = year if d_nbr > 0 & !missing(d_nbr)
by fips: egen first_nbr_event = min(incr_year)
gen spillover_cohort = cond(missing(first_nbr_event), 0, first_nbr_event)
drop d_nbr incr_year

* Restrict to the clean always-dry pool (29 counties; excludes all 13
* treated AND the partial-wet units, unlike v3's baseline_wet filter).
keep if always_dry == 1
quietly levelsof fips, local(ndry)
display as text "Always-dry counties in spillover sample: " ///
    `: word count `ndry''
assert `: word count `ndry'' == 29

* Cohort diagnostic -- eyeball against the v3 run (~20 treated /
* ~9-11 never, R2). Madison's dry neighbors should now show 2012.
display _newline "=== Spillover cohort distribution (post-recode) ==="
preserve
    keep fips county spillover_cohort
    duplicates drop
    tab spillover_cohort, missing
    list county spillover_cohort, sepby(spillover_cohort) noobs
restore

*==============================================================
* STEP 3: CONTINUOUS INTENSITY (Path B) -- from the panel itself
*==============================================================
gen L_share_wet_nbr  = L.share_wet_corr
gen D_share_wet_nbr  = D.share_wet_corr
gen L_share_wet_aug  = L.share_aug_corr            // OOS-inclusive robustness

*==============================================================
* STEP 4: PATH A -- C&S-A SPILLOVER ESTIMATION
*==============================================================
* results collector (literal handle so the program can post to it)
capture postclose spf
postfile spf str28 tag str24 outcome str8 method ///
    double att double p double preavg double preavg_p double prejoint_p ///
    long n using "spillover_v4_results.dta", replace

capture program drop run_cs_spillover
program define run_cs_spillover
    syntax, OUTcome(varname) METHod(string) TAG(string) ///
        [ COVars(string) SUBsample(string) ]

    display _newline(2) "=============================================="
    display "SPEC: `tag' | outcome=`outcome' | method=`method'"
    display "      covars=[`covars']  subsample=[`subsample']"
    display "=============================================="

    preserve
    if "`subsample'" != "" keep if `subsample'

    local att = .
    local p = .
    local preavg = .
    local preavg_p = .
    local prejoint = .
    local nobs = .

    capture noisily csdid `outcome' `covars', ///
        ivar(fips) time(year) gvar(spillover_cohort) ///
        method(`method') notyet
    if _rc != 0 {
        display as error "csdid failed with rc=" _rc " for `tag'"
        post spf ("`tag'") ("`outcome'") ("`method'") (.) (.) (.) (.) (.) (.)
        restore
        exit
    }
    estimates store _sp
    quietly count if e(sample)
    local nobs = r(N)

    * simple ATT (estimates restore before EACH estat -- log #2)
    estimates restore _sp
    capture noisily estat simple
    if !_rc {
        capture matrix R = r(table)
        if !_rc {
            local att = R[1,1]
            local p   = R[4,1]
        }
    }

    * interpretable Pre_avg (+p) from estat event (log #15)
    estimates restore _sp
    capture noisily estat event
    if !_rc {
        capture matrix E = r(table)
        if !_rc {
            local en : colnames E
            local j = 1
            foreach nm of local en {
                if "`nm'" == "Pre_avg" {
                    local preavg   = E[1,`j']
                    local preavg_p = E[4,`j']
                }
                local ++j
            }
        }
    }

    * joint pretrend chi2 -- REPORTED, not judged (rejects on cell noise)
    estimates restore _sp
    capture noisily estat pretrend
    if !_rc local prejoint = r(pchi2)

    post spf ("`tag'") ("`outcome'") ("`method'") (`att') (`p') ///
        (`preavg') (`preavg_p') (`prejoint') (`nobs')

    * event-study export (window -5..5, posted -> e(b)/e(V))
    estimates restore _sp
    capture noisily estat event, window(-5 5) post
    if _rc != 0 {
        display as error "estat event post failed for `tag'; skipping export"
        capture estimates drop _sp
        restore
        exit
    }
    matrix b = e(b)
    matrix V = e(V)
    capture estimates drop _sp

    clear
    local colnames : colnames b
    local ncoef : word count `colnames'
    set obs `ncoef'
    gen coef_name = ""
    gen coef = .
    gen se = .
    forvalues i = 1/`ncoef' {
        local nm : word `i' of `colnames'
        quietly replace coef_name = "`nm'" in `i'
        quietly replace coef = b[1,`i'] in `i'
        quietly replace se = sqrt(V[`i',`i']) in `i'
    }
    export delimited using "output/spillover_v4_`tag'_event.csv", replace

    * ---- navy/gold event-study plot (unchanged from v3_3) ----
    gen byte keep_row = regexm(coef_name, "^Tm[0-9]+$") | ///
                        regexm(coef_name, "^Tp[0-9]+$")
    keep if keep_row == 1
    gen event_time = real(regexr(coef_name, "^T[mp]", ""))
    replace event_time = -event_time if regexm(coef_name, "^Tm")
    gen ci_lo = coef - 1.96*se
    gen ci_hi = coef + 1.96*se
    sort event_time

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
        subtitle("95% CI; C&S-A, post-recode cohorts, always-dry pool", size(small)) ///
        legend(off) ///
        graphregion(color(white)) plotregion(color(white)) ///
        name(es_`tag', replace)
    if _rc != 0 {
        capture noisily twoway ///
            (rarea ci_lo ci_hi event_time, color(gs12) lwidth(none)) ///
            (line coef event_time, lcolor(navy) lwidth(medthick)) ///
            (scatter coef event_time, mcolor(gold) msize(medium) msymbol(O)) ///
            , ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(-0.5, lcolor(gold) lpattern(dash) lwidth(medthin)) ///
            xlabel(-5(1)5, nogrid) ylabel(, nogrid angle(0)) ///
            xtitle("Event time (years since first wet neighbor)") ///
            ytitle("ATT: `outcome'") ///
            title("Spillover event study: `tag'", size(medsmall)) ///
            legend(off) graphregion(color(white)) plotregion(color(white)) ///
            name(es_`tag', replace)
    }
    capture noisily graph export "output/spillover_v4_`tag'_event.png", ///
        name(es_`tag') replace width(1800)
    restore
end

* -- 4a. PRIMARY+ REG, full outcome battery (#8: same battery) --
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    local short = cond("`y'"=="fatal_crashes","fatal", ///
                  cond("`y'"=="alcohol_fatal_crashes","alcohol","nonalc"))
    run_cs_spillover, outcome(`y') method(reg) ///
        covars(log_pop poverty_rate) tag(`short'_primaryplus_reg)
}

* -- 4b. DRIPW robustness (log_pop only) ------------------------
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    local short = cond("`y'"=="fatal_crashes","fatal", ///
                  cond("`y'"=="alcohol_fatal_crashes","alcohol","nonalc"))
    run_cs_spillover, outcome(`y') method(dripw) ///
        covars(log_pop) tag(`short'_dripw)
}

* -- 4c. No-covariate baseline ----------------------------------
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    local short = cond("`y'"=="fatal_crashes","fatal", ///
                  cond("`y'"=="alcohol_fatal_crashes","alcohol","nonalc"))
    run_cs_spillover, outcome(`y') method(dripw) tag(`short'_nocov)
}

* -- 4d. RUCC rural/urban stratification (Primary+ REG) ----------
* (RUCC classifies the SPILLOVER-RECEIVING dry county; the attractor
*  predicts the rural dry neighbors shed the crashes.)
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    local short = cond("`y'"=="fatal_crashes","fatal", ///
                  cond("`y'"=="alcohol_fatal_crashes","alcohol","nonalc"))
    run_cs_spillover, outcome(`y') method(reg) ///
        covars(log_pop poverty_rate) tag(`short'_rural) ///
        subsample(rural_2013 == 1)
    run_cs_spillover, outcome(`y') method(reg) ///
        covars(log_pop poverty_rate) tag(`short'_urban) ///
        subsample(rural_2013 == 0)
}

postclose spf

*==============================================================
* STEP 5: PATH B -- CONTINUOUS SPILLOVER INTENSITY (TWFE)
*==============================================================
display _newline(2) "============================================"
display "PATH B: Continuous spillover intensity (TWFE)"
display "============================================"

capture which reghdfe
if _rc ssc install reghdfe

capture postclose pbf
postfile pbf str24 outcome str20 regressor str8 arm ///
    double(coef se t pval) long n ///
    using "spillover_v4_pathb.dta", replace

foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    foreach reg1 in share_wet_corr L_share_wet_nbr D_share_wet_nbr ///
                    L_share_wet_aug {
        capture noisily reghdfe `y' `reg1' log_pop poverty_rate, ///
            absorb(fips year) vce(cluster fips)
        if _rc == 0 {
            local b  = _b[`reg1']
            local se = _se[`reg1']
            post pbf ("`y'") ("`reg1'") ("all") (`b') (`se') (`b'/`se') ///
                (2*(1-normal(abs(`b'/`se')))) (e(N))
        }
    }
    * RUCC rural/urban dose-response (lagged share, primary regressor)
    foreach r in 1 0 {
        local lab = cond(`r'==1,"rural","urban")
        capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate ///
            if rural_2013 == `r', absorb(fips year) vce(cluster fips)
        if _rc == 0 {
            local b  = _b[L_share_wet_nbr]
            local se = _se[L_share_wet_nbr]
            post pbf ("`y'") ("L_share_wet_nbr") ("`lab'") (`b') (`se') ///
                (`b'/`se') (2*(1-normal(abs(`b'/`se')))) (e(N))
        }
    }
}
postclose pbf

*==============================================================
* STEP 6: DISPLAY + EXPORT SUMMARY TABLES
*==============================================================
use "spillover_v4_results.dta", clear
gen sig    = cond(p<.01,"***",cond(p<.05,"**",cond(p<.10,"*","")))
gen pre_ok = cond(missing(preavg_p),"",cond(preavg_p>=.10,"PASS","REJECT"))
order tag outcome method att p sig preavg preavg_p pre_ok prejoint_p n
list, sepby(outcome) noobs abbrev(28)
export delimited using "spillover_v4_results.csv", replace

use "spillover_v4_pathb.dta", clear
gen sig = cond(pval<.01,"***",cond(pval<.05,"**",cond(pval<.10,"*","")))
list, sepby(outcome) noobs abbrev(20)
export delimited using "spillover_v4_pathb.csv", replace

log close
display _newline "=== 03_spillovers_v4.do complete ==="
display "Summary: spillover_v4_results.csv + spillover_v4_pathb.csv"
display "SYMMETRY CHECK: compare the rural spillover ATT here against the"
display "rural direct ATT in het_rucc_results.csv (pre-recode: -1.19 vs +1.38)."
*==============================================================
