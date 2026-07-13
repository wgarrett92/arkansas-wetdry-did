* ============================================================================
* 05_driver_origin.do
* ATTRACTOR DIRECT TEST (ANALYSIS_LOG #10; corrected design per R12/R13).
*
* PREDICTION: after a rural county goes wet, the count of crash-involved
* NONRESIDENT drivers rises (level), and rises faster than resident
* involvement (composition). Residency does not flip with own-county
* treatment (R12), so this is clean where sh_home_dry was not.
*
* DESIGN (R13): count-based Poisson FE, not raw-share csdid -- denominators
* are tiny exactly in the attractor cells (rural treated median ~8 involved
* drivers/yr), shares are zero-inflated, missingness correlates with
* treatment. csdid on the raw shares is retained only as a FLOORED
* robustness check (Section 7).
*
* TWO EXPOSURE MARGINS (report as a pair):
*   LEVEL       exposure = total_pop.       "Inbound involvement per capita
*               rises." No conditioning on a crash occurring -> PRIMARY.
*   COMPOSITION exposure = n_resknown.      "Inbound share of involvement
*               rises." Sharper mechanism read BUT conditions on n>0, i.e.
*               on crashes happening, which treatment affects -> selection
*               caveat; report second.
*
* STAGGERED-BIAS HANDLING: static TWFE-Poisson is the transparent primary
* read; Section 5 = STACKED-by-cohort event study (Cengiz et al. logic:
* each cohort vs always-dry only, stack FE) which is clean of forbidden
* comparisons; Section 6 = jwdid (Wooldridge 2023 extended TWFE, Poisson)
* as the staggered-robust aggregate.
*
* INPUTS (run from ACTUAL/):
*   driver_origin_long.csv                            (build_driver_origin.py)
*   arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv
*   patch_madison_sebastian.do
* OUTPUT: driver_origin_results.csv, origin_event_{level,comp}_rural.csv,
*         driver_origin_descriptives.csv
* Stata:  /Applications/StataNow/StataSE.app/Contents/MacOS/stata-se -b do 05_driver_origin.do
* When done: append ANALYSIS_LOG PART-A entry #18.
* ============================================================================
clear all
set more off

* ── 0. dependencies (needs network on first run) ───────────────────────────
capture which ppmlhdfe
if _rc ssc install ppmlhdfe
capture which reghdfe
if _rc ssc install reghdfe
capture which ftools
if _rc ssc install ftools
capture which jwdid
if _rc ssc install jwdid

* ── 1. exact counts from the driver-level long file ────────────────────────
* driver_origin_long.csv: year, crash_fips, home_fips, dr_drink,
* resident / in_state / out_of_state / home_dry  (pandas True/False/empty).
* The county-year builder exports SHARES only; counts must come from here.
import delimited "driver_origin_long.csv", varnames(1) clear

* pandas booleans -> byte (empty = missing = residence unknown)
foreach v in resident in_state out_of_state home_dry {
    capture confirm string variable `v'
    if !_rc {
        gen byte __b = .
        replace __b = 1 if lower(`v')=="true"
        replace __b = 0 if lower(`v')=="false"
        drop `v'
        rename __b `v'
    }
}
capture confirm string variable crash_fips
if !_rc destring crash_fips, replace force
destring year dr_drink, replace force

gen byte one            = 1
gen byte resknown       = !missing(resident)
gen byte nonres         = (resident==0)                    if resknown
gen byte resknown_drink = resknown & dr_drink==1
gen byte nonres_drink   = (resident==0 & dr_drink==1)      if resknown
* sharpest attractor cell: inbound driver whose HOME county is still dry.
* (home_dry varies with the NEIGHBOR's status, not own treatment -> not the
*  R12 mechanical flip; still secondary because late neighbor adoption can
*  shrink it for reasons unrelated to own-county attraction.)
gen byte nonres_dry     = (resident==0 & home_dry==1)      if resknown

collapse (sum) n_drivers=one n_drink=dr_drink n_resknown=resknown ///
    n_nonres=nonres n_resknown_drink=resknown_drink ///
    n_nonres_drink=nonres_drink n_nonres_dry=nonres_dry, ///
    by(crash_fips year)
rename crash_fips fips
tempfile counts
save `counts'

* ── 2. panel + recode + merge ──────────────────────────────────────────────
import delimited "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", ///
    varnames(1) clear
destring fips year fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
    countywide_wet first_treated_year cohort years_since_treatment ///
    treated_unit neighbor_unit total_pop poverty_rate rural_2013 ///
    rucc_adjacent_2013 rural_nonadj_2013 ///
    orig_sh_nonresident orig_sh_nonresident_drink, replace force
do patch_madison_sebastian.do
egen county_id = group(fips)
xtset county_id year

merge 1:1 fips year using `counts', keep(master match)
* county-year with no fatal crash = genuinely zero involved drivers
foreach v in n_drivers n_drink n_resknown n_nonres n_resknown_drink ///
             n_nonres_drink n_nonres_dry {
    replace `v' = 0 if _merge==1
}
drop _merge

gen byte post = (cohort>0 & year>=cohort)

* QC: residence-known coverage (DR_ZIP missingness) by group -- if coverage
* itself moves with treatment, say so in the paper.
gen double cov_resknown = n_resknown / n_drivers if n_drivers>0
table rural_2013 post if cohort>0, statistic(mean cov_resknown) nototals

* ── 3. descriptive first fact (pooled-cell shares, not mean-of-shares) ─────
preserve
    gen str12 grp = "other"
    replace grp = "treat_rural" if cohort>0 & rural_2013==1
    replace grp = "treat_urban" if cohort>0 & rural_2013==0
    replace grp = "always_dry"  if always_dry==1
    keep if grp != "other"
    collapse (sum) n_nonres n_resknown n_nonres_drink n_resknown_drink ///
        n_nonres_dry, by(grp post)
    gen sh_nonres       = n_nonres       / n_resknown
    gen sh_nonres_drink = n_nonres_drink / n_resknown_drink
    gen sh_nonres_dry   = n_nonres_dry   / n_resknown
    list grp post sh_nonres sh_nonres_drink sh_nonres_dry ///
        n_resknown n_resknown_drink, sepby(grp) noobs abbrev(18)
    export delimited using "driver_origin_descriptives.csv", replace
restore

* ── 4. static Poisson arms: level (primary) + composition ──────────────────
capture program drop _pfit
program define _pfit, rclass
    args y expo ifc
    return scalar b  = .
    return scalar se = .
    return scalar p  = .
    return scalar n  = .
    capture noisily ppmlhdfe `y' post `ifc', ///
        absorb(county_id year) exposure(`expo') vce(cluster county_id)
    if _rc exit
    return scalar b  = _b[post]
    return scalar se = _se[post]
    return scalar p  = 2*normal(-abs(_b[post]/_se[post]))
    return scalar n  = e(N)
end

tempname pf
postfile `pf' str12 analysis str12 arm str28 outcome str16 exposure ///
    double b double pct double se double p long n ///
    using "driver_origin_results.dta", replace

* arm design mirrors 04/04b: {treated subset} + ALL always-dry controls.
* NB conditions are FULLY PARENTHESIZED: `&` binds tighter than `|` in Stata,
* so "... | always_dry==1 & expo>0" would leave the treated subset unguarded
* (zero-exposure county-years survive -> ppmlhdfe "exposure() must be greater
* than zero" -- this killed the rural/urban comp arms on the 2026-07-01 run).
local A_pool  "(est_sample==1)"
local A_rural "((cohort>0 & rural_2013==1) | always_dry==1)"
local A_urban "((cohort>0 & rural_2013==0) | always_dry==1)"

foreach y in n_nonres n_nonres_drink n_nonres_dry {
    foreach arm in pool rural urban {
        * LEVEL: per-capita inbound involvement
        _pfit `y' total_pop "if `A_`arm'' & total_pop>0"
        post `pf' ("level") ("`arm'") ("`y'") ("pop") ///
            (r(b)) (100*(exp(r(b))-1)) (r(se)) (r(p)) (r(n))
        * COMPOSITION: inbound share of involvement (selection caveat)
        local expv = cond("`y'"=="n_nonres_drink","n_resknown_drink","n_resknown")
        _pfit `y' `expv' "if `A_`arm'' & `expv'>0"
        post `pf' ("comp") ("`arm'") ("`y'") ("`expv'") ///
            (r(b)) (100*(exp(r(b))-1)) (r(se)) (r(p)) (r(n))
    }
}

* ── 5. stacked event study (clean of staggered contamination) ──────────────
* Each stack = one cohort's treated + ALL always-dry controls, event window
* [-5,+5]; dummies are treated x event-time; FE = stack#county, stack#year.
tempfile panelfull
save `panelfull'

levelsof cohort if cohort>0, local(cohs)
tempfile stacked
local first = 1
foreach g of local cohs {
    use `panelfull', clear
    keep if cohort==`g' | always_dry==1
    gen int  stack = `g'
    gen int  evt   = year - `g'
    keep if inrange(evt,-5,5)
    gen byte tr    = (cohort==`g')
    if `first' {
        save `stacked'
        local first = 0
    }
    else {
        append using `stacked'
        save `stacked', replace
    }
}
use `stacked', clear
egen sc = group(stack county_id)
egen sy = group(stack year)
local D ""
foreach k in -5 -4 -3 -2 0 1 2 3 4 5 {         // omit evt = -1
    local nm = cond(`k'<0, "m" + string(-`k'), "p" + string(`k'))
    gen byte d_`nm' = tr*(evt==`k')
    local D "`D' d_`nm'"
}

* rural arm is the attractor cell -- export its event paths for plotting
foreach ver in level comp {
    local expv = cond("`ver'"=="level","total_pop","n_resknown")
    capture noisily ppmlhdfe n_nonres `D' ///
        if (tr==0 | rural_2013==1) & `expv'>0, ///
        absorb(sc sy) exposure(`expv') vce(cluster county_id)
    if !_rc {
        tempname fh
        file open `fh' using "origin_event_`ver'_rural.csv", write replace
        file write `fh' "term,coef,se,p" _n
        foreach v of local D {
            local bb = _b[`v']
            local ss = _se[`v']
            local pp = 2*normal(-abs(`bb'/max(`ss',1e-12)))
            file write `fh' "`v',`bb',`ss',`pp'" _n
        }
        file close `fh'
        di "Saved: origin_event_`ver'_rural.csv"
    }
    else di as error "stacked `ver' event study failed (rc=" _rc ")"
}
use `panelfull', clear

* ── 6. jwdid robustness (Wooldridge extended TWFE, Poisson; no offset
*       support -> level-in-counts read with log_pop as covariate) ──────────
foreach y in n_nonres n_nonres_drink {
    capture noisily jwdid `y' log_pop poverty_rate if est_sample==1, ///
        ivar(county_id) tvar(year) gvar(cohort) method(poisson) never
    if !_rc {
        capture noisily estat simple
        capture matrix R = r(table)
        if !_rc post `pf' ("jwdid") ("pool") ("`y'") ("none") ///
            (R[1,1]) (100*(exp(R[1,1])-1)) (R[2,1]) (R[4,1]) (e(N))
        capture noisily estat event
    }
}

* ── 7. FLOORED robustness: raw-share csdid (R13 -- expect noise) ───────────
foreach y in orig_sh_nonresident orig_sh_nonresident_drink {
    capture noisily csdid `y' log_pop poverty_rate ///
        if (cohort>0 & rural_2013==1) | always_dry==1, ///
        ivar(county_id) time(year) gvar(cohort) method(reg) notyet
    if !_rc {
        capture noisily estat simple
        capture matrix R = r(table)
        if !_rc post `pf' ("share_csdid") ("rural") ("`y'") ("none") ///
            (R[1,1]) (.) (R[2,1]) (R[4,1]) (e(N))
    }
}
postclose `pf'

* ── 8. display + export ─────────────────────────────────────────────────────
use "driver_origin_results.dta", clear
gen sig = cond(p<.01,"***",cond(p<.05,"**",cond(p<.10,"*","")))
order analysis arm outcome exposure b pct se p sig n
format b se %9.4f
format pct %8.1f
format p %6.3f
list, sepby(analysis outcome) noobs abbrev(16)
export delimited using "driver_origin_results.csv", replace
di _n "Wrote driver_origin_results.csv"
di    "READ: pct = 100*(exp(b)-1) = % change in inbound involvement."
di    "Attractor signature = positive LEVEL + positive COMP in the RURAL arm,"
di    "flat/negative in URBAN; check the rural event CSVs for flat pre-paths."
* ============================================================================
