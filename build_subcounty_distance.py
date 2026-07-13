# =====================================================================
# build_subcounty_distance.py
# ---------------------------------------------------------------------
# Sub-county-resolution distance-to-nearest-wet for treated counties,
# built from the Arkansas ABC wet/dry GIS layer
# (ALCOHOLIC_BEVERAGE_WET_DRY_AREAS, FeatureServer 60, pub 2025-02).
#
# WHY THIS EXISTS
#   build_border_augment_v2.py computes dist_border_aug as pop-centroid ->
#   nearest WET COUNTY's border. But 42 AR counties contain BOTH wet and
#   dry sub-areas; the actual off-premise retail sits in specific wet
#   POLYGONS, not uniformly across a "wet" county. This script recomputes
#   the in-state border distance against the wet POLYGONS, producing
#   dist_border_subcty_instate as a clean ROBUSTNESS LAYER that sits beside
#   (does not replace) dist_border_instate / dist_border_aug.
#
# SCOPE / WHAT THIS DOES NOT DO  (read before trusting the numbers)
#   * IN-STATE ONLY. The shapefile is Arkansas-only, so this refines the
#     in-state distance. To get an augmented value, take the min with the
#     OOS distance your existing pipeline already computes (see STEP 5 note).
#   * STATIC 2025 SNAPSHOT. The layer has no usable transition timing
#     (munidate is populated on 17/260 rows, ~all 2024-10-23). Time-
#     awareness is therefore handled at the COUNTY level: a county's wet
#     polygons count as a source only if that county was wet as of the
#     treated county's pre-period (always-wet, or an earlier cohort, or
#     Sebastian). The SUB-COUNTY refinement is purely about WHERE within a
#     valid source county the wet area sits. Using 2025 sub-county geography
#     to proxy in-window geography is an assumption -- safe for stable
#     always-dry/parks areas, weaker near cities that flipped mid-window.
#     State this in the robustness note.
#
# OUTPUTS
#   dist_subcounty_by_treated.csv   one row per treated county:
#       fips, county, cohort, dist_border_subcty_instate (mi),
#       nearest_wet_source_fips, n_source_counties
#   wet_area_share_by_county.csv    one row per county:
#       fips, county, wet_area_share (0-1, by polygon area)
#
# DEPENDENCIES: pyshp, shapely>=2, pyproj
# =====================================================================

import csv
import shapefile                      # pyshp
from shapely.geometry import shape, Point
from shapely.ops import unary_union
from pyproj import Transformer

# ── CONFIG ───────────────────────────────────────────────────────────
SHP_PATH   = "ALCOHOLIC_BEVERAGE_WET_DRY_AREAS.shp"   # ABC wet/dry layer
POPCEN_CSV = "pop_centroids.csv"                       # your pop-weighted centroids
TRANS_CSV  = "transition_summary.csv"                  # cohort source of truth
OUT_TREATED = "dist_subcounty_by_treated.csv"
OUT_SHARE   = "wet_area_share_by_county.csv"
OUT_MANIFEST = "offpremise_source_manifest.csv"

SHP_EPSG   = 26915     # NAD83 / UTM 15N  (matches the .prj; same as ARDOT)
CEN_EPSG   = 4269      # NAD83 geographic (Census Centers of Population)
M_PER_MILE = 1609.344

# Source margin. False (default) = ANY off-premise retail (beer/wine in
# stores counts) -- the project's treatment margin. True = packaged-LIQUOR
# access only, excluding beer/wine-restricted areas (Logan, Woodruff, and
# the 'No Liquor' counties) -> a robustness "liquor distance".
LIQUOR_ONLY = False

# Treated cohort overrides reflecting the CURRENT (post-2026-06 recode)
# project state. transition_summary.csv predates the Madison recode, so we
# inject Madison g2012 here; everything else is read from the file.
COHORT_OVERRIDE = {
    "05087": 2012,     # Madison -> g2012 (AR SoS, Nov 6 2012)
}

# Counties whose WET polygons always count as an off-premise SOURCE,
# regardless of countywide-vote coding. Sebastian/Fort Smith is wet
# off-premise for the whole window (runbook: keep as a source even if
# dropped as an estimation unit).
ALWAYS_SOURCE_FIPS = {"05131"}        # Sebastian / Fort Smith

# AR county name -> 5-digit FIPS (matches the shapefile 'county' field).
NAME2FIPS = {
 "Arkansas":"05001","Ashley":"05003","Baxter":"05005","Benton":"05007",
 "Boone":"05009","Bradley":"05011","Calhoun":"05013","Carroll":"05015",
 "Chicot":"05017","Clark":"05019","Clay":"05021","Cleburne":"05023",
 "Cleveland":"05025","Columbia":"05027","Conway":"05029","Craighead":"05031",
 "Crawford":"05033","Crittenden":"05035","Cross":"05037","Dallas":"05039",
 "Desha":"05041","Drew":"05043","Faulkner":"05045","Franklin":"05047",
 "Fulton":"05049","Garland":"05051","Grant":"05053","Greene":"05055",
 "Hempstead":"05057","Hot Spring":"05059","Howard":"05061","Independence":"05063",
 "Izard":"05065","Jackson":"05067","Jefferson":"05069","Johnson":"05071",
 "Lafayette":"05073","Lawrence":"05075","Lee":"05077","Lincoln":"05079",
 "Little River":"05081","Logan":"05083","Lonoke":"05085","Madison":"05087",
 "Marion":"05089","Miller":"05091","Mississippi":"05093","Monroe":"05095",
 "Montgomery":"05097","Nevada":"05099","Newton":"05101","Ouachita":"05103",
 "Perry":"05105","Phillips":"05107","Pike":"05109","Poinsett":"05111",
 "Polk":"05113","Pope":"05115","Prairie":"05117","Pulaski":"05119",
 "Randolph":"05121","St. Francis":"05123","Saline":"05125","Scott":"05127",
 "Searcy":"05129","Sebastian":"05131","Sevier":"05133","Sharp":"05135",
 "Stone":"05137","Union":"05139","Van Buren":"05141","Washington":"05143",
 "White":"05145","Woodruff":"05147","Yell":"05149",
}

# ── 1. LOAD SHAPEFILE: per-county OFF-PREMISE-wet / all geometries ────
# CRITICAL FILTER: a polygon counts as an OFF-PREMISE RETAIL wet source
# only if it is a jurisdiction (county/city/township) that went wet --
# NOT a state park. Every park is wet by statute (Act 655, on-premise,
# NO takeaway retail) and is reliably tagged 'Per ACT 655 AR Code 3-9-103'.
# Counting parks as sources falsely makes dry controls (e.g. Crawford,
# whose only wet area is Lake Fort Smith State Park) look like off-premise
# access points and understates distance. We drop them by the notes tag.
#
# Product-restricted wet areas ('Beer Only', 'No Liquor', 'Beer and Native
# Wine Only') ARE off-premise retail (beer/wine in stores) and are KEPT --
# consistent with the project keeping Logan/Woodruff wet (partial_wet flag).
def _is_park(notes, name):
    n = (notes or "").lower(); nm = (name or "").lower()
    return ("655" in n) or ("3-9-103" in n) or nm.endswith("state park") \
           or nm.endswith("state museum") or nm.endswith("stadium state park")

def _is_beerwine_only(notes):
    n = (notes or "").lower()
    return ("no liquor" in n) or ("beer only" in n) or ("beer and native wine" in n)

def load_polygons(path):
    sf = shapefile.Reader(path)
    flds = [f[0] for f in sf.fields[1:]]
    ci, ti, ni, nmi = (flds.index("county"), flds.index("type"),
                       flds.index("notes"), flds.index("name"))
    wet_any, wet_liq, all_by, dropped, manifest = {}, {}, {}, [], []
    for sr in sf.shapeRecords():
        rec = sr.record
        fips = NAME2FIPS.get(rec[ci])
        if fips is None:
            raise KeyError(f"County name not in crosswalk: {rec[ci]!r}")
        geom = shape(sr.shape.__geo_interface__).buffer(0)   # fix self-intersections
        all_by.setdefault(fips, []).append(geom)
        if str(rec[ti]).strip().lower() != "wet":
            continue
        if _is_park(rec[ni], rec[nmi]):
            dropped.append((fips, rec[nmi]))                 # park -> not a source
            continue
        beerwine = _is_beerwine_only(rec[ni])
        wet_any.setdefault(fips, []).append(geom)            # off-premise any
        if not beerwine:
            wet_liq.setdefault(fips, []).append(geom)        # packaged liquor
        manifest.append(dict(fips=fips, county=_name(fips), name=rec[nmi],
                             notes=(rec[ni] or "").strip(),
                             beerwine_only=int(beerwine)))
    dissolve = lambda d: {f: unary_union(g) for f, g in d.items()}
    return dissolve(wet_any), dissolve(wet_liq), dissolve(all_by), dropped, manifest

# ── 2. COHORTS: read transition_summary, apply overrides ─────────────
def load_cohorts(path):
    cohort = {}     # fips -> cohort year (treated only)
    with open(path, newline="") as fh:
        for row in csv.DictReader(fh):
            fips = row["fips"].zfill(5)
            cohort[fips] = int(row["event_year"])
    for fips, yr in COHORT_OVERRIDE.items():
        cohort[fips] = yr
    return cohort

# ── 3. ALWAYS-WET SOURCE SET ─────────────────────────────────────────
# Any county whose wet polygons should count as a source for the WHOLE
# window: it has a wet sub-area in the layer, is NOT a treated cohort,
# OR is force-listed in ALWAYS_SOURCE_FIPS (Sebastian).
def always_wet_sources(wet_geom, cohort):
    src = set(ALWAYS_SOURCE_FIPS)
    for fips in wet_geom:                      # has a wet polygon in 2025
        if fips not in cohort:                 # and never transitioned in-window
            src.add(fips)
    return src

# ── 4. CENTROIDS: load pop-weighted centroids, reproject to UTM 15N ──
def load_centroids(path):
    """Return {fips: shapely Point in EPSG:26915}.
    Expects columns: a FIPS column and lat/lon columns. Adapts to common
    header spellings; edit COL_* below if your file differs."""
    COL_FIPS = ("fips", "FIPS", "geoid", "GEOID")
    COL_LAT  = ("lat", "latitude", "LATITUDE", "pclat10", "LATITUDE_pop")
    COL_LON  = ("lon", "lng", "longitude", "LONGITUDE", "pclon10", "LONGITUDE_pop")
    tf = Transformer.from_crs(CEN_EPSG, SHP_EPSG, always_xy=True)
    pts = {}
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh)
        hdr = rdr.fieldnames
        def pick(cands):
            for c in cands:
                if c in hdr: return c
            return None
        fcol, latcol, loncol = pick(COL_FIPS), pick(COL_LAT), pick(COL_LON)
        if not (fcol and latcol and loncol):
            raise KeyError(f"pop_centroids.csv: could not find fips/lat/lon among {hdr}. "
                           f"Edit COL_FIPS/COL_LAT/COL_LON in load_centroids().")
        for row in rdr:
            fips = str(row[fcol]).strip().zfill(5)
            if not fips.startswith("05"):        # AR counties only
                continue
            x, y = tf.transform(float(row[loncol]), float(row[latcol]))
            pts[fips] = Point(x, y)
    return pts

# ── 5. CORE: pre-treatment sub-county border distance per treated unit
def subcounty_distance(centroids, wet_geom, cohort, always_src):
    out = []
    treated = sorted(cohort.items(), key=lambda kv: (kv[1], kv[0]))
    for fips, g in treated:
        if fips not in centroids:
            out.append(dict(fips=fips, county=_name(fips), cohort=g,
                            dist_border_subcty_instate="", nearest_wet_source_fips="",
                            n_source_counties=0, note="NO CENTROID"))
            continue
        # source counties wet as of this cohort's pre-period:
        #   always-wet sources + earlier-cohort treated, minus self
        srcs = set(always_src)
        srcs |= {f for f, y in cohort.items() if y < g}
        srcs.discard(fips)
        geoms = [wet_geom[f] for f in srcs if f in wet_geom]
        if not geoms:
            out.append(dict(fips=fips, county=_name(fips), cohort=g,
                            dist_border_subcty_instate="", nearest_wet_source_fips="",
                            n_source_counties=0, note="NO IN-STATE SOURCE"))
            continue
        pt = centroids[fips]
        # nearest source + distance (point.distance(poly) = 0 if inside)
        dmin, nearest = min(((pt.distance(wet_geom[f]), f)
                             for f in srcs if f in wet_geom), key=lambda t: t[0])
        out.append(dict(fips=fips, county=_name(fips), cohort=g,
                        dist_border_subcty_instate=round(dmin / M_PER_MILE, 2),
                        nearest_wet_source_fips=nearest,
                        n_source_counties=len(geoms), note=""))
    return out

def _name(fips):
    for n, f in NAME2FIPS.items():
        if f == fips: return n
    return fips

# ── 6. WET-AREA SHARE (bonus static covariate) ───────────────────────
def wet_area_share(wet_geom, all_geom):
    rows = []
    for fips, allg in all_geom.items():
        wa = wet_geom[fips].area if fips in wet_geom else 0.0
        ta = allg.area
        rows.append(dict(fips=fips, county=_name(fips),
                         wet_area_share=round(wa / ta, 4) if ta else ""))
    rows.sort(key=lambda r: r["fips"])
    return rows

# ── MAIN ─────────────────────────────────────────────────────────────
def main():
    wet_any, wet_liq, all_geom, dropped, manifest = load_polygons(SHP_PATH)
    wet_geom = wet_liq if LIQUOR_ONLY else wet_any
    cohort = load_cohorts(TRANS_CSV)
    always_src = always_wet_sources(wet_geom, cohort)
    centroids = load_centroids(POPCEN_CSV)

    treated_rows = subcounty_distance(centroids, wet_geom, cohort, always_src)
    share_rows   = wet_area_share(wet_any, all_geom)        # share = ANY off-premise wet

    with open(OUT_TREATED, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["fips","county","cohort",
            "dist_border_subcty_instate","nearest_wet_source_fips",
            "n_source_counties","note"])
        w.writeheader(); w.writerows(treated_rows)
    with open(OUT_SHARE, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["fips","county","wet_area_share"])
        w.writeheader(); w.writerows(share_rows)
    with open(OUT_MANIFEST, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["fips","county","name","notes","beerwine_only"])
        w.writeheader(); w.writerows(sorted(manifest, key=lambda r: r["fips"]))

    margin = "PACKAGED LIQUOR only" if LIQUOR_ONLY else "ANY off-premise (incl beer/wine)"
    print(f"Source margin: {margin}")
    print(f"Wrote {OUT_TREATED} ({len(treated_rows)} treated counties)")
    print(f"Wrote {OUT_SHARE} ({len(share_rows)} counties)")
    print(f"Wrote {OUT_MANIFEST} ({len(manifest)} wet jurisdiction polygons)")
    print(f"Off-premise source counties: {len(always_src)}  "
          f"(+ earlier cohorts per treated unit)")
    print(f"Dropped {len(dropped)} Act-655 park polygons (on-premise, not sources)")
    print("\nPre-treatment sub-county border distance (in-state):")
    for r in treated_rows:
        print(f"  {r['county']:14s} g{r['cohort']}  "
              f"{str(r['dist_border_subcty_instate']):>6} mi  "
              f"-> nearest source {r['nearest_wet_source_fips']}  {r['note']}")
    print("\nNOTE: in-state only. To augment with out-of-state access, take the "
          "row-wise min of dist_border_subcty_instate and your existing OOS "
          "distance (nearest_wet_is_oos group); the shapefile has no OOS geometry.")

if __name__ == "__main__":
    main()
