#!/usr/bin/env /usr/local/bin/python3
"""
build_panel_v2_r15port.py -- T3 of the R15 port (ANALYSIS_LOG #25).

Builds the v2 canonical panels by SURGICAL column replacement on the archived
files (never a pandas round-trip, so every untouched cell stays byte-identical
by construction -- gates G5/G6 then verify it anyway):

  arkansas_panel_annual_border_vmt_nonalc_rucc.csv         -> *_rucc_v2.csv
  arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv  -> *_rucc_origin_v2.csv

REPLACED (everything else untouched):
  countywide_wet             full Section-2 wet-SOURCE timeline (D2 FULL):
                             Boone/Clark flip 2010, Madison 2012,
                             Sebastian/Logan/Woodruff wet all-window.
                             cohort / first_treated_year / treated_unit remain
                             PLACE-2-owned (Stata patch) -- NOT touched here.
  n_wet_neighbors            corrected in-state count (D3: corrected IN PLACE
  share_wet_neighbors        under the same names; no consumer should ever
  any_wet_neighbor           prefer the defective series)
  n_wet_neighbors_instate_chk  == n_wet_neighbors under the single timeline
  n_wet_neighbors_aug        corrected in-state + (unchanged) OOS count
  any_wet_neighbor_aug
  share_wet_neighbors_aug
  dist_* / nearest_wet_fips_aug   ONLY on the cells where the R15-port rebuild
                             (out_r15port/distance_neighbor_augment_v2.csv,
                             Logan excluded as a distance source per D1)
                             numerically differs from the certified augment --
                             the Boone/Clark decontamination cells (D4:
                             expected exactly 5 counties x 2008-09, 44 cells).

Inputs: out_r15port/distance_neighbor_augment_v2.csv (corrected, from the
PLACE-1-PATCH-v2 border build), distance_neighbor_augment_v2.csv (certified
archive, for the changed-cell set), wet_source_timeline.py.
Run gate_r15_port.py (G1-G7) after this; do not consume the v2 files before
the gates pass.
"""
import csv
import sys
from wet_source_timeline import build_timelines, cohort_and_cw_from_rows

AUG_NEW = 'out_r15port/distance_neighbor_augment_v2.csv'
AUG_OLD = 'distance_neighbor_augment_v2.csv'
PANELS = [
    ('arkansas_panel_annual_border_vmt_nonalc_rucc.csv',
     'arkansas_panel_annual_border_vmt_nonalc_rucc_v2.csv'),
    ('arkansas_panel_annual_border_vmt_nonalc_rucc_origin.csv',
     'arkansas_panel_annual_border_vmt_nonalc_rucc_origin_v2.csv'),
]
DISTCOLS = ['dist_popcen_instate', 'dist_popcen_aug', 'dist_border_instate',
            'dist_border_aug', 'nearest_wet_fips_aug', 'nearest_wet_is_oos']


def load_aug(path):
    return {(r['fips'].zfill(5), int(r['year'])): r
            for r in csv.DictReader(open(path))}


def num_differs(a, b):
    try:
        return abs(float(a) - float(b)) > 1e-9
    except ValueError:
        # fips-like / empty strings: compare as zero-stripped ints where possible
        return (a or '').lstrip('0') != (b or '').lstrip('0')


def main():
    aug_new = load_aug(AUG_NEW)
    aug_old = load_aug(AUG_OLD)

    # -- the D4 changed-cell set (corrected augment vs certified augment)
    changed = {}
    for k in aug_new:
        cols = [c for c in DISTCOLS if num_differs(aug_new[k][c], aug_old[k][c])]
        if cols:
            changed[k] = cols
    ctys = sorted({f for f, _ in changed})
    yrs = sorted({y for _, y in changed})
    ncells = sum(len(v) for v in changed.values())
    print(f'D4 dist decontamination: {ncells} cells, counties {ctys}, years {yrs}')
    assert ctys == ['05015', '05051', '05099', '05101', '05109'], \
        'unexpected counties in the dist decontamination set'
    assert yrs == [2008, 2009], 'dist changes outside 2008-09 -- STOP'
    assert ncells == 44, f'expected 44 changed dist cells, got {ncells}'

    for src, dst in PANELS:
        rows = list(csv.DictReader(open(src)))
        # timeline from the ARCHIVED coding (module is vintage-agnostic)
        cohort_csv, cw, years = cohort_and_cw_from_rows(rows)
        wet_nbr, _, info = build_timelines(cohort_csv, cw, years)

        with open(src) as f:
            rdr = csv.reader(f)
            hdr = next(rdr)
            idx = {c: i for i, c in enumerate(hdr)}
            out_rows = []
            for row in rdr:
                f5 = row[idx['fips']].zfill(5)
                y = int(row[idx['year']])
                k = (f5, y)
                a = aug_new[k]
                n_in = int(a['n_wet_neighbors_instate_chk'])
                den = int(row[idx['n_neighbors']])

                row[idx['countywide_wet']] = str(wet_nbr(f5, y))
                row[idx['n_wet_neighbors']] = str(n_in)
                row[idx['share_wet_neighbors']] = repr(n_in / den)
                row[idx['any_wet_neighbor']] = str(int(n_in > 0))
                row[idx['n_wet_neighbors_instate_chk']] = str(n_in)
                row[idx['n_wet_neighbors_aug']] = a['n_wet_neighbors_aug']
                row[idx['any_wet_neighbor_aug']] = a['any_wet_neighbor_aug']
                row[idx['share_wet_neighbors_aug']] = a['share_wet_neighbors_aug']
                # n_oos_wet_neighbors must be timeline-independent (G4 re-checks)
                assert int(row[idx['n_oos_wet_neighbors']]) == \
                    int(a['n_oos_wet_neighbors']), (k, 'n_oos moved')

                for c in changed.get(k, ()):
                    v = a[c]
                    if c == 'nearest_wet_fips_aug':
                        v = str(int(v))       # panel style: no leading zero
                    row[idx[c]] = v
                out_rows.append(row)

        with open(dst, 'w', newline='') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(hdr)
            w.writerows(out_rows)
        print(f'wrote {dst}: {len(out_rows)} rows x {len(hdr)} cols '
              f'(always-wet derived: {info["n_always_wet"]}, '
              f'sources 2008: {info.get("n_sources_2008")})')


if __name__ == '__main__':
    sys.exit(main())
