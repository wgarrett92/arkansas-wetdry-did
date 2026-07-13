*=============================================================================
* 04b_heterogeneity_rucc.do
* Rural/urban heterogeneity split, RUCC 2013 (PRIMARY) vs 20k-pop cutoff (ROBUST)
* Spec = "Primary+ REG": method(reg), notyet, xvars(log_pop poverty_rate)
* Outcomes: fatal_crashes, alcohol_fatal_crashes, nonalc_fatal_crashes
*
* PROVENANCE: see ANALYSIS_LOG.txt #15 (WHY + results). Ran 2026-07-01.
*   This file now (a) `do`-es patch_madison_sebastian.do right after import (the
*   RUCC CSV carries OLD treatment coding, so the guard would exit 459 without
*   it), (b) reports BOTH control sets -- alwaysdry (headline within-county
*   est_sample pool) and fullpool (as-written notyet + all never-treated), and
*   (c) captures the INTERPRETABLE Pre_avg/p (estat pretrend's p is r(pchi2),
*   NOT r(p)). Output: het_rucc_results.csv (24 rows). Maintenance: append an
*   ANALYSIS_LOG entry on any change here (see README DOCUMENTATION CONVENTION).
*
* RUN ORDER:  merge_rucc.py  builds the RUCC CSV this imports; the treatment
*   recode is applied IN-FILE via `do patch_madison_sebastian.do` (order-
*   independent of merge_rucc for the treatment columns).
*=============================================================================
clear all
set more off

* --- load the RUCC-merged panel (output of merge_rucc.py) -------------------
import delimited "arkansas_panel_annual_border_vmt_nonalc_rucc.csv", ///
    case(preserve) clear

* --- defensive destring (mirror 02_csdid): the patch + csdid need these ------
*     numeric (fips stays string -> the patch handles it via real()).
capture destring fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes ///
         countywide_wet first_treated_year cohort years_since_treatment ///
         treated_unit neighbor_unit total_pop poverty_rate rural_2013, ///
         replace force

* --- treatment recode (PLACE 2) ---------------------------------------------
* The RUCC CSV still carries the OLD treatment coding by design (Madison coded
* always-wet / never-treated; Sebastian/Logan/Woodruff coded dry). Apply the
* SAME recode 02_csdid uses so Madison enters g2012 and est_sample / always_dry
* exist for the headline (always-dry) control set below. This is the practical
* realization of the header's "run patch_madison_sebastian.do FIRST".
do patch_madison_sebastian.do

* fips imports with a leading zero -> build a clean numeric id either way
capture destring fips, replace
egen fips_id = group(fips)

* --- GUARD: confirm the Madison g2012 treatment recode is in place ----------
* (this CSV predates it; the .do must run after patch_madison_sebastian.do)
quietly count if county=="Madison" & cohort==2012
if r(N)==0 {
    di as error "================================================================"
    di as error "STOP: Madison is not coded to cohort 2012 in this file."
    di as error "Run patch_madison_sebastian.do (treatment recode) FIRST, then"
    di as error "re-run merge_rucc.py on the recoded panel, then this file."
    di as error "================================================================"
    exit 459
}

* --- estimation inputs ------------------------------------------------------
gen gvar    = cohort                 // 0 = never-treated; already clean
capture confirm variable log_pop     // patch_madison_sebastian.do already made it
if _rc gen double log_pop = ln(total_pop)
xtset fips_id year

* --- rural classifiers ------------------------------------------------------
* PRIMARY: RUCC 2013 nonmetro. rural_2013 from merge_rucc.py (1=rural/nonmetro).
capture confirm variable rural_2013
if _rc {
    di as error "rural_2013 missing -- did merge_rucc.py run on THIS file?"
    exit 111
}

* ROBUST: ad hoc 20k cutoff, made TIME-INVARIANT via 2010 reference population.
* NOTE: replace this block with your ORIGINAL 20k construction if it differed
* (e.g. a different reference year or a year-varying flag).
bysort fips_id (year): egen pop_ref = max(cond(year==2010, total_pop, .))
gen rural_pop20k = pop_ref < 20000 if !missing(pop_ref)
label define rurlbl 1 "rural" 0 "urban"
label values rural_2013 rural_pop20k rurlbl

* ---------------------------------------------------------------------------
* Results collector
* ---------------------------------------------------------------------------
tempname pf
postfile `pf' str10 classifier str9 controls str16 outcome str6 group ///
    double att double p double preavg double preavg_p double prejoint_p long n ///
    using "het_rucc_results.dta", replace

* Grab ATT (estat simple), the INTERPRETABLE pre-trend (Pre_avg from estat
* event -- the number comparable to the headline p=0.807), and the joint
* pre-trend test (estat pretrend stores its p in r(pchi2), NOT r(p); the joint
* test rejects on cell noise everywhere per the runbook, so read preavg_p).
program define _grab_het, rclass
    * args: 1=outcome 2=ifcond 3=classifier 4=group
    args y ifc cls grp
    return scalar att      = .
    return scalar p        = .
    return scalar preavg   = .
    return scalar preavg_p = .
    return scalar prejoint = .
    return scalar n        = .
    capture noisily csdid `y' log_pop poverty_rate `ifc', ///
        ivar(fips_id) time(year) gvar(gvar) method(reg) notyet
    if _rc exit
    estimates store _m
    quietly count if e(sample)
    return scalar n = r(N)
    capture noisily estat simple
    capture matrix R = r(table)
    return scalar att = cond(_rc, ., R[1,1])
    return scalar p   = cond(_rc, ., R[4,1])
    * interpretable pre-trend: Pre_avg column of estat event's r(table)
    estimates restore _m
    capture noisily estat event
    capture matrix E = r(table)
    if _rc==0 {
        local ecn : colnames E
        local pidx = 0
        local j = 1
        foreach nm of local ecn {
            if "`nm'"=="Pre_avg" local pidx = `j'
            local ++j
        }
        if `pidx'>0 {
            return scalar preavg   = E[1,`pidx']
            return scalar preavg_p = E[4,`pidx']
        }
    }
    * joint pre-trend test (p in r(pchi2))
    estimates restore _m
    capture noisily estat pretrend
    return scalar prejoint = cond(_rc, ., r(pchi2))
    capture estimates drop _m
end

* ---------------------------------------------------------------------------
* Loop: 3 outcomes x 2 classifiers x {rural, urban}
* ---------------------------------------------------------------------------
* controls dimension:
*   alwaysdry = headline within-county pool (treated + always-dry controls),
*               applied WITHIN each rural/urban subsample via est_sample==1
*   fullpool  = 04b as-written: notyet + all never-treated (includes always-wet)
foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
  foreach cls in rural_2013 rural_pop20k {
      local tag = cond("`cls'"=="rural_2013","RUCC2013","pop20k")
      foreach cs in alwaysdry fullpool {
          local extra = cond("`cs'"=="alwaysdry"," & est_sample==1","")
          * rural arm
          _grab_het `y' "if `cls'==1`extra'" "`tag'" "rural"
          post `pf' ("`tag'") ("`cs'") ("`y'") ("rural") (r(att)) (r(p)) ///
              (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
          * urban arm
          _grab_het `y' "if `cls'==0`extra'" "`tag'" "urban"
          post `pf' ("`tag'") ("`cs'") ("`y'") ("urban") (r(att)) (r(p)) ///
              (r(preavg)) (r(preavg_p)) (r(prejoint)) (r(n))
      }
  }
}
postclose `pf'

* ---------------------------------------------------------------------------
* Display + export the comparison table
* ---------------------------------------------------------------------------
use "het_rucc_results.dta", clear
gen sig = cond(p<.01,"***",cond(p<.05,"**",cond(p<.10,"*","")))
* pre-trend verdict on the INTERPRETABLE Pre_avg p (>=.10 = clean); the joint
* prejoint_p rejects on cell noise everywhere, so it is reported but not judged
gen pre_ok = cond(missing(preavg_p),"",cond(preavg_p>=.10,"PASS","REJECT"))
order classifier controls outcome group att p sig preavg preavg_p pre_ok prejoint_p n
list, sepby(classifier controls outcome) noobs abbrev(20)

* tidy wide view: rural vs urban ATT side by side, primary classifier on top
preserve
    keep classifier controls outcome group att
    reshape wide att, i(classifier controls outcome) j(group) string
    gen rural_minus_urban = attrural - atturban
    order classifier controls outcome attrural atturban rural_minus_urban
    sort controls classifier outcome
    di _n "{hline 70}"
    di "Rural vs urban ATT  (controls: alwaysdry = headline; fullpool = as-written)"
    di "(RUCC2013 = primary classifier; pop20k = robustness row)"
    di "{hline 70}"
    list, sepby(controls) noobs abbrev(20)
restore

export delimited using "het_rucc_results.csv", replace
di _n "Wrote het_rucc_results.csv  (RUCC2013 = headline; pop20k = robustness)."

*-----------------------------------------------------------------------------
* OPTIONAL event study per subsample (uncomment to export; nonalc pre-trends are
* your common-confounder diagnostic, so you'll want these for the decomposition):
*
* foreach y in fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes {
*   foreach g in 1 0 {
*       local lbl = cond(`g'==1,"rural","urban")
*       capture noisily csdid `y' log_pop poverty_rate if rural_2013==`g', ///
*           ivar(fips_id) time(year) gvar(gvar) method(reg) notyet
*       capture estat event
*       capture estimates restore .       // restore before any further estat
*       * -> export r(table)/e(b) to es_`y'_`lbl'.csv, then plot via twoway
*   }                                     // (csdid_plot does NOT aggregate event study)
* }
*-----------------------------------------------------------------------------
