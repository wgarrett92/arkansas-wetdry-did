"""
build_border_augment.py
========================
Augments the Arkansas wet/dry DiD panel with OUT-OF-STATE border-county
alcohol access. Produces, per county-year:
  - distance to nearest wet county, IN-STATE only (replicates current logic)
  - distance to nearest wet county, AUGMENTED with accessible out-of-state
    (OOS) wet counties, with a river-crossing accessibility constraint
  - augmented wet-neighbor counts (in-state + accessible OOS)

Treatment margin coded is OFF-PREMISE retail access (liquor/beer/wine for
take-home), which is the clean countywide margin. On that margin the relevant
border states are wet for the entire 2008-2023 window:
  MO  (29): no dry counties, wet statewide          -> land, wet
  OK  (40): package stores statewide entire window  -> land, wet
            (SQ792 Oct-2018 changed ON-premise only, not off-premise)
  TX  (48): AR-facing counties (Texarkana/Bowie) wet -> land, wet [verify]
  LA  (22): mostly wet (51/64 parishes wet)          -> land, wet [verify]
  MS  (28): patchwork; reachable only at river bridges-> river, crossing-gated
  TN  (47): liquor local-option but beer everywhere;  -> river, crossing-gated
            Memphis/Shelby wet, reached via West Memphis

RIVER-CROSSING CONSTRAINT: the eastern AR border is the Mississippi River.
Straight-line distance to a county "across the water" overstates access where
no bridge exists, so cross-river OOS counties are accessible ONLY through the
whitelisted bridge pairs below. All land borders (MO/OK/TX/LA) are unrestricted.

CENTROIDS: geometric (area) centroids from the plotly county GeoJSON. To use
POPULATION-WEIGHTED centroids instead (your open design question), supply
--popcentroids path/to/file.csv with columns [fips, lon, lat]; they override
the geometric centroids where present.

ADJACENCY: derived from the GeoJSON via buffered intersection, then VALIDATED
against the panel's existing in-state n_wet_neighbors. For the authoritative
version, pass --adjacency path/to/census_county_adjacency.txt to override.

Outputs (to OUTDIR):
  oos_wet_reference.csv              transparent, editable OOS coding
  distance_neighbor_augment.csv      fips x year, the new columns (merge key)
  arkansas_did_panel_with_border.csv panel + merged new columns
  pretreatment_distance_by_treated.csv  per treated county, dist at cohort-1
"""

import json, math, argparse, csv
from collections import defaultdict
from shapely.geometry import shape
from shapely.strtree import STRtree

# ----------------------------- config ---------------------------------------
R_MILES = 3958.8                       # Haversine radius, matches project conv.
ADJ_BUFFER_DEG = 0.0005                # ~50m tol: bridges shared borders (dist 0)
                                       # without linking near-corner counties
                                       # (e.g. Hempstead-Sevier sit ~150m apart)
LAND_STATES  = {'29', '40', '48', '22'}   # MO, OK, TX, LA  (unrestricted)
RIVER_STATES = {'28', '47'}               # MS, TN          (crossing-gated)
BORDER_STATES = LAND_STATES | RIVER_STATES

# Whitelisted Mississippi-River bridge crossings: AR county -> reachable OOS
CROSSINGS = {
    '05035': {'47157'},   # Crittenden (West Memphis) -> Shelby TN (Memphis), I-40/I-55
    '05107': {'28027'},   # Phillips (Helena)         -> Coahoma MS, Helena Bridge US-49
    '05017': {'28151'},   # Chicot (Lake Village)     -> Washington MS (Greenville), US-82
}
# Off-premise wet status for OOS ring counties (1=wet on off-premise margin).
# Default by state rule; per-FIPS overrides for the river crossings + verify flags.
def oos_offpremise_wet(fips, state):
    if state in ('29', '40'):           # MO, OK: wet, high confidence
        return 1, 'high'
    if state in ('48', '22'):           # TX, LA: wet AR-facing, verify
        return 1, 'verify'
    if fips in ('47157', '28027', '28151'):   # whitelisted crossings, wet
        return 1, 'med'
    return 0, 'na'                      # other river counties: not accessible


def accessible(ar_fips, oos_fips, oos_state):
    """Can residents of ar_fips practically reach oos_fips for off-premise?"""
    if oos_state in LAND_STATES:
        return True
    return oos_fips in CROSSINGS.get(ar_fips, set())   # river: bridge only


def haversine(lat1, lon1, lat2, lon2):
    p = math.pi / 180.0
    a = (math.sin((lat2-lat1)*p/2)**2
         + math.cos(lat1*p)*math.cos(lat2*p)*math.sin((lon2-lon1)*p/2)**2)
    return 2 * R_MILES * math.asin(math.sqrt(a))


# --------------------------- load inputs ------------------------------------
def load_centroids(geojson_path, pop_path=None):
    g = json.load(open(geojson_path))
    geoms, cents, names, states = {}, {}, {}, {}
    for feat in g['features']:
        fips = feat.get('id')
        if not fips:
            continue
        st = fips[:2]
        if st != '05' and st not in BORDER_STATES:
            continue
        gm = shape(feat['geometry'])
        geoms[fips] = gm
        c = gm.centroid
        cents[fips] = (c.y, c.x)        # (lat, lon)
        names[fips] = feat['properties'].get('NAME', '')
        states[fips] = st
    if pop_path:                        # optional population-weighted override
        for row in csv.DictReader(open(pop_path)):
            f = row['fips'].zfill(5)
            cents[f] = (float(row['lat']), float(row['lon']))
    return geoms, cents, names, states


def derive_adjacency(geoms):
    """Queen contiguity with tolerance, via buffered intersection."""
    fipses = list(geoms.keys())
    buffered = {f: geoms[f].buffer(ADJ_BUFFER_DEG) for f in fipses}
    tree = STRtree(fipses_geoms := [geoms[f] for f in fipses])
    adj = defaultdict(set)
    for f in fipses:
        if f[:2] != '05':               # only need adjacency anchored on AR
            continue
        for idx in tree.query(buffered[f]):
            g = fipses[idx]
            if g == f:
                continue
            if buffered[f].intersects(geoms[g]):
                adj[f].add(g)
    return adj


def load_panel(path):
    rows = list(csv.DictReader(open(path)))
    for r in rows:
        r['fips'] = r['fips'].zfill(5)
        r['year'] = int(r['year'])
        r['countywide_wet'] = int(r['countywide_wet'])
    return rows


# ------------------------------ main ----------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--panel',    default='/mnt/project/arkansas_did_panel.csv')
    ap.add_argument('--geojson',  default='/home/claude/counties.geojson')
    ap.add_argument('--popcentroids', default=None)
    ap.add_argument('--adjacency',    default=None)   # census file override
    ap.add_argument('--outdir',   default='/home/claude/out')
    args = ap.parse_args()

    import os; os.makedirs(args.outdir, exist_ok=True)

    geoms, cents, names, states = load_centroids(args.geojson, args.popcentroids)
    rows = load_panel(args.panel)
    years = sorted({r['year'] for r in rows})
    ar_fips = sorted({r['fips'] for r in rows})

    # wet-status-by-year for AR (authoritative: panel countywide_wet)
    wet = {(r['fips'], r['year']): r['countywide_wet'] for r in rows}

    # adjacency
    adj = derive_adjacency(geoms)

    # OOS ring = border-state counties adjacent to >=1 AR county
    oos_ring = sorted({g for f in ar_fips for g in adj.get(f, set())
                       if g[:2] in BORDER_STATES})

    # build OOS reference + which AR county each ring county is adjacent to
    oos_rows, oos_wet, oos_conf = [], {}, {}
    for j in oos_ring:
        st = states[j]
        w, conf = oos_offpremise_wet(j, st)
        oos_wet[j], oos_conf[j] = w, conf
        ar_neighbors = sorted(f for f in ar_fips if j in adj.get(f, set()))
        access_ar = sorted(f for f in ar_neighbors if accessible(f, j, st))
        oos_rows.append({
            'oos_fips': j, 'state': st, 'name': names[j],
            'border_type': 'land' if st in LAND_STATES else 'river',
            'offpremise_wet': w, 'confidence': conf,
            'adjacent_ar': ';'.join(ar_neighbors),
            'accessible_from_ar': ';'.join(access_ar),
        })

    # wet candidate centroids (for distance) split by in-state vs OOS-accessible
    def candidates_for(c, yr):
        """yield (fips, lat, lon) wet & accessible to AR county c in year yr."""
        for f in ar_fips:
            if f != c and wet.get((f, yr), 0) == 1:
                la, lo = cents[f]; yield f, la, lo
        for j in oos_ring:
            if oos_wet[j] == 1 and accessible(c, j, states[j]):
                la, lo = cents[j]; yield j, la, lo

    def candidates_instate(c, yr):
        for f in ar_fips:
            if f != c and wet.get((f, yr), 0) == 1:
                la, lo = cents[f]; yield f, la, lo

    # compute per county-year distances + neighbor counts
    aug = {}
    for c in ar_fips:
        clat, clon = cents[c]
        oos_nbrs = [j for j in adj.get(c, set())
                    if j[:2] in BORDER_STATES and oos_wet.get(j, 0) == 1
                    and accessible(c, j, states[j])]
        instate_nbrs = [f for f in adj.get(c, set()) if f[:2] == '05']
        for yr in years:
            # distances
            din = min((haversine(clat, clon, la, lo)
                       for _, la, lo in candidates_instate(c, yr)), default=float('nan'))
            best_f, best_d = None, float('inf')
            for f, la, lo in candidates_for(c, yr):
                d = haversine(clat, clon, la, lo)
                if d < best_d:
                    best_d, best_f = d, f
            daug = best_d if best_f else float('nan')
            nearest_oos = 1 if (best_f and best_f[:2] != '05') else 0
            # neighbor wet counts
            n_instate_wet = sum(wet.get((f, yr), 0) == 1 for f in instate_nbrs)
            n_oos_wet = len(oos_nbrs)            # OOS wet status time-invariant
            n_aug = n_instate_wet + n_oos_wet
            tot_nbrs = len(instate_nbrs) + len(oos_nbrs)
            aug[(c, yr)] = {
                'dist_nearest_wet_instate': round(din, 3),
                'dist_nearest_wet_aug':     round(daug, 3),
                'nearest_wet_is_oos':       nearest_oos,
                'nearest_wet_fips_aug':     best_f or '',
                'n_wet_neighbors_instate_chk': n_instate_wet,
                'n_oos_wet_neighbors':      n_oos_wet,
                'n_wet_neighbors_aug':      n_aug,
                'any_wet_neighbor_aug':     int(n_aug > 0),
                'share_wet_neighbors_aug':  round(n_aug / tot_nbrs, 4) if tot_nbrs else 0.0,
            }

    # ---- QC: my in-state wet-neighbor count vs panel's n_wet_neighbors ----
    match = tot = 0
    mism = []
    for r in rows:
        key = (r['fips'], r['year'])
        if 'n_wet_neighbors' in r and r['n_wet_neighbors'] != '':
            tot += 1
            if int(r['n_wet_neighbors']) == aug[key]['n_wet_neighbors_instate_chk']:
                match += 1
            else:
                mism.append((r['fips'], r['county'], r['year'],
                             r['n_wet_neighbors'], aug[key]['n_wet_neighbors_instate_chk']))
    qc_rate = match / tot if tot else 0

    # ---- write outputs ----
    od = args.outdir
    with open(f'{od}/oos_wet_reference.csv', 'w', newline='') as f:
        w_ = csv.DictWriter(f, fieldnames=list(oos_rows[0].keys())); w_.writeheader()
        w_.writerows(oos_rows)

    newcols = ['dist_nearest_wet_instate', 'dist_nearest_wet_aug',
               'nearest_wet_is_oos', 'nearest_wet_fips_aug',
               'n_wet_neighbors_instate_chk', 'n_oos_wet_neighbors',
               'n_wet_neighbors_aug', 'any_wet_neighbor_aug',
               'share_wet_neighbors_aug']
    with open(f'{od}/distance_neighbor_augment.csv', 'w', newline='') as f:
        w_ = csv.DictWriter(f, fieldnames=['fips', 'year'] + newcols); w_.writeheader()
        for c in ar_fips:
            for yr in years:
                w_.writerow({'fips': c, 'year': yr, **aug[(c, yr)]})

    panel_fields = list(rows[0].keys())
    with open(f'{od}/arkansas_did_panel_with_border.csv', 'w', newline='') as f:
        w_ = csv.DictWriter(f, fieldnames=panel_fields + newcols); w_.writeheader()
        for r in rows:
            w_.writerow({**{k: r[k] for k in panel_fields}, **aug[(r['fips'], r['year'])]})

    # pre-treatment distance for the 12 treated counties (dist at cohort-1)
    cohort = {}
    for r in rows:
        if r.get('treated_unit') == '1' and r.get('cohort') not in (None, '', '0'):
            cohort[r['fips']] = int(r['cohort'])
    with open(f'{od}/pretreatment_distance_by_treated.csv', 'w', newline='') as f:
        w_ = csv.DictWriter(f, fieldnames=[
            'fips', 'county', 'cohort', 'pre_year',
            'dist_instate_preyr', 'dist_aug_preyr', 'nearest_wet_is_oos_preyr',
            'nearest_wet_fips_preyr'])
        w_.writeheader()
        nm = {r['fips']: r['county'] for r in rows}
        for fp, ch in sorted(cohort.items(), key=lambda x: (x[1], x[0])):
            pre = ch - 1
            a = aug.get((fp, pre))
            if a:
                w_.writerow({'fips': fp, 'county': nm[fp], 'cohort': ch, 'pre_year': pre,
                             'dist_instate_preyr': a['dist_nearest_wet_instate'],
                             'dist_aug_preyr': a['dist_nearest_wet_aug'],
                             'nearest_wet_is_oos_preyr': a['nearest_wet_is_oos'],
                             'nearest_wet_fips_preyr': a['nearest_wet_fips_aug']})

    # ---- console summary ----
    print(f"OOS ring counties (adjacent to AR): {len(oos_ring)}")
    byst = defaultdict(int)
    for j in oos_ring: byst[states[j]] += 1
    print("  by state:", dict(sorted(byst.items())))
    naccess = sum(1 for jr in oos_rows if jr['accessible_from_ar'])
    print(f"  accessible (land or whitelisted crossing): {naccess}")
    print(f"\nAdjacency QC vs panel n_wet_neighbors: {match}/{tot} = {qc_rate:.1%} match")
    if mism[:8]:
        print("  sample mismatches (fips,county,year,panel,mine):")
        for m in mism[:8]: print("   ", m)
    print(f"\nWrote 4 files to {od}/")

if __name__ == '__main__':
    main()
