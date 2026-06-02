"""
Pull ACS 5-Year Marital Status Data (Table B12001) — CORRECTED
================================================================
Fixes variable hierarchy errors in the original pull:
  - B12001_004E is "Male: Now married" (TOTAL), not "spouse present"
  - B12001_005E is a child of 004, not a separate category
  - B12001_009E is Male: Widowed (not divorced)
  - B12001_010E is Male: Divorced (not widowed)

Correct B12001 hierarchy (from Census Reporter):
  001 = Total (pop 15+)
  002 = Male
    003 = Male: Never married
    004 = Male: Now married (TOTAL)
      005 = Male: Married, spouse present
      006 = Male: Married, spouse absent (TOTAL)
        007 = Male: Separated
        008 = Male: Other (spouse absent, not separated)
    009 = Male: Widowed
    010 = Male: Divorced
  011 = Female
    012 = Female: Never married
    013 = Female: Now married (TOTAL)
      014 = Female: Married, spouse present
      015 = Female: Married, spouse absent (TOTAL)
        016 = Female: Separated
        017 = Female: Other
    018 = Female: Widowed
    019 = Female: Divorced

We use ONLY the correct level of aggregation:
  n_married       = 004 + 013  (male + female now married totals)
  n_never_married = 003 + 012
  n_widowed       = 009 + 018
  n_divorced      = 010 + 019
  n_separated     = 007 + 016  (leaf nodes under spouse absent)

Usage:
  export CENSUS_API_KEY=your_key_here
  python3 pull_acs_marital_status_v2.py
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

VINTAGES = list(range(2009, 2024))

# Only pull the variables we actually need (leaf or correct-level nodes)
VARIABLES = [
    "B12001_001E",  # Total pop 15+
    "B12001_003E",  # Male: Never married
    "B12001_004E",  # Male: Now married (TOTAL — this is the right level)
    "B12001_007E",  # Male: Separated (leaf under spouse absent)
    "B12001_009E",  # Male: Widowed
    "B12001_010E",  # Male: Divorced
    "B12001_012E",  # Female: Never married
    "B12001_013E",  # Female: Now married (TOTAL)
    "B12001_016E",  # Female: Separated
    "B12001_018E",  # Female: Widowed
    "B12001_019E",  # Female: Divorced
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
        fips = d["state"] + d["county"]

        def safe_int(key):
            val = d.get(key, None)
            if val is None or int(val) < 0:
                return 0
            return int(val)

        pop_15plus = safe_int("B12001_001E")
        if pop_15plus == 0:
            continue

        # Correct aggregation using proper hierarchy levels
        n_never_married = safe_int("B12001_003E") + safe_int("B12001_012E")
        n_married       = safe_int("B12001_004E") + safe_int("B12001_013E")
        n_separated     = safe_int("B12001_007E") + safe_int("B12001_016E")
        n_widowed       = safe_int("B12001_009E") + safe_int("B12001_018E")
        n_divorced      = safe_int("B12001_010E") + safe_int("B12001_019E")

        # Validation: components should sum to total
        component_sum = n_never_married + n_married + n_widowed + n_divorced
        # Note: separated is a SUBSET of married (spouse absent), 
        # so it should NOT be added to the grand total.
        # Actually — Census treats "now married" as INCLUDING separated 
        # in some tables but NOT in B12001. In B12001:
        #   004 = Now married (total) which INCLUDES spouse present + spouse absent
        #   spouse absent INCLUDES separated + other
        # So separated is already inside n_married. Don't add it separately to the sum.

        pct_married = round(n_married / pop_15plus, 4)
        pct_divorced = round(n_divorced / pop_15plus, 4)
        pct_never_married = round(n_never_married / pop_15plus, 4)
        pct_widowed = round(n_widowed / pop_15plus, 4)
        pct_separated = round(n_separated / pop_15plus, 4)

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
            "pct_never_married": pct_never_married,
            "pct_widowed": pct_widowed,
            "pct_separated": pct_separated,
        })

    # Validate first row
    if rows_out:
        r = rows_out[0]
        check = r["n_never_married"] + r["n_married"] + r["n_widowed"] + r["n_divorced"]
        ratio = check / r["pop_15plus"]
        if abs(ratio - 1.0) > 0.01:
            print(f"  WARNING: {r['county_name']} components sum to {ratio:.4f} of total")

    return rows_out


def main():
    if API_KEY == "YOUR_API_KEY_HERE":
        print("ERROR: Set your Census API key.")
        print("  export CENSUS_API_KEY=your_key_here")
        sys.exit(1)

    all_rows = []
    print("Pulling ACS B12001 (Marital Status) — CORRECTED variable codes")
    print(f"Vintages: {VINTAGES[0]}–{VINTAGES[-1]}")
    print("=" * 60)

    for v in VINTAGES:
        rows = pull_vintage(v)
        print(f"  {v}: {len(rows)} counties")
        all_rows.extend(rows)
        time.sleep(0.5)

    print("=" * 60)
    print(f"Total rows: {len(all_rows)}  (expected: {75 * len(VINTAGES)})")

    # Spot-check: all pct_married should be < 1
    bad = [r for r in all_rows if r["pct_married"] > 1.0]
    if bad:
        print(f"WARNING: {len(bad)} rows with pct_married > 1.0 — something is still wrong")
    else:
        print("VALIDATION PASSED: all pct_married <= 1.0")

    fieldnames = [
        "fips", "county_name", "acs_vintage", "pop_15plus",
        "n_married", "n_divorced", "n_separated", "n_widowed", "n_never_married",
        "pct_married", "pct_divorced", "pct_never_married",
        "pct_widowed", "pct_separated",
    ]
    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"\nSaved: {OUTPUT_FILE}")
    print(f"\nMerge key: fips × acs_vintage")
    print(f"  Panel 2008–2009 → acs_vintage = 2009")
    print(f"  Panel 2010+     → acs_vintage = year")


if __name__ == "__main__":
    main()
