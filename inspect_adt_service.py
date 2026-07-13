#!/usr/bin/env python3
"""
inspect_adt_service.py
======================================================================
Field-inspection probe for the ARDOT ADT_Linear FeatureServer, BEFORE
committing to a corridor build. Answers three questions:

  1. Which YEAR columns exist, and how far back do they go?
     (Does the segment series actually reach 2008?)
  2. How is COUNTY / STATION encoded? (name? ARDOT 1-75 number? string?)
  3. For your treated counties, how many segments carry a NON-NULL ADT
     value in each year? (Is the treated-county corridor populated back
     to 2008, or do the early years go blank?)

Nothing here writes to your panel. It only reads + prints a report.

Run:  python inspect_adt_service.py
Deps: standard library only (urllib, json, re).
======================================================================
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request

# ---------------------------------------------------------------------
# CONFIG -- edit these two things if needed.
# ---------------------------------------------------------------------
# The service you linked. Layer 0 is ADT_Linear on this FeatureServer.
BASE  = "https://gis.ardot.gov/referenced/rest/services/SIR_TIS/ADTLinear/FeatureServer"
LAYER = 0

# FALLBACK if gis.ardot.gov bot-blocks programmatic access from your box:
# the Arkansas GIS Office mirrors the same ADT data here (layer 7).
# Field names differ slightly; the script auto-discovers them either way.
#   BASE  = "https://gis.arkansas.gov/arcgis/rest/services/FEATURESERVICES/Transportation/FeatureServer"
#   LAYER = 7

# Treated counties to probe. ARDOT often encodes county as a NAME or as
# its own 1-75 alpha number (NOT FIPS), so we match loosely on the name.
# Edit to taste; Boone + Benton are good early-cohort corridors.
TARGET_COUNTY_NAMES = ["BOONE", "BENTON", "SHARP", "MADISON"]

# Year range you care about for the panel.
YEAR_MIN, YEAR_MAX = 2008, 2023

TIMEOUT = 60
HEADERS = {"User-Agent": "Mozilla/5.0 (research data inspection; ADT field probe)"}
OUT_TXT = "adt_service_inspection.txt"


# ---------------------------------------------------------------------
# tiny HTTP helper
# ---------------------------------------------------------------------
def fetch_json(url, params=None):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        raw = r.read().decode("utf-8", "replace")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        raise RuntimeError(
            "Response was not JSON (likely a bot-detection HTML page).\n"
            "Try the gis.arkansas.gov mirror in CONFIG, or run from a browser-"
            "trusted network. First 200 chars:\n" + raw[:200]
        )


LINES = []
def say(s=""):
    print(s)
    LINES.append(s)

def rule(title):
    say()
    say("=" * 70)
    say(title)
    say("=" * 70)


# ---------------------------------------------------------------------
# 1. layer metadata + field discovery
# ---------------------------------------------------------------------
def inspect_layer():
    meta = fetch_json(f"{BASE}/{LAYER}", {"f": "json"})
    rule("1. LAYER METADATA")
    say(f"  name           : {meta.get('name')}")
    say(f"  geometryType   : {meta.get('geometryType')}")
    say(f"  maxRecordCount : {meta.get('maxRecordCount')}")
    say(f"  displayField   : {meta.get('displayField')}")

    fields = meta.get("fields", []) or []
    say(f"  field count    : {len(fields)}")

    # find the county-ish field and the station-ish field
    county_field = next(
        (f["name"] for f in fields if "county" in f["name"].lower()), None
    )
    station_field = next(
        (f["name"] for f in fields if "station" in f["name"].lower()
         or "stat" in f["name"].lower()), None
    )

    # discover YEAR columns: names ending in a 4-digit year, plus a
    # 'year_adt'-style pointer to the latest-year column.
    year_fields = {}            # {year_int: field_name}
    latest_pointer = None
    for f in fields:
        nm = f["name"]
        m = re.search(r"(?:^|_)((?:19|20)\d{2})$", nm)
        if m:
            year_fields[int(m.group(1))] = nm
        if nm.lower() in ("year_adt", "yearadt", "mostrecent", "adt_year"):
            latest_pointer = nm

    rule("2. FIELD DICTIONARY (name : type : alias)")
    for f in fields:
        say(f"  {f['name']:<28} {f.get('type','?'):<26} {f.get('alias','')}")

    rule("3. YEAR-COLUMN DISCOVERY")
    if year_fields:
        yrs = sorted(year_fields)
        say(f"  year columns found : {len(yrs)}")
        say(f"  earliest year col  : {yrs[0]}  ({year_fields[yrs[0]]})")
        say(f"  latest year col    : {yrs[-1]} ({year_fields[yrs[-1]]})")
        missing = [y for y in range(YEAR_MIN, YEAR_MAX + 1) if y not in year_fields]
        say(f"  reaches {YEAR_MIN}?      : {'YES' if YEAR_MIN in year_fields else 'NO'}")
        if missing:
            say(f"  year cols MISSING in {YEAR_MIN}-{YEAR_MAX}: "
                f"{', '.join(map(str, missing)) or 'none'}")
    else:
        say("  No 'year_YYYY' columns found. This service may store ADT as a")
        say("  single value-per-feature with the YEAR in a separate field, or")
        say("  it may be the 'most recent only' render layer. Inspect the field")
        say("  dictionary above for a YEAR / ADT_YEAR attribute, or switch to")
        say("  the gis.arkansas.gov mirror (layer 7), which is stored wide.")

    say(f"\n  detected county field  : {county_field}")
    say(f"  detected station field : {station_field}")
    say(f"  latest-year pointer    : {latest_pointer}")
    return county_field, station_field, year_fields, {f["name"]: f.get("type") for f in fields}


# ---------------------------------------------------------------------
# 2. total count + one full sample record (see how county is encoded)
# ---------------------------------------------------------------------
def total_count():
    j = fetch_json(f"{BASE}/{LAYER}/query",
                   {"where": "1=1", "returnCountOnly": "true", "f": "json"})
    return j.get("count")

def sample_record():
    j = fetch_json(f"{BASE}/{LAYER}/query",
                   {"where": "1=1", "outFields": "*",
                    "resultRecordCount": 1, "f": "json"})
    feats = j.get("features", [])
    rule("4. SAMPLE RECORD (so you can see county/station encoding)")
    if not feats:
        say("  (no features returned)")
        return
    attrs = feats[0].get("attributes", {})
    for k, v in attrs.items():
        say(f"  {k:<28} = {v}")


def distinct_counties(county_field):
    if not county_field:
        return
    rule("5. DISTINCT COUNTY VALUES (first 80)")
    try:
        j = fetch_json(f"{BASE}/{LAYER}/query",
                       {"where": "1=1", "outFields": county_field,
                        "returnDistinctValues": "true",
                        "orderByFields": county_field, "f": "json"})
        vals = [f["attributes"][county_field] for f in j.get("features", [])]
        say(f"  {len(vals)} distinct value(s):")
        say("  " + ", ".join(str(v) for v in vals[:80]))
        if len(vals) > 80:
            say(f"  ... (+{len(vals)-80} more)")
    except Exception as e:
        say(f"  (distinct query failed: {e})")


# ---------------------------------------------------------------------
# 3. per-year coverage for the treated counties
# ---------------------------------------------------------------------
def year_coverage(county_field, county_type, year_fields):
    rule("6. PER-YEAR NON-NULL COVERAGE FOR TREATED COUNTIES")
    if not county_field or not year_fields:
        say("  Skipped: need both a county field and year columns (see above).")
        return

    is_str = (county_type or "").lower().endswith("string")
    yrs = sorted(y for y in year_fields if YEAR_MIN <= y <= YEAR_MAX)

    for name in TARGET_COUNTY_NAMES:
        # loose name match; if county is numeric-coded this won't match and
        # you'll switch to the number you saw in section 5.
        if is_str:
            where_county = f"UPPER({county_field}) LIKE '%{name}%'"
        else:
            say(f"\n  {name}: county field is numeric ({county_type}); "
                f"set the ARDOT county number from section 5 and rerun.")
            continue

        total = fetch_json(f"{BASE}/{LAYER}/query",
                           {"where": where_county,
                            "returnCountOnly": "true", "f": "json"}).get("count", 0)
        say(f"\n  {name}  (segments matched: {total})")
        if not total:
            say("    no segments matched this name -- check encoding in section 5.")
            continue
        for y in yrs:
            yf = year_fields[y]
            w = f"{where_county} AND {yf} IS NOT NULL AND {yf} > 0"
            try:
                c = fetch_json(f"{BASE}/{LAYER}/query",
                               {"where": w, "returnCountOnly": "true",
                                "f": "json"}).get("count", 0)
            except Exception as e:
                c = f"ERR({e})"
            bar = ""
            if isinstance(c, int) and total:
                bar = "#" * int(round(20 * c / total))
            say(f"    {y} [{yf:<12}] {str(c):>5}/{total:<4} {bar}")
            time.sleep(0.05)   # be polite to the server


# ---------------------------------------------------------------------
def main():
    say("ARDOT ADT_Linear field-inspection probe")
    say(f"service: {BASE}/{LAYER}")
    try:
        county_field, station_field, year_fields, types = inspect_layer()
        say(f"\n  TOTAL FEATURES: {total_count()}")
        sample_record()
        distinct_counties(county_field)
        year_coverage(county_field, types.get(county_field), year_fields)
    except Exception as e:
        say(f"\nFATAL: {e}")
        sys.exit(1)

    rule("WHAT TO CHECK")
    say("  - Section 3: does 'reaches 2008' say YES? If the earliest year")
    say("    column is e.g. 2013, the segment series can't anchor the 2010/")
    say("    2012 cohorts -- same coverage wall as the county VMT.")
    say("  - Section 6: are the early years populated for Boone/Benton, or do")
    say("    they read 0/N? Sparse early years => corridor test starts later.")
    say("  - If county is numeric-coded, grab the number from section 5 and")
    say("    rerun with TARGET set to those numbers.")

    with open(OUT_TXT, "w") as fh:
        fh.write("\n".join(LINES) + "\n")
    say(f"\n(report written to {OUT_TXT})")


if __name__ == "__main__":
    main()
