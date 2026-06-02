# Alcohol Access Laws & Road Safety Externalities
## Arkansas Wet/Dry County DiD Analysis — Project README

**Author:** Will Garrett, PhD Candidate, Behavioral Economics
**Last updated:** 2026-03-20

---

## Project overview

This project estimates the causal effect of county-level wet/dry alcohol policy transitions on traffic fatalities in Arkansas using the Callaway & Sant'Anna (2021) staggered difference-in-differences framework. A secondary analysis examines spatial spillovers to neighboring counties.

## Key findings (preliminary)

- **Overall ATT is negative but insignificant** across all specifications (~0.5–2.1 fewer fatal crashes per county-year, not distinguishable from zero).
- **Short-run effects are significant:** Tp1 and Tp2 show reductions of 2.7–3.4 fatal crashes and 1.4–1.5 alcohol crashes per county-year (p < 0.05). Effects dissipate by Tp3+.
- **Interpretation:** Consistent with the travel-distance channel dominating in the short run (fewer impaired miles when local access opens) before the consumption channel catches up.
- **Pre-trend diagnostics:** The not-yet-treated comparison group passes the pre-trend test for alcohol crashes (p = 0.289). The always-wet comparison group fails (p ≈ 0.000), likely due to systematically different crash trajectories.

## Data

| File | Description |
|------|-------------|
| `arkansas_did_panel.csv` | Main analysis dataset. 1,200 rows (75 counties × 16 years, 2008–2023). County-year panel with FARS crash outcomes, wet/dry status, C&S-A cohort identifiers, and spillover variables. |
| `transition_summary.csv` | Summary of wet/dry transitions with dates and vote types. |
| `merge_log.txt` | Documents the panel construction pipeline, including FARS extraction, wet/dry merge, and cohort assignment. |

### Key data notes
- **FARS alcohol flag discontinuity:** `DRUNK_DR` variable removed from `ACCIDENT.CSV` in FARS 2021+. Resolved by joining vehicle-level records on `ST_CASE` and using `DR_DRINK=1`. The `alcohol_flag_source` column tracks which method was used per observation.
- **No clean never-treated controls:** All 75 Arkansas counties are either treated (12) or neighbor a treated county (63). This is addressed through the comparison group framing (see below).
- **Panel composition:** 12 treated counties (7 cohorts: 2010, 2012, 2014, 2016, 2018, 2020, 2022), 32 always-wet neighbor counties, 31 always-dry neighbor counties.

## Comparison group framing

| Group | N counties | Role |
|-------|-----------|------|
| Treated (transitioning) | 12 | Treatment group; also serve as not-yet-treated comparison for earlier cohorts |
| Always-wet neighbors | 32 | Never-treated comparison in Robustness A (demoted from primary due to pre-trend failure) |
| Always-dry neighbors | 31 | Excluded from direct-effect estimation (spillover-contaminated); used in separate spillover analysis |

**Primary specification:** Not-yet-treated only (12 treated counties). Passes pre-trend test for alcohol crashes.
**Robustness A:** Adds 32 always-wet counties as never-treated. Fails pre-trend test — permanently wet counties have different crash trajectories than transitioning counties.

## Estimation

### Estimator
Callaway & Sant'Anna (2021) group-time ATT estimator, implemented via `csdid` in Stata (Rios-Avila, Sant'Anna, Callaway).

### Specifications

| Spec | Comparison group | Sample | Estimator | Pre-trend (alcohol) |
|------|-----------------|--------|-----------|-------------------|
| **Primary** | Not-yet-treated only | Full panel (2008–2023) | DRIPW | p = 0.289 ✓ |
| Robust A | + always-wet neighbors | Full panel | DRIPW | p = 0.000 ✗ |
| Robust B | Not-yet-treated only | Pre-COVID (2008–2019) | DRIPW | p = 0.295 ✓ |
| Robust C | Not-yet-treated only | Full panel | Regression | p = 0.289 ✓ |

### Simple ATTs (overall)

| Spec | Fatal crashes | Alcohol crashes |
|------|--------------|----------------|
| Primary (NYT, DRIPW) | −0.52 (1.30) | −0.66 (0.91) |
| Robust A (+ wet) | −1.13 (1.25) | −0.41 (0.94) |
| Robust B (pre-COVID) | −2.11 (1.45) | −0.82 (1.07) |
| Robust C (regression) | −0.52 (1.30) | −0.66 (0.91) |

Standard errors in parentheses. None significant at 5%.

### Event-study dynamics (primary spec)

Short-run effects (Tp1, Tp2) are significant and negative for both outcomes. Effects attenuate by Tp3+.

| Event time | Fatal crashes | p-value | Alcohol crashes | p-value |
|-----------|--------------|---------|----------------|---------|
| Tp0 | +0.46 | 0.701 | +0.43 | 0.664 |
| Tp1 | −2.71 | 0.000 | −1.50 | 0.024 |
| Tp2 | −3.37 | 0.016 | −1.36 | 0.043 |
| Tp3 | −2.20 | 0.242 | −0.54 | 0.583 |

## Code files

| File | Language | Description |
|------|----------|-------------|
| `01_descriptives.do` | Stata | Data import, labeling, summary statistics, raw time series and event-study plots, cohort composition |
| `02_csdid_estimation_v2.do` | Stata | C&S-A estimation: primary spec (NYT), robustness A/B/C, pre-trend diagnostics, event-study exports |
| `descriptive_plots.py` | Python | Descriptive figures: treated vs. neighbor time series, raw event-time plots, cohort composition (matplotlib) |
| `event_study_plots.py` | Python | Publication-quality event-study figures from Stata-exported CSV coefficients (matplotlib) |

### Workflow
- **Stata** for estimation and core analysis (`csdid` package)
- **Python** for custom plotting (matplotlib, matching Beamer navy/gold palette)
- Stata `.do` files are written to be run locally; Python scripts can run in either environment

## Output files

### Figures
- `fig1_fatal_timeseries.png` — Raw time series, treated vs. neighbor, fatal crashes
- `fig2_alcohol_timeseries.png` — Raw time series, treated vs. neighbor, alcohol crashes
- `fig3_event_fatal.png` — Raw event-time means, fatal crashes
- `fig4_event_alcohol.png` — Raw event-time means, alcohol crashes
- `fig5_cohort_composition.png` — Cohort composition by event time
- `es_fatal_nyt_publication.png` — Publication event study, fatal crashes (C&S-A coefficients)
- `es_alcohol_nyt_publication.png` — Publication event study, alcohol crashes (C&S-A coefficients)
- `primary_event_*.png` — Stata `csdid_plot` output, primary spec
- `robust_*_event_*.png` — Stata `csdid_plot` output, robustness specs

### Data exports
- `event_study_fatal_nyt.csv` — Event-study coefficients and SEs, fatal crashes, primary spec
- `event_study_alcohol_nyt.csv` — Event-study coefficients and SEs, alcohol crashes, primary spec

## Presentation
- `alcohol_road_safety_beamer.tex` — LaTeX Beamer deck (pdfLaTeX/Overleaf). Navy/gold palette. Currently reflects original proposal framing; needs updating with estimation results.

## Known issues & next steps

### Issues to address
1. **Fatal crash pre-trend rejection:** Joint pre-trend test rejects for fatal crashes even in NYT spec. Pre_avg is small (0.32), suggesting noise not systematic violation.
2. **g2022 cohort omitted:** No not-yet-treated comparison exists. Effectively estimating off 10 counties / 6 cohorts.
3. **Small sample:** 12 treated counties. Standard errors reflect this.
4. **HPMS VMT data:** Not yet collected. Would provide direct behavioral mechanism test.

### Task tracker
- [x] Descriptive plots (time series, raw event-time)
- [x] C&S-A estimation with pre-trend diagnostics
- [x] Control group framing (NYT primary, always-wet robustness)
- [x] Publication-quality event-study plots
- [x] Project README
- [ ] Spillover analysis (03_spillovers.do)
- [ ] HPMS VMT data collection and merge
- [ ] Update Beamer presentation with results
- [ ] Welfare/policy discussion
