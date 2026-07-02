#!/usr/bin/env /usr/local/bin/python3
"""
rebuild_neighbor_counts.py -- R14 fix (ANALYSIS_LOG R14, #19).

The canonical panel's neighbor-count columns are built on a wet timeline in
which Boone (05009) and Clark (05019) are wet for the ENTIRE window despite
cohort = 2010 (R9: 2010 confirmed primary), and the plain n_wet_neighbors
additionally predates the Madison recode. This script rebuilds the in-state
neighbor counts/shares from adjacency x the CORRECTED (PLACE-2) wet timeline
and emits neighbor_counts_corrected.csv keyed fips x year, to be merged at
run time by 03_spillovers_v4.do (mirroring how patch_madison_sebastian.do
owns treatment coding at run time -- the canonical CSV is NOT modified).

ADJACENCY: Plotly geojson-counties-fips.json (counties.geojson), the SAME
source PLACE-1 used (RERUN_RUNBOOK Step 1), buffer 0.0005 deg + intersects.
VALIDATION GATE (stage A): under the PLACE-1 timeline (panel countywide_wet
with Madison->year>=2012, Sebastian->1) the rebuilt counts must reproduce
n_wet_neighbors_instate_chk on all 1200 cells. Only then is the corrected
series (stage B) trusted.

CORRECTED (PLACE-2) TIMELINE (matches patch_madison_sebastian.do):
  treated (13, incl Madison 2012, Boone/Clark 2010): wet = (year >= cohort)
  partial_wet trio 05131 Sebastian / 05083 Logan / 05147 Woodruff: wet all window
  all other never-treated: panel countywide_wet (constant; asserted)
Expected diff vs _chk decomposes EXACTLY as:
  (a) Boone/Clark AR-neighbors, 2008-2009 only (counts fall);
  (b) Logan AR-neighbors, all years (+1: PLACE-1 left Logan dry as a source;
      PLACE-2 codes it wet -- constant, so no spurious events either way).

OUTPUT COLUMNS (neighbor_counts_corrected.csv):
  fips, year, n_wet_corr, share_wet_corr, n_aug_corr, share_aug_corr
  (aug = corrected in-state + the panel's n_oos_wet_neighbors, which is
   unaffected by R14; aug share uses the panel's own aug denominator.)
"""
import csv, json, sys
from collections import defaultdict
from shapely.geometry import shape
from shapely.strtree import STRtree

ADJ_BUFFER_DEG = 0.0005
LAND_STATES  = {'29', '40', '48', '22'}
RIVER_STATES = {'28', '47'}
BORDER_STATES = LAND_STATES | RIVER_STATES

PANEL   = 'arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv'
GEOJSON = 'counties.geojson'
OUT     = 'neighbor_counts_corrected.csv'

PARTIAL_WET = {'05131', '05083', '05147'}   # Sebastian / Logan / Woodruff
MADISON = '05087'

# ---- load panel -----------------------------------------------------------
rows = list(csv.DictReader(open(PANEL)))
for r in rows:
    r['fips'] = r['fips'].zfill(5)
    r['year'] = int(r['year'])
years   = sorted({r['year'] for r in rows})
ar_fips = sorted({r['fips'] for r in rows})
name    = {r['fips']: r['county'] for r in rows}
cw      = {(r['fips'], r['year']): int(r['countywide_wet']) for r in rows}
chk     = {(r['fips'], r['year']): int(r['n_wet_neighbors_instate_chk']) for r in rows}
noos    = {(r['fips'], r['year']): int(r['n_oos_wet_neighbors']) for r in rows}
naug    = {(r['fips'], r['year']): int(r['n_wet_neighbors_aug']) for r in rows}
shaug   = {(r['fips'], r['year']): float(r['share_wet_neighbors_aug']) for r in rows}
nnbr    = {r['fips']: int(r['n_neighbors']) for r in rows}
cohort  = {}
for r in rows:
    c = r['cohort']
    cohort[r['fips']] = int(float(c)) if c not in ('', 'nan') else 0
cohort[MADISON] = 2012          # patch rule; CSV carries old coding by design

# ---- adjacency (same construction as build_border_augment_v2_patched.py) --
gj = json.load(open(GEOJSON))
geoms = {}
for ft in gj['features']:
    f = ft.get('id'); st = f[:2] if f else None
    if st == '05' or st in BORDER_STATES:
        geoms[f] = shape(ft['geometry'])
fl = list(geoms)
buf = {f: geoms[f].buffer(ADJ_BUFFER_DEG) for f in fl}
tree = STRtree([geoms[f] for f in fl])
adj = defaultdict(set)
for f in fl:
    if f[:2] != '05':
        continue
    for idx in tree.query(buf[f]):
        g = fl[idx]
        if g != f and buf[f].intersects(geoms[g]):
            adj[f].add(g)
ar_nbrs = {c: sorted(g for g in adj[c] if g[:2] == '05') for c in ar_fips}

# ---- stage A: validation gate against n_wet_neighbors_instate_chk ---------
def wet_p1(f, yr):                       # PLACE-1 timeline (defective by design)
    if f == MADISON:  return 1 if yr >= 2012 else 0
    if f == '05131':  return 1
    return cw[(f, yr)]

bad = 0
for c in ar_fips:
    for yr in years:
        n = sum(wet_p1(g, yr) for g in ar_nbrs[c])
        if n != chk[(c, yr)]:
            bad += 1
            if bad <= 5:
                print(f'  MISMATCH {c} {name[c]} {yr}: rebuilt {n} vs _chk {chk[(c,yr)]}')
if bad:
    sys.exit(f'STAGE A FAILED: {bad}/1200 cells differ from n_wet_neighbors_instate_chk '
             '-- adjacency does NOT reproduce PLACE-1; do not trust stage B.')
print('STAGE A PASS: adjacency reproduces n_wet_neighbors_instate_chk on 1200/1200 cells.')

# ---- stage B: corrected (PLACE-2) timeline --------------------------------
def wet_corr(f, yr):
    if cohort[f] > 0:        return 1 if yr >= cohort[f] else 0
    if f in PARTIAL_WET:     return 1
    return cw[(f, yr)]

# never-treated non-partial counties must be constant (always-wet or always-dry)
for f in ar_fips:
    if cohort[f] == 0 and f not in PARTIAL_WET:
        vals = {cw[(f, yr)] for yr in years}
        assert len(vals) == 1, f'{f} {name[f]} never-treated but countywide_wet varies: {vals}'

ncorr = {(c, yr): sum(wet_corr(g, yr) for g in ar_nbrs[c]) for c in ar_fips for yr in years}

# QC 1: monotone non-decreasing within county
for c in ar_fips:
    prev = None
    for yr in years:
        assert prev is None or ncorr[(c, yr)] >= prev, f'DECREASE at {c} {yr}'
        prev = ncorr[(c, yr)]

# QC 2: the diff vs _chk decomposes exactly as documented
bc_nbrs   = {c for c in ar_fips if '05009' in ar_nbrs[c] or '05019' in ar_nbrs[c]}
logan_nbr = {c for c in ar_fips if '05083' in ar_nbrs[c]}
undecomposed = 0
for c in ar_fips:
    for yr in years:
        d = ncorr[(c, yr)] - chk[(c, yr)]
        expect = (1 if c in logan_nbr else 0) \
               - ((('05009' in ar_nbrs[c]) + ('05019' in ar_nbrs[c])) if yr < 2010 else 0)
        if d != expect:
            undecomposed += 1
            if undecomposed <= 5:
                print(f'  UNDECOMPOSED {c} {name[c]} {yr}: diff {d}, expected {expect}')
assert undecomposed == 0, f'{undecomposed} cells differ from _chk in unexplained ways'
print('QC PASS: corrected-vs-_chk diff = Boone/Clark neighbors pre-2010 '
      '+ Logan neighbors (constant) exactly.')

# QC 3: increment years now include 2010; show the distribution
inc_by_year = defaultdict(int)
first_inc = {}
for c in ar_fips:
    prev = None
    for yr in years:
        if prev is not None and ncorr[(c, yr)] > prev:
            inc_by_year[yr] += 1
            first_inc.setdefault(c, yr)
        prev = ncorr[(c, yr)]
print('increments by year (corrected):', dict(sorted(inc_by_year.items())))
assert 2010 in inc_by_year, 'no 2010 increments -- Boone/Clark fix did not land'
mad_dry_2012 = [name[c] for c in ar_nbrs[MADISON] if cohort[c] == 0 and first_inc.get(c) == 2012]
print('Boone neighbors:', [name[g] for g in ar_nbrs['05009']])
print('Clark neighbors:', [name[g] for g in ar_nbrs['05019']])
print('Madison AR-neighbors with first increment 2012:', mad_dry_2012)

# ---- aug series + shares ---------------------------------------------------
# aug denominator per county, recovered from the panel's own aug count/share
den_aug = {}
for c in ar_fips:
    ds = {round(naug[(c, yr)] / shaug[(c, yr)]) for yr in years if shaug[(c, yr)] > 0}
    assert len(ds) <= 1, f'{c}: aug denominator not constant: {ds}'
    den_aug[c] = ds.pop() if ds else None

with open(OUT, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['fips', 'year', 'n_wet_corr', 'share_wet_corr',
                'n_aug_corr', 'share_aug_corr'])
    for c in ar_fips:
        for yr in years:
            n_in  = ncorr[(c, yr)]
            n_aug = n_in + noos[(c, yr)]
            sh_in  = round(n_in / nnbr[c], 4) if nnbr[c] else 0.0
            if den_aug[c]:
                sh_aug = round(n_aug / den_aug[c], 4)
            else:
                assert n_aug == 0, f'{c} {yr}: aug count >0 but no denominator'
                sh_aug = 0.0
            w.writerow([c, yr, n_in, sh_in, n_aug, sh_aug])
print(f'Wrote {OUT} ({len(ar_fips) * len(years)} rows).')
