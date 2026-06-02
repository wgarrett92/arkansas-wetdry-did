/*==============================================================
  01_descriptives.do
  Arkansas Wet/Dry DiD Panel — Data Load & Descriptive Analysis
  
  PURPOSE:
    1. Import and label the panel dataset
    2. Generate summary statistics by treatment group
    3. Produce time series plots (treated vs. neighbor)
    4. Produce event-study plots (centered on transition year)
    5. Cohort composition table
  
  REQUIREMENTS:
    - Stata 16+ (for frames/style options; core code runs on 14+)
    - Update the global $datadir path below
    
  AUTHOR: [Your Name]
  DATE:   2026-03-19
==============================================================*/

clear all
set more off
set scheme s2color

* ── USER: Set your working directory here ────────────────────
global datadir "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas"          // <-- update to your project folder
global outdir  "/Users/willgarrett/Desktop/Research_copy/Crime/General_Crime/Data/Arkansas/output"
cap mkdir "$outdir"

* ══════════════════════════════════════════════════════════════
* 1. IMPORT & LABEL
* ══════════════════════════════════════════════════════════════

import delimited "/Volumes/LaCie/Research/Crime/General_Crime/Data/Arkansas/arkansas_did_panel.csv", clear varnames(1)

* Destring any variables that came in as strings
destring fips year fatal_crashes total_fatalities alcohol_fatal_crashes ///
         countywide_wet first_treated_year cohort years_since_treatment ///
         any_wet_neighbor n_wet_neighbors share_wet_neighbors ///
         any_wet_area_neighbor n_neighbors partial_county ///
         treated_unit neighbor_unit clean_control, replace force

* Numeric county identifier for panel commands
egen county_id = group(fips)

* Label key variables
label var fatal_crashes        "Fatal crashes (FARS)"
label var total_fatalities     "Total fatalities (FARS)"
label var alcohol_fatal_crashes "Alcohol-involved fatal crashes"
label var alcohol_share        "Share alcohol-involved"
label var countywide_wet       "County is wet (=1)"
label var treated_unit         "Treated county (ever transitions wet)"
label var neighbor_unit        "Neighbor of treated county"
label var cohort               "C&S-A cohort year (year of wet transition)"
label var years_since_treatment "Years since wet transition"

* Declare panel
xtset county_id year
di "Panel declared: `r(panelvar)' by `r(timevar)'"

* ── Event time variable for all treated counties ─────────────
gen event_time = year - cohort if treated_unit == 1 & cohort != .

label var event_time "Years relative to wet transition"

* ── Group indicator for plots ────────────────────────────────
gen     group = 0
replace group = 1 if treated_unit == 1
replace group = 2 if neighbor_unit == 1
label define grp_lbl 0 "Other" 1 "Treated" 2 "Neighbor"
label values group grp_lbl

* ══════════════════════════════════════════════════════════════
* 2. SUMMARY STATISTICS
* ══════════════════════════════════════════════════════════════

di _n "{hline 60}"
di "PANEL OVERVIEW"
di "{hline 60}"
tab year, summarize(fatal_crashes)
quietly levelsof county_id, local(all_counties)
di "Total counties: `r(r)'"
quietly levelsof county_id if treated_unit == 1, local(treated_counties)
di "Treated counties: `r(r)'"
quietly levelsof county_id if neighbor_unit == 1, local(neighbor_counties)
di "Neighbor counties: `r(r)'"

di _n "{hline 60}"
di "OUTCOME MEANS BY TREATMENT GROUP"
di "{hline 60}"

* Overall
tabstat fatal_crashes total_fatalities alcohol_fatal_crashes alcohol_share, ///
    by(group) stats(mean sd min p50 max n) format(%9.2f) columns(statistics)

* Pre vs post for treated counties
di _n "TREATED COUNTIES: Pre vs. Post Transition"
tabstat fatal_crashes alcohol_fatal_crashes alcohol_share ///
    if treated_unit == 1, ///
    by(countywide_wet) stats(mean sd n) format(%9.2f) columns(statistics)

* ── Cohort summary table ────────────────────────────────────
di _n "{hline 60}"
di "COHORT SUMMARY"
di "{hline 60}"
tabstat fatal_crashes alcohol_fatal_crashes ///
    if treated_unit == 1 & event_time == 0, ///
    by(cohort) stats(n mean) format(%9.2f) columns(statistics)

* ══════════════════════════════════════════════════════════════
* 3. TIME SERIES PLOTS: Treated vs. Neighbor
* ══════════════════════════════════════════════════════════════

* Collapse to group × year means
preserve
    collapse (mean) mean_fatal=fatal_crashes ///
                    mean_alc=alcohol_fatal_crashes ///
             (sd)   sd_fatal=fatal_crashes ///
                    sd_alc=alcohol_fatal_crashes ///
             (count) n_fatal=fatal_crashes, ///
        by(group year)
    
    * Standard errors
    gen se_fatal = sd_fatal / sqrt(n_fatal)
    gen se_alc   = sd_alc   / sqrt(n_fatal)
    
    * 95% CIs
    gen ci_lo_fatal = mean_fatal - 1.96 * se_fatal
    gen ci_hi_fatal = mean_fatal + 1.96 * se_fatal
    gen ci_lo_alc   = mean_alc   - 1.96 * se_alc
    gen ci_hi_alc   = mean_alc   + 1.96 * se_alc
    
    * ── Figure 1: Fatal Crashes ──────────────────────────────
    twoway (rarea ci_lo_fatal ci_hi_fatal year if group == 1, ///
                color("201 168 76%20") lwidth(none)) ///
           (rarea ci_lo_fatal ci_hi_fatal year if group == 2, ///
                color("140 155 181%15") lwidth(none)) ///
           (connected mean_fatal year if group == 1, ///
                lcolor("201 168 76") mcolor("201 168 76") ///
                lwidth(medthick) msymbol(O) msize(small)) ///
           (connected mean_fatal year if group == 2, ///
                lcolor("36 53 96") mcolor("36 53 96") ///
                lwidth(medthick) msymbol(S) msize(small)), ///
        xline(2020.5, lcolor("199 81 70%40") lpattern(dash)) ///
        text(12 2021.5 "FARS" "discont.", size(vsmall) color("199 81 70")) ///
        title("Fatal Crashes: Treated vs. Neighbor Counties", ///
              color("26 39 68") size(medium)) ///
        subtitle("2008–2023", color("140 155 181")) ///
        ytitle("Mean Fatal Crashes per County") ///
        xtitle("Year") ///
        xlabel(2008(2)2023) ///
        legend(order(3 "Treated (newly wet)" 4 "Neighbor counties") ///
               rows(1) size(small) pos(11) ring(0)) ///
        graphregion(color("244 244 240")) plotregion(color("244 244 240")) ///
        name(fig1_fatal_ts, replace)
    graph export "$outdir/fig1_fatal_timeseries.png", replace width(2000)
    
    * ── Figure 2: Alcohol-Involved Fatal Crashes ─────────────
    twoway (rarea ci_lo_alc ci_hi_alc year if group == 1, ///
                color("201 168 76%20") lwidth(none)) ///
           (rarea ci_lo_alc ci_hi_alc year if group == 2, ///
                color("140 155 181%15") lwidth(none)) ///
           (connected mean_alc year if group == 1, ///
                lcolor("201 168 76") mcolor("201 168 76") ///
                lwidth(medthick) msymbol(O) msize(small)) ///
           (connected mean_alc year if group == 2, ///
                lcolor("36 53 96") mcolor("36 53 96") ///
                lwidth(medthick) msymbol(S) msize(small)), ///
        xline(2020.5, lcolor("199 81 70%40") lpattern(dash)) ///
        text(4 2021.5 "FARS" "discont.", size(vsmall) color("199 81 70")) ///
        title("Alcohol-Involved Fatal Crashes: Treated vs. Neighbor", ///
              color("26 39 68") size(medium)) ///
        subtitle("2008–2023", color("140 155 181")) ///
        ytitle("Mean Alcohol-Involved Fatal Crashes per County") ///
        xtitle("Year") ///
        xlabel(2008(2)2023) ///
        legend(order(3 "Treated (newly wet)" 4 "Neighbor counties") ///
               rows(1) size(small) pos(11) ring(0)) ///
        graphregion(color("244 244 240")) plotregion(color("244 244 240")) ///
        name(fig2_alc_ts, replace)
    graph export "$outdir/fig2_alcohol_timeseries.png", replace width(2000)
restore

* ══════════════════════════════════════════════════════════════
* 4. EVENT-STUDY PLOTS (Raw Means, Treated Counties)
* ══════════════════════════════════════════════════════════════

preserve
    keep if treated_unit == 1 & event_time != .
    keep if inrange(event_time, -8, 8)
    
    collapse (mean) mean_fatal=fatal_crashes ///
                    mean_alc=alcohol_fatal_crashes ///
             (sd)   sd_fatal=fatal_crashes ///
                    sd_alc=alcohol_fatal_crashes ///
             (count) n=fatal_crashes, ///
        by(event_time)
    
    gen se_fatal = sd_fatal / sqrt(n)
    gen se_alc   = sd_alc   / sqrt(n)
    gen ci_lo_fatal = mean_fatal - 1.96 * se_fatal
    gen ci_hi_fatal = mean_fatal + 1.96 * se_fatal
    gen ci_lo_alc   = mean_alc   - 1.96 * se_alc
    gen ci_hi_alc   = mean_alc   + 1.96 * se_alc
    
    * ── Figure 3: Event-time fatal crashes ───────────────────
    twoway (rarea ci_lo_fatal ci_hi_fatal event_time, ///
                color("36 53 96%15") lwidth(none)) ///
           (connected mean_fatal event_time, ///
                lcolor("26 39 68") mcolor("26 39 68") ///
                lwidth(medthick) msymbol(O) msize(small)), ///
        xline(-0.5, lcolor("201 168 76") lwidth(medium) lpattern(dash)) ///
        text(14 -4.5 "PRE", size(small) color("140 155 181")) ///
        text(14  4   "POST", size(small) color("201 168 76")) ///
        title("Event Study: Fatal Crashes in Treated Counties", ///
              color("26 39 68") size(medium)) ///
        subtitle("t = 0 is wet transition year", color("140 155 181")) ///
        ytitle("Mean Fatal Crashes per County") ///
        xtitle("Years Relative to Wet Transition") ///
        xlabel(-8(1)8) ///
        legend(order(2 "Mean outcome" 1 "95% CI") ///
               rows(1) size(small) pos(11) ring(0)) ///
        graphregion(color("244 244 240")) plotregion(color("244 244 240")) ///
        name(fig3_event_fatal, replace)
    graph export "$outdir/fig3_event_fatal.png", replace width(2000)
    
    * ── Figure 4: Event-time alcohol crashes ─────────────────
    twoway (rarea ci_lo_alc ci_hi_alc event_time, ///
                color("36 53 96%15") lwidth(none)) ///
           (connected mean_alc event_time, ///
                lcolor("26 39 68") mcolor("26 39 68") ///
                lwidth(medthick) msymbol(O) msize(small)), ///
        xline(-0.5, lcolor("201 168 76") lwidth(medium) lpattern(dash)) ///
        text(6 -4.5 "PRE", size(small) color("140 155 181")) ///
        text(6  4   "POST", size(small) color("201 168 76")) ///
        title("Event Study: Alcohol-Involved Fatal Crashes", ///
              color("26 39 68") size(medium)) ///
        subtitle("Treated counties, t = 0 is wet transition", ///
              color("140 155 181")) ///
        ytitle("Mean Alcohol-Involved Fatal Crashes") ///
        xtitle("Years Relative to Wet Transition") ///
        xlabel(-8(1)8) ///
        legend(order(2 "Mean outcome" 1 "95% CI") ///
               rows(1) size(small) pos(11) ring(0)) ///
        graphregion(color("244 244 240")) plotregion(color("244 244 240")) ///
        name(fig4_event_alc, replace)
    graph export "$outdir/fig4_event_alcohol.png", replace width(2000)
    
    * ── Sample size at each event time (for reference) ───────
    di _n "{hline 40}"
    di "SAMPLE SIZE BY EVENT TIME"
    di "{hline 40}"
    list event_time n mean_fatal mean_alc, clean noobs
restore

* ══════════════════════════════════════════════════════════════
* 5. COHORT COMPOSITION AT EACH EVENT TIME
* ══════════════════════════════════════════════════════════════

preserve
    keep if treated_unit == 1 & event_time != . & inrange(event_time, -8, 8)
    
    * Tabulate cohort × event_time
    di _n "{hline 60}"
    di "COHORT × EVENT TIME CROSS-TAB"
    di "{hline 60}"
    tab event_time cohort
restore

* ══════════════════════════════════════════════════════════════
* 6. DATA QUALITY FLAGS
* ══════════════════════════════════════════════════════════════

di _n "{hline 60}"
di "ALCOHOL FLAG SOURCE BY YEAR"
di "{hline 60}"
tab year alcohol_flag_source

di _n "{hline 60}"
di "ZERO-CRASH COUNTY-YEARS"
di "{hline 60}"
count if fatal_crashes == 0
di "County-years with 0 fatal crashes: `r(N)'"
count if alcohol_fatal_crashes == 0
di "County-years with 0 alcohol crashes: `r(N)'"

di _n "Done. Figures saved to: $outdir"
