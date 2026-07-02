#!/usr/bin/env /usr/local/bin/python3
"""
wet_source_timeline.py -- THE authoritative wet-SOURCE timeline (R15 port).

Single source of truth for "which Arkansas counties are off-premise wet
SOURCES in year t", per ANALYSIS_LOG #25 (Section 2 of the R15-port brief).
Every script that needs a wet timeline imports THIS module instead of reading
the panel's countywide_wet column raw -- reading that column as a timeline is
exactly how R15 happened (Boone/Clark coded wet-all-window despite g2010).

wet_source(fips, year) = 1 iff
  a) county is always-wet (derived programmatically from the panel: never-
     treated in-CSV and wet the whole window, MINUS Madison and the partial-
     wet trio, which are owned by rules (b)/(c)), OR
  b) county is partial-wet-all-window: Sebastian 05131, Logan 05083,
     Woodruff 05147, OR
  c) county is one of the 13 treated and year >= cohort (TREATED_COHORTS), OR
  d) otherwise 0 (always-dry).

TWO timelines are exposed because of design decision D1 (ANALYSIS_LOG #25):
  wet_nbr  -- the full Section-2 timeline (Logan wet). Used for NEIGHBOR
              counts/shares; matches rebuild_neighbor_counts.py exactly.
  wet_dist -- the DISTANCE-source timeline. Logan's wetness is sub-county
              (Booneville area, beer & native wine only; see
              SUBCOUNTY_DISTANCE_NOTES.txt), so whether it serves as a
              distance TARGET is a real design choice, parameterized via
              logan_distance_source. The D1 empirical test (gate G5) decides
              the default recorded in ANALYSIS_LOG #25.

The builder is idempotent across panel vintages: it accepts either the OLD
(pre-v2) coding (Madison wet-all-window & cohort 0; Sebastian/Logan dry) or
the corrected v2 coding, and returns the same timeline either way.
"""

WINDOW = range(2008, 2024)

TREATED_COHORTS = {
    '05009': 2010, '05019': 2010,                    # Boone, Clark
    '05007': 2012, '05087': 2012, '05135': 2012,     # Benton, Madison, Sharp
    '05027': 2014, '05125': 2014,                    # Columbia, Saline
    '05081': 2016,                                   # Little River
    '05121': 2018,                                   # Randolph
    '05133': 2020, '05141': 2020,                    # Sevier, Van Buren
    '05059': 2022, '05113': 2022,                    # Hot Spring, Polk
}
PARTIAL_WET = {'05131', '05083', '05147'}            # Sebastian, Logan, Woodruff
MADISON = '05087'
LOGAN   = '05083'

# In-CSV cohorts the OLD panels are known to disagree on, BY DESIGN:
# Madison carries cohort 0 in every pre-v2 CSV (PLACE-2 owns its g2012).
_CSV_COHORT_EXEMPT = {MADISON}


def build_timelines(cohort_csv, cw, years=None, logan_distance_source=False):
    """Build (wet_nbr, wet_dist, info) from a panel's in-CSV coding.

    cohort_csv : dict fips -> in-CSV cohort (int; 0 = never-treated in-CSV)
    cw         : dict (fips, year) -> in-CSV countywide_wet (0/1)
    years      : iterable of panel years (default 2008-2023)
    Returns two callables wet_*(fips, year) -> 0/1 plus an info dict.
    """
    years = sorted(years) if years else list(WINDOW)
    fips = sorted(cohort_csv)

    # -- cross-check the hardcoded cohorts against the CSV where it carries them
    for f, g in TREATED_COHORTS.items():
        got = cohort_csv.get(f)
        if got is None:
            raise AssertionError(f'treated county {f} missing from panel')
        if got not in (g, 0 if f in _CSV_COHORT_EXEMPT else g):
            raise AssertionError(
                f'{f}: in-CSV cohort {got} != authoritative {g} '
                '(and not a documented exemption)')

    # -- always-wet set, derived (not hand-listed): never-treated in-CSV and
    #    wet the whole window, minus Madison + the partial trio (rules b/c own
    #    those). Works on old AND corrected panels (Madison/Sebastian/Logan
    #    fall out of or into the derived set consistently either way).
    always_wet = {f for f in fips
                  if cohort_csv[f] == 0
                  and all(cw[(f, y)] == 1 for y in years)}
    always_wet -= ({MADISON} | PARTIAL_WET)

    # -- every remaining county must be constant in-CSV (no stealth timelines)
    for f in fips:
        if f in TREATED_COHORTS or f in PARTIAL_WET:
            continue
        vals = {cw[(f, y)] for y in years}
        if len(vals) != 1:
            raise AssertionError(
                f'{f}: never-treated non-partial county with a time-varying '
                f'countywide_wet {sorted(vals)} -- unexpected panel coding')

    def wet_nbr(f, yr):
        g = TREATED_COHORTS.get(f)
        if g:
            return 1 if yr >= g else 0
        if f in PARTIAL_WET:
            return 1
        return 1 if f in always_wet else 0

    if logan_distance_source:
        wet_dist = wet_nbr
    else:
        def wet_dist(f, yr):
            if f == LOGAN:
                return 0
            return wet_nbr(f, yr)

    # -- reconciliation asserts (only meaningful on the full 75-county panel)
    info = {'always_wet': always_wet,
            'n_always_wet': len(always_wet),
            'n_treated': len(TREATED_COHORTS),
            'logan_distance_source': logan_distance_source}
    if len(fips) == 75:
        pre2010 = sum(wet_nbr(f, 2008) for f in fips)
        n_dry = sum(1 for f in fips
                    if f not in TREATED_COHORTS and f not in PARTIAL_WET
                    and f not in always_wet)
        assert len(TREATED_COHORTS) == 13, 'expected 13 treated counties'
        # The CSV's 32 never-treated wet-all-window counties = 30 plain
        # always-wet + Madison (treated, rule c) + Woodruff (partial, rule b),
        # so the derived set here is 30. The brief's "31 always-wet" counts
        # Woodruff inside it; either bookkeeping gives the same reconciliation:
        # wet sources pre-2010 = 30 + {Sebastian, Logan, Woodruff} = 33
        # (matches rebuild_neighbor_counts.py: 31 always-wet + Sebastian +
        # Logan, with Woodruff inside the 31).
        assert len(always_wet) == 30, \
            f'derived always-wet set has {len(always_wet)} counties, expected 30'
        assert pre2010 == 33, f'expected 33 wet sources in 2008, got {pre2010}'
        assert n_dry == 29, f'expected 29 always-dry counties, got {n_dry}'
        info['n_sources_2008'] = pre2010
        info['n_always_dry'] = n_dry
    return wet_nbr, wet_dist, info


def hard_asserts(wet, years=None, neighbors_variant=True):
    """The T1 hard asserts (ANALYSIS_LOG #25), run on a timeline callable.

    neighbors_variant=True asserts Logan wet all-window (wet_nbr);
    False asserts Logan dry all-window (wet_dist under the D1 default).
    """
    years = sorted(years) if years else list(WINDOW)
    for f, g in TREATED_COHORTS.items():
        for y in years:
            assert wet(f, y) == (1 if y >= g else 0), \
                f'{f} (cohort {g}): wet({y}) = {wet(f, y)}'
    for f in ('05131', '05147'):                      # Sebastian, Woodruff
        assert all(wet(f, y) == 1 for y in years), f'{f} not wet all-window'
    if neighbors_variant:
        assert all(wet(LOGAN, y) == 1 for y in years), \
            'Logan not wet all-window in the neighbor timeline'
    else:
        assert all(wet(LOGAN, y) == 0 for y in years), \
            'Logan is a distance source but logan_distance_source=False'


def cohort_and_cw_from_rows(rows):
    """Convenience: extract (cohort_csv, cw, years) from csv.DictReader rows
    that carry fips / year / cohort / countywide_wet (fips zero-padded here)."""
    cohort_csv, cw, years = {}, {}, set()
    for r in rows:
        f = str(r['fips']).zfill(5)
        y = int(r['year'])
        c = str(r.get('cohort', '') or '0')
        try:
            cohort_csv[f] = int(float(c))
        except ValueError:
            cohort_csv[f] = 0
        cw[(f, y)] = int(r['countywide_wet'])
        years.add(y)
    return cohort_csv, cw, sorted(years)
