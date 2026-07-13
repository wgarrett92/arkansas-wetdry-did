================================================================
ALCOHOL ACCESS LAWS & ROAD SAFETY EXTERNALITIES
Arkansas Wet/Dry County DiD Analysis -- Project README
================================================================
Author:       Will Garrett, PhD Candidate, Behavioral Economics, Clemson
Last updated: 2026-06-19
Paper title:  "Alcohol Access Laws & Road Safety Externalities: A Spatial
              Difference-in-Differences Analysis of Arkansas Wet/Dry Transitions"
================================================================


PROJECT OVERVIEW
================
Estimates the causal effect of county-level wet/dry alcohol policy transitions
in Arkansas on fatal and alcohol-involved traffic crashes, using the Callaway &
Sant'Anna (2021) staggered difference-in-differences estimator. A secondary
analysis examines spatial spillovers to neighboring counties.

Theoretical framework: a spatial (Hotelling) travel-cost model + Becker (1968)
rational-behavior model + an impaired-miles function. THREE channels now (full
detail in the THEORETICAL FRAMEWORK section below):
  - Consumption channel (+): going wet raises local drinking -> more crashes
  - Travel-distance channel (-): going wet eliminates long impaired trips to
    distant retailers -> fewer impaired miles -> fewer crashes
  - Attractor channel (+): a newly-wet county draws drivers from still-dry
    neighbors, relocating their crashes onto its own roads
Net effect is theoretically ambiguous; the empirical design resolves it.
Impaired-miles spec is now PURELY MULTIPLICATIVE, m_i = gamma*a_i*d_i (the old
alpha*a_i base term is dropped). The crash object is reframed from individual
(pi_i) to county-level (Pi_c) -- the unit change that houses the attractor
channel, and that matches FARS county-of-crash and the county-level C&S-A
estimand. Utility carries a perceived-risk disutility lambda*pi_i*kappa (added
after workshop feedback).

Panel: 75 Arkansas counties x 2008-2023 (16 years). 13 treated counties across
7 cohorts (Madison added as a 2012 cohort 2026-06 -- see TREATMENT DEFINITION).
Effective C&S-A estimation uses 11 counties / 6 cohorts (the 2022 cohort is
mechanically excluded -- no not-yet-treated comparators in window).


THEORETICAL FRAMEWORK (revised 2026-06)
=======================================
Spatial (Hotelling) travel-cost model + Becker (1968), revised after the April
workshop. TWO LAYERS: (1) individuals choose consumption and trips; (2) crashes
are realized and MEASURED at the county level. Lifting the crash object from
individual i to county c is what lets the cross-border "attractor" channel live
inside the model -- and it aligns the theory with FARS county-of-crash and with
the county-year C&S-A estimand.

CONSUMER PROBLEM (individual i in county c) -- unchanged, stays individual:
  max  U_i = u(a_i) + x_i - lambda*pi_i*kappa
  s.t. p*a_i + tau(d_i) + x_i = y_i
  Effective per-unit price:  p* = p + tau(d_i)/a_i,  tau'(d) > 0.
  Distance:  d_i = delta_c * n_i,  delta_c >= 1 (dry) or = 1 (wet); n_i is the
  within-county distance to a retailer. Going wet sets delta_c -> 1 (shrinks but
  does not zero out d_i). The tau/a_i form builds in stockpiling: dry consumers
  make fewer, larger trips -- relevant to whether VMT moves much.
  pi_i is the individual's PERCEIVED own-crash risk; it drives behavior and is
  partially internalized (lambda in [0,1]). Kept distinct from the county
  outcome below -- do not collapse the two.

IMPAIRED MILES -- now purely multiplicative (corrects old alpha*a_i + ... form):
  m_i = gamma * a_i * d_i        (NO additive base term)
  Every impaired mile runs through the consumption x distance product.

COUNTY CRASH OUTCOME -- the measured object:
  Pi_c = Pi(A_c, M_c), DEFINED as a county-level crash hazard over total impaired
  exposure on c's roads (a representative-county primitive -- NOT the nonlinear
  micro pi summed, which would need an exact-aggregation assumption; Jensen bites
  if pi is convex). Total impaired miles driven on c's roads:
    M_c = M_c^own + M_c^inbound
      own:     gamma * a^own * delta_c * n            (falls as delta_c -> 1)
      inbound: sum_{j adj c} gamma * a^j * d_{j->c} * 1[c wet]   (jumps from 0)
  Inbound = drivers from still-dry neighbors who arrive once c goes wet. Large
  where the catchment is large (rural, far from competing wet retailers); small
  for urban counties already near other wet areas.

COMPARATIVE STATIC (corrected -- restores pi_m on the distance/interaction terms;
the slide-8 version dropped it, leaving those terms in mile units):
    dPi_c/dD_c  =  [ pi_a * a_p* * p*_D ]                consumption   (+)
                +  [ pi_m * gamma*a * d_D ]              own distance  (-)
                +  [ pi_m * gamma*d * a_p* * p*_D ]      interaction   (+)
                +  [ pi_m * (dM^inbound/dD_c) ]          attractor     (+)  [NEW]
  (subscripts denote partials: pi_m = d pi / d m, a_p* = d a / d p*, etc.)

WHAT THE REVISION BUYS:
  - Rationalizes the headline finding. The single-agent static predicts distance
    DOMINATES for large d-bar (rural) -> rural should be most negative. Rural is
    POSITIVE. The attractor term -- present ONLY in the county-level model --
    flips the net sign where catchment is large: rural positive, urban negative,
    both as PREDICTIONS rather than surprises.
  - Framing. The within-county distance prediction is not "wrong"; it is swamped
    by a cross-county externality (crash relocation) the prior literature ignores.
    That externality IS the spatial contribution -- present it as a discovery, not
    a model repair.
  - VMT's role. VMT is the empirical shadow of the MILES terms (own-distance
    collapse + local interaction); it is blind to the direct consumption term
    pi_a. Under the attractor extension it DISCRIMINATES the two rural hypotheses:
    H2 (attractor) predicts an INBOUND VMT rise in treated rural counties; H1
    (low baseline traffic) predicts none. See the VMT DATA section.

DISCIPLINE / OPEN:
  - Extension is legitimate only because the attractor makes NEW, independently
    testable predictions (inbound VMT; rural-symmetric spillover). Do not keep
    adding channels until the model fits everything -- that buys nothing.
  - Decide whether to formalize the attractor in the model (cleaner, matches the
    data) or keep a minimal own-resident model + discuss the externality in
    interpretation (leaner, some referees prefer it). Current lean: formalize.


SAMPLE COMPOSITION
==================
75 counties:
  13 treated (dry -> wet transition in window)   [Madison added 2026-06]
  31 always-wet neighbors   [was 32; Madison moved to treated]
  31 always-dry neighbors   [PENDING: reclassify Sebastian 05131 -> wet if it is
                             in the pool; see TREATMENT DEFINITION]
   0 clean never-treated controls

Treated cohorts (countywide wet vote = off-premise treatment date):
  2010: Boone (05009), Clark (05019)
  2012: Benton (05007), Sharp (05135), Madison (05087)   [Madison added 2026-06]
  2014: Columbia (05027), Saline (05125)
  2016: Little River (05081)   [off-premise only]
  2018: Randolph (05121)
  2020: Sevier (05133), Van Buren (05141)   [Van Buren off-premise only]
  2022: Hot Spring (05059), Polk (05113)    [excluded from NYT estimation]


TREATMENT DEFINITION & LEGISLATION
==================================
"Going wet" in Arkansas is a BUNDLE of margins that switch on at different
dates/geographies, NOT a single binary:
  1. OFF-PREMISE RETAIL (liquor stores capped 1 per 7,500 pop; unlimited
     beer/wine; beer/wine in grocery/convenience). Turns on at the countywide
     wet vote. <-- THIS is the treatment used.
  2. ON-PREMISE beer/wine in restaurants: also at the countywide vote.
  3. ON-PREMISE liquor-by-the-drink (bars, mixed drinks): SEPARATE sub-county
     margin. Pre-2013 cohorts needed a separate city election; after Act 1008
     (2013), cities in counties that went wet after Nov 2012 with >=100 ABC
     permits could authorize by ordinance. Staggered, sub-county, later.
  4. PRIVATE CLUBS: existed in "dry" counties since ~2003, so on-premise
     consumption was NOT zero at baseline (Benton had the most pre-2012).
  5. SUNDAY SALES: legalized with the transitions (relevant to monthly/DOW).
The off-premise vote date is the clean margin; on/off-premise heterogeneity is
genuinely messy and is NOT recoverable from the state GIS shapefile (which does
not encode on- vs off-premise) -- it requires ABC permit-type records.

RESOLVED (2026-06-19): Madison County (05087) IS a 13th treated county. Verified
against Arkansas Secretary of State returns -- countywide off-premise wet vote,
Nov 6 2012, 57.29% yes (3,793-2,828), the SAME election as Benton/Sharp.
Corroborated by the DFA/ABC "wet counties with exceptions" list and contemporary
press. Recoded to the 2012 cohort; distances + estimation re-run pending (see the
RE-RUN RUNBOOK). NB: the Jan-2017 NABCA white paper listing Madison "dry" is an
error; a separate Nov-2012 "Madison County" wet vote is in KENTUCKY (irrelevant).

DAMP / OFF-PREMISE CONTROL PURITY (resolved 2026-06-19):
Verified the always-dry control pool against the Arkansas ABC wet/dry GIS layer
(ALCOHOLIC_BEVERAGE_WET_DRY_AREAS, FeatureServer layer 60, pub. 2025-02), which
encodes RETAIL/off-premise status geography (it excludes liquor-by-the-drink
elections by design):
  - All 29 fully-dry counties are "Dry with ABC Permits" = PRIVATE CLUBS only
    (on-premise). Their only wet sub-areas are STATE PARKS (wet by statute, Act
    655, on-premise). => clean on the off-premise treatment margin; nothing to
    toggle. Resolves the Craighead/Faulkner sub-county concern (issue #7).
  - ONE exception: Sebastian (05131) -- City of Fort Smith is wet off-premise
    (~75% of county pop), remainder dry. NOT a clean dry control -> code wet
    (Fort Smith dominates) or exclude. It is not contiguous to any treated county,
    so confirm it was ever in the estimation/spillover sample before relying on it.
  - Product-limited WET counties: Logan (05083, beer & native-wine only),
    Woodruff (05147, Augusta beer-only) -- in the wet set, flagged partial_wet.
  - Off-premise access in AR turns on ONLY via a countywide wet vote OR a city
    local-option election -- NOT via private clubs or the Betty Pickett (private-
    club restaurant) route, which are on-premise only. So the off-premise vote
    date captures the treatment margin near-perfectly.
HANDLING: baseline codes treatment on the countywide off-premise vote (Madison
g2012; Sebastian wet; Logan/Woodruff kept wet) and carries a partial_wet flag.
Run ONE "conservative control set" robustness panel dropping partial_wet units
and re-estimating the HEADLINE ATT only -- do NOT double every table (controls
are clean, so baseline ~ robustness). CAVEAT: the ABC layer's free-text date
notes are unreliable (it tags Boone "2012" though Boone went wet in 2010); trust
it for STATUS GEOGRAPHY, not transition dates -- use SoS-verified cohort years.
Reference sheet: dry_control_offpremise_check.txt.


DATA
====
Outcomes (FARS 2008-2023): fatal_crashes, alcohol_fatal_crashes, total_fatalities.
  FARS alcohol-flag discontinuity: DRUNK_DR removed from ACCIDENT.CSV in 2021+;
  resolved by joining DR_DRINK from VEHICLE.CSV on ST_CASE. alcohol_flag_source
  tracks the method per observation.

Panel lineage (annual):
  arkansas_did_panel.csv              base panel, 1200 rows x 20 cols
  arkansas_panel_annual_merged.csv    + ACS controls, CBP churches, DOW shares
                                      (1200 x 50; built locally, README_4_19)
  arkansas_panel_monthly_merged.csv   monthly, 14,400 rows (75 x 16 x 12)

Augmentations added 2026-06 (keyed on fips x year; merge onto the 50-col panel):
  distance_neighbor_augment_v2.csv    border + distance variables (see below)
  vmt_county_year.csv                 VMT measures, 2013-2023 (see below)

Convenience combined files (built on the 20-col BASE panel, so they LACK the
ACS/churches/DOW columns -- for the full analysis panel, merge the two augment
files above onto arkansas_panel_annual_merged.csv):
  arkansas_did_panel_with_border_v2.csv   base + border augmentation
  arkansas_panel_border_vmt.csv           base + border + VMT

Controls (ACS 5-yr, vintage-mapped; 2008-09 use 2009 vintage):
  total_pop, median_hh_income, median_age, poverty_rate, pct_white, pct_black,
  pct_under_18, pct_21plus, pop_21plus
CBP churches (NAICS 813110): church_establishments, churches_pc (per 10k);
  2008-09 backfilled from 2010. (Refinement flagged: control for denomination,
  not just per-capita -- Southern Baptist vs Catholic differ on prohibition.)
DOW: share_sun..share_sat, crashes_sun..crashes_sat (weekend/alcohol pattern
  motivates the monthly + day-of-week panel; all counties legalized Sunday sales).


BORDER-STATE AUGMENTATION & DISTANCE-TO-NEAREST-WET
===================================================
Out-of-state (OOS) border-county alcohol access was added because most AR dry
counties were NOT isolated -- the nearest off-premise source was often across a
state line. Coding (off-premise margin), with the OOS ring = border-state
counties adjacent to AR (from GeoJSON adjacency, validated 100% vs panel
n_wet_neighbors):
  MO (29), OK (40)  wet entire window. (OK: package stores statewide throughout;
                    SQ792 Oct-2018 changed ON-premise only.)
  TX (48) Bowie/Cass off-premise beer/wine ONLY, and only FROM 2013 (Texarkana
                    dry for off-premise before; still no packaged liquor).
                    NB: AR (Texarkana/Miller) historically supplied TX, not the
                    reverse. wet_from_year=2013. VERIFY.
  LA (22)           wet via municipalities; some parishes dry by ward. PARTIAL.
  MS (28), TN (47)  river border; accessible ONLY via whitelisted bridges:
                    Crittenden 05035->Shelby TN 47157 (West Memphis);
                    Phillips 05107->Coahoma MS 28027 (Helena);
                    Chicot 05017->Washington MS 28151 (Greenville).
  RIVER-CROSSING CONSTRAINT: straight-line distance overstates access across the
  Mississippi/Red rivers where no bridge exists; cross-river OOS counties are
  gated to the bridge whitelist. Land borders (MO/OK/TX/LA) are unrestricted.

DISTANCE METRIC: population-weighted centroids (2020 Census Centers of
Population, via the USpopcenters CRAN package; census.gov direct-download is
firewalled in the build env). Two metrics, each in-state-only and OOS-augmented:
  popcen : pop-centroid -> nearest wet county's pop-centroid
  border : pop-centroid -> nearest point on the wet county's border (PREFERRED:
           residents drive to the edge of wet territory, where county-line
           stores cluster; robust to large-county geometry).

KEY FINDINGS (pre-treatment distance, treated counties):
  - The METRIC choice dominates the OOS choice. Median pre-treatment distance:
        popcen ~26 mi  |  border ~10 mi
    Most treated counties are ADJACENT to a wet county, so residents sit ~10 mi
    from the wet edge, not ~26 from a wet centroid. The old geometric-centroid
    metric (median ~28 mi, the prior "28.2") was measuring county geometry, not
    access -- e.g. Little River read 33 mi to adjacent wet Miller (Texarkana AR).
  - OOS access is the NEAREST source for 4 treated counties (contamination
    group): Little River (Bowie TX), Polk (Le Flore OK), Sevier (McCurtain OK),
    Sharp (Oregon MO). The other 8 -- 9 incl. Madison (added 2026-06; pre-2012
    nearest wet = adjacent Washington) -- have in-state adjacent access.
  - Sharp is the only genuinely "far" treated county (~22 mi even after OOS +
    border). All others are 4-13 mi from access.
  - Use dist_border_aug as primary, dist_popcen_aug as robustness; report the
    median split under both (membership moves between them). Group by
    nearest_wet_is_oos for the contamination split.

DISTANCE RECOMPUTE REQUIRED (2026-06-19, Madison/Sebastian recode):
The population-weighted CENTROIDS are unaffected (geography x population, not
policy) -- do NOT recompute pop_centroids.csv. The distance-to-nearest-wet
metrics DO change, because the wet-SOURCE set moved:
  - Madison (05087): was treated as always-wet; now wet_from_year=2012. NOT a wet
    source in 2008-2011 (small effect -- its neighbors sit next to always-wet
    Washington/Carroll). Madison itself, now treated, needs its own pre-2012
    distance row: nearest wet = Washington (in-state, adjacent).
  - Sebastian/Fort Smith (05131): wet off-premise for decades but coded dry, so
    WRONGLY OMITTED as a source for the whole window -- this OVERSTATED distance
    for Fort Smith-adjacent counties (Crawford [a dry control], Scott, Franklin,
    Logan). Add Sebastian as an all-window wet source. Keep it as a SOURCE even
    if you DROP Sebastian as an estimation unit.
Both flow through all four distance vars (popcen/border x instate/aug). Re-run
build_border_augment_v2.py (wet-source/timing inputs only) per
patch_border_madison_sebastian.py; regenerate distance_neighbor_augment_v2.csv +
pretreatment_distance_by_treated_v2.csv.

New columns (in distance_neighbor_augment_v2.csv and the combined panels):
  dist_popcen_instate, dist_popcen_aug, dist_border_instate, dist_border_aug,
  nearest_wet_fips_aug, nearest_wet_is_oos, n_wet_neighbors_instate_chk,
  n_oos_wet_neighbors, n_wet_neighbors_aug, any_wet_neighbor_aug,
  share_wet_neighbors_aug


VMT DATA (mechanism test)
=========================
Source: ARDOT "Road and Street Mileage Report - County Summary" .xls, 2013-2023
(one sheet per county; grand-total line parsed). 825 county-years; all 75
counties matched to FIPS; rural/small-urban/urbanized DVMT reconciles to total.
  Columns: dvmt_total (Daily VMT), vmt_annual (=dvmt*365), road_length_total
  (road SUPPLY, a control -- not the VMT mechanism), dvmt_rural/small_urban/
  urbanized, and (in the merged panel) fatal_per_100m_vmt, alcohol_per_100m_vmt.

  COVERAGE CAVEAT: 2013-2023 only (68.8% of panel). No pre-treatment VMT for the
  2010/2012 cohorts; 1 pre-year for 2014. VMT outcomes are effectively a
  2014+-cohort / 2013-2023-window analysis -- state this; do not run VMT
  outcomes on the full cohort set as if pre-trends were observed.

  WHAT IT TESTS: regress fatal_per_100m_vmt on treatment to separate "fewer
  miles" from "safer miles." Interact the VMT drop with dist_border_aug (the
  travel-distance channel predicts larger drops where access was farther).
  LIMITATION: DVMT is TOTAL travel, not impaired/alcohol-related miles -- a
  partial proxy for m_i, not a direct measure. Be explicit about this.


COMPARISON GROUP FRAMING
========================
  Group                   N    Role
  Treated (transitioning) 12   Treatment; also not-yet-treated comparators
  Always-wet neighbors    32   Never-treated comparison in Robust A (demoted:
                               fails pre-trend -- different crash trajectories)
  Always-dry neighbors    31   Excluded from direct-effect design (spillover-
                               contaminated); valid controls in the SPILLOVER
                               design (treatment defined differently there)
Within-county design control = always-dry; spillover design control = always-wet.


ESTIMATION
==========
Estimator: Callaway & Sant'Anna (2021) group-time ATT, Stata `csdid`.
  Workflow discipline: csdid -> estimates store -> estat simple -> estimates
  restore -> estat event -> estimates restore -> estat pretrend. `estimates
  restore` required before EACH estat call (each overwrites active results).
  Wrap estat calls in `capture noisily` (small cohorts fail on restricted samples).
  csdid_plot does NOT support event-study aggregation -- use twoway for custom plots.
  DRIPW propensity-score separation occurs for single-county cohorts (g2016, g2018)
  when >1-2 covariates enter; method(reg) avoids it.

Specifications (evolving):
  Primary (NYT, DRIPW)     not-yet-treated only; alcohol pre-trend p=0.289 (pass),
                           fatal pre-trend REJECTS.
  Robust A (+ always-wet)  fails pre-trend (p~0.000).
  Robust B (pre-COVID)     2008-2019, NYT; alcohol pre-trend p=0.295.
  Robust C / "Primary+ REG" method(reg), notyet, xvars(log_pop, poverty_rate).
                           Headline spec: best pre-trend balance (fatal p~0.84).
  NOTE (2026-06-19): all results below PREDATE the Madison g2012 recode +
  Sebastian fix. g2012 now carries 3 counties (Benton, Sharp, Madison);
  effective sample 11 counties / 6 cohorts. Re-run pending -- recheck the fatal
  pre-trend under Primary+ REG first. Do not cite these numbers post-recode.

Results (no-covariate baseline, 2026-03-20):
  Simple ATTs (none sig at 5%):  Fatal / Alcohol
    Primary (NYT, DRIPW)         -0.52 / -0.66
    Robust A (+ wet)             -1.13 / -0.41
    Robust B (pre-COVID)         -2.11 / -0.82
  Event-study (primary):  Fatal (p) | Alcohol (p)
    Tp0  +0.46 (.701) | +0.43 (.664)
    Tp1  -2.71 (.000) | -1.50 (.024)   <- significant
    Tp2  -3.37 (.016) | -1.36 (.043)   <- significant
    Tp3  -2.20 (.242) | -0.54 (.583)
  Interpretation: travel-distance channel dominates short-run (Tp1-Tp2); the
  consumption channel catches up, producing a near-zero overall ATT.

CENTRAL EMPIRICAL RESULT -- rural/urban heterogeneity:
  Rural newly-wet counties show INCREASES in fatal and alcohol crashes; urban
  show DECREASES. Opposite-signed, consistent with the multiplicative model.
  Leading interpretation: the "attractor hypothesis" -- newly-wet rural counties
  become destinations for drivers from neighboring dry counties, redistributing
  crashes (cross-border inflow). Direct test pending: FARS vehicle REGISTRATION
  STATE (out-of-state inflow); county-of-origin is not standard in FARS -- verify
  vintage. (NB: the year-8 event-study spike is a composition artifact -- only
  the 2010 cohort reaches t+8; cap the window where >=3-4 cohorts are present.)

SPILLOVER (v3): aggregate null ATTs; a significant rural-spillover alcohol effect
  symmetric in sign/magnitude to the rural direct effect (consistent with the
  attractor/redistribution story). Always-dry counties are valid controls here.


CODE FILES
==========
  01_descriptives.do            Stata: import, labels, summary stats, raw plots
  02_csdid_estimation_v2.do     Stata: C&S-A primary + robust A/B/C, pre-trends
  (02_csdid_estimation_v3.do)   Stata: covariate re-estimation (ACS+churches);
                                PENDING -- per-capita & VMT outcomes, DOW shares
  (03_spillovers_v2.do)         Stata: spillover with covariates; PENDING
  (04_heterogeneity_robustness.do) Stata: distance median-split (use
                                dist_border_aug) + jackknife-by-cohort; PENDING
  descriptive_plots.py          Python: treated-vs-neighbor series, event-time
  event_study_plots.py          Python: publication event studies from csdid CSV
  build_border_augment_v2.py    Python: pop-weighted centroids, two distance
                                metrics, OOS coding + crossing constraint
  build_vmt_panel.py            Python: ARDOT .xls -> VMT panel + merge
  patch_madison_sebastian.do    Stata: Madison g2012 recode + Sebastian/partial-
                                wet handling + baseline-vs-robustness sample
                                (paste at top of 02_csdid, before csdid)
  patch_border_madison_sebastian.py  Python: wet-source/timing edit for
                                build_border_augment_v2.py (Madison 2012;
                                Sebastian all-window source)

Convention: Stata for estimation (.do run locally; Claude does not execute
Stata). Python (matplotlib) for custom plots. Navy/gold palette
(NAVY=#1A2744, GOLD=#C9A84C). Code provided alongside outputs. READMEs as .txt.
Targeted fixes over full rewrites.


DATA / OUTPUT FILES
===================
  arkansas_did_panel.csv                  base panel (20 cols)
  arkansas_panel_annual_merged.csv        + ACS/churches/DOW (50 cols)
  arkansas_panel_monthly_merged.csv       monthly (14,400 rows)
  transition_summary.csv                  wet/dry transitions, dates, vote types
  merge_log.txt                           panel-construction pipeline log
  -- border augmentation (2026-06) --
  pop_centroids.csv                       2020 pop-weighted centroids (AR + 6
                                          border states)
  oos_wet_reference_v2.csv                OOS ring coding (editable; wet_from_year)
  distance_neighbor_augment_v2.csv        fips x year distance/neighbor vars
  pretreatment_distance_by_treated_v2.csv per-treated-county pre-treatment dist
  arkansas_did_panel_with_border_v2.csv   base + border (superseded by below)
  border_states_and_legislation_notes.txt border coding + legislation detail
  AUGMENT_NOTES_v2.txt                     border-augmentation column dictionary
  -- verification (2026-06) --
  ALCOHOLIC_BEVERAGE_WET_DRY_AREAS.*       ABC wet/dry GIS layer (FeatureServer 60,
                                          pub 2025-02; retail/off-premise geography)
  dry_control_offpremise_check.txt         29 dry controls verified off-premise-
                                          clean; Sebastian/Logan/Woodruff flags
  RERUN_RUNBOOK.txt                        step-by-step Madison/Sebastian re-run order
  -- VMT (2026-06) --
  vmt_county_year.csv                     VMT, 2013-2023 (825 rows)
  arkansas_panel_border_vmt.csv           base + border + VMT (current combined)
  VMT_NOTES.txt                            VMT column dictionary + caveats
  -- figures --
  fig1-5_*.png, es_*_publication.png, primary/robust_event_*.png

Estimator scalar names (estat simple): r(att_1_1), r(se_1_1), r(p_1_1) -- may
vary by csdid version; verify with `return list` after first run.


KNOWN ISSUES & OPEN QUESTIONS
=============================
  1. Madison County (05087): RESOLVED 2026-06-19 -- confirmed a 2012 treated
     county (AR SoS returns, Nov 6 2012, 57.29%). Recoded to g2012; distances +
     estimation re-run pending (see RERUN_RUNBOOK.txt).
  2. Fatal-crash pre-trend rejects under DRIPW (pre_avg small ~0.32, likely
     noise). Primary+ REG resolves it (fatal p~0.84).
  3. g2022 cohort (Hot Spring, Polk) mechanically omitted from NYT (no
     comparators). Effective sample: 10 counties / 6 cohorts.
  4. Small sample (12 treated). SEs reflect this; pre-trend tests overpowered.
  5. TX/LA border coding flagged VERIFY/PARTIAL -- confirm Bowie/Cass TX and the
     facing LA parishes against state ABC before publication.
  6. VMT coverage 2013-2023 only (see VMT caveat).
  7. On/off-premise heterogeneity still needs ABC permit-type records (the GIS
     shapefile does not encode on- vs off-premise). RESOLVED 2026-06-19: the damp
     dry controls (Craighead, Faulkner, etc.) are verified via the ABC wet/dry GIS
     layer as "Dry with ABC Permits" = private clubs (on-premise only) -- clean on
     the off-premise margin. Sole exception Sebastian/Fort Smith (code wet). See
     the DAMP / OFF-PREMISE CONTROL PURITY note in TREATMENT DEFINITION.


NEXT STEPS / TASK TRACKER
=========================
  [x] Descriptive plots; C&S-A estimation + pre-trend diagnostics
  [x] Control-group framing; publication event-study plots
  [x] Rural/urban heterogeneity; spillover (v3)
  [x] Border-state OOS coding + population-weighted distance metrics
  [x] VMT (2013-2023) extraction and merge
  [x] VERIFY Madison -- confirmed g2012 (AR SoS, Nov 2012)
  [x] Verify dry-control off-premise purity vs ABC GIS layer (clean; Sebastian excl.)
  [ ] RE-RUN with Madison g2012 + Sebastian recode: border distances -> panel ->
      02_csdid -> heterogeneity -> spillover; recheck fatal pre-trend (RERUN_RUNBOOK)
  [ ] 04_heterogeneity_robustness.do: median split on dist_border_aug +
      contamination split (nearest_wet_is_oos) + jackknife-by-cohort
  [ ] 02_v3 / 03_v2: covariate re-estimation; per-capita & VMT/exposure outcomes
  [ ] Disjoint outcomes: report NON-alcohol fatal (= fatal - alcohol) separately
  [ ] Add non-fatal crashes + DUIs (ARDOT) for power
  [ ] Reframe identification as cross-border shopping / tax-avoidance (not
      classic border-discontinuity); cite gas-tax border literature
  [ ] FARS registration-state test for the rural attractor hypothesis
  [ ] Rural/urban cutoff: replace ad hoc 20k with USDA RUCC
  [ ] Monthly panel + day-of-week FE (Sunday-sales effect); PPML/NB FE for zeros
  [ ] Welfare/policy discussion; full paper write-up
================================================================
