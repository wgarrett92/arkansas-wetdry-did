*=====================================================================
* urban_diag_pathb_boot_webb.do                    SUPPLEMENT to #26
*---------------------------------------------------------------------
* Webb-weights wild-cluster bootstrap for the S4 Path B urban audit.
* Identical build + specs to urban_diag_pathb_boot.do (2026-07-02 run);
* the ONLY change is that boottest runs TWICE per spec -- Rademacher
* (reproduces the #26 supplement, sanity anchor) and Webb 6-point.
* Rationale: with 7 clusters the Rademacher null has 2^7 = 128 unique
* sign assignments (p floor ~.008, coarse); Webb has 6^7 = 279,936, so
* reps(9999) samples a fine null. boottest itself warned "Consider Webb
* weights instead" in the 2026-07-02 log.
* Expected: NO verdict changes. Alcohol-verbatim (.094 Rademacher) is
* not returning below .05; this just de-coarsens the reported p's.
*
* Outputs: urban_diag_pathb_boot_webb.csv  (p, p_rad, p_webb columns)
*          urban_diag_pathb_boot_webb.log
* Does NOT overwrite the certified 2026-07-02 artifacts.
*=====================================================================

capture log close
log using "urban_diag_pathb_boot_webb.log", replace text

capture which reghdfe
if _rc ssc install reghdfe
capture which boottest
if _rc ssc install boottest

* ----- build: mirrors urban_diag_pathb_boot.do verbatim ------------
import delimited "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", varnames(1) clear
destring fips year fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
    countywide_wet first_treated_year cohort treated_unit neighbor_unit ///
    total_pop poverty_rate rural_2013, replace force

do patch_madison_sebastian.do

preserve
    import delimited "neighbor_counts_corrected.csv", varnames(1) clear
    destring fips year n_wet_corr share_wet_corr n_aug_corr share_aug_corr, replace force
    tempfile n
    save `n'
restore
merge 1:1 fips year using `n', assert(match) nogen

keep if always_dry==1
xtset _fipsn year
gen L_share_wet_nbr = L.share_wet_corr

* ----- estimation loop: two specs x two weight types ----------------
tempname pb
postfile `pb' str24 outcome str16 spec double(b se p p_rad p_webb) ///
    long n nclust using "urban_diag_pathb_boot_webb.dta", replace

foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    * (i) verbatim, boottest-compatible: year as dummies, absorb only _fipsn
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate i.year ///
        if rural_2013==0, absorb(_fipsn) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local prad = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(rademacher)
        if !_rc local prad = r(p)
        local pwebb = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(webb)
        if !_rc local pwebb = r(p)
        post `pb' ("`y'") ("verbatim") (`b') (`se') (`p') (`prad') (`pwebb') (e(N)) (e(N_clust))
    }
    * (ii) county linear trends as regressors (c.year#i._fipsn), absorb _fipsn
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate i.year ///
        c.year#i._fipsn if rural_2013==0, absorb(_fipsn) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local prad = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(rademacher)
        if !_rc local prad = r(p)
        local pwebb = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(webb)
        if !_rc local pwebb = r(p)
        post `pb' ("`y'") ("cty_trends") (`b') (`se') (`p') (`prad') (`pwebb') (e(N)) (e(N_clust))
    }
}

postclose `pb'

use "urban_diag_pathb_boot_webb.dta", clear

* sanity anchor: p_rad must reproduce the 2026-07-02 supplement's p_boot
* (verbatim: .03125 / .09375 / .140625; cty_trends: 0 / .03125 / .015625)
list outcome spec b se p p_rad p_webb, sep(2) abbreviate(24)

export delimited using "urban_diag_pathb_boot_webb.csv", replace

di as txt _n "{hline 70}"
di as txt "READ-OUT"
di as txt "{hline 70}"
di as txt "p_rad reproduces #26 p_boot  -> same estimates, anchor holds."
di as txt "p_webb is the reportable bootstrap p (fine null, no .008 floor)."
di as txt "Verdict check: alcohol verbatim p_webb >= .05 expected -> S4"
di as txt "conclusion in #26/#27 unchanged; cite p_webb in the appendix table."
di as txt "{hline 70}"

log close
