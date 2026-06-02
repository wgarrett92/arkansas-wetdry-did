/*
============================================================
  02_csdid_covariate_diagnostic.do
  Find the largest covariate set that works with DRIPW
  
  Run this BEFORE the full estimation file.
  Tests progressively larger covariate sets.
============================================================
*/

clear all
set more off

local datafile "arkansas_panel_annual_merged_v2.csv"
import delimited "`datafile'", clear varnames(1) case(lower)

egen county_id = group(fips)

gen gvar_nyt = .
replace gvar_nyt = cohort if treated_unit == 1

gen log_pop = ln(total_pop)

xtset county_id year

* ── Test 1: No covariates (baseline — should work) ─────────
di _n "============================================================"
di "TEST 1: No covariates"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 1: PASSED"
}
if _rc != 0 di "TEST 1: FAILED (rc = " _rc ")"

* ── Test 2: log_pop only ───────────────────────────────────
di _n "============================================================"
di "TEST 2: log_pop"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 2: PASSED"
}
if _rc != 0 di "TEST 2: FAILED (rc = " _rc ")"

* ── Test 3: log_pop + poverty_rate ─────────────────────────
di _n "============================================================"
di "TEST 3: log_pop poverty_rate"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop poverty_rate, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 3: PASSED"
}
if _rc != 0 di "TEST 3: FAILED (rc = " _rc ")"

* ── Test 4: log_pop + poverty_rate + pct_white ─────────────
di _n "============================================================"
di "TEST 4: log_pop poverty_rate pct_white"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop poverty_rate pct_white, ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 4: PASSED"
}
if _rc != 0 di "TEST 4: FAILED (rc = " _rc ")"

* ── Test 5: + pct_married ──────────────────────────────────
di _n "============================================================"
di "TEST 5: log_pop poverty_rate pct_white pct_married"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop poverty_rate pct_white pct_married, ///
        ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 5: PASSED"
}
if _rc != 0 di "TEST 5: FAILED (rc = " _rc ")"

* ── Test 6: + pct_21plus ───────────────────────────────────
di _n "============================================================"
di "TEST 6: log_pop poverty_rate pct_white pct_married pct_21plus"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop poverty_rate pct_white pct_married pct_21plus, ///
        ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 6: PASSED"
}
if _rc != 0 di "TEST 6: FAILED (rc = " _rc ")"

* ── Test 7: + churches_pc ──────────────────────────────────
di _n "============================================================"
di "TEST 7: log_pop poverty_rate pct_white pct_married pct_21plus churches_pc"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop poverty_rate pct_white pct_married pct_21plus churches_pc, ///
        ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 7: PASSED"
}
if _rc != 0 di "TEST 7: FAILED (rc = " _rc ")"

* ── Test 8: Full set (+ median_hh_income) ──────────────────
di _n "============================================================"
di "TEST 8: FULL — log_pop median_hh_income poverty_rate pct_white pct_21plus churches_pc pct_married"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop median_hh_income poverty_rate pct_white pct_21plus churches_pc pct_married, ///
        ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(dripw) notyet long2
    estat simple
    di "TEST 8: PASSED"
}
if _rc != 0 di "TEST 8: FAILED (rc = " _rc ")"

* ── Fallback: Full set with method(reg) ────────────────────
di _n "============================================================"
di "TEST 9: FULL covariate set + method(reg) — no propensity score"
di "============================================================"
capture noisily {
    csdid alcohol_fatal_crashes log_pop median_hh_income poverty_rate pct_white pct_21plus churches_pc pct_married, ///
        ivar(county_id) time(year) gvar(gvar_nyt) ///
        method(reg) notyet long2
    estat simple
    di "TEST 9: PASSED"
}
if _rc != 0 di "TEST 9: FAILED (rc = " _rc ")"

di _n "============================================================"
di "DIAGNOSTIC COMPLETE"
di "============================================================"
di "Use the largest passing DRIPW test for the primary spec."
di "If only method(reg) works with full covariates, use that"
di "as primary and DRIPW with reduced covariates as robustness."
