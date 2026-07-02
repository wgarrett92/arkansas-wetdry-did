"""
build_border_augment_v2.py   (supersedes v1)
PATCHED: PLACE 1 PATCH v2 (R15 port, 2026-07-01) -- the wet-SOURCE timeline
now comes from wet_source_timeline.py (ANALYSIS_LOG #25); Boone/Clark are dry
until 2010, Madison until 2012, Sebastian/Logan/Woodruff wet all-window
(Logan a NEIGHBOR source always, a DISTANCE source only via
--logan-distance-source 1 -- design decision D1).
============================================
Rebuilds the border augmentation on POPULATION-WEIGHTED centroids
(2020 Census Centers of Population), with two distance metrics and the
verified TX/LA border coding.

DISTANCE METRICS (origin = dry county's population center):
  popcen : pop-centroid -> nearest wet county's POP-CENTROID  (the literal
           "population-weighted centroid" swap of the old metric)
  border : pop-centroid -> nearest POINT ON the nearest wet county's border
           (preferred: residents drive to the edge of wet territory, where
           county-line stores cluster; robust to large-county geometry)
Both are reported in-state-only and augmented-with-OOS, so the effect of
adding out-of-state access is visible, and the metric choice is visible.

VERIFIED BORDER CODING (off-premise / any-alcohol margin):
  MO (29), OK (40)  wet entire window (HIGH)
  LA (22)           wet via municipalities, parishes partly dry by ward
                    (PARTIAL); coded wet from 2008, flagged for sub-parish check
  TX (48) Bowie/Cass off-premise beer/wine only, and only FROM 2013 (dry before;
                    Texarkana still has no packaged liquor). wet_from=2013 (VERIFY).
                    NB: AR (Texarkana/Miller) historically supplied TX, not vice
                    versa -- Little River's real adjacent access is in-state Miller.
  MS (28), TN (47)  river border; accessible ONLY via whitelisted bridges:
                    Crittenden 05035->Shelby TN 47157; Phillips 05107->Coahoma
                    MS 28027; Chicot 05017->Washington MS 28151. wet from 2008.

INPUTS : panel csv, counties.geojson, pop_centroids.csv [fips,lon,lat,pop,name]
OUTPUTS: oos_wet_reference_v2.csv, distance_neighbor_augment_v2.csv,
         arkansas_did_panel_with_border_v2.csv, pretreatment_distance_by_treated_v2.csv
"""
import json, math, csv, argparse, os
from collections import defaultdict
from shapely.geometry import shape, Point
from shapely.ops import nearest_points
from shapely.strtree import STRtree

R_MILES = 3958.8
ADJ_BUFFER_DEG = 0.0005
LAND_STATES  = {'29', '40', '48', '22'}
RIVER_STATES = {'28', '47'}
BORDER_STATES = LAND_STATES | RIVER_STATES
WINDOW_START = 2008
CROSSINGS = {'05035': {'47157'}, '05107': {'28027'}, '05017': {'28151'}}

def oos_coding(fips, state):
    """return (wet_from_year or None, confidence)."""
    if state in ('29', '40'):           return WINDOW_START, 'high'
    if state == '22':                   return WINDOW_START, 'partial'   # LA: wet in towns
    if state == '48':                   return 2013,         'verify'    # TX: beer/wine from 2013
    if fips in ('47157','28027','28151'): return WINDOW_START, 'med'     # MS/TN crossings
    return None, 'na'

def accessible(ar_fips, oos_fips, oos_state):
    if oos_state in LAND_STATES: return True
    return oos_fips in CROSSINGS.get(ar_fips, set())

def haversine(lat1, lon1, lat2, lon2):
    p = math.pi/180.0
    a = (math.sin((lat2-lat1)*p/2)**2
         + math.cos(lat1*p)*math.cos(lat2*p)*math.sin((lon2-lon1)*p/2)**2)
    return 2*R_MILES*math.asin(math.sqrt(a))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--panel',   default='/mnt/project/arkansas_did_panel.csv')
    ap.add_argument('--geojson', default='/home/claude/counties.geojson')
    ap.add_argument('--popcentroids', default='/home/claude/pop_centroids.csv')
    ap.add_argument('--outdir',  default='/home/claude/out')
    ap.add_argument('--logan-distance-source', type=int, default=0, choices=(0, 1),
                    help='D1 (ANALYSIS_LOG #25): treat Logan 05083 as a wet '
                         'SOURCE for the DISTANCE metrics (its wetness is '
                         'sub-county Booneville, beer & native wine only). '
                         'Default 0 = excluded, preserving prior distance '
                         'behavior; neighbor counts include Logan either way.')
    args = ap.parse_args(); os.makedirs(args.outdir, exist_ok=True)

    # geometries (for borders + adjacency) and geometric centroids (fallback)
    gj = json.load(open(args.geojson))
    geoms, names, states = {}, {}, {}
    for ft in gj['features']:
        f = ft.get('id');  st = f[:2] if f else None
        if st == '05' or st in BORDER_STATES:
            geoms[f] = shape(ft['geometry']); names[f] = ft['properties'].get('NAME',''); states[f] = st

    # population-weighted centroids (origins + targets)
    popcen = {}
    for r in csv.DictReader(open(args.popcentroids)):
        popcen[r['fips'].zfill(5)] = (float(r['lat']), float(r['lon']))

    # panel + AR wet-by-year
    rows = list(csv.DictReader(open(args.panel)))
    for r in rows:
        r['fips'] = r['fips'].zfill(5); r['year'] = int(r['year']); r['countywide_wet'] = int(r['countywide_wet'])
    # ===== PLACE 1 PATCH v2 (R15 port) -- authoritative wet-SOURCE timeline =====
    # Supersedes the two ad hoc recodes (Madison, Sebastian): the FULL Section-2
    # timeline from wet_source_timeline.py now owns the wet-source geography
    # (subsumes Madison g2012 + Sebastian all-window, and adds the R15 fix --
    # Boone/Clark dry until their 2010 cohort -- plus Logan/Woodruff as partial-
    # wet-all-window sources). Two timelines (design decision D1, ANALYSIS_LOG
    # #25): wet_nbr feeds the NEIGHBOR counts (Logan wet, matching
    # rebuild_neighbor_counts.py); wet_dist feeds the DISTANCE metrics (Logan
    # excluded unless --logan-distance-source 1). Treatment coding for
    # ESTIMATION remains PLACE 2 (Stata patch); countywide_wet written to the
    # outputs is the at-rest wet-SOURCE timeline (D2 FULL scope).
    from wet_source_timeline import (build_timelines, hard_asserts,
                                     cohort_and_cw_from_rows, TREATED_COHORTS)
    cohort_csv, cw0, yrs0 = cohort_and_cw_from_rows(rows)
    wet_nbr, wet_dist, tl_info = build_timelines(
        cohort_csv, cw0, yrs0,
        logan_distance_source=bool(args.logan_distance_source))
    for r in rows:
        r['countywide_wet'] = wet_nbr(r['fips'], r['year'])
    # hard asserts (T1): fail loudly if the recode did not land
    hard_asserts(wet_nbr, yrs0, neighbors_variant=True)
    hard_asserts(wet_dist, yrs0,
                 neighbors_variant=bool(args.logan_distance_source))
    for r in rows:
        f, y, w = r['fips'], r['year'], r['countywide_wet']
        if f in ('05009', '05019'):                       # Boone, Clark: g2010
            assert w == (1 if y >= 2010 else 0), (f, y, w)
        elif f == '05087':                                # Madison: g2012
            assert w == (1 if y >= 2012 else 0), (f, y, w)
        elif f in ('05131', '05083', '05147'):            # Seb/Logan/Woodruff
            assert w == 1, (f, y, w)
    print(f"PLACE 1 PATCH v2 (R15 port): sources 2008 = "
          f"{sum(wet_nbr(f, 2008) for f in cohort_csv)} (expect 33); "
          f"logan_distance_source={bool(args.logan_distance_source)}")
    # ===========================================================================
    years = sorted({r['year'] for r in rows}); ar_fips = sorted({r['fips'] for r in rows})
    wet = {(r['fips'], r['year']): r['countywide_wet'] for r in rows}
    nm = {r['fips']: r['county'] for r in rows}

    # adjacency (validated in v1 at 100% vs panel)
    fl = list(geoms); buf = {f: geoms[f].buffer(ADJ_BUFFER_DEG) for f in fl}
    tree = STRtree([geoms[f] for f in fl]); adj = defaultdict(set)
    for f in fl:
        if f[:2] != '05': continue
        for idx in tree.query(buf[f]):
            g = fl[idx]
            if g != f and buf[f].intersects(geoms[g]): adj[f].add(g)

    oos_ring = sorted({g for f in ar_fips for g in adj[f] if g[:2] in BORDER_STATES})
    oos_wf, oos_conf = {}, {}
    for j in oos_ring:
        oos_wf[j], oos_conf[j] = oos_coding(j, states[j])

    def oos_wet_in(j, yr):
        return oos_wf[j] is not None and yr >= oos_wf[j]

    # candidate wet counties for AR county c in year yr -> list of fips
    # (DISTANCE timeline: wet_dist -- Logan per --logan-distance-source, D1)
    def wet_candidates(c, yr, include_oos):
        out = [f for f in ar_fips if f != c and wet_dist(f, yr) == 1]
        if include_oos:
            out += [j for j in oos_ring if accessible(c, j, states[j]) and oos_wet_in(j, yr)]
        return out

    def border_dist(c, target_fips):
        la, lo = popcen[c]; pt = Point(lo, la)
        _, q = nearest_points(pt, geoms[target_fips])
        return haversine(la, lo, q.y, q.x)

    aug = {}
    for c in ar_fips:
        clat, clon = popcen[c]
        instate_nbrs = [f for f in adj[c] if f[:2] == '05']
        oos_nbrs_all = [j for j in adj[c] if j[:2] in BORDER_STATES]
        for yr in years:
            rec = {}
            for tag, inc in (('instate', False), ('aug', True)):
                cand = wet_candidates(c, yr, inc)
                if not cand:
                    rec[f'dist_popcen_{tag}'] = float('nan')
                    rec[f'dist_border_{tag}'] = float('nan')
                    if tag == 'aug': rec['nearest_wet_fips_aug'] = ''; rec['nearest_wet_is_oos'] = 0
                    continue
                # pop-centroid -> pop-centroid
                dp = [(haversine(clat, clon, *popcen[t]), t) for t in cand]
                dp.sort(); rec[f'dist_popcen_{tag}'] = round(dp[0][0], 3)
                # pop-centroid -> nearest border: refine over 8 nearest-by-centroid
                near = [t for _, t in dp[:8]]
                db = sorted((border_dist(c, t), t) for t in near)
                rec[f'dist_border_{tag}'] = round(db[0][0], 3)
                if tag == 'aug':
                    bf = db[0][1]
                    rec['nearest_wet_fips_aug'] = bf
                    rec['nearest_wet_is_oos'] = int(bf[:2] != '05')
            # neighbor wet counts (now respecting OOS time-variation)
            n_in = sum(wet.get((f, yr), 0) == 1 for f in instate_nbrs)
            n_oos = sum(accessible(c, j, states[j]) and oos_wet_in(j, yr) for j in oos_nbrs_all)
            tot = len(instate_nbrs) + len(oos_nbrs_all)
            rec.update({'n_wet_neighbors_instate_chk': n_in, 'n_oos_wet_neighbors': n_oos,
                        'n_wet_neighbors_aug': n_in + n_oos,
                        'any_wet_neighbor_aug': int(n_in + n_oos > 0),
                        'share_wet_neighbors_aug': round((n_in+n_oos)/tot, 4) if tot else 0.0})
            aug[(c, yr)] = rec

    # ---- outputs ----
    od = args.outdir
    st_ab = {'22':'LA','28':'MS','29':'MO','40':'OK','47':'TN','48':'TX'}
    with open(f'{od}/oos_wet_reference_v2.csv','w',newline='') as f:
        w = csv.writer(f); w.writerow(['oos_fips','state','name','border_type','wet_from_year','confidence','adjacent_ar','accessible_from_ar'])
        for j in oos_ring:
            arn = sorted(x for x in ar_fips if j in adj[x])
            acc = sorted(x for x in arn if accessible(x, j, states[j]))
            w.writerow([j, st_ab[states[j]], names[j], 'land' if states[j] in LAND_STATES else 'river',
                        oos_wf[j] if oos_wf[j] else 'NA', oos_conf[j], ';'.join(arn), ';'.join(acc)])

    newcols = ['dist_popcen_instate','dist_popcen_aug','dist_border_instate','dist_border_aug',
               'nearest_wet_fips_aug','nearest_wet_is_oos','n_wet_neighbors_instate_chk',
               'n_oos_wet_neighbors','n_wet_neighbors_aug','any_wet_neighbor_aug','share_wet_neighbors_aug']
    with open(f'{od}/distance_neighbor_augment_v2.csv','w',newline='') as f:
        w = csv.DictWriter(f, fieldnames=['fips','year']+newcols); w.writeheader()
        for c in ar_fips:
            for yr in years: w.writerow({'fips':c,'year':yr,**aug[(c,yr)]})

    pf = list(rows[0].keys())
    with open(f'{od}/arkansas_did_panel_with_border_v2.csv','w',newline='') as f:
        w = csv.DictWriter(f, fieldnames=pf+newcols); w.writeheader()
        for r in rows: w.writerow({**{k:r[k] for k in pf}, **aug[(r['fips'],r['year'])]})

    # PLACE 1 PATCH v2 (R15 port): pretreatment rows for ALL 13 authoritative
    # treated counties (replaces the treated_unit scan + Madison override).
    cohort = dict(TREATED_COHORTS)
    with open(f'{od}/pretreatment_distance_by_treated_v2.csv','w',newline='') as f:
        w = csv.writer(f); w.writerow(['fips','county','cohort','pre_year','popcen_instate','popcen_aug',
                                       'border_instate','border_aug','nearest_wet_is_oos','nearest_wet'])
        for fp, ch in sorted(cohort.items(), key=lambda x:(x[1],x[0])):
            a = aug.get((fp, ch-1));  bf = a['nearest_wet_fips_aug']
            where = (names[bf]+','+st_ab[states[bf]]) if bf and bf[:2]!='05' else (nm.get(bf,bf)+',AR' if bf else '')
            w.writerow([fp, nm[fp], ch, ch-1, a['dist_popcen_instate'], a['dist_popcen_aug'],
                        a['dist_border_instate'], a['dist_border_aug'], a['nearest_wet_is_oos'], where])

    # QC vs panel n_wet_neighbors (in-state). NB under the R15-port timeline a
    # LOW match count vs an OLD-coded panel is EXPECTED (the old plain column
    # is defective: Madison/Boone/Clark wet-all-window, Logan/Sebastian dry);
    # against a v2 panel this should be 1200/1200.
    m = t = 0
    for r in rows:
        if r.get('n_wet_neighbors','') != '':
            t += 1; m += int(r['n_wet_neighbors']) == aug[(r['fips'],r['year'])]['n_wet_neighbors_instate_chk']
    print(f"OOS ring: {len(oos_ring)}  | adjacency QC vs panel plain n_wet_neighbors: {m}/{t}"
          f"  (mismatches EXPECTED vs old-coded panels -- see PLACE 1 PATCH v2)")
    print(f"pop-centroid coverage: AR {sum(1 for f in ar_fips if f in popcen)}/75")
    print(f"Wrote v2 outputs to {od}/")

if __name__ == '__main__':
    main()
