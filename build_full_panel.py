"""
Full FARS Pipeline: Arkansas crash-level extract → county × year × month panel
Coverage: 2008–2023 (16 years)
Handles:
  - 2008–2020: DRUNK_DR from ACCIDENT file
  - 2021–2023: DR_DRINK from VEHICLE file joined on ST_CASE
  
Outputs:
  1. fars_crash_level_arkansas_2008_2023.csv  — crash-level extract
  2. arkansas_county_year_month.csv           — county × year × month panel
  3. arkansas_county_year_dow.csv             — county × year DOW distributions
"""

import csv
import os
from collections import defaultdict, Counter

UPLOAD = "/mnt/user-data/uploads"

# ── File registry ───────────────────────────────────────────
# (filename, year, encoding, has_drunk_dr)
FARS_ACCIDENT = [
    ("ACCIDENT_08.CSV",      2008, "latin-1",   True),
    ("ACCIDENT.CSV",         2009, "latin-1",   True),   # 2009 file
    ("ACCIDENT_10.CSV",      2010, "utf-8-sig",  True),
    ("ACCIDENT_11.CSV",      2011, "utf-8-sig",  True),
    ("ACCIDENT_12.csv",      2012, "utf-8-sig",  True),
    ("ACCIDENT_13.csv",      2013, "utf-8-sig",  True),
    ("ACCIDENT_14.csv",      2014, "utf-8-sig",  True),
    ("accident_15.csv",      2015, "utf-8-sig",  True),
    ("accident_16.CSV",      2016, "utf-8-sig",  True),
    ("accident_17.CSV",      2017, "utf-8-sig",  True),
    ("accident__18csv.csv",  2018, "utf-8-sig",  True),
    ("accident_19.CSV",      2019, "latin-1",    True),
    ("accident_20.csv",      2020, "latin-1",    True),
    ("accident_21.csv",      2021, "utf-8-sig",  False),
    ("accident_22.csv",      2022, "utf-8-sig",  False),
    ("accident_23.csv",      2023, "utf-8-sig",  False),
]

# Vehicle files for 2021-2023 alcohol flag
VEHICLE_FILES = {
    2021: "vehicle_arkansas_2021.csv",
    2022: "vehicle_arkansas_2022.csv",
    2023: "vehicle_arkansas_2023.csv",
}

DOW_LABELS = {1:"Sun", 2:"Mon", 3:"Tue", 4:"Wed", 5:"Thu", 6:"Fri", 7:"Sat"}

# ── Helper: find column by normalized name ──────────────────
def find_col(headers, target):
    for h in headers:
        if h.strip().upper().replace('\ufeff', '') == target:
            return h
    return None

def safe_int(val, default=0):
    try:
        return int(val.strip())
    except (ValueError, AttributeError):
        return default

# ── Step 1: Build alcohol lookup from vehicle files ─────────
print("=" * 65)
print("STEP 1: Building alcohol lookup from vehicle-level files (2021-2023)")
print("=" * 65)

# For each year, get set of ST_CASE values where any DR_DRINK == 1
alcohol_cases = {}  # year -> set of st_case values with alcohol

for yr, vfile in VEHICLE_FILES.items():
    path = os.path.join(UPLOAD, vfile)
    cases = set()
    with open(path, encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames
        col_stcase = find_col(headers, 'ST_CASE')
        col_drink = find_col(headers, 'DR_DRINK')
        
        for row in reader:
            if safe_int(row[col_drink]) == 1:
                cases.add(row[col_stcase].strip())
    
    alcohol_cases[yr] = cases
    print(f"  {yr}: {len(cases)} crashes with alcohol-involved driver")

# ── Step 2: Extract all Arkansas crashes ────────────────────
print("\n" + "=" * 65)
print("STEP 2: Extracting Arkansas crash-level records (2008-2023)")
print("=" * 65)

crashes = []
year_counts = {}

for fname, yr, enc, has_drunk in FARS_ACCIDENT:
    path = os.path.join(UPLOAD, fname)
    with open(path, encoding=enc) as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames
        
        col_state    = find_col(headers, 'STATE')
        col_stcase   = find_col(headers, 'ST_CASE')
        col_county   = find_col(headers, 'COUNTY')
        col_month    = find_col(headers, 'MONTH')
        col_day      = find_col(headers, 'DAY')
        col_day_week = find_col(headers, 'DAY_WEEK')
        col_hour     = find_col(headers, 'HOUR')
        col_fatals   = find_col(headers, 'FATALS')
        col_persons  = find_col(headers, 'PERSONS')
        col_drunk    = find_col(headers, 'DRUNK_DR') if has_drunk else None
        
        n = 0
        for row in reader:
            if row[col_state].strip() != '5':
                continue
            
            county_raw = safe_int(row[col_county])
            fips = 5000 + county_raw
            
            st_case = row[col_stcase].strip() if col_stcase else ''
            month   = safe_int(row[col_month])
            day     = safe_int(row[col_day])
            day_week= safe_int(row[col_day_week], 9)
            hour    = safe_int(row[col_hour], 99)
            fatals  = safe_int(row[col_fatals], 1)
            persons = safe_int(row[col_persons])
            
            # Alcohol determination
            if has_drunk and col_drunk:
                drunk_dr = safe_int(row[col_drunk])
                is_alcohol = 1 if drunk_dr > 0 else 0
                alc_source = "DRUNK_DR"
            else:
                # Use vehicle-level lookup
                is_alcohol = 1 if st_case in alcohol_cases.get(yr, set()) else 0
                drunk_dr = is_alcohol
                alc_source = "DR_DRINK"
            
            crash = {
                'st_case': st_case,
                'fips': fips,
                'county_fips_3': county_raw,
                'year': yr,
                'month': month,
                'day': day,
                'day_week': day_week,
                'hour': hour,
                'drunk_dr': drunk_dr,
                'alcohol_flag_source': alc_source,
                'fatals': fatals,
                'persons': persons,
                'is_alcohol': is_alcohol,
                'is_weekend': 1 if day_week in (1, 7) else 0,
                'is_night': 1 if (hour >= 20 or hour <= 5) else 0,
            }
            crashes.append(crash)
            n += 1
        
        year_counts[yr] = n
        print(f"  {yr}: {n} Arkansas crashes (alcohol source: {alc_source})")

print(f"\n  Total crash-level records: {len(crashes):,}")

# ── Save crash-level extract ────────────────────────────────
crash_cols = ['st_case', 'fips', 'county_fips_3', 'year', 'month', 'day',
              'day_week', 'hour', 'drunk_dr', 'alcohol_flag_source',
              'fatals', 'persons', 'is_alcohol', 'is_weekend', 'is_night']

with open('/home/claude/fars_crash_level_arkansas_2008_2023.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=crash_cols)
    writer.writeheader()
    writer.writerows(crashes)
print(f"\n  Crash-level file saved: fars_crash_level_arkansas_2008_2023.csv")

# ── Step 3: Load panel FIPS and county names ────────────────
print("\n" + "=" * 65)
print("STEP 3: Building county × year × month panel")
print("=" * 65)

panel_fips = set()
fips_to_county = {}
with open('/mnt/project/arkansas_did_panel.csv') as f:
    for row in csv.DictReader(f):
        fips = int(row['fips'])
        panel_fips.add(fips)
        fips_to_county[fips] = row['county']

print(f"  Panel counties: {len(panel_fips)}")

# Check for crashes outside panel
outside = set()
for c in crashes:
    if c['fips'] not in panel_fips:
        outside.add(c['fips'])
if outside:
    print(f"  WARNING: {len(outside)} FIPS codes in crashes not in panel: {sorted(outside)}")

# ── Aggregate to county × year × month ─────────────────────
cym_data = defaultdict(lambda: {
    'fatal_crashes': 0, 'total_fatalities': 0, 'alcohol_fatal_crashes': 0,
    'weekend_crashes': 0, 'night_crashes': 0, 'persons': 0,
    'dow_counts': Counter(),
    'alcohol_flag_sources': set(),
})

for c in crashes:
    if c['fips'] not in panel_fips:
        continue
    key = (c['fips'], c['year'], c['month'])
    d = cym_data[key]
    d['fatal_crashes'] += 1
    d['total_fatalities'] += c['fatals']
    d['alcohol_fatal_crashes'] += c['is_alcohol']
    d['weekend_crashes'] += c['is_weekend']
    d['night_crashes'] += c['is_night']
    d['persons'] += c['persons']
    if c['day_week'] in DOW_LABELS:
        d['dow_counts'][c['day_week']] += 1
    d['alcohol_flag_sources'].add(c['alcohol_flag_source'])

# Build balanced panel: all 75 counties × 16 years × 12 months
cym_rows = []
for fips in sorted(panel_fips):
    for yr in range(2008, 2024):
        for mo in range(1, 13):
            key = (fips, yr, mo)
            d = cym_data.get(key)
            row = {
                'fips': fips,
                'county': fips_to_county.get(fips, ''),
                'year': yr,
                'month': mo,
                'fatal_crashes': d['fatal_crashes'] if d else 0,
                'total_fatalities': d['total_fatalities'] if d else 0,
                'alcohol_fatal_crashes': d['alcohol_fatal_crashes'] if d else 0,
                'weekend_crashes': d['weekend_crashes'] if d else 0,
                'night_crashes': d['night_crashes'] if d else 0,
            }
            for dow_num, dow_label in DOW_LABELS.items():
                row[f'crashes_{dow_label.lower()}'] = d['dow_counts'][dow_num] if d else 0
            
            if d:
                sources = d['alcohol_flag_sources'] - {''}
                row['alcohol_flag_source'] = '|'.join(sorted(sources)) if sources else ''
            else:
                row['alcohol_flag_source'] = ''
            
            cym_rows.append(row)

cym_rows.sort(key=lambda r: (r['fips'], r['year'], r['month']))

cym_cols = ['fips', 'county', 'year', 'month',
            'fatal_crashes', 'total_fatalities', 'alcohol_fatal_crashes',
            'weekend_crashes', 'night_crashes',
            'crashes_sun', 'crashes_mon', 'crashes_tue', 'crashes_wed',
            'crashes_thu', 'crashes_fri', 'crashes_sat',
            'alcohol_flag_source']

with open('/home/claude/arkansas_county_year_month.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=cym_cols)
    writer.writeheader()
    writer.writerows(cym_rows)

n_nonzero = sum(1 for r in cym_rows if r['fatal_crashes'] > 0)
print(f"  Rows: {len(cym_rows):,}  (75 counties × 16 years × 12 months)")
print(f"  Non-zero crash months: {n_nonzero:,}")
print(f"  Zero-crash months: {len(cym_rows) - n_nonzero:,}")

# ── Step 4: County × year DOW distributions ─────────────────
print("\n" + "=" * 65)
print("STEP 4: Building county × year day-of-week distributions")
print("=" * 65)

cy_dow = defaultdict(lambda: Counter())
cy_totals = defaultdict(int)

for c in crashes:
    if c['fips'] not in panel_fips:
        continue
    key = (c['fips'], c['year'])
    if c['day_week'] in DOW_LABELS:
        cy_dow[key][c['day_week']] += 1
        cy_totals[key] += 1

dow_rows = []
for fips in sorted(panel_fips):
    for yr in range(2008, 2024):
        key = (fips, yr)
        total = cy_totals.get(key, 0)
        row = {'fips': fips, 'county': fips_to_county.get(fips, ''),
               'year': yr, 'total_crashes': total}
        for dow_num, dow_label in DOW_LABELS.items():
            count = cy_dow[key][dow_num]
            row[f'crashes_{dow_label.lower()}'] = count
            row[f'share_{dow_label.lower()}'] = round(count / total, 4) if total > 0 else 0
        dow_rows.append(row)

dow_rows.sort(key=lambda r: (r['fips'], r['year']))

dow_cols = ['fips', 'county', 'year', 'total_crashes']
for dl in ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']:
    dow_cols.extend([f'crashes_{dl}', f'share_{dl}'])

with open('/home/claude/arkansas_county_year_dow.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=dow_cols)
    writer.writeheader()
    writer.writerows(dow_rows)

print(f"  Rows: {len(dow_rows):,}  (75 counties × 16 years)")

# ── Step 5: Validation against existing panel ───────────────
print("\n" + "=" * 65)
print("STEP 5: Validation against existing county × year panel")
print("=" * 65)

# Load existing panel for comparison
existing = {}
with open('/mnt/project/arkansas_did_panel.csv') as f:
    for row in csv.DictReader(f):
        key = (int(row['fips']), int(row['year']))
        existing[key] = {
            'fatal_crashes': int(row['fatal_crashes']),
            'alcohol_fatal_crashes': int(row['alcohol_fatal_crashes']),
        }

# Aggregate our monthly data to county-year for comparison
our_cy = defaultdict(lambda: {'fatal': 0, 'alcohol': 0})
for r in cym_rows:
    key = (r['fips'], r['year'])
    our_cy[key]['fatal'] += r['fatal_crashes']
    our_cy[key]['alcohol'] += r['alcohol_fatal_crashes']

mismatches_fatal = 0
mismatches_alc = 0
total_compared = 0
for key in sorted(existing.keys()):
    if key in our_cy:
        total_compared += 1
        ef = existing[key]['fatal_crashes']
        of = our_cy[key]['fatal']
        ea = existing[key]['alcohol_fatal_crashes']
        oa = our_cy[key]['alcohol']
        if ef != of:
            mismatches_fatal += 1
            if mismatches_fatal <= 5:
                print(f"  FATAL mismatch: FIPS {key[0]}, {key[1]}: existing={ef}, new={of}")
        if ea != oa:
            mismatches_alc += 1
            if mismatches_alc <= 5:
                print(f"  ALCOHOL mismatch: FIPS {key[0]}, {key[1]}: existing={ea}, new={oa}")

print(f"\n  County-years compared: {total_compared}")
print(f"  Fatal crash mismatches: {mismatches_fatal}")
print(f"  Alcohol crash mismatches: {mismatches_alc}")

# ── Step 6: Summary statistics ──────────────────────────────
print("\n" + "=" * 65)
print("SUMMARY STATISTICS (2008-2023)")
print("=" * 65)

# Overall DOW distribution
overall_dow = Counter()
overall_dow_alc = Counter()
for c in crashes:
    if c['fips'] in panel_fips and c['day_week'] in DOW_LABELS:
        overall_dow[c['day_week']] += 1
        if c['is_alcohol']:
            overall_dow_alc[c['day_week']] += 1

total_all = sum(overall_dow.values())
print("\n  Day-of-week distribution (all AR fatal crashes):")
print(f"  {'Day':<5} {'All':>6} {'%':>6}  {'Alc':>5} {'Alc%':>6}")
for dow_num in sorted(DOW_LABELS.keys()):
    ct = overall_dow[dow_num]
    act = overall_dow_alc[dow_num]
    pct = ct / total_all * 100
    apct = act / ct * 100 if ct > 0 else 0
    print(f"  {DOW_LABELS[dow_num]:<5} {ct:>6,} {pct:>5.1f}%  {act:>5,} {apct:>5.1f}%")

# Year totals
print("\n  Annual crash totals:")
year_fatal = Counter()
year_alc = Counter()
for c in crashes:
    if c['fips'] in panel_fips:
        year_fatal[c['year']] += 1
        year_alc[c['year']] += c['is_alcohol']
for yr in range(2008, 2024):
    print(f"  {yr}: {year_fatal[yr]:>4} fatal crashes, {year_alc[yr]:>4} alcohol-involved ({year_alc[yr]/max(year_fatal[yr],1)*100:.1f}%)")

# Monthly seasonality
print("\n  Monthly distribution:")
monthly = Counter()
mo_names = {1:'Jan',2:'Feb',3:'Mar',4:'Apr',5:'May',6:'Jun',
             7:'Jul',8:'Aug',9:'Sep',10:'Oct',11:'Nov',12:'Dec'}
for c in crashes:
    if c['fips'] in panel_fips:
        monthly[c['month']] += 1
for mo in range(1, 13):
    print(f"  {mo_names[mo]}: {monthly[mo]:>5,} ({monthly[mo]/len(crashes)*100:.1f}%)")

print("\nDone.")
