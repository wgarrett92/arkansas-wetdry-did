"""
Pull ACS 5-Year Marital Status Data (Table B12001) for All 75 Arkansas Counties
================================================================================
Pulls from Census Bureau API, vintages 2009–2023.
Outputs: arkansas_acs_marital_status_2009_2023.csv

Merge into annual panel via: fips × acs_vintage
  - Panel years 2008–2009 → ACS vintage 2009
  - Panel years 2010–2023 → same-year vintage

Variables constructed:
  pop_15plus    — total population 15 years and over
  n_married     — currently married (spouse present or absent)
  n_divorced    — currently divorced
  n_separated   — currently separated
  n_widowed     — currently widowed
  n_never_married — never married
  pct_married   — share married among 15+
  pct_divorced  — share divorced among 15+

Usage:
  python pull_acs_marital_status.py
  (requires Census API key in CENSUS_API_KEY environment variable,
   or paste your key into the API_KEY variable below)
"""

import os
import requests
import csv
import time
import sys

# ── Configuration ───────────────────────────────────────────
API_KEY = os.environ.get("CENSUS_API_KEY", "YOUR_API_KEY_HERE")
STATE_FIPS = "05"  # Arkansas
OUTPUT_FILE = "arkansas_acs_marital_status_2009_2023.csv"

# ACS 5-year vintages to pull (labeled by end-year)
VINTAGES = list(range(2009, 2024))  # 2009 through 2023

# ── B12001 Variables ────────────────────────────────────────
# B12001_001E  Total (pop 15+)
# B12001_002E  Never married
# B12001_004E  Now married (spouse present) — MALE
# B12001_005E  Now married (spouse absent, excl. separated) — MALE
# B12001_006E  Separated — MALE
# B12001_009E  Divorced — MALE
# B12001_010E  Widowed — MALE
# B12001_013E  Now married (spouse present) — FEMALE
# B12001_014E  Now married (spouse absent, excl. separated) — FEMALE
# B12001_015E  Separated — FEMALE
# B12001_018E  Divorced — FEMALE
# B12001_019E  Widowed — FEMALE
#
# Strategy: pull total + never married, then compute married/divorced
# from male + female subtotals. Alternatively, use the simpler approach
# of pulling the sex-combined detailed cells.
#
# Actually B12001 is sex-specific. The cleaner table is B12001 with
# the following aggregation:
#   pop_15plus    = B12001_001E
#   never_married = B12001_003E + B12001_012E  (male + female never married)
#   married       = B12001_004E + B12001_005E + B12001_013E + B12001_014E
#   separated     = B12001_006E + B12001_015E
#   widowed       = B12001_010E + B12001_019E
#   divorced      = B12001_009E + B12001_018E

VARIABLES = [
    "B12001_001E",  # Total pop 15+
    # Male
    "B12001_003E",  # Male: never married
    "B12001_004E",  # Male: now married, spouse present
    "B12001_005E",  # Male: now married, spouse absent (excl separated)
    "B12001_006E",  # Male: separated
    "B12001_009E",  # Male: divorced
    "B12001_010E",  # Male: widowed
    # Female
    "B12001_012E",  # Female: never married
    "B12001_013E",  # Female: now married, spouse present
    "B12001_014E",  # Female: now married, spouse absent (excl separated)
    "B12001_015E",  # Female: separated
    "B12001_018E",  # Female: divorced
    "B12001_019E",  # Female: widowed
]

VAR_STRING = ",".join(VARIABLES)


def pull_vintage(vintage):
    """Pull B12001 for all Arkansas counties for a given ACS 5-year vintage."""
    url = (
        f"https://api.census.gov/data/{vintage}/acs/acs5"
        f"?get=NAME,{VAR_STRING}"
        f"&for=county:*"
        f"&in=state:{STATE_FIPS}"
        f"&key={API_KEY}"
    )

    resp = requests.get(url, timeout=30)
    if resp.status_code != 200:
        print(f"  WARNING: vintage {vintage} returned status {resp.status_code}")
        print(f"  Response: {resp.text[:200]}")
        return []

    data = resp.json()
    header = data[0]
    rows_out = []

    for row in data[1:]:
        d = dict(zip(header, row))

        # Build 5-digit FIPS
        fips = d["state"] + d["county"]

        # Parse integers (Census returns strings; -666666666 = missing)
        def safe_int(key):
            val = d.get(key, None)
            if val is None or int(val) < 0:
                return None
            return int(val)

        pop_15plus = safe_int("B12001_001E")
        if pop_15plus is None or pop_15plus == 0:
            continue

        n_never_married = (safe_int("B12001_003E") or 0) + (safe_int("B12001_012E") or 0)
        n_married = (
            (safe_int("B12001_004E") or 0)
            + (safe_int("B12001_005E") or 0)
            + (safe_int("B12001_013E") or 0)
            + (safe_int("B12001_014E") or 0)
        )
        n_separated = (safe_int("B12001_006E") or 0) + (safe_int("B12001_015E") or 0)
        n_divorced = (safe_int("B12001_009E") or 0) + (safe_int("B12001_018E") or 0)
        n_widowed = (safe_int("B12001_010E") or 0) + (safe_int("B12001_019E") or 0)

        pct_married = round(n_married / pop_15plus, 4)
        pct_divorced = round(n_divorced / pop_15plus, 4)

        rows_out.append({
            "fips": fips,
            "county_name": d["NAME"].replace(", Arkansas", "").replace(" County", ""),
            "acs_vintage": vintage,
            "pop_15plus": pop_15plus,
            "n_married": n_married,
            "n_divorced": n_divorced,
            "n_separated": n_separated,
            "n_widowed": n_widowed,
            "n_never_married": n_never_married,
            "pct_married": pct_married,
            "pct_divorced": pct_divorced,
        })

    return rows_out


def main():
    if API_KEY == "YOUR_API_KEY_HERE":
        print("ERROR: Set your Census API key.")
        print("  Option 1: export CENSUS_API_KEY=your_key_here")
        print("  Option 2: edit the API_KEY variable in this script")
        print("  Get a free key at: https://api.census.gov/data/key_signup.html")
        sys.exit(1)

    all_rows = []
    print(f"Pulling ACS B12001 (Marital Status) for Arkansas counties")
    print(f"Vintages: {VINTAGES[0]}–{VINTAGES[-1]}")
    print("=" * 60)

    for v in VINTAGES:
        rows = pull_vintage(v)
        print(f"  {v}: {len(rows)} counties retrieved")
        all_rows.extend(rows)
        time.sleep(0.5)  # polite rate limiting

    print("=" * 60)
    print(f"Total rows: {len(all_rows)}  (expected: {75 * len(VINTAGES)} = 75 x {len(VINTAGES)})")

    # Write CSV
    fieldnames = [
        "fips", "county_name", "acs_vintage",
        "pop_15plus", "n_married", "n_divorced", "n_separated",
        "n_widowed", "n_never_married", "pct_married", "pct_divorced",
    ]
    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"\nSaved: {OUTPUT_FILE}")
    print(f"\nMerge instructions:")
    print(f"  1. Map panel year to ACS vintage:")
    print(f"       2008-2009 -> acs_vintage = 2009")
    print(f"       2010+     -> acs_vintage = year")
    print(f"  2. Merge on: fips x acs_vintage")
    print(f"  3. Key variables for estimation: pct_married, pct_divorced")


if __name__ == "__main__":
    main()
