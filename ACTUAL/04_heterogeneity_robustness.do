*=============================================================================
* 04_heterogeneity_robustness.do
* Distance median split + contamination split + dose-response + jackknife.
* HEADLINE spec (within-county always-dry). See HANDOFF_distance_split.txt +
* ANALYSIS_LOG #15. Append an ANALYSIS_LOG entry when you finalize results.
*
* DESIGN NOTE (Section 3 of the handoff): a split attribute is defined on
* TREATED units only; the always-dry controls are SHARED across arms:
*     arm sample = {its treated subset} | always_dry==1
* Never `keep if far==1` -- that deletes the control pool.
*
* DATA TRAP (Section 2): the split uses the STATIC pre-treatment (cohort-1)
* distance from pretreatment_distance_by_treated_v2.csv, NOT the panel's
* year-varying dist_border_aug column.
*
* Small cells expected (far=6 / near=7; dose 6/3/4): csdid may fail or return
* missing on some arms -- the postfile records missings on purpose.
*=============================================================================
clear all
set more off

* -- 1. load + recode ---------------------------------------------------
import delimited "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", ///
    varnames(1) clear
destring fips year fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
    countywide_wet first_treated_year cohort years_since_treatment treated_unit ///
    neighbor_unit total_pop poverty_rate rural_2013 rucc_adjacent_2013 ///
    rural_nonadj_2013, replace force
do patch_madison_sebastian.do          // Madison g2012; est_sample; always_dry; log_pop
egen county_id = group(fips)
xtset county_id year

* -- 2. broadcast STATIC pre-treatment distance (handoff Section 2) -----
preserve
    import delimited "pretreatment_distance_by_treated_v2.csv", varnames(1) clear
    destring fips border_aug popcen_aug nearest_wet_is_oos, replace force
    rename border_aug         dist_border_pre
    rename popcen_aug         dist_popcen_pre
    rename nearest_wet_is_oos oos_pre
    keep fips dist_border_pre dist_popcen_pre oos_pre
    tempfile predist
    save `predist'
restore
merge m:1 fips using `predist', keep(master match) nogen   // controls -> missing

* QC: all 13 treated counties must carry a pre-treatment distance
quietly count if cohort>0 & missing(dist_border_pre)
if r(N) > 0 {
    di as error "FATAL: `r(N)' treated rows missing dist_border_pre -- merge broken."
    error 459
}

* -- 3. treated-only split attributes ----------------------------------
quietly summarize dist_border_pre if cohort>0, detail
scalar med_b = r(p50)
di as txt "median border_aug (treated) = " scalar(med_b)
gen byte far_b = (dist_border_pre > scalar(med_b)) if cohort>0   // 1=far 0=near .=ctrl
quietly summarize dist_popcen_pre if cohort>0, detail
scalar med_p = r(p50)
di as txt "median popcen_aug (treated) = " scalar(med_p)
gen byte far_p = (dist_popcen_pre > scalar(med_p)) if cohort>0   // robustness metric

* membership diagnostic -- eyeball vs the handoff Section 1 table
di as txt _n "=== Split membership (treated counties) ==="
preserve
    keep if cohort>0
    keep county cohort dist_border_pre dist_popcen_pre far_b far_p oos_pre ///
        rural_2013 rucc_adjacent_2013 rural_nonadj_2013
    duplicates drop
    sort dist_border_pre
    list, noobs abbrev(20)
restore

* -- helper: headline within-county csdid on an arm; grab ATT + Pre_avg -
*    (mirrors 04b _grab_het: estat simple -> R[1,1]/R[4,1]; Pre_avg from
*     estat event r(table); joint p is r(pchi2), reported but not judged)
program define _armfit, rclass
    args y ifc
    return scalar att      = .
    return scalar p        = .
    return scalar preavg   = .
    return scalar preavg_p = .
    return scalar prejoint = .
    return scalar n        = .
    capture matrix drop R
    capture matrix drop E
    capture noisily csdid `y' log_pop poverty_rate `ifc', ///
        ivar(county_id) time(year) gvar(cohort) method(reg) notyet
    if _rc exit
    estimates store _a
    quietly count if e(sample)
    return scalar n = r(N)
    capture noisily estat simple
    capture matrix R = r(table)
    if _rc==0 {
        return scalar att = R[1,1]
        return scalar p   = R[4,1]
    }
    estimates restore _a
    capture noisily estat event
    capture matrix E = r(table)
    if _rc==0 {
        local en : colnames E
        local pidx = 0
        local j = 1
        foreach nm of local en {
            if "`nm'"=="Pre_avg" local pidx = `j'
            local ++j
        }
        if `pidx'>0 {
            return scalar preavg   = E[1,`pidx']
            return scalar preavg_p = E[4,`pidx']
        }
    }
    * joint pre-trend chi2 -- REPORTED, not judged (rejects on cell noise, #15)
    estimates restore _a
    capture noisily estat pretrend
    return scalar prejoint = cond(_rc, ., r(pchi2))
    capture estimates drop _a
end

tempname pf
postfile `pf' str12 analysis str16 arm str24 outcome ///
    double att double p double preavg double preavg_p double prejoint_p long n ///
    using "het_distance_results.dta", replace

* -- 5a. distance median split: border_aug PRIMARY, popcen_aug robustness
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    _armfit `y' "if (cohort>0 & far_b==1) | always_dry==1"
    post `pf' ("dist_border") ("far")  ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & far_b==0) | always_dry==1"
    post `pf' ("dist_border") ("near") ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & far_p==1) | always_dry==1"
    post `pf' ("dist_popcen") ("far")  ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & far_p==0) | always_dry==1"
    post `pf' ("dist_popcen") ("near") ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
}

* -- 5b. contamination split (pre-treatment nearest_wet_is_oos) ---------
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    _armfit `y' "if (cohort>0 & oos_pre==1) | always_dry==1"
    post `pf' ("contam") ("oos")     ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & oos_pre==0) | always_dry==1"
    post `pf' ("contam") ("instate") ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
}

* -- 5c. dose-response (attractor strength) -----------------------------
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    _armfit `y' "if (cohort>0 & rural_nonadj_2013==1) | always_dry==1"
    post `pf' ("dose") ("rural_nonadj") ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & rucc_adjacent_2013==1) | always_dry==1"
    post `pf' ("dose") ("rural_adj")    ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    _armfit `y' "if (cohort>0 & rural_2013==0) | always_dry==1"
    post `pf' ("dose") ("urban")        ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
}

* -- 5d. jackknife-by-cohort (headline; drop one treated cohort each) ---
levelsof cohort if cohort>0, local(cohs)
foreach y in fatal_crashes alcohol_fatal_crashes {
    foreach c of local cohs {
        _armfit `y' "if est_sample==1 & cohort!=`c'"
        post `pf' ("jackknife") ("drop`c'") ("`y'") (r(att)) (r(p)) (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
    }
}
postclose `pf'

use "het_distance_results.dta", clear
gen sig    = cond(p<.01,"***",cond(p<.05,"**",cond(p<.10,"*","")))
gen pre_ok = cond(missing(preavg_p),"",cond(preavg_p>=.10,"PASS","REJECT"))
order analysis arm outcome att p sig preavg preavg_p pre_ok prejoint_p n
list, sepby(analysis outcome) noobs abbrev(24)
export delimited using "het_distance_results.csv", replace
di _n "Wrote het_distance_results.csv"
*=============================================================================
* END 04_heterogeneity_robustness.do
*=============================================================================
