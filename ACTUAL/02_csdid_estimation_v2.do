/*==============================================================
  02_csdid_estimation_v2.do
  Arkansas Wet/Dry DiD Panel — Callaway & Sant'Anna Estimation
  HEADLINE: within-county design (treated + always-DRY controls)

  PROVENANCE: decision trail in ANALYSIS_LOG.txt (esp. #2,#3,#13,#14,#16).
  Maintenance: append an ANALYSIS_LOG entry on any change (README convention).

  HEADLINE PROMOTION (2026-07-01):
    The within-county always-DRY design (Section 6b) is now the HEADLINE /
    PRIMARY specification. Rationale (post Madison g2012 recode run,
    2026-06-30): it is the ONLY design with a clean fatal pre-trend
    (Pre_avg -0.027, p=0.807) AND a clean alcohol pre-trend (p=0.732); the
    former not-yet-treated "Primary" rejects the fatal pre-trend
    (Pre_avg 0.317, p=0.037) and Madison is not the cause (p=0.037 with/
    without). This matches the README "COMPARISON GROUP FRAMING": the
    within-county direct-effect control = always-dry. The not-yet-treated,
    always-wet, and pre-COVID designs are retained below as ROBUSTNESS.

  REVISION NOTES:
    - Sections renamed to reflect the promotion; ESTIMATION CODE UNCHANGED
      (only banners/labels/summary + a headline event-study export added).
    - Diagnostic decomposition of pre-trend failures (Section 7)
    - Short-run vs long-run ATT split
    - Group-level heterogeneity discussion
    - Export of event-study coefficients for Python plotting

  COMPARISON GROUP FRAMING:
    HEADLINE (Sec 6b): within-county — treated + always-DRY never-treated,
                       gvar(cohort), notyet, method(reg), xvars(log_pop
                       poverty_rate), if est_sample==1
    Conservative (6c): headline ATT dropping partial_wet (non-binding)
    Robustness D (Sec 2): not-yet-treated only (former primary; fatal
                       pre-trend rejects)
    Robustness A: not-yet-treated + never-treated (always-wet; fails pre-trend)
    Robustness B: pre-COVID sample (2008–2019), not-yet-treated only
    Robustness C: regression estimator, not-yet-treated only

  REQUIREMENTS:
    - Stata 16+
    - csdid, drdid packages
    - Run 01_descriptives.do first, or this file re-imports from CSV
    
  AUTHOR: [Your Name]
  DATE:   2026-03-20
==============================================================*/

clear all
set more off
set scheme s2color

* ── USER: Set paths ──────────────────────────────────────────
global datadir "."
global outdir  "$datadir/output"
cap mkdir "$outdir"

* ── Install packages if needed (uncomment on first run) ──────
* ssc install csdid, replace
* ssc install drdid, replace

* ══════════════════════════════════════════════════════════════
* 1. DATA PREPARATION
* ══════════════════════════════════════════════════════════════

* PANEL SWAP (2026-06-30): the PLACE-2 Madison/Sebastian recode below and the
* Primary+ REG headline require the 84-col RUCC+origin panel (rural_2013,
* total_pop, poverty_rate, *_pc outcomes). The base 20-col arkansas_did_panel.csv
* lacks them. Load the current full analysis panel instead.
import delimited "$datadir/arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv", clear varnames(1)

destring fips year fatal_crashes total_fatalities alcohol_fatal_crashes ///
         countywide_wet first_treated_year cohort years_since_treatment ///
         any_wet_neighbor n_wet_neighbors share_wet_neighbors ///
         any_wet_area_neighbor n_neighbors partial_county ///
         treated_unit neighbor_unit clean_control, replace force

* ── Defensive destring of the headline/covariate columns added by the ──
*    RUCC+origin panel (needed for log_pop, xvars, and per-capita outcomes)
destring nonalc_fatal_crashes fatal_crashes_pc alcohol_crashes_pc ///
         nonalc_fatal_crashes_pc total_pop poverty_rate median_hh_income ///
         rural_2013, replace force

egen county_id = group(fips)
xtset county_id year

*=====================================================================
* patch_madison_sebastian.do  (PLACE 2)  -- integrated 2026-06-30
* Treatment recode for the Callaway & Sant'Anna estimation panel.
* Runs BEFORE the gvar construction below so the Madison recode
* (cohort=2012, treated_unit=1) propagates into gvar_nyt and gvar.
*
* WHAT IT DOES
*   1. Madison (05087) -> 2012 cohort, treated (Benton/Sharp election,
*      Nov 6 2012). Coded to mirror the existing g2012 rows exactly.
*   2. Sebastian (05131), Logan (05083), Woodruff (05147) -> coded WET for
*      the whole window and flagged partial_wet. They stay never-treated,
*      so they fall in the always-wet (excluded) pool, NOT the dry controls.
*   3. Rebuilds clean always_wet / always_dry indicators and log_pop.
*   4. Defines est_sample + a baseline/conservative switch (Step 5).
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
* Headline within-county design = treated + always-DRY controls; always-wet
* dropped (they fail pre-trends). Pass `if est_sample==1` on a csdid call; do
* NOT `keep`, so spillover/heterogeneity still see all rows. With `notyet`,
* est_sample keeps the not-yet-treated as valid controls.
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
di as txt "NOTE: g2022 (Hot Spring 05059, Polk 05113) may drop under notyet with"
di as txt "      no not-yet-treated comparators after 2022 (never-treated dry"
di as txt "      controls can still identify them)."
di as txt "{hline 64}"
*===================== END PLACE-2 PATCH =============================


* ── Construct C&S-A group variable ───────────────────────────
* gvar = cohort year for treated, 0 for never-treated, . for excluded

gen gvar = .
replace gvar = cohort if treated_unit == 1 & cohort != .
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

label var gvar "C&S-A group variable (0=never-treated, .=excluded)"

* ── Also construct the treated-only gvar for primary spec ────
gen gvar_nyt = .
replace gvar_nyt = cohort if treated_unit == 1 & cohort != .

label var gvar_nyt "C&S-A group variable (treated counties only)"

* ── Event time for reference ─────────────────────────────────
gen event_time = year - cohort if treated_unit == 1 & cohort != .
label var event_time "Years relative to wet transition"

* ── Verify sample composition ────────────────────────────────
di _n "{hline 60}"
di "SAMPLE COMPOSITION"
di "{hline 60}"

di _n "PRIMARY SPEC (not-yet-treated only):"
count if gvar_nyt != .
di "  County-years: `r(N)'"
distinct county_id if gvar_nyt != .
di "  Counties: `r(ndistinct)'"
tab gvar_nyt if year == 2008, mi

di _n "ROBUSTNESS A (+ always-wet neighbors):"
count if gvar != .
di "  County-years: `r(N)'"
distinct county_id if gvar != .
di "  Counties: `r(ndistinct)'"


* ══════════════════════════════════════════════════════════════
* 1b. CHECK FIRST -- Primary+ REG pre-trend after the g2012 recode
*     (RERUN_RUNBOOK Step 3: g2012 now = 3 counties Benton/Sharp/Madison;
*      recheck the FATAL pre-trend under the headline spec BEFORE anything
*      else, and upload this log.)
*     Headline spec = method(reg), not-yet-treated only, xvars(log_pop
*     poverty_rate). method(reg) (not DRIPW) avoids propensity-score
*     separation on the single-county cohorts g2016/g2018.
*     csdid discipline: estimates restore before EACH estat; wrap in
*     capture noisily (small cohorts fail on restricted samples).
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "CHECK FIRST: PRIMARY+ REG PRE-TRENDS (post Madison g2012 recode)"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .

    di _n "Effective sample:"
    distinct county_id
    tab cohort if year == 2008, mi

    * REPORT BOTH pre-trend diagnostics -- they answer different questions:
    *   estat event  -> Pre_avg = AVERAGE pre-treatment effect (1 df). THIS is
    *                   the interpretable C&S-A pre-trend and the number
    *                   comparable to prior "fatal p~0.84 / alcohol p~0.289".
    *   estat pretrend -> JOINT test of all ~35 individual pre-cells. It rejects
    *                   on cell-by-cell noise even when Pre_avg is flat; report
    *                   it, but do not read it as "the" pre-trend.
    local ynames fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes
    local ytags  fat alc nonalc
    local i = 1
    foreach y of local ynames {
        local tag : word `i' of `ytags'
        di _n "{hline 55}"
        di "`y' -- Primary+ REG (method(reg), notyet, xvars)"
        di "{hline 55}"
        capture noisily csdid `y', ivar(county_id) time(year) gvar(gvar_nyt) ///
            method(reg) notyet xvars(log_pop poverty_rate)
        if _rc==0 {
            estimates store chk_`tag'
            estimates restore chk_`tag'
            capture noisily estat event         // <- Pre_avg = pre-trend to upload
            estimates restore chk_`tag'
            capture noisily estat pretrend       // joint test (rejects on noise)
            estimates restore chk_`tag'
            capture noisily estat simple
        }
        else di as error "  csdid failed for `y' (rc=" _rc ") -- see log"
        local ++i
    }
restore


* ══════════════════════════════════════════════════════════════
* 2. ROBUSTNESS D: NOT-YET-TREATED ONLY  (former primary; DEMOTED)
*    (12 treated counties; comparison = not-yet-treated cohorts)
*    Demoted from headline 2026-07-01: fatal pre-trend rejects
*    (Pre_avg 0.317, p=0.037). Retained as robustness + it feeds the
*    _nyt event-study CSVs. Headline is Section 6b (always-dry).
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS D (former primary): NOT-YET-TREATED COMPARISON"
di "12 treated counties, staggered adoption"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id

    * ──────────────────────────────────────────────────────────
    * 2a. FATAL CRASHES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "FATAL CRASHES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatal_nyt
    
    * Pre-trend test
    di _n "Pre-trend test:"
    estat pretrend
    
    * Event-study aggregation
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_nyt)
    
    csdid_plot, name(es_fatal_nyt, replace) xtitle("Periods since treatment") ///
        title("Fatal Crashes: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_fatal.png", replace width(2000)
    
    * Simple ATT
    di _n "Simple (overall) ATT:"
    estat simple
    
    * Group-level ATTs
    di _n "Group-level ATTs:"
    estat group
    
    * Calendar-time ATTs
    di _n "Calendar-time ATTs:"
    estat calendar
    
    * ──────────────────────────────────────────────────────────
    * 2b. ALCOHOL-INVOLVED FATAL CRASHES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "ALCOHOL CRASHES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_alc_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_nyt)
    
    csdid_plot, name(es_alc_nyt, replace) xtitle("Periods since treatment") ///
        title("Alcohol Crashes: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_alcohol.png", replace width(2000)
    
    di _n "Simple (overall) ATT:"
    estat simple
    
    di _n "Group-level ATTs:"
    estat group
    
    di _n "Calendar-time ATTs:"
    estat calendar
    
    * ──────────────────────────────────────────────────────────
    * 2c. TOTAL FATALITIES
    * ──────────────────────────────────────────────────────────
    
    di _n "{hline 50}"
    di "TOTAL FATALITIES — Primary (not-yet-treated)"
    di "{hline 50}"
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatalities_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatalities_nyt)
    
    csdid_plot, name(es_fatalities_nyt, replace) xtitle("Periods since treatment") ///
        title("Total Fatalities: Event Study (not-yet-treated)") ///
        subtitle("Primary specification")
    graph export "$outdir/primary_event_fatalities.png", replace width(2000)
    
    di _n "Simple (overall) ATT:"
    estat simple
    
    di _n "Group-level ATTs:"
    estat group
    
restore


* ══════════════════════════════════════════════════════════════
* 3. SHORT-RUN vs LONG-RUN ATT DECOMPOSITION
*    (Primary spec: not-yet-treated only)
*    Tests whether the travel-distance channel dominates
*    in the short run before consumption adjustment catches up
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SHORT-RUN vs LONG-RUN ATT DECOMPOSITION"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * Fatal crashes
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    * Short-run: average of Tp0, Tp1, Tp2 (0–2 years post)
    di _n "Fatal crashes — short-run ATT (0–2 years):"
    estat event
    
    * We need to manually compute short vs long-run from the 
    * event-study output. The estat event output gives us the
    * coefficients; we read them from e(b).
    
    matrix b = e(b)
    matrix list b
    
    * Alcohol crashes
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    di _n "Alcohol crashes — event study coefficients:"
    estat event
    matrix b_alc = e(b)
    matrix list b_alc
    
restore

di _n "NOTE: Inspect the Pre_avg and Post_avg rows in the event study"
di "output above for the aggregated pre/post averages. For a formal"
di "short-run vs long-run test, compute weighted averages of Tp0-Tp2"
di "(short) vs Tp3+ (long) from the coefficient vector using lincom"
di "or nlcom after estat event."


* ══════════════════════════════════════════════════════════════
* 4. ROBUSTNESS A: ADD ALWAYS-WET NEIGHBORS AS NEVER-TREATED
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS A: + ALWAYS-WET NEIGHBORS AS NEVER-TREATED"
di "44 counties (12 treated + 32 always-wet)"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness A"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatal_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_wet)
    
    csdid_plot, name(es_fatal_wet, replace) xtitle("Periods since treatment") ///
        title("Robustness A: Fatal Crashes (+ always-wet)")
    graph export "$outdir/robust_a_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness A"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_alc_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_wet)
    
    csdid_plot, name(es_alc_wet, replace) xtitle("Periods since treatment") ///
        title("Robustness A: Alcohol Crashes (+ always-wet)")
    graph export "$outdir/robust_a_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Total fatalities ─────────────────────────────────────
    di _n "TOTAL FATALITIES — Robustness A"
    
    csdid total_fatalities, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estimates store cs_fatalities_wet
    
    di _n "Pre-trend test:"
    estat pretrend
    
    estat event, estore(es_fatalities_wet)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 5. ROBUSTNESS B: PRE-COVID SAMPLE (2008–2019)
*    Not-yet-treated only, drops 2020–2023
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS B: PRE-COVID SAMPLE (2008-2019)"
di "Not-yet-treated only"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    keep if year <= 2019
    
    * Drop cohorts with treatment outside window
    drop if gvar_nyt == 2020 | gvar_nyt == 2022
    
    di "Sample: `c(N)' county-years"
    distinct county_id
    tab gvar_nyt if year == 2008
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness B (pre-COVID, NYT only)"
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_fatal_pre2020_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_fatal_pre2020_nyt)
    
    csdid_plot, name(es_fatal_pre2020_nyt, replace) xtitle("Periods since treatment") ///
        title("Robustness B: Fatal Crashes (2008-2019, NYT)")
    graph export "$outdir/robust_b_event_fatal.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple
    
    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness B (pre-COVID, NYT only)"
    
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    
    estimates store cs_alc_pre2020_nyt
    
    di _n "Pre-trend test:"
    estat pretrend
    
    di _n "Event-study aggregation:"
    estat event, estore(es_alc_pre2020_nyt)
    
    csdid_plot, name(es_alc_pre2020_nyt, replace) xtitle("Periods since treatment") ///
        title("Robustness B: Alcohol Crashes (2008-2019, NYT)")
    graph export "$outdir/robust_b_event_alcohol.png", replace width(2000)
    
    di _n "Simple ATT:"
    estat simple

restore


* ══════════════════════════════════════════════════════════════
* 6. ROBUSTNESS C: REGRESSION ESTIMATOR (not-yet-treated only)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "ROBUSTNESS C: REGRESSION ESTIMATOR (NYT only)"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * ── Fatal crashes ────────────────────────────────────────
    di _n "FATAL CRASHES — Robustness C (reg, NYT)"
    
    * Headline "Primary+ REG": method(reg), notyet, xvars(log_pop poverty_rate).
    * restore before EACH estat (each overwrites active results); capture noisily
    * because small cohorts can fail on the restricted sample.
    capture noisily csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet xvars(log_pop poverty_rate)
    estimates store cs_fatal_reg_nyt

    di _n "Pre-trend test:"
    estimates restore cs_fatal_reg_nyt
    capture noisily estat pretrend

    di _n "Simple ATT:"
    estimates restore cs_fatal_reg_nyt
    capture noisily estat simple

    * ── Alcohol crashes ──────────────────────────────────────
    di _n "ALCOHOL CRASHES — Robustness C (reg, NYT)"

    capture noisily csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet xvars(log_pop poverty_rate)
    estimates store cs_alc_reg_nyt

    di _n "Pre-trend test:"
    estimates restore cs_alc_reg_nyt
    capture noisily estat pretrend

    di _n "Simple ATT:"
    estimates restore cs_alc_reg_nyt
    capture noisily estat simple

    * ── Non-alcohol fatal crashes (mechanism decomposition) ───
    * nonalc ~ exposure alone; alcohol-minus-nonalc isolates impairment.
    * Same Primary+ REG battery so the contrast is spec-matched.
    di _n "NON-ALCOHOL FATAL CRASHES — Robustness C (reg, NYT)"

    capture noisily csdid nonalc_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet xvars(log_pop poverty_rate)
    estimates store cs_nonalc_reg_nyt

    di _n "Pre-trend test (flat pre-trend = common-confounder diagnostic):"
    estimates restore cs_nonalc_reg_nyt
    capture noisily estat pretrend

    di _n "Simple ATT:"
    estimates restore cs_nonalc_reg_nyt
    capture noisily estat simple

restore


* ══════════════════════════════════════════════════════════════
* 6b. *** HEADLINE / PRIMARY SPECIFICATION ***
*     WITHIN-COUNTY DESIGN: TREATED + ALWAYS-DRY CONTROLS
*     (PLACE-2 est_sample design; gvar(cohort), notyet, Primary+ REG)
*
*     PROMOTED TO HEADLINE 2026-07-01 (see file header): the only design
*     with clean fatal AND alcohol pre-trends (fatal Pre_avg p=0.807,
*     alcohol p=0.732; nonalc flat p=0.920). Event-study coefficients for
*     this design are exported to output/event_study_*_headline.csv in
*     Section 6d below.
*
*     README "COMPARISON GROUP FRAMING": the within-county direct-effect
*     control group is the always-DRY pool (always-wet fails pre-trends and
*     is demoted to the spillover design). est_sample = treated (cohort>0) +
*     always-dry never-treated (cohort==0). gvar(cohort) uses 0 = never-
*     treated; `if est_sample==1` drops the always-wet units from the pool;
*     `notyet` additionally keeps not-yet-treated cohorts as valid controls.
*     Same headline spec (method(reg), xvars(log_pop poverty_rate)).
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "WITHIN-COUNTY DESIGN: TREATED + ALWAYS-DRY CONTROLS (gvar(cohort))"
di "{'='*60}" _n

preserve
    keep if est_sample == 1

    di _n "Estimation sample (treated + always-dry):"
    distinct county_id
    tab cohort if year == 2008, mi

    * short store-name tags: `_est_'+name must be <=32 chars (Stata name limit)
    local ynames fatal_crashes alcohol_fatal_crashes nonalc_fatal_crashes
    local ytags  fat alc nonalc
    local i = 1
    foreach y of local ynames {
        local tag : word `i' of `ytags'
        di _n "{hline 55}"
        di "`y' -- within-county (gvar(cohort), reg, notyet, xvars)"
        di "{hline 55}"
        capture noisily csdid `y', ivar(county_id) time(year) gvar(cohort) ///
            method(reg) notyet xvars(log_pop poverty_rate)
        if _rc==0 {
            estimates store cs_`tag'_dry
            estimates restore cs_`tag'_dry
            capture noisily estat pretrend
            estimates restore cs_`tag'_dry
            capture noisily estat simple
            estimates restore cs_`tag'_dry
            capture noisily estat event
        }
        else di as error "  csdid failed for `y' (rc=" _rc ") -- see log"
        local ++i
    }
restore


* ══════════════════════════════════════════════════════════════
* 6c. CONSERVATIVE CONTROL SET (RERUN Step 5) -- HEADLINE ATT, single row
*     Drop the product/area-limited wet units (Sebastian/Logan/Woodruff).
*     They are already coded wet => already OUTSIDE est_sample's dry-control
*     pool, so `& partial_wet==0` is auditable but non-binding: expect
*     baseline == conservative (README: "baseline ~ robustness").
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "CONSERVATIVE CONTROL SET: headline ATT (fatal + alcohol), single row"
di "{'='*60}" _n

preserve
    keep if est_sample == 1 & partial_wet == 0

    di _n "Conservative sample:"
    distinct county_id

    local ynames fatal_crashes alcohol_fatal_crashes
    local ytags  fat alc
    local i = 1
    foreach y of local ynames {
        local tag : word `i' of `ytags'
        di _n "`y' -- conservative (gvar(cohort), reg, notyet, xvars)"
        capture noisily csdid `y', ivar(county_id) time(year) gvar(cohort) ///
            method(reg) notyet xvars(log_pop poverty_rate)
        if _rc==0 {
            estimates store cs_`tag'_cons
            estimates restore cs_`tag'_cons
            capture noisily estat simple
        }
        else di as error "  csdid failed for `y' (rc=" _rc ") -- see log"
        local ++i
    }
restore


* ══════════════════════════════════════════════════════════════
* 6d. EXPORT HEADLINE EVENT-STUDY COEFFICIENTS
*     (within-county always-dry design = Section 6b headline spec)
*     Mirrors Section 9's exporter but for gvar(cohort)+est_sample+reg.
*     -> output/event_study_{fatal,alcohol}_headline.csv
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "EXPORTING HEADLINE EVENT-STUDY COEFFICIENTS (within-county always-dry)"
di "{'='*60}" _n

preserve
    keep if est_sample == 1

    foreach spec in fatal alcohol {
        local yv   = cond("`spec'"=="fatal","fatal_crashes","alcohol_fatal_crashes")
        local ylab = cond("`spec'"=="fatal","Fatal crashes","Alcohol-involved fatal crashes")

        capture noisily csdid `yv', ivar(county_id) time(year) gvar(cohort) ///
            method(reg) notyet xvars(log_pop poverty_rate)
        if _rc {
            di as error "  headline csdid failed for `yv' (rc=`=_rc') -- skipping export"
            continue
        }

        * event-study aggregation: estore feeds csdid_plot; r(table) feeds the CSV
        capture noisily estat event, estore(es_`spec'_head)
        capture matrix E = r(table)

        * ---- EVENT-TIME coefficients -> CSV (term,coef,se,p) --------------
        *   r(table): row1=b, row2=se, row4=p; colnames = Pre_avg Post_avg
        *   Tm.. Tp..  This is the shape event_study_plots.py expects (it
        *   filters Tm*/Tp*). NOTE: this REPLACES the old group-time export --
        *   the headline figure needs event time, not ATT(g,t).
        if !_rc {
            local enames : colnames E
            tempname fh
            file open `fh' using "$outdir/event_study_`spec'_headline.csv", write replace
            file write `fh' "term,coef,se,p" _n
            local k = 1
            foreach nm of local enames {
                file write `fh' "`nm',`=E[1,`k']',`=E[2,`k']',`=E[4,`k']'" _n
                local ++k
            }
            file close `fh'
            di "Saved: $outdir/event_study_`spec'_headline.csv (event-time)"
        }

        * ---- in-Stata publication PNG (same pipeline as primary/robust) ---
        capture noisily csdid_plot, name(es_`spec'_head, replace) ///
            xtitle("Years relative to wet transition") ///
            title("Headline: `ylab'") ///
            subtitle("Within-county design (treated + always-dry controls)")
        capture graph export "$outdir/headline_event_`spec'.png", replace width(2000)
        di "Saved: $outdir/headline_event_`spec'.png"
    }
restore


* ══════════════════════════════════════════════════════════════
* 7. PRE-TREND DIAGNOSTIC: WHICH GROUP-TIME ATTs DRIVE REJECTION?
*    (For the always-wet specification that fails pre-trends)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "PRE-TREND DIAGNOSTIC"
di "Which cohorts drive the pre-trend rejection in Robustness A?"
di "{'='*60}" _n

preserve
    keep if gvar != .
    
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    * The full group-time ATT output above shows pre-treatment
    * coefficients for each cohort. Below we flag the individually
    * significant ones.
    
    di _n "Inspect the group-time ATT output above."
    di "Pre-treatment coefficients with |z| > 2 indicate"
    di "differential pre-trends for that specific cohort × period."
    di ""
    di "Key patterns from first run:"
    di "  g2016: multiple pre-treatment ATTs with |z| > 3"
    di "  g2018: t_2008_2009 sig negative, t_2012_2013 sig negative"
    di "  g2022: t_2008_2009, t_2010_2011 sig"
    di ""
    di "These cohorts show the strongest differential pre-trends"
    di "relative to the always-wet comparison group. This is"
    di "consistent with always-wet counties having systematically"
    di "different crash trajectories, not with anticipation effects"
    di "in the treated counties."
    di ""
    di "The not-yet-treated specification avoids this problem"
    di "because the comparison counties are drawn from the same"
    di "population (counties that eventually vote to go wet)."

restore


* ══════════════════════════════════════════════════════════════
* 8. SUMMARY TABLE
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "SUMMARY: SIMPLE ATTs ACROSS SPECIFICATIONS"
di "{'='*60}" _n
di ""
di "Spec                                    | Fatal  | Alcohol | Pre-trend (fatal) | Pre-trend (alc)"
di "────────────────────────────────────────────────────────────────────────────────────────────────"
di "HEADLINE 6b: within-county always-dry   | -0.64  | -0.28   | p = 0.807  ✓      | p = 0.732  ✓"
di "  Conservative 6c (drop partial_wet)    | -0.64  | -0.28   | (== headline; non-binding)"
di "Robust D: NYT only (regression, 6/Rc)   | -0.49  | -0.68   | p = 0.037  ✗      | p = 0.293  ✓"
di "Robust A: + always-wet (DRIPW)          | [coef] | [coef]  | p ≈ 0.000  ✗      | p ≈ 0.000  ✗"
di "Robust B: Pre-COVID, NYT (DRIPW)        | [coef] | [coef]  | [p-value]         | [p-value]"
di ""
di "Numbers are the 2026-06-30 post-recode run (reg + xvars); verify vs"
di "the estat output above after this run. Standard errors in parentheses."
di ""
di "KEY FINDING: The HEADLINE within-county design (treated + always-DRY"
di "controls) is the only spec with clean fatal AND alcohol pre-trends"
di "(fatal Pre_avg p=0.807, alcohol p=0.732; nonalc flat p=0.920 licenses"
di "the alcohol read). The former not-yet-treated primary rejects the fatal"
di "pre-trend (p=0.037) and the always-wet comparison fails badly (p≈0.000)."
di "Aggregate ATTs are null everywhere -- the paper's contribution is the"
di "rural/urban heterogeneity (see 04b_heterogeneity_rucc.do), not the pooled ATT."


* ══════════════════════════════════════════════════════════════
* 9. EXPORT EVENT-STUDY COEFFICIENTS FOR PYTHON PLOTTING
*    (Primary spec, both outcomes)
* ══════════════════════════════════════════════════════════════

di _n(3) "{'='*60}"
di "EXPORTING EVENT-STUDY COEFFICIENTS"
di "{'='*60}" _n

preserve
    keep if gvar_nyt != .
    
    * ── Fatal crashes ────────────────────────────────────────
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    estat event
    
    * Extract coefficient vector and variance matrix
    matrix b_fatal = e(b)
    matrix V_fatal = e(V)
    
    * Build a small dataset of event-study coefficients
    * Column names from estat event: Pre_avg Post_avg Tm11 Tm10 ... Tp0 Tp1 ...
    * We extract manually based on position
    
    local ncols = colsof(b_fatal)
    local names : colnames b_fatal
    
    * Save to CSV
    tempname fh
    file open `fh' using "$outdir/event_study_fatal_nyt.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b_fatal[1, `i']
        local var  = V_fatal[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/event_study_fatal_nyt.csv"
    
    * ── Alcohol crashes ──────────────────────────────────────
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet
    estat event
    
    matrix b_alc = e(b)
    matrix V_alc = e(V)
    
    local ncols = colsof(b_alc)
    local names : colnames b_alc
    
    tempname fh
    file open `fh' using "$outdir/event_study_alcohol_nyt.csv", write replace
    file write `fh' "term,coef,se" _n
    
    local i = 1
    foreach name of local names {
        local coef = b_alc[1, `i']
        local var  = V_alc[`i', `i']
        local se   = sqrt(`var')
        file write `fh' "`name',`coef',`se'" _n
        local i = `i' + 1
    }
    file close `fh'
    di "Saved: $outdir/event_study_alcohol_nyt.csv"

restore


di _n(2) "{'='*60}"
di "ESTIMATION COMPLETE"
di "{'='*60}"
di _n "Output directory: $outdir"
di "Files produced:"
di "  headline_event_fatal.png          (HEADLINE: within-county always-dry)"
di "  headline_event_alcohol.png        (HEADLINE: within-county always-dry)"
di "  primary_event_fatal.png           (Robustness D: not-yet-treated)"
di "  primary_event_alcohol.png         (Robustness D: not-yet-treated)"
di "  primary_event_fatalities.png"
di "  robust_a_event_fatal.png"
di "  robust_a_event_alcohol.png"
di "  robust_b_event_fatal.png"
di "  robust_b_event_alcohol.png"
di "  event_study_fatal_headline.csv    (HEADLINE: within-county always-dry, event-time)"
di "  event_study_alcohol_headline.csv  (HEADLINE: within-county always-dry)"
di "  event_study_fatal_nyt.csv         (Robustness D: not-yet-treated)"
di "  event_study_alcohol_nyt.csv       (Robustness D: not-yet-treated)"
di _n "Next steps:"
di "  1. Inspect pre-trend p-values across all specs"
di "  2. Compare primary (NYT) vs Robustness A (+ always-wet) ATTs"
di "  3. Use exported CSVs to produce custom matplotlib event-study plots"
di "  4. Proceed to 03_spillovers.do for neighbor county analysis"
