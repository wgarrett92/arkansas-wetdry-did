/* ============================================================
   04_heterogeneity_robustness.do
   Arkansas Wet/Dry DiD — Annual heterogeneity & robustness
   
   Contents:
     A. Pre-treatment distance heterogeneity (close vs. far split)
     B. Jackknife by cohort (drop-one robustness)
   
   Depends on:
     arkansas_panel_annual_merged_v2.csv
     treated_pretreat_distance.csv      (produced by Python)
   
   Outputs (all in output_v3/):
     Distance heterogeneity:
       es_fatal_close.csv / es_alcohol_close.csv
       es_fatal_far.csv   / es_alcohol_far.csv
       distance_atts.csv  (simple ATTs for close/far × outcome)
     
     Jackknife:
       jackknife_atts.csv  (ATT for each drop-one cohort × outcome)
   
   Estimator: Primary+ REG throughout
     method(reg), notyet, xvars(log_pop poverty_rate)
   
   Workflow reminder:
     csdid → estimates store → estat simple → estimates restore
             → estat event   → estimates restore → estat pretrend
   ============================================================ */

clear all
set more off
cap log close
log using "output_v3/04_heterogeneity_robustness.log", replace text

/* ── Paths ─────────────────────────────────────────────── */
local panelpath  "arkansas_panel_annual_merged_v2.csv"
local distpath   "treated_pretreat_distance.csv"
local outdir     "output_v3"
cap mkdir "`outdir'"

/* ── Load main panel ───────────────────────────────────── */
import delimited "`panelpath'", clear varnames(1) stringcols(1)

/* Panel identifiers */
encode fips, gen(county_id)
xtset county_id year

/* Log population */
gen log_pop = log(total_pop)
label var log_pop "Log total population"

/* gvar for Primary+ REG (not-yet-treated only) */
gen gvar_nyt = cohort if treated_unit == 1
/* non-treated get missing → excluded from NYT estimation */

/* ── Load and merge distance data ──────────────────────── */
preserve
  import delimited "`distpath'", clear varnames(1) stringcols(1)
  keep fips dist_nearest_wet_miles
  rename fips fips_str
  tempfile distdata
  save `distdata'
restore

/* Merge distance onto panel (treated counties only) */
gen fips_str = fips
merge m:1 fips_str using `distdata', keep(master match) nogen

/* Median distance split: 28.2 miles (Benton, cohort 2012) */
/* Close: <= 28.2 mi  (7 counties: Saline, Sevier, Hot Spring,    */
/*                     Boone, Randolph, Van Buren, Benton)         */
/* Far:    > 28.2 mi  (5 counties: Little River, Clark, Polk,      */
/*                     Columbia, Sharp)                             */
gen dist_far = (dist_nearest_wet_miles > 28.2) if treated_unit == 1

/* gvar for close-treated counties */
gen gvar_close = cohort if treated_unit == 1 & dist_far == 0
/* gvar for far-treated counties */
gen gvar_far   = cohort if treated_unit == 1 & dist_far == 1

label var dist_nearest_wet_miles "Pre-treatment distance to nearest wet county (miles)"
label var dist_far "Far from wet county (> 28.2 mi at t-1)"

/* ── Helper program ────────────────────────────────────── */
cap program drop run_spec_het
program define run_spec_het
  /* Syntax: run_spec_het gvar outcome label outdir */
  args gvar outcome label outdir
  
  capture noisily {
    csdid `outcome', ivar(county_id) time(year) gvar(`gvar') ///
      method(reg) notyet xvars(log_pop poverty_rate)
  }
  if _rc != 0 {
    di as error "csdid failed for `label' - `outcome'"
    exit
  }
  
  estimates store est_`label'_`outcome'
  
  /* Simple ATT */
  capture noisily estat simple
  estimates restore est_`label'_`outcome'
  
  /* Event study */
  capture noisily {
    estat event
    csdid_stats event
    parmest, saving(`outdir'/es_`outcome'_`label'.dta, replace) ///
      label list(parm label estimate min95 max95 p)
  }
  estimates restore est_`label'_`outcome'
  
  /* Pre-trend */
  capture noisily estat pretrend
  estimates restore est_`label'_`outcome'
  
end

/* ============================================================
   PART A: DISTANCE HETEROGENEITY
   ============================================================ */

di "============================================================"
di "PART A: DISTANCE HETEROGENEITY"
di "Median split at 28.2 miles (pre-treatment distance to"
di "nearest wet county, measured at t-1)"
di "Close (<=28.2 mi): Saline, Sevier, Hot Spring, Boone,"
di "                   Randolph, Van Buren, Benton (n=7)"
di "Far (>28.2 mi):    Little River, Clark, Polk, Columbia,"
di "                   Sharp (n=5)"
di "============================================================"

/* ── A1. Close counties ─────────────────────────────────── */
di _n "--- A1. CLOSE counties (n=7, distance <= 28.2 mi) ---"

foreach outcome in fatal_crashes alcohol_fatal_crashes {
  
  capture noisily {
    csdid `outcome', ivar(county_id) time(year) gvar(gvar_close) ///
      method(reg) notyet xvars(log_pop poverty_rate)
  }
  if _rc == 0 {
    estimates store est_close_`outcome'
    
    di _n "Simple ATT — CLOSE — `outcome':"
    capture noisily estat simple
    estimates restore est_close_`outcome'
    
    di _n "Event study — CLOSE — `outcome':"
    capture noisily estat event
    estimates restore est_close_`outcome'
    
    di _n "Pre-trend — CLOSE — `outcome':"
    capture noisily estat pretrend
    estimates restore est_close_`outcome'
    
    /* Export event study to CSV */
    capture noisily {
      estat event
      /* Store matrix */
      matrix es = r(table)
      /* Export via putexcel or manual approach */
    }
    estimates restore est_close_`outcome'
  }
}

/* ── A2. Far counties ───────────────────────────────────── */
di _n "--- A2. FAR counties (n=5, distance > 28.2 mi) ---"

foreach outcome in fatal_crashes alcohol_fatal_crashes {
  
  capture noisily {
    csdid `outcome', ivar(county_id) time(year) gvar(gvar_far) ///
      method(reg) notyet xvars(log_pop poverty_rate)
  }
  if _rc == 0 {
    estimates store est_far_`outcome'
    
    di _n "Simple ATT — FAR — `outcome':"
    capture noisily estat simple
    estimates restore est_far_`outcome'
    
    di _n "Event study — FAR — `outcome':"
    capture noisily estat event
    estimates restore est_far_`outcome'
    
    di _n "Pre-trend — FAR — `outcome':"
    capture noisily estat pretrend
    estimates restore est_far_`outcome'
  }
}

/* ── A3. Export simple ATTs to CSV ──────────────────────── */
/* Run again cleanly and capture scalars for export */

tempname memhold
postfile `memhold' str20 group str30 outcome ///
  double att se pval using "`outdir'/distance_atts.dta", replace

foreach grp in close far {
  local gv "gvar_`grp'"
  foreach outcome in fatal_crashes alcohol_fatal_crashes {
    capture noisily {
      csdid `outcome', ivar(county_id) time(year) gvar(`gv') ///
        method(reg) notyet xvars(log_pop poverty_rate)
    }
    if _rc == 0 {
      estimates store tmp_`grp'_`outcome'
      capture noisily estat simple
      /* estat simple posts ATT/SE/p to r() */
      local att_val = r(att_1_1)   /* may vary by csdid version */
      local se_val  = r(se_1_1)
      local p_val   = r(p_1_1)
      post `memhold' ("`grp'") ("`outcome'") ///
        (`att_val') (`se_val') (`p_val')
      estimates restore tmp_`grp'_`outcome'
    }
  }
}
postclose `memhold'

use "`outdir'/distance_atts.dta", clear
export delimited using "`outdir'/distance_atts.csv", replace
di "Distance ATTs exported to `outdir'/distance_atts.csv"

/* ── A4. Export event study CSVs ────────────────────────── */
/* Note: csdid estat event output format requires manual matrix extraction */
/* Use the same approach as 02_csdid_estimation_v3.do                      */

use "`panelpath'", clear   /* reload — panel may have been altered */
encode fips, gen(county_id)
xtset county_id year
gen log_pop = log(total_pop)
gen gvar_nyt = cohort if treated_unit == 1
gen fips_str = fips
merge m:1 fips_str using `distdata', keep(master match) nogen
gen dist_far = (dist_nearest_wet_miles > 28.2) if treated_unit == 1
gen gvar_close = cohort if treated_unit == 1 & dist_far == 0
gen gvar_far   = cohort if treated_unit == 1 & dist_far == 1

foreach grp in close far {
  local gv "gvar_`grp'"
  foreach outcome in fatal_crashes alcohol_fatal_crashes {
    local stub = cond("`outcome'" == "fatal_crashes", "fatal", "alcohol")
    
    capture noisily {
      csdid `outcome', ivar(county_id) time(year) gvar(`gv') ///
        method(reg) notyet xvars(log_pop poverty_rate)
    }
    if _rc == 0 {
      estimates store tmp2_`grp'_`stub'
      capture noisily {
        estat event
        /* Export event study matrix to csv */
        matrix B  = e(b)
        matrix V  = e(V)
        /* Collect via parmest if available, else manual */
        cap which parmest
        if _rc == 0 {
          parmest, saving("`outdir'/es_`stub'_`grp'.dta", replace) ///
            eform label
          use "`outdir'/es_`stub'_`grp'.dta", clear
          export delimited using "`outdir'/es_`stub'_`grp'.csv", replace
          di "Exported: `outdir'/es_`stub'_`grp'.csv"
        }
        else {
          /* Fallback: save from estat event stored r() matrix */
          estat event
          mat res = r(table)
          /* Write manually — row names are event times */
          local ncols = colsof(res)
          di "Event study coefficients for `grp' — `stub':"
          mat list res
        }
      }
      estimates restore tmp2_`grp'_`stub'
    }
  }
}

/* ============================================================
   PART B: JACKKNIFE BY COHORT
   ============================================================ */

di _n "============================================================"
di "PART B: JACKKNIFE BY COHORT (drop-one robustness)"
di "Primary+ REG: method(reg), notyet, xvars(log_pop poverty_rate)"
di "Drops one cohort at a time from treated set; re-estimates"
di "aggregate ATT on remaining cohorts."
di "Cohorts: 2010 2012 2014 2016 2018 2020"
di "(g2022 already excluded from NYT estimation)"
di "============================================================"

/* Reload clean panel */
import delimited "`panelpath'", clear varnames(1) stringcols(1)
encode fips, gen(county_id)
xtset county_id year
gen log_pop = log(total_pop)

tempname jkhold
postfile `jkhold' int dropped_cohort str30 outcome ///
  double att se pval using "`outdir'/jackknife_atts.dta", replace

local cohorts "2010 2012 2014 2016 2018 2020"

foreach drop_g of local cohorts {
  di _n "--- Dropping cohort `drop_g' ---"
  
  /* gvar excluding the dropped cohort */
  gen gvar_jk = cohort if treated_unit == 1 & cohort != `drop_g'
  
  foreach outcome in fatal_crashes alcohol_fatal_crashes {
    capture noisily {
      csdid `outcome', ivar(county_id) time(year) gvar(gvar_jk) ///
        method(reg) notyet xvars(log_pop poverty_rate)
    }
    if _rc == 0 {
      estimates store jk_`drop_g'_`outcome'
      
      di "Simple ATT (drop cohort `drop_g') — `outcome':"
      capture noisily estat simple
      
      /* Capture ATT/SE/p */
      local att_v = r(att_1_1)
      local se_v  = r(se_1_1)
      local p_v   = r(p_1_1)
      post `jkhold' (`drop_g') ("`outcome'") (`att_v') (`se_v') (`p_v')
      
      estimates restore jk_`drop_g'_`outcome'
    }
    else {
      di as error "csdid failed: drop cohort `drop_g' — `outcome'"
      post `jkhold' (`drop_g') ("`outcome'") (.) (.) (.)
    }
  }
  
  drop gvar_jk
}

postclose `jkhold'

use "`outdir'/jackknife_atts.dta", clear
export delimited using "`outdir'/jackknife_atts.csv", replace
di "Jackknife ATTs exported to `outdir'/jackknife_atts.csv"

/* Print summary table */
di _n "============================================================"
di "JACKKNIFE SUMMARY"
di "============================================================"
list dropped_cohort outcome att se pval, sep(2) noobs

/* ============================================================
   DONE
   ============================================================ */
di _n "============================================================"
di "04_heterogeneity_robustness.do complete"
di "Outputs in `outdir'/:"
di "  distance_atts.csv"
di "  es_fatal_close.csv, es_alcohol_close.csv"
di "  es_fatal_far.csv,   es_alcohol_far.csv"
di "  jackknife_atts.csv"
di "============================================================"

log close
