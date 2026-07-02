#!/usr/bin/env /usr/local/bin/python3
"""
gate_r15_port.py -- validation gates G1-G7 for the R15 port (ANALYSIS_LOG #25).

Mirrors the #24 gate structure that certified rebuild_neighbor_counts.py, now
run against the v2 panels produced by build_panel_v2_r15port.py. G5 is the
RESTATED version signed off 2026-07-01 (D4): dist_* byte-identical EXCEPT an
exactly-enumerated 44-cell Boone/Clark decontamination (5 counties x 2008-09,
distances weakly increase, nearest reassignments away from Boone/Clark).

Writes R15_PORT_GATELOG.txt. Exit code 0 iff every gate passes.
"""
import csv, json, sys, datetime
from collections import defaultdict
from shapely.geometry import shape
from shapely.strtree import STRtree
from wet_source_timeline import (build_timelines, hard_asserts,
                                 cohort_and_cw_from_rows, TREATED_COHORTS,
                                 PARTIAL_WET, MADISON, LOGAN)

ADJ_BUFFER_DEG = 0.0005
BORDER_STATES = {'29', '40', '48', '22', '28', '47'}
GEOJSON = 'counties.geojson'
ARCH_RUCC = 'arkansas_panel_annual_border_vmt_nonalc_rucc.csv'
V2_RUCC   = 'arkansas_panel_annual_border_vmt_nonalc_rucc_v2.csv'
ARCH_ORIG = 'arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv'
V2_ORIG   = 'arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv'
CORR      = 'neighbor_counts_corrected.csv'
AUG_OLD   = 'distance_neighbor_augment_v2.csv'
AUG_NEW   = 'out_r15port/distance_neighbor_augment_v2.csv'
PRE_OLD   = 'pretreatment_distance_by_treated_v2.csv'
PRE_NEW   = 'out_r15port/pretreatment_distance_by_treated_v2.csv'
OOS_OLD   = 'oos_wet_reference_v2.csv'
OOS_NEW   = 'out_r15port/oos_wet_reference_v2.csv'
GATELOG   = 'R15_PORT_GATELOG.txt'

NBR_REPLACED = ['countywide_wet', 'n_wet_neighbors', 'share_wet_neighbors',
                'any_wet_neighbor', 'n_wet_neighbors_instate_chk',
                'n_wet_neighbors_aug', 'any_wet_neighbor_aug',
                'share_wet_neighbors_aug']
DISTCOLS = ['dist_popcen_instate', 'dist_popcen_aug', 'dist_border_instate',
            'dist_border_aug', 'nearest_wet_fips_aug', 'nearest_wet_is_oos']
D4_COUNTIES = ['05015', '05051', '05099', '05101', '05109']
D4_YEARS = [2008, 2009]

log_lines = []
failures = []


def log(msg):
    print(msg)
    log_lines.append(msg)


def gate(name, ok, detail=''):
    tag = 'PASS' if ok else 'FAIL'
    log(f'[{tag}] {name}' + (f' -- {detail}' if detail else ''))
    if not ok:
        failures.append(name)


def load_rows(p):
    rows = list(csv.DictReader(open(p)))
    for r in rows:
        r['fips'] = r['fips'].zfill(5)
        r['year'] = int(r['year'])
    return rows


def keyed(rows):
    return {(r['fips'], r['year']): r for r in rows}


def main():
    log('=' * 78)
    log('R15 PORT GATE LOG  --  generated %s by gate_r15_port.py'
        % datetime.date.today().isoformat())
    log('Decisions (confirmed with Will 2026-07-01): D1 Logan EXCLUDED from the')
    log('distance-source set (empirically NOT a no-op: 332 dist/nearest cells');
    log('move when included, e.g. Franklin 10.352 -> 4.813 mi); D2 FULL Section-2')
    log('timeline written to countywide_wet at rest; D3 plain neighbor columns')
    log('corrected IN PLACE under the same names; D4 the 44 R15-contaminated')
    log('dist cells are corrected too (G5 restated below).')
    log('=' * 78)

    arch = load_rows(ARCH_RUCC); archk = keyed(arch)
    v2 = load_rows(V2_RUCC); v2k = keyed(v2)
    arch_o = load_rows(ARCH_ORIG)
    v2_o = load_rows(V2_ORIG)
    corr = keyed(load_rows(CORR))
    augN = keyed(load_rows(AUG_NEW))
    augO = keyed(load_rows(AUG_OLD))
    years = sorted({r['year'] for r in arch})
    ar_fips = sorted({r['fips'] for r in arch})
    name = {r['fips']: r['county'] for r in arch}

    cohort_csv, cw, _ = cohort_and_cw_from_rows(arch)
    wet_nbr, wet_dist, info = build_timelines(cohort_csv, cw, years)

    # ---- adjacency (same construction as PLACE 1 / rebuild_neighbor_counts) --
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
        for i in tree.query(buf[f]):
            g = fl[i]
            if g != f and buf[f].intersects(geoms[g]):
                adj[f].add(g)
    nbrs = {c: sorted(g for g in adj[c] if g[:2] == '05') for c in ar_fips}

    # ================= G1: STAGE A (logic identity) ==========================
    def wet_p1(f, yr):                    # PLACE-1 timeline (defective, by design)
        if f == MADISON:
            return 1 if yr >= 2012 else 0
        if f == '05131':
            return 1
        return cw[(f, yr)]

    bad = [(c, y) for c in ar_fips for y in years
           if sum(wet_p1(g, y) for g in nbrs[c])
           != int(archk[(c, y)]['n_wet_neighbors_instate_chk'])]
    gate('G1 STAGE A: adjacency x PLACE-1 timeline reproduces archived '
         'n_wet_neighbors_instate_chk', not bad,
         f'{1200 - len(bad)}/1200 cells' + (f'; first bad {bad[:3]}' if bad else ''))

    ncorr = {(c, y): sum(wet_nbr(g, y) for g in nbrs[c])
             for c in ar_fips for y in years}
    bad = [(c, y) for c in ar_fips for y in years
           if ncorr[(c, y)] != int(augN[(c, y)]['n_wet_neighbors_instate_chk'])]
    gate('G1b: gate-recomputed corrected counts == PLACE-1-PATCH-v2 border '
         'build output', not bad, f'{1200 - len(bad)}/1200')

    # ================= G2: DIFF DECOMPOSITION ================================
    bc = ('05009', '05019')
    undec = []
    for c in ar_fips:
        for y in years:
            d = ncorr[(c, y)] - int(archk[(c, y)]['n_wet_neighbors_instate_chk'])
            exp = (LOGAN in nbrs[c]) - (sum(b in nbrs[c] for b in bc)
                                        if y < 2010 else 0)
            if d != exp:
                undec.append((c, y, d, exp))
    gate('G2a: corrected-vs-_chk == {Boone/Clark nbrs pre-2010} + {Logan nbrs, '
         'constant} EXACTLY', not undec, f'{len(undec)} undecomposed')

    undec = []
    for c in ar_fips:
        for y in years:
            d = ncorr[(c, y)] - int(archk[(c, y)]['n_wet_neighbors'])
            exp = ((LOGAN in nbrs[c]) + ('05131' in nbrs[c])
                   - (sum(b in nbrs[c] for b in bc) if y < 2010 else 0)
                   - ((MADISON in nbrs[c]) if y < 2012 else 0))
            if d != exp:
                undec.append((c, y, d, exp))
    gate('G2b: corrected-vs-PLAIN additionally == {Madison nbrs pre-2012} + '
         '{Sebastian nbrs, constant}', not undec, f'{len(undec)} undecomposed')
    mad_inc = sorted(name[c] for c in ar_fips if MADISON in nbrs[c])
    log(f'     Madison AR-neighbor increment set: {mad_inc}')

    # ================= G3: STRUCTURE =========================================
    mono_ok = all(ncorr[(c, years[i])] <= ncorr[(c, years[i + 1])]
                  for c in ar_fips for i in range(len(years) - 1))
    gate('G3a: neighbor counts monotone non-decreasing within county', mono_ok)
    bc10 = all(ncorr[(c, 2010)] - ncorr[(c, 2009)] == sum(b in nbrs[c] for b in bc)
               for c in ar_fips if any(b in nbrs[c] for b in bc))
    gate('G3b: 2010 increments present for every Boone/Clark neighbor', bc10)
    mad12 = all(ncorr[(c, 2012)] > ncorr[(c, 2011)]
                for c in ar_fips if MADISON in nbrs[c])
    gate('G3c: 2012 increments present for every Madison neighbor', mad12)

    # ================= G4: IDENTITY vs certified artifact ====================
    for label, v2rows in (('rucc_v2', v2), ('origin_v2', v2_o)):
        bad = []
        for r in v2rows:
            k = (r['fips'], r['year'])
            c = corr[k]
            ok = (int(r['n_wet_neighbors']) == int(c['n_wet_corr'])
                  == int(r['n_wet_neighbors_instate_chk'])
                  and abs(round(float(r['share_wet_neighbors']), 4)
                          - float(c['share_wet_corr'])) < 5e-5
                  and int(r['n_wet_neighbors_aug']) == int(c['n_aug_corr'])
                  and abs(float(r['share_wet_neighbors_aug'])
                          - float(c['share_aug_corr'])) < 5e-5
                  and int(r['any_wet_neighbor']) == int(int(c['n_wet_corr']) > 0)
                  and int(r['any_wet_neighbor_aug']) == int(int(c['n_aug_corr']) > 0)
                  and int(r['n_oos_wet_neighbors'])
                  == int(archk[k]['n_oos_wet_neighbors']))
            if not ok:
                bad.append(k)
        gate(f'G4 ({label}): neighbor columns == neighbor_counts_corrected.csv '
             'on all cells; n_oos unchanged', not bad,
             f'{1200 - len(bad)}/1200' + (f'; first bad {bad[:3]}' if bad else ''))

    # ================= G5 (RESTATED, D4): DIST ==============================
    for label, arows, vrows in (('rucc_v2', arch, v2), ('origin_v2', arch_o, v2_o)):
        ak, vk = keyed(arows), keyed(vrows)
        diff = defaultdict(list)
        for k in ak:
            for c in DISTCOLS:
                if ak[k][c] != vk[k][c]:
                    diff[k].append(c)
        cells = sum(len(v) for v in diff.values())
        cty = sorted({f for f, _ in diff})
        yr = sorted({y for _, y in diff})
        ok = (cty == D4_COUNTIES and yr == D4_YEARS and cells == 44
              and all(c != 'nearest_wet_is_oos' for v in diff.values() for c in v))
        # corrected distances must weakly increase (sources were removed)
        incr = all(float(vk[k][c]) >= float(ak[k][c]) - 1e-9
                   for k, cols in diff.items() for c in cols
                   if not c.startswith('nearest'))
        gate(f'G5a ({label}): dist_*/nearest_* byte-identical EXCEPT exactly the '
             '44 D4 cells (5 counties x 2008-09), increases only',
             ok and incr,
             f'{cells} changed cells, counties {cty}, years {yr}')
        # nearest never points at Boone/Clark pre-2010 in the v2 panel
        bad = [k for k in vk if vk[k]['year'] < 2010
               and vk[k]['nearest_wet_fips_aug'].zfill(5) in ('05009', '05019')]
        gate(f'G5b ({label}): v2 nearest_wet_fips_aug never points at '
             'Boone/Clark pre-2010', not bad, f'{len(bad)} offending cells')

    same_pre = open(PRE_NEW).read() == open(PRE_OLD).read()
    gate('G5c: regenerated pretreatment_distance_by_treated_v2.csv byte-identical '
         'to certified (13 treated rows)', same_pre)
    same_oos = open(OOS_NEW).read() == open(OOS_OLD).read()
    gate('G5d: regenerated oos_wet_reference_v2.csv byte-identical to certified',
         same_oos)
    bad = [(k, c) for k in augN for c in DISTCOLS
           if (k[0], k[1]) not in {(f, y) for f in D4_COUNTIES for y in D4_YEARS}
           and augN[k][c] != augO[k][c]]
    gate('G5e: regenerated augment dist columns reproduce certified on every '
         'non-D4 cell', not bad, f'{len(bad)} unexpected diffs')

    # ================= G6: FREEZE EVERYTHING ELSE ============================
    for label, srcp, dstp in (('rucc_v2', ARCH_RUCC, V2_RUCC),
                              ('origin_v2', ARCH_ORIG, V2_ORIG)):
        with open(srcp) as fa, open(dstp) as fb:
            ra, rb = csv.reader(fa), csv.reader(fb)
            ha, hb = next(ra), next(rb)
            assert ha == hb, f'{label}: header changed'
            allowed = set(NBR_REPLACED) | set(DISTCOLS)
            iy = {c: i for i, c in enumerate(ha)}
            bad = []
            n = 0
            for a, b in zip(ra, rb):
                n += 1
                for i, c in enumerate(ha):
                    if a[i] != b[i] and c not in allowed:
                        bad.append((a[iy['fips']], a[iy['year']], c))
            gate(f'G6 ({label}): every non-replaced column byte-identical '
                 f'({n} rows, {len(ha)} cols)', not bad and n == 1200,
                 f'{len(bad)} stray diffs' + (f' e.g. {bad[:3]}' if bad else ''))

    # ================= G7: TIMELINE ASSERTS on the v2 panels =================
    for label, vrows, ncols in (('rucc_v2', v2, 77), ('origin_v2', v2_o, 84)):
        try:
            cc2, cw2, yr2 = cohort_and_cw_from_rows(vrows)
            wet2, _, info2 = build_timelines(cc2, cw2, yr2)   # idempotence
            hard_asserts(wet2, yr2, neighbors_variant=True)
            bad = [(r['fips'], r['year']) for r in vrows
                   if int(r['countywide_wet']) != wet_nbr(r['fips'], r['year'])]
            assert not bad, f'countywide_wet cells off-timeline: {bad[:5]}'
            # 10 remaining treated flip at their in-CSV cohorts
            for f, g in TREATED_COHORTS.items():
                if f == MADISON:
                    continue
                assert cc2[f] == g, (f, cc2[f], g)
            # always-dry all-zero
            for f in cc2:
                if (f not in TREATED_COHORTS and f not in PARTIAL_WET
                        and f not in info2['always_wet']):
                    assert all(cw2[(f, y)] == 0 for y in yr2), f
            assert len(vrows) == 1200 and len(vrows[0]) == ncols, \
                (len(vrows), len(vrows[0]))
            gate(f'G7 ({label}): Section-2 timeline asserts (Boone/Clark 2010, '
                 f'Madison 2012, trio all-window, always-dry zero, '
                 f'1200 x {ncols})', True)
        except AssertionError as e:
            gate(f'G7 ({label})', False, str(e))

    # ================= summary ==============================================
    log('=' * 78)
    if failures:
        log(f'RESULT: {len(failures)} GATE(S) FAILED: {failures}')
    else:
        log('RESULT: ALL GATES PASS (G1, G1b, G2a, G2b, G3a-c, G4 x2, G5a-e, '
            'G6 x2, G7 x2)')
        log('The v2 panels are certified: '
            f'{V2_RUCC} + {V2_ORIG}')
    log('=' * 78)
    with open(GATELOG, 'w') as f:
        f.write('\n'.join(log_lines) + '\n')
    print(f'gate log -> {GATELOG}')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
