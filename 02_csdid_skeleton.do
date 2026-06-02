/*==============================================================
  02_csdid_estimation.do  [SKELETON — control group framing]
  
  Shows how the comparison group choice maps to csdid syntax.
  Full estimation file to follow once framing is confirmed.
==============================================================*/

* ── Install csdid if needed ──────────────────────────────────
* ssc install csdid, replace
* ssc install drdid, replace    // dependency

* ── Setup (assumes 01_descriptives.do has been run) ──────────

* Key variable: gvar = cohort year for treated, 0 for never-treated
* C&S-A treats gvar==0 as "never treated" comparison group

* ── Define the cohort variable for csdid ─────────────────────

* Treated counties: gvar = their cohort year (2010, 2012, ..., 2022)
* Already assigned in the CSV as 'cohort'

* Always-wet neighbors: gvar = 0 (never-treated comparison)
* Always-dry neighbors: EXCLUDE from direct-effect estimation
*   (they receive spillover treatment; used in spillover analysis)

gen gvar = .

* Treated counties: use their cohort year
replace gvar = cohort if treated_unit == 1 & cohort != .

* Always-wet neighbors: never-treated comparison group (gvar = 0)
replace gvar = 0 if neighbor_unit == 1 & countywide_wet == 1

* Always-dry neighbors: drop from main sample 
*   (contaminated by spillovers — used separately)
* They have neighbor_unit==1 & countywide_wet==0

label var gvar "C&S-A group variable (0 = never-treated)"

* ── Main estimation sample ───────────────────────────────────

* Option C (recommended): treated + always-wet neighbors
preserve
    keep if gvar != .    // drops the 31 always-dry neighbor counties
    
    * Confirm sample
    tab gvar, mi
    
    * BASELINE: not-yet-treated + never-treated comparison
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet
    
    estat event, estore(cs_fatal)
    csdid_plot, title("C&S-A Event Study: Fatal Crashes")
    
    * ROBUSTNESS: not-yet-treated only (drop never-treated)
    csdid fatal_crashes, ivar(county_id) time(year) gvar(gvar) ///
        method(dripw) notyet long
restore

* ── Spillover estimation (separate analysis) ─────────────────
* Uses always-dry neighbors as the "treated by spillover" group
* Comparison: always-wet neighbors (no spillover change)
* This is a separate DiD — to be developed in 03_spillovers.do
