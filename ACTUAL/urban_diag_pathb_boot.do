*==============================================================================
* urban_diag_pathb_boot.do  (supplement to 06 Section 4)
* boottest cannot run after reghdfe with two-way absorbed FE / absorbed
* interactions, so 06's p_boot came back empty. This refits the SAME models
* in a boottest-COMPATIBLE form (year & county-trend as regressors, single
* absorbed FE _fipsn) -- coefficients are numerically identical to 06's S4 --
* and reports the wild-cluster restricted bootstrap p on the 7 urban-dry
* clusters (the S4(iii) check). Output: urban_diag_pathb_boot.csv
*==============================================================================
version 17
clear all
set more off
capture log close
log using "urban_diag_pathb_boot.log", replace text

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

tempname pb
postfile `pb' str24 outcome str16 spec double(b se p p_boot) long n nclust ///
    using "urban_diag_pathb_boot.dta", replace

foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    * (i) verbatim, boottest-compatible: year as dummies, absorb only _fipsn
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate i.year ///
        if rural_2013==0, absorb(_fipsn) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local pboot = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(rademacher)
        if !_rc local pboot = r(p)
        post `pb' ("`y'") ("verbatim") (`b') (`se') (`p') (`pboot') (e(N)) (e(N_clust))
    }
    * (ii) county linear trends as regressors (c.year#i._fipsn), absorb _fipsn
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate i.year ///
        c.year#i._fipsn if rural_2013==0, absorb(_fipsn) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local pboot = .
        capture noisily boottest L_share_wet_nbr, reps(9999) nograph weighttype(rademacher)
        if !_rc local pboot = r(p)
        post `pb' ("`y'") ("cty_trends") (`b') (`se') (`p') (`pboot') (e(N)) (e(N_clust))
    }
}
postclose `pb'
use "urban_diag_pathb_boot.dta", clear
export delimited using "urban_diag_pathb_boot.csv", replace
list, noobs abbrev(24)
log close
