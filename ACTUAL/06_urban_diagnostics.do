*==============================================================================
* 06_urban_diagnostics.do
* Purpose: stress-test the emerging URBAN-POSITIVE pattern (#20/#22/#24) with
*          the same discipline that retired the rural attractor, BEFORE any of
*          it is theorized in the paper.
*   S1  05-extension: urban stacked event studies (LEVEL + COMP), the missing
*       counterpart to origin_event_*_rural.csv. Strongest single diagnostic:
*       urban COMP with flat pre + sharp post jump = real; wobbly pre = trends.
*   S2  05-extension: jackknife-by-county on the urban driver-origin arms
*       (urban treated = Benton 05007, Little River 05081, Madison 05087,
*        Saline 05125; Madison is g2012 via the patch AND urban under RUCC
*        code 2 (Fayetteville metro), so it enters the urban arm -- README
*        RUCC note. The original roster here omitted it; fixed 2026-07-02).
*   S3  03-extension: jackknife-by-county on the urban spillover arm
*       (treated urban-dry: Crawford 05033, Faulkner 05045, Grant 05053,
*        Perry 05105; never urban-dry: Craighead 05031, Lincoln 05079,
*        Lonoke 05085).
*   S4  Path B urban audit: reproduce the +18.1 cell, echo the honest units
*       (per-unit-SHARE on a raw COUNT, 7 clusters), re-estimate with
*       county-specific linear trends, wild-cluster bootstrap if available.
*   S5  Spillover dose re-cut: FIRST EXPOSURE FROM ZERO (extensive margin)
*       instead of first increment -- removes Crawford-type near-zero-dose
*       events (wet Sebastian next door all window; 2012 "event" = Madison).
*   S6  VMT exposure probe (mechanism M2): does wet access raise ln(VMT) in
*       urban treated / urban dry-neighbor counties? VMT is 2013+ only --
*       TWFE with honest caveats, NOT csdid (g2014 has one pre-year).
*
* REQUIRES (local dir): arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv
*   patch_madison_sebastian.do, driver_origin_long.csv,
*   neighbor_counts_corrected.csv  (certified #24 artifact)
* OUTPUT: urban_diag_results.csv        (S2 + S3 jackknife arms)
*         origin_event_{level,comp}_urban_{nonres,drink}.csv   (S1)
*         urban_diag_pathb.csv          (S4)
*         urban_diag_fromzero.csv       (S5)
*         urban_diag_vmt.csv            (S6)
* CONVENTIONS: capture noisily throughout; postfile collects missings by
*   design (empty/tiny arms are informative); conditions FULLY PARENTHESIZED
*   (Stata & binds tighter than | -- see #22 patch note); estimates restore
*   before EVERY estat (log #2).
*==============================================================================
version 17
clear all
set more off
capture log close
log using "06_urban_diagnostics.log", replace text

capture which ppmlhdfe
if _rc ssc install ppmlhdfe
capture which reghdfe
if _rc ssc install reghdfe

*==============================================================================
* SECTION 0 -- master build (mirrors 05 Sec 1-2 + 03 Sec 1)
*==============================================================================

* -- 0a. exact driver counts from the long file (05 Sec 1, verbatim logic) ----
import delimited "driver_origin_long.csv", varnames(1) clear
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
gen byte nonres_dry     = (resident==0 & home_dry==1)      if resknown

collapse (sum) n_drivers=one n_drink=dr_drink n_resknown=resknown ///
    n_nonres=nonres n_resknown_drink=resknown_drink ///
    n_nonres_drink=nonres_drink n_nonres_dry=nonres_dry, ///
    by(crash_fips year)
rename crash_fips fips
tempfile counts
save `counts'

* -- 0b. panel + PLACE-2 recode + corrected neighbor counts -------------------
import delimited "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", ///
    varnames(1) clear
destring fips year fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
    countywide_wet first_treated_year cohort years_since_treatment ///
    treated_unit neighbor_unit total_pop poverty_rate rural_2013 ///
    rucc_adjacent_2013 rural_nonadj_2013 vmt_annual vmt_present, ///
    replace force

do patch_madison_sebastian.do

preserve
    import delimited "neighbor_counts_corrected.csv", varnames(1) clear
    destring fips year n_wet_corr share_wet_corr n_aug_corr share_aug_corr, ///
        replace force
    tempfile nbrcorr
    save `nbrcorr'
restore
merge 1:1 fips year using `nbrcorr', assert(match) nogen

merge 1:1 fips year using `counts', keep(master match) nogen
foreach v in n_nonres n_nonres_drink n_nonres_dry n_resknown ///
    n_resknown_drink n_drivers n_drink {
    replace `v' = 0 if missing(`v')     // no drivers observed = zero count
}

xtset _fipsn year
gen byte post = (cohort>0 & year>=cohort)
gen L_share_wet_nbr = L.share_wet_corr
gen L_share_wet_aug = L.share_aug_corr

* runtime identity asserts (the arms below are county-name-specific)
quietly levelsof _fipsn if cohort>0 & rural_2013==0, local(_utr)
* Benton, Little River, Madison, Saline. Madison 05087 is g2012 (patch) AND
* urban under RUCC (code 2, Fayetteville metro) -> it belongs in the urban
* treated arm (README RUCC note; matches 05's A_urban). The original assert
* omitted 5087 and aborted the run; corrected 2026-07-02.
assert "`_utr'" == "5007 5081 5087 5125"
quietly count if always_dry==1 & rural_2013==0 & year==2008
assert r(N)==7                               // the 7-county urban-dry stratum

tempfile master
save `master'

*==============================================================================
* SECTION 1 -- urban stacked event studies (05 Sec 5, urban arm)
*   Same Cengiz-style stacks: each cohort's treated + ALL always-dry controls,
*   window [-5,+5], omit t-1, FE = stack#county, stack#year. Controls include
*   rural always-dry counties -- SAME convention as the rural run, so the two
*   arms are read against a common control pool.
*==============================================================================
use `master', clear
levelsof cohort if cohort>0, local(cohs)
tempfile stacked
local first = 1
foreach g of local cohs {
    use `master', clear
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
egen sc = group(stack _fipsn)
egen sy = group(stack year)
local D ""
foreach k in -5 -4 -3 -2 0 1 2 3 4 5 {          // omit evt = -1
    local nm = cond(`k'<0, "m" + string(-`k'), "p" + string(`k'))
    gen byte d_`nm' = tr*(evt==`k')
    local D "`D' d_`nm'"
}

* outcomes: n_nonres (primary) AND n_nonres_drink (the +57%/+39.5% signal cell)
foreach y in n_nonres n_nonres_drink {
    local ytag = cond("`y'"=="n_nonres","nonres","drink")
    foreach ver in level comp {
        if "`ver'"=="level" local expv "total_pop"
        else local expv = cond("`y'"=="n_nonres_drink", ///
                               "n_resknown_drink","n_resknown")
        capture noisily ppmlhdfe `y' `D' ///
            if ((tr==0) | (rural_2013==0)) & `expv'>0, ///
            absorb(sc sy) exposure(`expv') vce(cluster _fipsn)
        if !_rc {
            tempname fh
            file open `fh' using "origin_event_`ver'_urban_`ytag'.csv", ///
                write replace
            file write `fh' "term,coef,se,p" _n
            foreach v of local D {
                local bb = _b[`v']
                local ss = _se[`v']
                local pp = 2*normal(-abs(`bb'/max(`ss',1e-12)))
                file write `fh' "`v',`bb',`ss',`pp'" _n
            }
            file close `fh'
            di as txt "Saved: origin_event_`ver'_urban_`ytag'.csv"
        }
        else di as error "urban stacked `ver' `y' failed (rc=" _rc ")"
    }
}

*==============================================================================
* SECTION 2 -- jackknife-by-county, urban driver-origin arms (05 Sec 4)
*   If +57% level / +39.5% comp (n_nonres_drink) dies when one county drops,
*   it is a county story (expect: Benton), not an urban story.
*==============================================================================
use `master', clear

capture program drop _pfit
program define _pfit, rclass
    args y expo ifc
    return scalar b  = .
    return scalar se = .
    return scalar p  = .
    return scalar n  = .
    capture noisily ppmlhdfe `y' post `ifc', ///
        absorb(_fipsn year) exposure(`expo') vce(cluster _fipsn)
    if _rc exit
    return scalar b  = _b[post]
    return scalar se = _se[post]
    return scalar p  = 2*normal(-abs(_b[post]/_se[post]))
    return scalar n  = e(N)
end

tempname jk
postfile `jk' str12 section str16 arm str28 outcome str16 exposure ///
    long dropped double(b pct se p) long n ///
    using "urban_diag_results.dta", replace

* full urban arm first (reproduce #22), then leave-one-out over the 4 treated
* (5087 Madison added 2026-07-02 -- it is in A_urban via rural_2013==0, so a
*  complete leave-one-out must drop it too, else it silently rides every arm)
local A_urban "((cohort>0 & rural_2013==0) | always_dry==1)"
foreach dropf in 0 5007 5081 5087 5125 {
    local ifextra = cond(`dropf'==0, "", " & _fipsn!=`dropf'")
    foreach y in n_nonres n_nonres_drink n_nonres_dry {
        _pfit `y' total_pop "if `A_urban' & total_pop>0`ifextra'"
        post `jk' ("s2_origin") ("urban_jk") ("`y'") ("pop") (`dropf') ///
            (r(b)) (100*(exp(r(b))-1)) (r(se)) (r(p)) (r(n))
        local expv = cond("`y'"=="n_nonres_drink","n_resknown_drink","n_resknown")
        _pfit `y' `expv' "if `A_urban' & `expv'>0`ifextra'"
        post `jk' ("s2_origin") ("urban_jk") ("`y'") ("`expv'") (`dropf') ///
            (r(b)) (100*(exp(r(b))-1)) (r(se)) (r(p)) (r(n))
    }
}

*==============================================================================
* SECTION 3 -- jackknife-by-county, urban spillover arm (03 v4.1 Sec 4d)
*   Rebuild spillover cohorts exactly as 03 v4.1 (first INCREMENT of
*   n_wet_corr), restrict to the 29 always-dry, urban stratum, then drop each
*   of the 7 urban-dry counties in turn. Focus: the fatal +4.88 (p=.014) cell;
*   nonalc run alongside (the M2 tell).
*==============================================================================
use `master', clear
sort _fipsn year
by _fipsn: gen d_nbr = n_wet_corr - n_wet_corr[_n-1]
quietly count if d_nbr < 0 & !missing(d_nbr)
if r(N) > 0 {
    display as error "FATAL: n_wet_corr decreases in " r(N) " cells."
    error 459
}
by _fipsn: gen incr_year = year if d_nbr > 0 & !missing(d_nbr)
by _fipsn: egen first_nbr_event = min(incr_year)
gen spillover_cohort = cond(missing(first_nbr_event), 0, first_nbr_event)
drop d_nbr incr_year
keep if always_dry == 1
quietly levelsof _fipsn, local(ndry)
assert `: word count `ndry'' == 29

* verify the urban-dry roster before jackknifing it
di as txt _n "Urban always-dry stratum (expect 7):"
tab _fipsn spillover_cohort if rural_2013==0 & year==2008

tempfile sppool
save `sppool'

capture program drop _spjack
program define _spjack
    syntax , outcome(string) tag(string) dropped(integer) [dropcond(string)]
    preserve
    if "`dropcond'" != "" quietly drop if `dropcond'
    quietly keep if rural_2013==0
    local att = .
    local p = .
    local preavg = .
    local preavg_p = .
    local nobs = .
    capture noisily csdid `outcome' log_pop poverty_rate, ///
        ivar(_fipsn) time(year) gvar(spillover_cohort) ///
        method(reg) notyet
    if _rc == 0 {
        estimates store _sj
        quietly count if e(sample)
        local nobs = r(N)
        estimates restore _sj
        capture noisily estat simple
        if !_rc {
            capture matrix R = r(table)
            if !_rc {
                local att = R[1,1]
                local p   = R[4,1]
            }
        }
        estimates restore _sj
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
        capture estimates drop _sj
    }
    post spjk ("s3_spill") ("`tag'") ("`outcome'") (`dropped') ///
        (`att') (`p') (`preavg') (`preavg_p') (`nobs')
    restore
end

tempname spjk
postfile spjk str12 section str16 tag str28 outcome long dropped ///
    double(att p preavg preavg_p) long n ///
    using "urban_diag_spill.dta", replace

use `sppool', clear
foreach y in fatal_crashes nonalc_fatal_crashes alcohol_fatal_crashes {
    _spjack , outcome(`y') tag(full) dropped(0)
    * treated urban-dry, then never-treated urban-dry controls
    foreach f in 5033 5045 5053 5105 5031 5079 5085 {
        _spjack , outcome(`y') tag(drop) dropped(`f') dropcond(_fipsn==`f')
    }
}
postclose spjk

*==============================================================================
* SECTION 4 -- Path B urban audit (03 v4.1 Step 5)
*   (i)  reproduce the urban cells verbatim (raw-COUNT outcome on a 0-1 share,
*        7 clusters -- echo the honest interpretation scale);
*   (ii) add county-specific linear trends: collapse => M3 (growth selection);
*   (iii) wild-cluster bootstrap p if boottest is installed (7 clusters).
*==============================================================================
use `sppool', clear
xtset _fipsn year

* honest scale: within-county SD of the regressor in the urban stratum
quietly xtsum L_share_wet_nbr if rural_2013==0
local sdw = r(sd_w)
di as txt _n "Path B urban: within-county SD of L_share_wet_nbr = " %6.4f `sdw'
di as txt "  => quote coef x " %6.4f `sdw' " (per-within-SD), never the 0->1 unit."
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    quietly sum `y' if rural_2013==0
    di as txt "  urban-dry mean `y' = " %6.3f r(mean)
}

tempname pb
postfile `pb' str28 outcome str24 spec double(b b_per_sdw se p p_boot) ///
    long n nclust using "urban_diag_pathb.dta", replace

foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    * (i) verbatim reproduction (p from reghdfe's cluster-t, NOT normal())
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate ///
        if rural_2013==0, absorb(_fipsn year) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local pboot = .
        capture which boottest
        if !_rc {
            capture noisily boottest L_share_wet_nbr, reps(9999) nograph
            if !_rc local pboot = r(p)
        }
        post `pb' ("`y'") ("verbatim") (`b') (`b'*`sdw') (`se') (`p') ///
            (`pboot') (e(N)) (e(N_clust))
    }
    * (ii) + county linear trends
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate ///
        if rural_2013==0, absorb(_fipsn year _fipsn#c.year) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        local pboot = .
        capture which boottest
        if !_rc {
            capture noisily boottest L_share_wet_nbr, reps(9999) nograph
            if !_rc local pboot = r(p)
        }
        post `pb' ("`y'") ("cty_trends") (`b') (`b'*`sdw') (`se') (`p') ///
            (`pboot') (e(N)) (e(N_clust))
    }
    * (iii) rural comparison under trends (symmetry check, one line)
    capture noisily reghdfe `y' L_share_wet_nbr log_pop poverty_rate ///
        if rural_2013==1, absorb(_fipsn year _fipsn#c.year) vce(cluster _fipsn)
    if !_rc {
        local b  = _b[L_share_wet_nbr]
        local se = _se[L_share_wet_nbr]
        local p  = 2*ttail(e(df_r), abs(`b'/`se'))
        post `pb' ("`y'") ("rural_trends") (`b') (`b'*`sdw') (`se') (`p') ///
            (.) (e(N)) (e(N_clust))
    }
}
postclose `pb'

*==============================================================================
* SECTION 5 -- spillover dose re-cut: FIRST EXPOSURE FROM ZERO
*   Extensive margin: only counties starting 2008 at n_wet_corr==0 enter;
*   cohort = first year n_wet_corr>0; controls = stay at zero (+ notyet).
*   Removes marginal-increment events (Crawford). Cells WILL be small --
*   empty arms are recorded as missing BY DESIGN and are themselves the
*   finding (the extensive margin barely exists among the always-dry).
*==============================================================================
use `sppool', clear
by _fipsn (year): gen base08 = n_wet_corr[1]
di as txt _n "From-zero recut: always-dry counties with ZERO 2008 exposure:"
tab _fipsn if base08==0 & year==2008
keep if base08==0
by _fipsn: gen posyr = year if n_wet_corr>0
by _fipsn: egen firstpos = min(posyr)
gen zcohort = cond(missing(firstpos), 0, firstpos)
di as txt "From-zero cohort distribution:"
tab zcohort if year==2008

tempname fz
postfile `fz' str16 arm str28 outcome double(att p preavg preavg_p) long n ///
    using "urban_diag_fromzero.dta", replace
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
    foreach arm in pool rural urban {
        preserve
        if "`arm'"=="rural" quietly keep if rural_2013==1
        if "`arm'"=="urban" quietly keep if rural_2013==0
        local att = .
        local p = .
        local preavg = .
        local preavg_p = .
        local nobs = .
        capture noisily csdid `y' log_pop poverty_rate, ///
            ivar(_fipsn) time(year) gvar(zcohort) method(reg) notyet
        if _rc == 0 {
            estimates store _fz
            quietly count if e(sample)
            local nobs = r(N)
            estimates restore _fz
            capture noisily estat simple
            if !_rc {
                capture matrix R = r(table)
                if !_rc {
                    local att = R[1,1]
                    local p   = R[4,1]
                }
            }
            estimates restore _fz
            capture noisily estat event
            if !_rc {
                capture matrix E = r(table)
                if !_rc {
                    local en : colnames E
                    local j = 1
                    foreach nm of local en {
                        if "`nm'"=="Pre_avg" {
                            local preavg   = E[1,`j']
                            local preavg_p = E[4,`j']
                        }
                        local ++j
                    }
                }
            }
            capture estimates drop _fz
        }
        post `fz' ("`arm'") ("`y'") (`att') (`p') (`preavg') (`preavg_p') (`nobs')
        restore
    }
}
postclose `fz'

*==============================================================================
* SECTION 6 -- VMT exposure probe (mechanism M2: generic traffic, not
*   impairment). VMT 2013+ only, so TWFE with post, NOT csdid (g2014 cohorts
*   have a single pre-year -- pre-trends untestable; read as descriptive).
*   (a) urban TREATED arm: does going wet raise own-county ln(VMT)?
*       Identified off Saline g2014 / Little River g2016 (Benton g2012 has no
*       pre-VMT and is absorbed by its FE trend -- note in the read).
*   (b) always-dry: does wet-neighbor share raise ln(VMT)? (corridor traffic)
*==============================================================================
use `master', clear
keep if vmt_present==1
gen ln_vmt = ln(vmt_annual)
xtset _fipsn year

tempname vm
postfile `vm' str8 arm str24 spec double(b se p) long n nclust ///
    using "urban_diag_vmt.dta", replace

* (a) urban treated + always-dry controls
capture noisily reghdfe ln_vmt post ///
    if ((cohort>0 & rural_2013==0) | always_dry==1), ///
    absorb(_fipsn year) vce(cluster _fipsn)
if !_rc post `vm' ("urban") ("treated_post") (_b[post]) (_se[post]) ///
    (2*ttail(e(df_r), abs(_b[post]/_se[post]))) (e(N)) (e(N_clust))
* rural counterpart for symmetry
capture noisily reghdfe ln_vmt post ///
    if ((cohort>0 & rural_2013==1) | always_dry==1), ///
    absorb(_fipsn year) vce(cluster _fipsn)
if !_rc post `vm' ("rural") ("treated_post") (_b[post]) (_se[post]) ///
    (2*ttail(e(df_r), abs(_b[post]/_se[post]))) (e(N)) (e(N_clust))

* (b) always-dry corridor probe
gen Lsw = L.share_wet_corr
foreach r in 0 1 {
    local lab = cond(`r'==0,"urban","rural")
    capture noisily reghdfe ln_vmt Lsw log_pop ///
        if always_dry==1 & rural_2013==`r', ///
        absorb(_fipsn year) vce(cluster _fipsn)
    if !_rc post `vm' ("`lab'") ("dry_Lshare") (_b[Lsw]) (_se[Lsw]) ///
        (2*ttail(e(df_r), abs(_b[Lsw]/_se[Lsw]))) (e(N)) (e(N_clust))
}
postclose `vm'

*==============================================================================
* SECTION 7 -- close postfiles, export, read-out template
*==============================================================================
postclose `jk'

use "urban_diag_results.dta", clear
export delimited using "urban_diag_results.csv", replace
use "urban_diag_spill.dta", clear
export delimited using "urban_diag_spill.csv", replace
use "urban_diag_pathb.dta", clear
export delimited using "urban_diag_pathb.csv", replace
use "urban_diag_fromzero.dta", clear
export delimited using "urban_diag_fromzero.csv", replace
use "urban_diag_vmt.dta", clear
export delimited using "urban_diag_vmt.csv", replace

di as txt _n "{hline 70}"
di as txt "READ-OUT GUIDE"
di as txt "{hline 70}"
di as txt "S1  urban COMP drink event path: flat pre + post jump  -> M1 gains."
di as txt "    wobbly pre (like the rural LEVEL Tm5/Tm4)          -> M3 gains."
di as txt "S2  drop-Benton kills +57%/+39.5%                      -> county story (M4)."
di as txt "S3  drop-Crawford or drop-Faulkner kills fatal +4.88   -> county story;"
di as txt "    nonalc tracks fatal across drops                   -> M2 over M1."
di as txt "S4  cty_trends collapses the Path B urban positives    -> M3;"
di as txt "    p_boot >> p on 7 clusters                          -> inference artifact."
di as txt "S5  from-zero urban arm empty/null                     -> increment 'events'"
di as txt "    were carrying the result; extensive margin absent."
di as txt "S6  urban treated_post > 0 and/or urban dry_Lshare > 0 -> exposure (M2)"
di as txt "    channel live; nulls push back toward M1/M3."
di as txt "{hline 70}"

log close
exit
