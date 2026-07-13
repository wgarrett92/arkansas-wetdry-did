# =====================================================================
# PATCH for build_border_augment_v2.py
# Madison g2012 timing  +  Sebastian/Fort Smith as a wet SOURCE
# ---------------------------------------------------------------------
# WHY: the distance-to-nearest-wet metrics depend on the set of WET
# SOURCES per year. Two corrections from the 2026-06 verification:
#   - Madison (05087) was treated as always-wet; it is wet only FROM 2012.
#   - Sebastian/Fort Smith (05131) is long-standing wet off-premise but
#     was coded dry, so it was wrongly omitted as a source (overstating
#     distance for Crawford/Scott/Franklin/Logan).
# The population-weighted CENTROIDS do NOT change -- do not recompute
# pop_centroids.csv. Only the wet-source TIMING changes.
# =====================================================================

# WHERE THIS GOES:
#   Insert AFTER the in-state wet-source table / wet_from_year mapping is
#   assembled, and BEFORE nearest-wet distances are computed. It overrides
#   two entries regardless of how that table was sourced (hardcoded dict,
#   transition_summary.csv, or the panel's cohort column).

# `wet_from_year[fips]` = first year the county counts as an OFF-PREMISE
# wet source for distance purposes. A county is NOT a source in years < that.
INSTATE_WET_OVERRIDE = {
    5087: 2012,   # Madison  -> countywide off-premise wet vote, Nov 2012
                  #            (was mis-set always-wet). NOT a source 2008-2011.
    5131: 2008,   # Sebastian/Fort Smith -> wet off-premise for the whole window
                  #            (was wrongly dry). Keep as a SOURCE even if you
                  #            DROP Sebastian as an estimation unit -- neighbors'
                  #            access is real regardless.
}

# --- adapt the line below to your actual structure --------------------
# If wet_from_year is a dict:
for _f, _y in INSTATE_WET_OVERRIDE.items():
    wet_from_year[_f] = _y
# If it is a DataFrame column keyed on fips, instead do:
#   for _f, _y in INSTATE_WET_OVERRIDE.items():
#       wet.loc[wet['fips'] == _f, 'wet_from_year'] = _y
#   # and make sure Sebastian 05131 EXISTS as a row in the in-state wet set
#   # (add it if your table only listed counties that were already 'wet').
# ----------------------------------------------------------------------

# SANITY CHECKS to print after the override, before computing distances:
#   assert wet_from_year.get(5087) == 2012, "Madison not set to 2012"
#   assert wet_from_year.get(5131, 9999) <= 2008, "Sebastian not an all-window source"
#   # Madison must be EXCLUDED from the wet set in 2008-2011 and INCLUDED 2012+.
#   # Sebastian must be INCLUDED in every year.

# EXPECTED EFFECTS after re-running:
#   - pretreatment_distance_by_treated_v2.csv gains a MADISON (05087) row;
#     its pre-2012 nearest wet = Washington (in-state, adjacent), short (~10mi).
#   - Crawford (a dry control), Scott, Franklin, Logan: dist_*_aug SHRINK
#     (Fort Smith now counted as the nearest wet for them).
#   - All four distance vars (dist_popcen_instate/_aug, dist_border_instate/_aug)
#     inherit the change. nearest_wet_fips_aug updates for the affected counties.
#
# DO NOT TOUCH: pop_centroids.csv (centroids unchanged);
#               oos_wet_reference_v2.csv (Madison/Sebastian are in-state).
# =====================================================================
