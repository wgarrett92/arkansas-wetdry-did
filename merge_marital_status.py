"""
Merge ACS Marital Status into Annual and Monthly Panels
========================================================
Reads:  arkansas_acs_marital_status_2009_2023.csv  (from corrected pull)
        arkansas_panel_annual_merged.csv
        arkansas_panel_monthly_merged.csv

Writes: arkansas_panel_annual_merged_v2.csv   (+ 5 marital cols)
        arkansas_panel_monthly_merged_v2.csv  (+ 5 marital cols)

Merge key: fips × acs_vintage
  Annual panel already has acs_vintage column.
  Monthly panel: acs_vintage = max(year, 2009).

New columns added:
  pct_married, pct_divorced, pct_never_married, pct_widowed, pct_separated

Usage:
  python3 merge_marital_status.py

  Expects all input files in the current working directory.
  Adjust paths below if needed.
"""

import csv
import os
import sys

# ── File paths (adjust if needed) ───────────────────────────
MARITAL_FILE = "arkansas_acs_marital_status_2009_2023.csv"
ANNUAL_FILE  = "arkansas_panel_annual_merged.csv"
MONTHLY_FILE = "arkansas_panel_monthly_merged.csv"

ANNUAL_OUT   = "arkansas_panel_annual_merged_v2.csv"
MONTHLY_OUT  = "arkansas_panel_monthly_merged_v2.csv"

# Columns to merge from marital status file
MARITAL_COLS = [
    "pct_married", "pct_divorced", "pct_never_married",
    "pct_widowed", "pct_separated",
]


def load_marital_lookup(path):
    """Load marital status data into a dict keyed by (fips, acs_vintage)."""
    lookup = {}
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["fips"], str(row["acs_vintage"]))
            lookup[key] = {col: row[col] for col in MARITAL_COLS}
    return lookup


def get_acs_vintage(year):
    """Map panel year to ACS vintage (same logic as existing panel)."""
    yr = int(year)
    return str(max(yr, 2009))


def merge_annual(marital_lookup, in_path, out_path):
    """Merge marital status into annual panel using existing acs_vintage column."""
    with open(in_path, newline="") as fin:
        reader = csv.DictReader(fin)
        in_fields = reader.fieldnames

        # Check for existing marital columns (avoid duplicates on re-run)
        out_fields = [f for f in in_fields if f not in MARITAL_COLS]
        out_fields.extend(MARITAL_COLS)

        rows = list(reader)

    matched = 0
    missed = 0

    with open(out_path, "w", newline="") as fout:
        writer = csv.DictWriter(fout, fieldnames=out_fields)
        writer.writeheader()

        for row in rows:
            fips = row["fips"]
            vintage = row.get("acs_vintage", get_acs_vintage(row["year"]))
            key = (fips, str(vintage))

            marital = marital_lookup.get(key)
            if marital:
                row.update(marital)
                matched += 1
            else:
                for col in MARITAL_COLS:
                    row[col] = ""
                missed += 1

            # Write only the columns in out_fields
            writer.writerow({k: row.get(k, "") for k in out_fields})

    return matched, missed


def merge_monthly(marital_lookup, in_path, out_path):
    """Merge marital status into monthly panel (no acs_vintage column — derive it)."""
    with open(in_path, newline="") as fin:
        reader = csv.DictReader(fin)
        in_fields = reader.fieldnames

        out_fields = [f for f in in_fields if f not in MARITAL_COLS]
        out_fields.extend(MARITAL_COLS)

        rows = list(reader)

    matched = 0
    missed = 0

    with open(out_path, "w", newline="") as fout:
        writer = csv.DictWriter(fout, fieldnames=out_fields)
        writer.writeheader()

        for row in rows:
            fips = row["fips"]
            vintage = get_acs_vintage(row["year"])
            key = (fips, vintage)

            marital = marital_lookup.get(key)
            if marital:
                row.update(marital)
                matched += 1
            else:
                for col in MARITAL_COLS:
                    row[col] = ""
                missed += 1

            writer.writerow({k: row.get(k, "") for k in out_fields})

    return matched, missed


def main():
    # Check files exist
    for f in [MARITAL_FILE, ANNUAL_FILE, MONTHLY_FILE]:
        if not os.path.exists(f):
            print(f"ERROR: {f} not found in current directory.")
            print(f"  Current directory: {os.getcwd()}")
            sys.exit(1)

    print("=" * 60)
    print("Merging ACS Marital Status into Panels")
    print("=" * 60)

    # Load lookup
    marital = load_marital_lookup(MARITAL_FILE)
    print(f"Marital status lookup: {len(marital)} county-vintage pairs")

    # Spot check
    sample_key = list(marital.keys())[0]
    print(f"  Sample: {sample_key} -> {marital[sample_key]}")

    # Validate: no pct_married > 1
    bad = [k for k, v in marital.items() if float(v["pct_married"]) > 1.0]
    if bad:
        print(f"  WARNING: {len(bad)} entries with pct_married > 1.0")
        print(f"  Did you run the CORRECTED pull script (v2)?")
        sys.exit(1)
    else:
        print("  Validation: all pct_married <= 1.0 ✓")

    # Merge annual
    print(f"\nMerging annual panel...")
    am, amiss = merge_annual(marital, ANNUAL_FILE, ANNUAL_OUT)
    print(f"  Matched: {am}  |  Missed: {amiss}")
    print(f"  Saved: {ANNUAL_OUT}")

    # Merge monthly
    print(f"\nMerging monthly panel...")
    mm, mmiss = merge_monthly(marital, MONTHLY_FILE, MONTHLY_OUT)
    print(f"  Matched: {mm}  |  Missed: {mmiss}")
    print(f"  Saved: {MONTHLY_OUT}")

    # Summary
    print("\n" + "=" * 60)
    print("MERGE COMPLETE")
    print("=" * 60)
    print(f"New columns: {', '.join(MARITAL_COLS)}")
    print(f"\nAnnual:  {ANNUAL_OUT}  ({am + amiss} rows, {am} matched)")
    print(f"Monthly: {MONTHLY_OUT}  ({mm + mmiss} rows, {mm} matched)")
    if amiss > 0 or mmiss > 0:
        print(f"\n  NOTE: {amiss} annual / {mmiss} monthly rows unmatched.")
        print(f"  These are likely 2008-2009 rows if ACS 2009 vintage is missing.")


if __name__ == "__main__":
    main()
