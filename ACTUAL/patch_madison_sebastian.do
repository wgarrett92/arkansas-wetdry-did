*=====================================================================
* patch_madison_sebastian.do                         PLACE 2 (Step 3)
* Treatment recode for the Callaway & Sant'Anna estimation panel.
*---------------------------------------------------------------------
* PASTE THIS AT THE TOP of 02_csdid_estimation_v2.do --
*   AFTER:   import delimited using ///
*              "arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", clear
*   BEFORE:  the first csdid call.
*
* The merged panel still carries the OLD (pre-Madison) treatment coding by
* design -- PLACE 1 (distance) only recoded wet SOURCES for the distance
* metric. This script owns the treatment coding so the two places agree.
*
* WHAT IT DOES
*   1. Madison (05087) -> 2012 cohort, treated (Benton/Sharp election,
*      Nov 6 2012). Coded to mirror the existing g2012 rows exactly.
*   2. Sebastian (05131), Logan (05083), Woodruff (05147) -> coded WET for
*      the whole window (Fort Smith off-premise; Logan beer & native-wine;
*      Woodruff beer-only) and flagged partial_wet. They stay never-treated,
*      so they fall in the always-wet (excluded) pool, NOT the dry controls.
*   3. Rebuilds clean always_wet / always_dry indicators and log_pop.
*   4. Defines est_sample + a baseline/conservative switch.
*
* REQUIRES the RUCC+origin panel (rural_2013 present), 1200 obs x 84 vars.
*
* AFTER PASTING: confirm the two TODO hooks below match your 02_csdid file
*   (a) gvar variable          -> should be  gvar(cohort)
*   (b) rural indicator name    -> rural_2013 (only needed in Step 4)
*=====================================================================

*--------------------------------------------------------------------
* 0.  Numeric FIPS key  (robust to fips imported as string OR numeric)
*--------------------------------------------------------------------
capture drop _fipsn
capture confirm string variable fips
if _rc==0 {
    gen long _fipsn = real(fips)
}
else {
    gen long _fipsn = fips
}
assert !missing(_fipsn)

* environment sanity (non-fatal warnings -- do not stop the run)
quietly count
if r(N)!=1200 di as error ///
    "WARN: panel has " r(N) " rows, expected 1200 -- check you loaded ..._rucc_origin.csv"
capture confirm variable rural_2013
if _rc di as error ///
    "WARN: rural_2013 not found -- this is the pre-RUCC panel; Step 4 heterogeneity will fail."

*--------------------------------------------------------------------
* 1.  Madison (05087) -> 2012 treated cohort
*     (exact mirror of the Benton 05007 / Sharp 05135 g2012 coding)
*--------------------------------------------------------------------
replace cohort               = 2012             if _fipsn==5087
replace first_treated_year   = 2012             if _fipsn==5087
replace treated_unit         = 1                if _fipsn==5087
replace neighbor_unit        = 0                if _fipsn==5087
replace countywide_wet       = (year>=2012)     if _fipsn==5087
replace years_since_treatment= year-2012        if _fipsn==5087

*--------------------------------------------------------------------
* 2.  Sebastian / Logan / Woodruff -> WET + partial_wet flag
*     (Woodruff already wet=1; Sebastian & Logan were coded 0)
*--------------------------------------------------------------------
replace countywide_wet = 1 if inlist(_fipsn, 5131, 5083, 5147)

capture drop partial_wet
gen byte partial_wet = inlist(_fipsn, 5131, 5083, 5147)
label var partial_wet "Wet but product/area-limited (Sebastian/Logan/Woodruff)"

*--------------------------------------------------------------------
* 3.  Clean always_wet / always_dry + log_pop   (rebuilt AFTER recodes)
*--------------------------------------------------------------------
capture drop _cw_min _cw_max
bysort _fipsn (year): egen byte _cw_min = min(countywide_wet)
bysort _fipsn (year): egen byte _cw_max = max(countywide_wet)

capture drop always_wet always_dry
gen byte always_wet = (cohort==0 & _cw_min==1)   // never-treated, wet throughout
gen byte always_dry = (cohort==0 & _cw_max==0)   // never-treated, dry throughout
label var always_wet "Never-treated, wet entire window (excluded from direct design)"
label var always_dry "Never-treated, dry entire window (clean within-county control)"
drop _cw_min _cw_max

capture drop log_pop
gen double log_pop = ln(total_pop)
label var log_pop "ln(total_pop) -- C&S-A covariate"

*--------------------------------------------------------------------
* 4.  Estimation sample + baseline/conservative switch
*--------------------------------------------------------------------
* csdid gvar = cohort  (0 = never-treated control). NOT first_treated_year,
* which is missing for controls. TODO(a): confirm 02_csdid uses gvar(cohort).
*
* Headline within-county design = treated + always-DRY controls; always-wet
* dropped (they fail pre-trends -- README "demoted"). Pass `if est_sample==1`
* on the csdid call; do NOT `keep`, so spillover/heterogeneity still see all
* rows. With `notyet`, est_sample keeps the not-yet-treated as valid controls.
*
* Conservative panel (Step 5): additionally drop the product/area-limited wet
* units. They are already wet => already outside the dry-control pool, so the
* switch is explicit/auditable rather than outcome-changing (baseline ~ robust).

local conservative = 0       // set to 1 for the single conservative-control row

gen byte est_sample = (cohort>0 | always_dry==1)
if `conservative'==1 {
    replace est_sample = 0 if partial_wet==1
}
label var est_sample "1 = in C&S-A direct-effect estimation sample"

*--------------------------------------------------------------------
* 5.  QC  -- verify the recode landed as expected
*--------------------------------------------------------------------
di as txt _n "{hline 64}"
di as txt "PLACE 2 recode QC  (conservative = `conservative')"
di as txt "{hline 64}"

* Madison is now a full 16-year g2012 treated unit
quietly count if _fipsn==5087 & cohort==2012
assert r(N)==16
quietly count if _fipsn==5087 & countywide_wet==1 & year>=2012
assert r(N)==12
quietly count if _fipsn==5087 & countywide_wet==0 & year<2012
assert r(N)==4

preserve
    collapse (first) cohort always_wet always_dry partial_wet, by(_fipsn)
    quietly count if cohort==2012
    di as txt "  g2012 cohort counties (expect 3): " r(N)
    assert r(N)==3
    quietly count if cohort>0
    di as txt "  treated counties        (expect 13): " r(N)
    assert r(N)==13
    quietly count if cohort==0
    di as txt "  never-treated counties  (expect 62): " r(N)
    quietly count if always_wet==1
    di as txt "  always-wet counties     (expect 33): " r(N)
    quietly count if always_dry==1
    di as txt "  always-dry controls     (expect 29): " r(N)
    assert r(N)==29
    quietly count if partial_wet==1
    di as txt "  partial_wet counties    (expect 3):  " r(N)
    assert r(N)==3
restore

quietly levelsof _fipsn if est_sample==1, local(_ss)
di as txt "  est_sample counties (baseline expect 42; conservative 42): " ///
    `: word count `_ss''
di as txt "  cohort composition of the estimation sample:"
tab cohort if est_sample==1
di as txt "{hline 64}"
di as txt "NOTE: g2022 (Hot Spring 05059, Polk 05113) stay in est_sample but are"
di as txt "      mechanically dropped by csdid -- no not-yet-treated comparators"
di as txt "      after 2022. Effective C&S-A sample = 11 counties / 6 cohorts."
di as txt "{hline 64}"

*=====================================================================
* END PATCH.  The first csdid call follows below in 02_csdid.
*=====================================================================
*
* ----- OPTIONAL: copy the block below to run the Step-3 "CHECK FIRST" -----
* The runbook says: before anything else, check the FATAL pre-trend under the
* headline Primary+ REG spec now that g2012 = 3 counties. Drop this in right
* after the patch, run it, and upload the log.
*
*   * Primary+ REG headline: method(reg), not-yet-treated, log_pop+poverty_rate
*   csdid fatal_crashes_pc, ///
*       ivar(_fipsn) time(year) gvar(cohort) ///
*       method(reg) notyet ///
*       agg(event) ///
*       xvars(log_pop poverty_rate) ///
*       if est_sample==1
*   estimates store fatal_reg
*
*   * pre-trend test (csdid discipline: restore before EACH estat)
*   estimates restore fatal_reg
*   capture noisily estat pretrend          // <- FATAL pre-trend p you need
*   estimates restore fatal_reg
*   capture noisily estat simple
*   estimates restore fatal_reg
*   capture noisily estat event
*
*   * repeat for alcohol_crashes_pc to confirm it still passes (was p~0.289)
* -------------------------------------------------------------------------
