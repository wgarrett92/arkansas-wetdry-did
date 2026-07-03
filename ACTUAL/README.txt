================================================================
ALCOHOL ACCESS LAWS & ROAD SAFETY EXTERNALITIES
Arkansas Wet/Dry County DiD Analysis -- Project README
================================================================
Author:       Will Garrett, PhD Candidate, Behavioral Economics, Clemson
Last updated: 2026-07-01
Paper title:  "Alcohol Access Laws & Road Safety Externalities: A Spatial
              Difference-in-Differences Analysis of Arkansas Wet/Dry Transitions"
================================================================


DOCUMENTATION & PROVENANCE CONVENTION (this is a JOB-MARKET PAPER)
=================================================================
Every consequential analytical decision is logged, decision-first (WHAT / WHY /
HOW / RESULT / PAPER section), in:
      ANALYSIS_LOG.txt   <-- the lab notebook / audit trail for writing the paper
Three docs, three jobs:
  README.txt          standing description (data, specs, files)   [this file]
  RERUN_RUNBOOK.txt   ordered re-run recipe for the Madison/Sebastian recode
  ANALYSIS_LOG.txt    WHY each choice was made + where it lands in the manuscript
Each analysis .do file carries a header pointing to ANALYSIS_LOG.txt. When you
(or Claude) make an analytical change: append an ANALYSIS_LOG entry, update the
.do header, and refresh the affected README results/figure text. Claude: keep
maintaining ANALYSIS_LOG.txt on every future session by default.
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
press. Recoded to the 2012 cohort; distances rebuilt + panel re-merged (Steps 1-2)
and the estimation recode integrated into 02_csdid (Step 3, 2026-06-30) -- Stata
RUN executed 2026-06-30 (see the RE-RUN RUNBOOK). NB: the Jan-2017 NABCA white paper listing
Madison "dry" is an
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
Outcomes (FARS 2008-2023): fatal_crashes, alcohol_fatal_crashes, total_fatalities,
  nonalc_fatal_crashes (= fatal - alcohol; added 2026-06-29), plus per-100k versions
  fatal_crashes_pc / alcohol_crashes_pc / nonalc_fatal_crashes_pc.
  nonalc_fatal_crashes is NOT a clean placebo -- the attractor relocates TRAFFIC, so
  the exposure channel can move sober crashes too. Treat it as a MECHANISM-
  DECOMPOSITION outcome: alcohol effect ~ impairment + exposure, nonalc ~ exposure
  alone, so the alcohol-minus-nonalc contrast isolates the impairment channel. Run it
  through the SAME spec battery as alcohol (NOT just Primary+ REG) across treated +
  spillover, WITH the event study (flat nonalc pre-trends = common-confounder
  diagnostic that licenses the alcohol read). Built on the 68-col panel ->
  arkansas_panel_annual_border_vmt_nonalc.csv (70 cols).
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

Current analysis panel (2026-06-29; built on the 68-col arkansas_panel_annual_border_vmt.csv):
  arkansas_panel_annual_border_vmt_nonalc.csv       + nonalc_fatal_crashes(_pc)   (70 cols)
  arkansas_panel_annual_border_vmt_nonalc_rucc.csv  + RUCC cols (rural_2013 etc.)  (77 cols)
                                                    <-- FEED THIS to 02_v3 / 04b
  UPDATE 2026-07-01 (R15 PORT, ANALYSIS_LOG #25): the pair above is now the
  ARCHIVE. Feed the v2 pair instead (corrected countywide_wet + neighbor +
  dist columns at rest; see the "R15 PORT / PANEL v2" section):
  arkansas_panel_annual_border_vmt_nonalc_rucc_v2.csv          (77 cols)
  arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv   (84 cols)

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

STATUS (2026-06-26): DONE -- Steps 1 & 2 of the RERUN_RUNBOOK executed.
  - build_border_augment_v2_patched.py realizes the PLACE-1 patch adapted to the
    script's actual structure: it has no wet_from_year dict, so the override
    recodes countywide_wet directly (Madison 05087 -> 0 pre-2012 / 1 from 2012;
    Sebastian 05131 -> 1 all years) and injects Madison g2012 into the
    pretreatment-distance emitter. Run with the Plotly county GeoJSON
    (geojson-counties-fips.json: id=FIPS, properties.NAME -- the same source the
    adjacency was built from).
  - VALIDATION: the unmodified (PRE) build reproduced the AUGMENT_NOTES v2 medians
    to the decimal (popcen 26.3/24.7, border 10.8/10.1; Little River 7.47/13.58;
    Sharp 22.16) with adjacency QC 1200/1200 -- the GeoJSON reproduces the pipeline,
    it does not perturb it. The POST recode then moves ONLY Madison/Sebastian-related
    cells: pretreatment table grows 12 -> 13 (Madison row: pre_year 2011, border_aug
    10.63 mi, nearest wet = Washington AR, in-state); Crawford 9.07->7.29,
    Scott 19.94->8.77, Franklin 21.97->10.35 now point at Fort Smith (05131); Carroll
    & Washington lose Madison as nearest in 2008-2011 only; the 76-cell neighbor-count
    move (QC 1200->1124) decomposes exactly as 20 (Madison's 5 nbrs, 2008-11) + 32
    (Sebastian-only nbrs Logan/Scott, all yrs) + 24 (Crawford/Franklin adj-both, 2012+).
    OOS reference byte-identical pre/post (in-state recode; OOS ring untouched).
  - CORRECTION to the runbook prediction: Logan's distance does NOT shrink. It already
    sits 6.36 mi from wet Franklin (05047, countywide_wet=1), closer than Fort Smith,
    so only its neighbor COUNT moves. The "Logan dist shrinks" line in
    patch_border_madison_sebastian.py / RERUN_RUNBOOK is wrong; the result is correct.
  - Step 2 (merge_step2.py): distance_neighbor_augment_v2.csv (POST) + vmt_county_year.csv
    merged onto arkansas_panel_annual_merged.csv -> arkansas_panel_annual_border_vmt.csv
    (1200 rows x 68 cols; distance coverage 1200/1200, vmt_present=1 on 825 rows,
    0 distance NaN). Purely additive: treatment coding (Madison g2012 / Sebastian /
    partial_wet) remains PLACE 2 (patch_madison_sebastian.do in Stata), not touched here.

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
  ** HEADLINE (2026-07-01): the within-county always-DRY design (below) is now the
     PRIMARY spec in 02_csdid_estimation_v2.do -- it is the only spec with clean
     fatal AND alcohol pre-trends. The NYT/always-wet/pre-COVID specs are ROBUSTNESS
     (the old "Primary" NYT is relabeled Robustness D). See Sec 6b/6d. **
  Robust D / Primary (NYT, DRIPW)  not-yet-treated only (FORMER primary; demoted
                           2026-07-01); alcohol pre-trend p=0.293 (pass), fatal
                           pre-trend REJECTS (Pre_avg p=0.037).
  Robust A (+ always-wet)  fails pre-trend (p~0.000).
  Robust B (pre-COVID)     2008-2019, NYT; alcohol pre-trend p=0.295.
  Robust C / "Primary+ REG" method(reg), notyet, xvars(log_pop, poverty_rate) on
                           the NYT pool (fatal pre-trend actually REJECTS post-recode,
                           p=0.037 -- the "p~0.84" belonged to the always-dry design).
  Within-county (always-dry) = HEADLINE  gvar(cohort), notyet, Primary+ REG, if
                           est_sample==1 (treated + always-DRY controls; always-wet
                           demoted to spillover). Added 2026-06-30 as 02_csdid Sec 6b;
                           PROMOTED TO HEADLINE 2026-07-01. Clean pre-trends: fatal
                           Pre_avg p=0.807, alcohol p=0.732, nonalc p=0.920. ATTs
                           (reg+xvars): fatal -0.638, alcohol -0.276, nonalc -0.362
                           (all ns; het is the story). Event study exported by Sec 6d
                           -> output/event_study_{fatal,alcohol}_headline.csv.
  Conservative control set  Section 6c: headline ATT with partial_wet==0 dropped
                           (non-binding => baseline==conservative by construction).
  NOTE (2026-06-19): all results below PREDATE the Madison g2012 recode +
  Sebastian fix. g2012 now carries 3 counties (Benton, Sharp, Madison);
  effective sample 11 counties / 6 cohorts. Do not cite these numbers post-recode.
  UPDATE (2026-06-30): the recode (PLACE 2, patch_madison_sebastian.do) is now
  INTEGRATED into 02_csdid_estimation_v2.do -- import swapped to the RUCC+origin
  panel, recode pasted before the gvar construction (Madison g2012 flows into
  gvar_nyt/gvar), CHECK-FIRST pre-trend block + nonalc battery + within-county +
  conservative sections added. Stata RUN executed 2026-06-30 (StataNow 19.5 SE,
  exit 0) -- see "RESULTS -- POST-RECODE RUN" below. Headline finding: the
  within-county always-dry design (Sec 6b) has CLEAN pre-trends (fatal Pre_avg
  p=0.807); the NYT treated-only fatal pre-trend rejects (p=0.037), and Madison is
  not the cause.

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

RESULTS -- POST-RECODE RUN (2026-06-30, StataNow 19.5 SE, ran 02_csdid on the
RUCC+origin panel; recode QC all pass: 13 treated / g2012=3 / 29 always-dry):
  Aggregate ATTs are NULL everywhere (expected -- the paper's contribution is the
  rural/urban HETEROGENEITY, not the pooled ATT). Simple ATT (reg+xvars):
    Design                         Fatal / Alcohol / Nonalc
    NYT treated-only (Robust C)    -0.49 / -0.68 / +0.18   (all ns)
    Within-county + always-dry(6b) -0.64 / -0.28 / -0.36   (all ns)
    Conservative (6c, partial_wet==0) == within-county (non-binding, as predicted)

  PRE-TREND (Pre_avg = avg pre-treatment effect; the interpretable C&S-A diagnostic.
  The joint estat pretrend chi2 over ~35 individual pre-cells rejects everywhere on
  cell noise -- do NOT read it as "the" pre-trend):
    Outcome   NYT treated-only        Within-county + always-dry (6b)
    Fatal     0.317  p=0.037 (REJECT) -0.027  p=0.807  (PASS)
    Alcohol   0.257  p=0.293 (pass)   -0.037  p=0.732  (PASS)
    Nonalc    0.027  p=0.791 (flat)    0.010  p=0.920  (flat)

  TWO CORRECTIONS to the pre-recode notes:
    (a) Madison is NOT the cause of the fatal pre-trend. Same panel/spec WITH vs
        WITHOUT Madison in g2012: fatal Pre_avg p=0.037 both ways (0.317 vs 0.321).
    (b) The remembered "Primary+ REG fatal p~0.84 (best pre-trend balance)" does NOT
        reproduce for the NYT treated-only design (fatal p=0.037). It reproduces for
        the WITHIN-COUNTY design that adds the clean always-DRY never-treated controls
        (fatal Pre_avg p=0.807 ~ 0.84). => the clean-pre-trend headline belongs to the
        gvar(cohort)+always-dry design (02_csdid Sec 6b), matching the README
        "COMPARISON GROUP FRAMING" (within-county control = always-dry), NOT to the
        pure not-yet-treated Primary. Recommend promoting 6b to the headline spec.
    The nonalc pre-trend is flat under both (p=0.79/0.92) -- the common-confounder
    diagnostic that licenses the alcohol read.
  Artifacts: output/event_study_{fatal,alcohol}_nyt.csv + primary/robust_a/robust_b
  event PNGs; full log 02_csdid_estimation_v2.log (6155 lines, exit 0).

CENTRAL EMPIRICAL RESULT -- rural/urban heterogeneity:
  Rural newly-wet counties show INCREASES in fatal and alcohol crashes; urban
  show DECREASES. Opposite-signed, consistent with the multiplicative model.
  Leading interpretation: the "attractor hypothesis" -- newly-wet rural counties
  become destinations for drivers from neighboring dry counties, redistributing
  crashes (cross-border inflow). Direct test (script built 2026-06-29,
  build_driver_origin.py): use FARS VEHICLE DR_ZIP = the DRIVER'S HOME ZIP (one
  driver per vehicle row; ~97% populated in AR driver-rows), NOT REG_STAT. DR_ZIP is
  the person (not the car) at ZIP->county resolution, so it maps to a home COUNTY --
  superior to registration STATE. Pipeline: join VEHICLE<-ACCIDENT on ST_CASE for the
  crash county, map DR_ZIP->home county via HUD ZIP-county xwalk, tag the home county
  DRY-that-year via panel countywide_wet. Outcome: crash-county x year share of
  involved (and DR_DRINK==1) drivers living in a still-dry county (sh_home_dry /
  sh_home_dry_drink), predicted to RISE in newly-wet rural counties. Inputs to supply:
  accident_*.csv (all yrs) + a ZIP-county xwalk. Adjacent-dry refinement needs a
  county adjacency graph (not yet a panel column).
  (NB: the year-8 event-study spike is a composition artifact -- only
  the 2010 cohort reaches t+8; cap the window where >=3-4 cohorts are present.)

RURAL/URBAN CLASSIFIER -- RUCC replaces the ad hoc 20k cutoff (2026-06-29):
  merge_rucc.py merges USDA ERS Rural-Urban Continuum Codes (both vintages, 2013 .xls
  + 2023 .xlsx) onto the panel. PRIMARY = RUCC 2013 (rural_2013 = nonmetro = codes
  4-9); 2023 carried as robustness (metro_2023). Also rucc_adjacent_2013 (codes 4/6/8)
  and rural_nonadj_2013 (codes 5/7/9 = isolated catchment = strongest attractor cells).
  CONSEQUENTIAL, not cosmetic -- 6 of 12 treated counties flip vs the 20k cut; the
  treated split moves 5R/7U -> 9R/3U:
    flip to RURAL (nonmetro w/ a mid-size town; 20k rule mis-filed as urban):
      Boone(7) Clark(7) Columbia(7) Polk(7) Hot Spring(6)
    flip to URBAN (small pop but metro-integrated): Little River(3 = Texarkana metro)
  The flips are MECHANISM-CONSISTENT: Little River sits inside the Texarkana metro next
  to existing wet retail (not an isolated attractor -> correctly urban); the nonmetro-
  with-a-town counties are catchment-capable (-> correctly rural). So this is a genuine
  RE-TEST of the headline reversal under a defensible classifier, NOT a rubber-stamp --
  the rural/urban ATTs WILL move on re-estimation (5 counties enter rural, 1 leaves).
  VINTAGE is immaterial for treated counties: only Cleveland/Jefferson/Lincoln (none
  treated; Pine Bluff metro dissolving) cross the metro/nonmetro line 2013->2023; no
  treated county does (Sharp shifts 7->9, still rural).
  rural_nonadj_2013 unlocks a dose-response the 20k cut could not: if the attractor is
  real the positive rural effect should CONCENTRATE in the nonadjacent cells
  (Boone/Clark/Columbia/Polk/Randolph/Sharp) and be weaker in adjacent rural
  (Sevier/Van Buren/Hot Spring).
  MADISON (pending 13th, added at the Stata recode) is URBAN under RUCC (code 2,
  Fayetteville metro) -- it flips from rural-under-20k, so post-recode it joins the
  URBAN arm, not the rural one.

SPILLOVER (v3): aggregate null ATTs; a significant rural-spillover alcohol effect
  symmetric in sign/magnitude to the rural direct effect (consistent with the
  attractor/redistribution story). Always-dry counties are valid controls here.
  STATUS 2026-07-01: RE-TESTED under v4.1 on corrected neighbor counts (KNOWN
  ISSUES #9 workaround; ANALYSIS_LOG #24). The symmetry claim does NOT survive
  intact: rural spillover alcohol -1.20 (p=.029**) numerically reproduces the
  old -1.19 but its Pre_avg REJECTS (p=.022), and the direct-side partner
  (+1.38 rural alcohol) already attenuated to -0.41 under RUCC. Pooled
  spillover ATTs are null (pre PASS); URBAN dry neighbors show POSITIVE
  spillovers (fatal +4.88, p=.014**, pre PASS). Cite #24, not the v3 numbers.


CODE FILES
==========
  01_descriptives.do            Stata: import, labels, summary stats, raw plots
  02_csdid_estimation_v2.do     Stata: C&S-A primary + robust A/B/C, pre-trends.
                                UPDATED 2026-06-30: imports the RUCC+origin panel;
                                patch_madison_sebastian.do integrated (lines ~69-210);
                                + CHECK-FIRST Primary+ REG pre-trend (Sec 1b), xvars +
                                nonalc battery on Robust C (Sec 6), within-county
                                always-dry design (Sec 6b), conservative row (Sec 6c)
  (02_csdid_estimation_v3.do)   Stata: covariate re-estimation (ACS+churches);
                                PENDING -- per-capita & VMT outcomes, DOW shares
  03_spillovers_v4.do           Stata: spillover re-run (Excel workbook retired);
                                v4.1 merges neighbor_counts_corrected.csv at run
                                time and builds cohorts from n_wet_corr (the
                                panel's own neighbor columns are R15-defective --
                                do not revert). RAN 2026-07-01 with valid cohorts
                                -> spillover_v4_results.csv + _pathb.csv.
                                See ANALYSIS_LOG #23 (defect) + #24 (results).
                                v4.2 (2026-07-01, #25): prefers the v2 panel,
                                asserts its at-rest columns == the corrected
                                CSV 1200/1200, falls back to the archived-panel
                                merge; design/results unchanged (not re-run;
                                STEP 1-2 smoke-tested, cohorts reproduce #24).
  rebuild_neighbor_counts.py    Python: R15 fix -- adjacency from the public
                                Plotly counties.geojson x corrected PLACE-2 wet
                                timeline -> neighbor_counts_corrected.csv.
                                STAGE-A gate: reproduces n_wet_neighbors_instate
                                _chk 1200/1200 under the PLACE-1 timeline before
                                emitting the corrected series (needs shapely;
                                /usr/local/bin/python3). RAN 2026-07-01.
  04_heterogeneity_robustness.do Stata: distance median split (STATIC pre-treatment
                                dist_border_aug primary / popcen robustness) +
                                contamination split (nearest_wet_is_oos) +
                                dose-response (rural_nonadj/adj/urban) + jackknife-
                                by-cohort, all under the headline always-dry spec;
                                arm = treated subset + ALL always-dry controls.
                                RAN 2026-07-01 -> het_distance_results.csv.
                                See ANALYSIS_LOG #20.
  05_driver_origin.do           Stata: driver-origin attractor test, corrected
                                design (#10/R12/R13): exact counts from
                                driver_origin_long.csv; LEVEL (exposure=pop) +
                                COMPOSITION (exposure=n_resknown) ppmlhdfe arms;
                                stacked-by-cohort event studies; jwdid + raw-share
                                csdid robustness. UPDATED version transferred +
                                patched + RAN 2026-07-01 -> driver_origin_results
                                .csv etc. NOT supportive of the rural attractor;
                                jwdid arm non-convergent (open). ANALYSIS_LOG #22.
  descriptive_plots.py          Python: treated-vs-neighbor series, event-time
  event_study_plots.py          Python: HEADLINE publication event studies. Reads
                                output/event_study_{fatal,alcohol}_headline.csv
                                (event-time, from 02_csdid Sec 6d) -> output/
                                es_*_headline_publication.png. Repointed to the
                                always-dry headline 2026-07-01 (was NYT). RUN with
                                /usr/local/bin/python3 (matplotlib; default python3
                                lacks it). See ANALYSIS_LOG #16.
  build_border_augment_v2.py    Python: pop-weighted centroids, two distance
                                metrics, OOS coding + crossing constraint
  build_border_augment_v2_patched.py  Python: build_border_augment_v2.py with the
                                PLACE-1 Madison/Sebastian recode applied (RAN
                                2026-06-26, Plotly GeoJSON); emits the POST
                                distance_neighbor_augment_v2.csv + 13-row
                                pretreatment_distance_by_treated_v2.csv.
                                UPDATED 2026-07-01 (#25): "PLACE 1 PATCH v2" --
                                wet sources now come from wet_source_timeline.py
                                (Boone/Clark 2010 fixed; Logan a neighbor source
                                but not a distance source unless
                                --logan-distance-source 1); hard asserts added.
  merge_step2.py                Python: RERUN Step 2 re-merge -- distance augment
                                + VMT onto arkansas_panel_annual_merged.csv,
                                defensive (fips zfill, 1:1 validate, collision +
                                coverage report) -> arkansas_panel_annual_border_vmt.csv.
                                UPDATED 2026-07-01 (#25): --r15-correct (default
                                ON) rewrites countywide_wet + plain neighbor cols
                                to the authoritative timeline at merge time.
  wet_source_timeline.py        Python: THE authoritative wet-source timeline
                                (#25 Section 2) -- 13 treated cohorts, partial
                                trio, derived always-wet set, hard asserts;
                                vintage-agnostic/idempotent. Import this; never
                                read countywide_wet raw from an archived CSV.
  build_panel_v2_r15port.py     Python: surgical column replacement archived ->
                                v2 panels (no pandas round-trip; untouched cells
                                byte-identical by construction). RAN 2026-07-01.
  gate_r15_port.py              Python: gates G1-G7 for the R15 port (mirrors
                                the #24 gate structure) -> R15_PORT_GATELOG.txt.
                                ALL 21 GATES PASS 2026-07-01 (needs shapely;
                                /usr/local/bin/python3).
  build_vmt_panel.py            Python: ARDOT .xls -> VMT panel + merge
  patch_madison_sebastian.do    Stata: Madison g2012 recode + Sebastian/partial-
                                wet handling + baseline-vs-robustness sample.
                                INTEGRATED into 02_csdid_estimation_v2.do 2026-06-30
                                (standalone file retained for reference/provenance)
  patch_border_madison_sebastian.py  Python: wet-source/timing edit for
                                build_border_augment_v2.py (Madison 2012;
                                Sebastian all-window source)
  merge_rucc.py                 Python: merge USDA ERS RUCC (2013 .xls + 2023 .xlsx)
                                onto the panel; builds rural_2013 (PRIMARY) + 2023
                                robustness + adjacency/nonadj flags (2026-06-29)
  build_driver_origin.py        Python: FARS attractor test on DR_ZIP -- joins
                                VEHICLE<-ACCIDENT on ST_CASE, DR_ZIP->home county via
                                HUD xwalk (ZIP-COUNTY or ZIP-TRACT), tags home_dry,
                                collapses to crash-county x year origin shares
                                (sh_home_dry[_drink]), and LEFT-MERGES them onto the
                                annual panel -> *_origin.csv (--monthly adds a
                                year x month file; --selftest runs the vehicle-side
                                only). Case-insensitive FARS discovery + Latin-1
                                fallback. RUN + MERGED 2026-06-29
  06_urban_diagnostics.do       Stata: stress-tests the URBAN-POSITIVE pattern
                                (#20/#22/#24) -- urban stacked event studies,
                                jackknife-by-county (origin + spillover arms),
                                Path B audit w/ county trends, from-zero dose
                                re-cut, VMT probe. Received from the claude.ai
                                session; FIXED 2026-07-02 before running: the
                                urban-treated roster omitted Madison 05087
                                (g2012 + RUCC-urban -> 4 treated, not 3; assert
                                + S2 leave-one-out corrected). RAN exit 0.
                                RESULT: urban-positive pattern NOT robust
                                (Benton+Saline story; S3 dies on drop-Craighead;
                                alcohol Path B ns under wild bootstrap; from-zero
                                urban arm empty; VMT null). See ANALYSIS_LOG #26.
  urban_diag_pathb_boot.do      Stata: S4 supplement -- boottest cannot follow
                                reghdfe with 2-way absorbed FE, so this refits
                                the Path B urban models boottest-compatibly
                                (identical coefs) and adds wild-cluster
                                bootstrap p on the 7 urban-dry clusters (#26)
  04b_heterogeneity_rucc.do     Stata: rural/urban split on rural_2013 (PRIMARY) +
                                rural_pop20k (robustness), Primary+ REG, across
                                fatal/alcohol/nonalc outcomes; guards on the Madison
                                g2012 recode -> het_rucc_results.csv (2026-06-29)

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
  arkansas_panel_annual_border_vmt.csv    50-col panel + POST border augment + VMT
                                          (1200 x 68; merge_step2.py, 2026-06-26;
                                          current full analysis panel for re-estimation)
  VMT_NOTES.txt                            VMT column dictionary + caveats
  -- session 2026-06-29 (nonalc outcome + RUCC) --
  arkansas_panel_annual_border_vmt_nonalc.csv       68-col panel + nonalc_fatal_crashes(_pc) (70)
  arkansas_panel_annual_border_vmt_nonalc_rucc.csv  + RUCC cols; FEED THIS to 02_v3/04b   (77)
  ruralurbancodes2013.xls                           ERS RUCC 2013 source (PRIMARY vintage)
  Ruralurbancontinuumcodes2023.xlsx                 ERS RUCC 2023 source (robustness)
  het_rucc_results.csv                              generated by 04b -- rural-vs-urban ATT table
  -- driver origin / attractor test (2026-06-29, RUN + MERGED) --
  ZIP-COUNTY_032017.xlsx                  HUD ZIP->county xwalk (2017Q1); maps DR_ZIP ->
                                          home county (static across window -- signal is
                                          the post-treatment SHIFT, not the level). A
                                          ZIP-TRACT_032017.xlsx variant also works
                                          (county=GEOID[:5]; ratios summed to county).
  driver_origin_long.csv                  one row per present driver in an AR fatal crash:
                                          crash fips/year/month, home_fips (5-digit
                                          COUNTY), DR_DRINK, resident/in_state/
                                          out_of_state, home_dry (AR home counties only)
  driver_origin_county_year.csv           collapsed to crash-fips x year (one row per
                                          county-year with >=1 present driver): n_drivers,
                                          n_drink, sh_nonresident, sh_out_of_state,
                                          sh_home_dry, sh_nonresident_drink,
                                          sh_home_dry_drink
  driver_origin_county_year_month.csv     same shares at crash-fips x year x MONTH
                                          (home_dry stays annual); produced but NOT
                                          merged -- no monthly panel yet
  arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv
                                          MERGED PANEL: 77-col RUCC panel LEFT-joined with
                                          the county-year origin shares on fips x year
                                          (1200 rows), adding 7 namespaced cols --
                                          orig_n_drivers, orig_n_drink, orig_sh_nonresident,
                                          orig_sh_out_of_state, orig_sh_home_dry,
                                          orig_sh_nonresident_drink, orig_sh_home_dry_drink.
                                          orig_* are NaN where no involved drivers (share
                                          undefined, not 0). Ready for csdid.
                                          KNOWN DEFECT (R15, 2026-07-01): countywide_wet
                                          is wet-all-window for Boone/Clark (g2010) ->
                                          n_wet_neighbors / *_chk / *_aug / share_wet_*
                                          miss all 2010 neighbor events (plain
                                          n_wet_neighbors also misses Madison 2012).
                                          cohort / first_treated_year / dist_* are CLEAN.
                                          For neighbor-based work use
                                          neighbor_counts_corrected.csv instead.
  -- session 2026-07-01 (04 splits + 05 origin test + R15 fix + 03 v4.1) --
  het_distance_results.csv                generated by 04 -- 41 rows: distance/contam/
                                          dose/jackknife ATTs + Pre_avg (ANALYSIS_LOG #20)
  origin_descriptive_cells.csv            generated by the 05 DRAFT run (#21, superseded)
  driver_origin_results.csv               generated by 05 -- 20 rows: level/comp x
                                          pool/rural/urban Poisson arms + robustness (#22)
  driver_origin_descriptives.csv          pooled-cell origin shares by group x post (#22)
  origin_event_{level,comp}_rural.csv     stacked event-study paths, rural arm (#22)
  counties.geojson                        public Plotly geojson-counties-fips.json
                                          (downloaded 2026-07-01; same source PLACE-1
                                          used -- id=FIPS, properties.NAME)
  neighbor_counts_corrected.csv           R15 fix output (rebuild_neighbor_counts.py):
                                          fips x year corrected n_wet_corr /
                                          share_wet_corr / n_aug_corr / share_aug_corr;
                                          merged by 03 v4.1 at run time
  spillover_v4_results.csv, spillover_v4_pathb.csv, output/spillover_v4_*
                                          generated by 03 v4.1 on CORRECTED cohorts --
                                          VALID as of 2026-07-01 (#24; the earlier
                                          quarantined first-run outputs were overwritten)
  BRINGBACK_2026-07-01.txt                session handback: results + diagnosis summary
                                          for the claude.ai session
  -- session 2026-07-01 (R15 PORT -> panel v2; ANALYSIS_LOG #25) --
  arkansas_panel_annual_border_vmt_nonalc_rucc_v2.csv         NEW CANONICAL
                                          (1200 x 77): corrected countywide_wet +
                                          neighbor + dist cols at rest; feed to
                                          02_v3 / 04b instead of the archive
  arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv  NEW CANONICAL
                                          (1200 x 84): same + orig_* cols; feed
                                          to 02_csdid / 03 v4.2 / 05
  R15_PORT_GATELOG.txt                    gate log (G1-G7, all 21 pass) certifying
                                          the v2 pair; regenerate via gate_r15_port.py
  out_r15port/                            regenerated PLACE-1 side-files under the
                                          v2 timeline (augment; pretreatment + OOS
                                          reproduce the certified originals byte-
                                          identically); certified originals in the
                                          project root remain untouched
  BRINGBACK_2026-07-01_R15PORT.txt        session handback for the R15 port
  -- session 2026-07-02 (urban diagnostics; ANALYSIS_LOG #26) --
  urban_diag_results.csv                  S2 origin jackknife (4 urban treated
                                          incl. Madison, leave-one-out)
  urban_diag_spill.csv                    S3 spillover jackknife (7 urban-dry)
  urban_diag_pathb.csv                    S4 Path B audit (verbatim + county
                                          trends + rural symmetry; p_boot empty
                                          BY CONSTRUCTION -- see _boot suppl.)
  urban_diag_pathb_boot.csv               S4 wild-cluster bootstrap supplement
                                          (alcohol +10.7 -> p_boot=.094 ns;
                                          fatal p_boot=.031 at the 7-cluster
                                          resolution floor)
  urban_diag_fromzero.csv                 S5 extensive-margin re-cut (urban arm
                                          EMPTY -- itself the finding)
  urban_diag_vmt.csv                      S6 VMT probe (all null; 2013+ only)
  origin_event_{level,comp}_urban_{nonres,drink}.csv   S1 urban stacked event
                                          paths (post all ns -- no jump behind
                                          the +57%/+39.5% statics)
  -- figures --
  HEADLINE (within-county always-dry, 2026-07-01):
    output/headline_event_{fatal,alcohol}.png            (Stata csdid_plot, Sec 6d)
    output/es_{fatal,alcohol}_headline_publication.png   (Python, navy/gold)
    output/es_panel_headline_publication.png             (side-by-side, Figure 1)
  ROBUSTNESS D (not-yet-treated, former primary):
    output/primary_event_{fatal,alcohol,fatalities}.png
    output/robust_a_event_*.png, output/robust_b_event_*.png
  fig1-5_*.png (descriptive)

Estimator scalar names (estat simple): r(att_1_1), r(se_1_1), r(p_1_1) -- may
vary by csdid version; verify with `return list` after first run.


R15 PORT / PANEL v2  (2026-07-01, ANALYSIS_LOG #25)
===================================================
The R15 defect (countywide_wet coded wet-all-window for Boone 05009 / Clark
05019 despite g2010; KNOWN ISSUE #9) is now fixed AT REST. New canonical pair
(the pre-v2 CSVs stay on disk as archives; nothing was overwritten):
  arkansas_panel_annual_border_vmt_nonalc_rucc_v2.csv          (1200 x 77)
  arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv   (1200 x 84)
Built by SURGICAL column replacement (build_panel_v2_r15port.py) so every
untouched cell is byte-identical to the archive; certified by 21 gates in
gate_r15_port.py -> R15_PORT_GATELOG.txt (logic identity vs the archived
_chk 1200/1200; exact diff decomposition; identity with the certified
neighbor_counts_corrected.csv; dist freeze; full-column freeze; timeline
asserts).

CORRECTED COLUMNS (everything else byte-identical to the archive):
  countywide_wet          the FULL authoritative wet-SOURCE timeline
                          (wet_source_timeline.py): Boone/Clark flip 2010,
                          Madison 2012, Sebastian/Logan/Woodruff wet
                          all-window, always-dry zero. It is now SAFE to read
                          countywide_wet as a wet-source timeline. cohort /
                          first_treated_year / treated_unit remain PLACE-2-
                          owned (patch_madison_sebastian.do -- unchanged,
                          verified idempotent on the v2 coding): Madison
                          still carries cohort 0 in-CSV.
  n_wet_neighbors, share_wet_neighbors, any_wet_neighbor,
  n_wet_neighbors_instate_chk, n_wet_neighbors_aug, any_wet_neighbor_aug,
  share_wet_neighbors_aug all rebuilt under that timeline (plain == _chk by
                          construction now; n_oos_wet_neighbors unchanged).
  dist_* / nearest_wet_fips_aug   corrected in EXACTLY 44 cells (5 counties x
                          2008-09: Carroll/Newton via Boone, Garland/Nevada/
                          Pike via Clark) where the not-yet-wet Boone/Clark
                          had understated distances (increases only, e.g.
                          Pike dist_border_aug 9.72 -> 19.18 mi). No
                          nearest_wet_is_oos change; the 13-row pretreatment
                          distance table is byte-identical, so 04's median /
                          contamination splits are untouched.
DESIGN DECISIONS (confirmed with Will, logged as #25 D1-D4): Logan is a
NEIGHBOR-count source but NOT a distance source (empirically not a no-op:
332 cells would move; parameterized via --logan-distance-source); the "CSV
carries the old coding by design" convention is RETIRED for countywide_wet.

DEPRECATION: runtime neighbor merges are no longer needed -- the v2 panels
carry correct columns. 03_spillovers_v4.do is v4.2: it prefers the v2 panel,
ASSERTS its columns equal neighbor_counts_corrected.csv on 1200/1200 cells
(the certified artifact stays as the verification path), and falls back to
the archived-panel runtime merge only if the v2 file is absent. No
estimation was re-run: 02/04/04b/05 key off cohort (unchanged) and 03 v4.1
already used exactly these neighbor values via the runtime merge (#24
results stand; smoke test reproduced the #24 cohort distribution).

PIPELINE (future rebuilds are correct by construction):
  wet_source_timeline.py            the ONE timeline; import it, never read
                                    countywide_wet raw from an archived CSV
  build_border_augment_v2_patched.py  "PLACE 1 PATCH v2": timeline + asserts
  merge_step2.py --r15-correct      rewrites countywide_wet + plain neighbor
                                    cols at merge time (refuses pre-port
                                    augments); regenerated side-files live in
                                    out_r15port/ (certified originals kept)


KNOWN ISSUES & OPEN QUESTIONS
=============================
  1. Madison County (05087): RESOLVED 2026-06-19 -- confirmed a 2012 treated
     county (AR SoS returns, Nov 6 2012, 57.29%). Recoded to g2012; border
     distances rebuilt + panel re-merged DONE 2026-06-26 (RERUN Steps 1-2);
     estimation recode INTEGRATED into 02_csdid_estimation_v2.do 2026-06-30
     (PLACE 2) -- Stata RUN executed 2026-06-30, exit 0 (see RERUN_RUNBOOK.txt).
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
  8. Rural/urban reclassification (2026-06-29): RUCC reassigns 6 of 12 treated
     counties vs the old 20k cut (split 5R/7U -> 9R/3U). The headline rural/urban
     reversal must be RE-TESTED under RUCC, not assumed robust -- ATTs will move.
     See the RURAL/URBAN CLASSIFIER note under ESTIMATION.
  9. countywide_wet miscoded for Boone (05009) and Clark (05019) -- coded wet for
     the ENTIRE window despite cohort=2010 (2010 confirmed primary; ANALYSIS_LOG
     R9/R15, found 2026-07-01). Harmless to the direct designs (csdid keys off
     cohort; dist_* verified clean) but it breaks EVERY neighbor-count column
     (n_wet_neighbors misses 2010 + Madison-2012 events; the PLACE-1 _chk/_aug
     rebuilds miss 2010). WORKED AROUND same day: rebuild_neighbor_counts.py ->
     neighbor_counts_corrected.csv (validated), merged by 03 v4.1 at run time --
     spillover results are VALID again (#24). STILL OPEN: the canonical panel's
     own countywide_wet / n_wet_neighbors / share_wet_* columns remain defective;
     fix at the next panel rebuild, and until then use ONLY the corrected file
     for neighbor-based work.
     RESOLVED 2026-07-01 (R15 PORT, #25): fixed AT REST in the v2 canonical
     pair (..._rucc_v2.csv / ..._rucc_origin_v2.csv), 21 gates pass
     (R15_PORT_GATELOG.txt); the same defect had also contaminated 44 dist_*
     cells (5 counties x 2008-09), corrected under #25/D4. Pre-v2 CSVs are
     archives. See the "R15 PORT / PANEL v2" section.


NEXT STEPS / TASK TRACKER
=========================
  [x] Descriptive plots; C&S-A estimation + pre-trend diagnostics
  [x] Control-group framing; publication event-study plots
  [x] Rural/urban heterogeneity; spillover (v3)
  [x] Border-state OOS coding + population-weighted distance metrics
  [x] VMT (2013-2023) extraction and merge
  [x] VERIFY Madison -- confirmed g2012 (AR SoS, Nov 2012)
  [x] Verify dry-control off-premise purity vs ABC GIS layer (clean; Sebastian excl.)
  [~] RE-RUN with Madison g2012 + Sebastian recode (RERUN_RUNBOOK):
      [x] Step 1 -- border distances rebuilt (build_border_augment_v2_patched.py,
          Plotly GeoJSON; PRE reproduces AUGMENT_NOTES exactly, POST clean) 2026-06-26
      [x] Step 2 -- panel re-merge -> arkansas_panel_annual_border_vmt.csv
          (merge_step2.py; 1200x68, full distance coverage) 2026-06-26
      [x] Step 3 -- 02_csdid re-estimate: DONE 2026-06-30 (StataNow 19.5 SE, exit 0,
          log 6155 lines, QC all pass). FINDINGS (see "RESULTS -- POST-RECODE RUN"):
          fatal pre-trend REJECTS under NYT treated-only (Pre_avg p=0.037) but PASSES
          under the within-county always-dry design (Sec 6b, p=0.807); Madison is not
          the cause (p=0.037 with/without). Aggregate ATTs all null (het is the story).
          OPEN DECISION: promote Sec 6b (always-dry controls) to the headline spec.
      [~] Step 4 -- heterogeneity + spillover with corrected control set
          [x] 04b_heterogeneity_rucc.do RAN 2026-07-01 (StataNow 19.5 SE, exit 0, QC
              all pass). Now calls `do patch_madison_sebastian.do` after import (the
              RUCC CSV carries old coding), runs BOTH control sets {alwaysdry=headline
              est_sample pool | fullpool=as-written notyet+all never-treated}, and
              captures the interpretable Pre_avg + p (estat pretrend p is r(pchi2),
              not r(p)). -> het_rucc_results.csv (24 rows). Headline (RUCC2013,
              alwaysdry): fatal rural -0.81/urban -0.65; alcohol rural -0.41/urban
              +0.33 (urban Pre_avg REJECTS p=0.005); nonalc rural -0.40/urban -0.99;
              all ns. Under RUCC the alcohol rural+/urban- reversal does NOT survive
              in the point estimates -- ATTs moved as predicted; read urban-alcohol
              with caution (pre-trend fails).
          [x] 04_heterogeneity_robustness.do (dist median split + contamination +
              dose-response + jackknife): RAN 2026-07-01 (StataNow 19.5 SE, exit 0,
              41/41 arms converged) -> het_distance_results.csv. NO attractor
              gradient: border split alcohol far -1.09 (p=.16) vs near +0.98
              (p=.26) -- wrong direction; dose NOT monotone (rural_nonadj fatal
              -1.19 p=.061* pre-PASS is the one clean near-significant cell, and
              it is NEGATIVE; rural_adj alcohol +1.02*** sits on a REJECTED
              Pre_avg in a 3-county cell); contamination oos alcohol +0.86***
              also pre-REJECT. Jackknife: alcohol stable null; fatal drop2012 ->
              -2.02** (2012 cohort pulls the pooled fatal ATT toward zero).
              Convergent NON-confirmation of the catchment gradient; corroborates
              the #15 attenuation. See ANALYSIS_LOG #20.
          [x] 03 spillover: RESOLVED SAME DAY. First run (exit 0) failed the
              cohort verification -- countywide_wet miscoded wet-all-window for
              Boone/Clark (g2010) so NO 2010 spillover events existed in any
              neighbor column, and plain n_wet_neighbors also predated the
              Madison recode (ANALYSIS_LOG #23 + R15). FIXED locally:
              rebuild_neighbor_counts.py (public Plotly geojson; STAGE-A
              validated vs n_wet_neighbors_instate_chk 1200/1200) ->
              neighbor_counts_corrected.csv, merged by 03 v4.1 at run time;
              re-run exit 0 with VALID cohorts (22 treated / 7 never; 2010 =
              Newton/Searcy/Pike/Nevada/Montgomery; Madison's dry neighbors at
              2012). RESULTS (#24): pooled spillover ATTs null (pre PASS);
              rural alcohol -1.20 (p=.029**) numerically reproduces v3's -1.19
              BUT Pre_avg REJECTS (p=.022); URBAN dry neighbors POSITIVE (fatal
              +4.88 p=.014**, pre PASS; Path B urban +18.1***/+10.7***); Path B
              pooled alcohol share +1.74 (p=.020**, positive = wrong direction
              for shedding). The v3 symmetry claim does not survive intact.
              Direct designs (02/04/05) unaffected throughout (key off cohort;
              distances verified clean).
  [x] 04_heterogeneity_robustness.do: median split on dist_border_aug +
      contamination split (nearest_wet_is_oos) + jackknife-by-cohort
      -> DONE 2026-07-01, see Step 4 box above + ANALYSIS_LOG #20
  [ ] 02_v3 / 03_v2: covariate re-estimation; per-capita & VMT/exposure outcomes
  [x] Disjoint outcomes: NON-alcohol fatal (= fatal - alcohol) added as a
      mechanism-decomposition outcome -- nonalc_fatal_crashes(_pc) 2026-06-29
  [ ] Add non-fatal crashes + DUIs (ARDOT) for power
  [ ] Reframe identification as cross-border shopping / tax-avoidance (not
      classic border-discontinuity); cite gas-tax border literature
  [~] FARS attractor test via DR_ZIP (driver home ZIP, not REG_STAT):
      build_driver_origin.py RUN 2026-06-29 (ZIP-COUNTY_032017 xwalk + FARS 2008-2023);
      origin shares MERGED onto the RUCC panel ->
      arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv (orig_* cols). Remaining:
      test post-treatment rise in orig_sh_home_dry; extend to adjacent-county conditioning.
      2026-07-01: 05_driver_origin.do (06-30 draft) RAN provisionally (ppmlhdfe +
      jwdid now installed): PRIMARY nonresident inflow null; SHARPEST drinking
      inflow urban RR 1.42 (p=.021) vs rural 0.81 (ns), differential p=.009 --
      OPPOSITE-signed to the attractor; BORDER OOS rural RR 1.30 (ns). The
      UPDATED 05 (LEVEL/COMP event arms, DR_ZIP coverage table, jwdid Sec 6) was
      never transferred from the claude.ai session -- transfer + re-run before
      citing. See ANALYSIS_LOG #21.
      2026-07-01 (later): UPDATED 05 transferred, patched (arm-condition
      parenthesization bug that killed the rural/urban COMP arms; str28
      outcome), RAN clean (18/18 arms; hdfe installed). RESULT -- NOT
      SUPPORTIVE of the rural attractor: rural arms ALL NULL on every margin
      (level/comp x nonres/drink/dry; the sharpest inbound-from-dry cell level
      -0.7% p=.97); urban drinking inflow RISES (level +57% p=.019**, comp +39%
      p=.032**); rural LEVEL event pre-path not flat (Tm5/Tm4 negative sig);
      coverage QC clean (~99%, moves <1pp). jwdid arm does not converge (open).
      -> driver_origin_results.csv, origin_event_{level,comp}_rural.csv,
      driver_origin_descriptives.csv. See ANALYSIS_LOG #22 (supersedes #21).
  [x] Rural/urban cutoff: replaced ad hoc 20k with USDA RUCC (merge_rucc.py;
      rural_2013 primary / 2023 robustness) 2026-06-29 -- re-test headline split
  [ ] Monthly panel + day-of-week FE (Sunday-sales effect); PPML/NB FE for zeros
  [ ] Welfare/policy discussion; full paper write-up
================================================================
