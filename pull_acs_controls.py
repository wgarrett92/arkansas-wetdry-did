"""
Pull ACS 5-Year Summary Tables from Census Bureau API
for all 75 Arkansas counties, 2009-2023.

ACS 5-year estimates labeled by end-year:
  "ACS 2009" = surveys from 2005-2009
  "ACS 2023" = surveys from 2019-2023

Variables pulled:
  - B01001: Total population + age groups
  - B19013: Median household income
  - B17001: Poverty status
  - B02001: Race
  - B01002: Median age
  - B09001: Population under 18

Usage:
  python3 pull_acs_controls.py [API_KEY]
  Get a free key at: https://api.census.gov/data/key_signup.html

Output:
  arkansas_acs_controls_2009_2023.csv
"""

import urllib.request
import json
import csv
import sys
import time

API_KEY = sys.argv[1] if len(sys.argv) > 1 else None
STATE_FIPS = "05"
BASE_URL = "https://api.census.gov/data/{year}/acs/acs5"
VINTAGES = list(range(2009, 2024))

VARIABLES = {
    "B01001_001E": "total_pop",
    "B19013_001E": "median_hh_income",
    "B17001_001E": "poverty_universe",
    "B17001_002E": "poverty_below",
    "B02001_001E": "race_total",
    "B02001_002E": "race_white",
    "B02001_003E": "race_black",
    "B01002_001E": "median_age",
    "B09001_001E": "pop_under_18",
}

VAR_STRING = ",".join(VARIABLES.keys())

def pull_acs_vintage(year):
    url = BASE_URL.format(year=year)
    url += f"?get=NAME,{VAR_STRING}&for=county:*&in=state:{STATE_FIPS}"
    if API_KEY:
        url += f"&key={API_KEY}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        return data[0], data[1:]
    except Exception as e:
        print(f"  ERROR pulling {year}: {e}")
        return None, None

print("=" * 65)
print("Pulling ACS 5-Year Estimates for Arkansas Counties")
print("=" * 65)

all_rows = []
for vintage in VINTAGES:
    print(f"  Pulling ACS {vintage}...", end=" ", flush=True)
    headers, rows = pull_acs_vintage(vintage)
    if rows is None:
        print("FAILED")
        continue
    for row in rows:
        record = dict(zip(headers, row))
        county_fips = int(record['state']) * 1000 + int(record['county'])
        parsed = {'fips': county_fips, 'county_name': record['NAME'], 'acs_vintage': vintage}
        for var_code, var_name in VARIABLES.items():
            val = record.get(var_code)
            try:
                parsed[var_name] = float(val) if val and val != 'null' else None
            except ValueError:
                parsed[var_name] = None
        tp = parsed.get('total_pop')
        if tp and tp > 0:
            pu, pb = parsed.get('poverty_universe'), parsed.get('poverty_below')
            parsed['poverty_rate'] = round(pb / pu, 4) if pu and pu > 0 and pb is not None else None
            rw, rb, rt = parsed.get('race_white'), parsed.get('race_black'), parsed.get('race_total')
            parsed['pct_white'] = round(rw / rt, 4) if rt and rt > 0 and rw is not None else None
            parsed['pct_black'] = round(rb / rt, 4) if rt and rt > 0 and rb is not None else None
            p18 = parsed.get('pop_under_18')
            parsed['pct_under_18'] = round(p18 / tp, 4) if p18 is not None else None
            parsed['pop_21plus'] = tp - p18 if p18 is not None else None
            parsed['pct_21plus'] = round((tp - p18) / tp, 4) if p18 is not None else None
        else:
            for k in ['poverty_rate','pct_white','pct_black','pct_under_18','pop_21plus','pct_21plus']:
                parsed[k] = None
        all_rows.append(parsed)
    print(f"{len(rows)} counties")
    time.sleep(0.5)

output_cols = ['fips', 'county_name', 'acs_vintage', 'total_pop',
               'median_hh_income', 'median_age',
               'poverty_universe', 'poverty_below', 'poverty_rate',
               'race_total', 'race_white', 'race_black', 'pct_white', 'pct_black',
               'pop_under_18', 'pct_under_18', 'pop_21plus', 'pct_21plus']

outpath = '/home/claude/arkansas_acs_controls_2009_2023.csv'
with open(outpath, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=output_cols, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(all_rows)

print(f"\nSaved: {outpath}")
print(f"Rows: {len(all_rows)} ({len(all_rows)//max(len(VINTAGES),1)} counties x {len(VINTAGES)} vintages)")
