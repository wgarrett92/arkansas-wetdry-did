"""
build_vmt_panel.py
==================
Parses ARDOT "Road and Street Mileage Report - County Summary" .xls files
(2013-2023), extracts per-county totals from each county's sheet, and merges
onto the border-augmented panel.

Each .xls has 75 sheets (one per county). The grand-total line is the row whose
col 1 reads "<NAME> County Total"; in that row:
  col 5/6  = Rural (<5,000 pop area)        road length / DVMT
  col 7/8  = Small Urban (5,000-49,999)     road length / DVMT
  col 10/11= Urbanized (>=50,000)           road length / DVMT
  col 13/14= TOTAL                          road length / DVMT
DVMT = Daily Vehicle Miles of Travel. Annual VMT = DVMT * 365.

Outputs:
  vmt_county_year.csv            fips x year (2013-2023), VMT measures
  arkansas_panel_border_vmt.csv  border-aug panel + VMT cols (NaN for 2008-2012)
"""
import pandas as pd, numpy as np, csv, glob, re, os

UP = '/mnt/user-data/uploads'
PANEL = '/home/claude/out/arkansas_did_panel_with_border_v2.csv'
OUT = '/home/claude/out'

# county name -> fips from the panel
panel = pd.read_csv(PANEL, dtype={'fips': str})
panel['fips'] = panel['fips'].str.zfill(5)
name2fips = {c.strip().upper(): f for c, f in zip(panel['county'], panel['fips'])}

def grand_total(df):
    for i in range(df.shape[0]):
        v = df.iat[i, 1]
        if isinstance(v, str) and 'County Total' in v:
            name = v.replace('County Total', '').strip().upper()
            row = df.iloc[i]
            num = lambda c: float(row[c]) if pd.notna(row[c]) and str(row[c]).strip() != '' else 0.0
            return name, num(13), num(14), num(6), num(8), num(11)
    return None

records, unmatched = [], set()
for f in sorted(glob.glob(f'{UP}/Road_and_Street_Mileage_Report_-_County_Summary_-_*.xls')):
    yr = int(re.search(r'(\d{4})\.xls$', f).group(1))
    xl = pd.ExcelFile(f, engine='xlrd')
    for sh in xl.sheet_names:
        d = pd.read_excel(f, engine='xlrd', sheet_name=sh, header=None)
        gt = grand_total(d)
        if not gt:
            continue
        name, rlen, dvmt, dvmt_r, dvmt_su, dvmt_u = gt
        fips = name2fips.get(name)
        if not fips:
            unmatched.add(name); continue
        records.append({'fips': fips, 'year': yr, 'dvmt_total': round(dvmt, 3),
                        'vmt_annual': round(dvmt * 365, 1), 'road_length_total': round(rlen, 3),
                        'dvmt_rural': round(dvmt_r, 3), 'dvmt_small_urban': round(dvmt_su, 3),
                        'dvmt_urbanized': round(dvmt_u, 3)})

vmt = pd.DataFrame(records).sort_values(['fips', 'year'])
vmt.to_csv(f'{OUT}/vmt_county_year.csv', index=False)

# ---- QC ----
print(f"files parsed: {len(glob.glob(f'{UP}/*.xls'))}  | rows: {len(vmt)}")
print(f"counties matched: {vmt['fips'].nunique()}/75  | years: {sorted(vmt['year'].unique())}")
if unmatched:
    print("UNMATCHED county names:", sorted(unmatched))
# check rural+smurban+urbanized ~= total
chk = vmt.assign(s=vmt.dvmt_rural + vmt.dvmt_small_urban + vmt.dvmt_urbanized)
bad = chk[(chk.s - chk.dvmt_total).abs() > 1.0]
print(f"rows where rural+su+urb != total (>1 DVMT): {len(bad)}")
# expect 75*11 = 825 rows
print(f"expected 825 rows: {'OK' if len(vmt)==825 else 'CHECK'}")

# ---- merge onto border panel (left join; 2008-2012 -> NaN) ----
merged = panel.merge(vmt, on=['fips', 'year'], how='left')
# exposure-adjusted crash rates (per 100 million annual VMT), where VMT present
with np.errstate(divide='ignore', invalid='ignore'):
    hund_m = merged['vmt_annual'] / 1e8
    merged['fatal_per_100m_vmt'] = (merged['fatal_crashes'] / hund_m).round(3)
    merged['alcohol_per_100m_vmt'] = (merged['alcohol_fatal_crashes'] / hund_m).round(3)
merged.to_csv(f'{OUT}/arkansas_panel_border_vmt.csv', index=False)

cov = merged['vmt_annual'].notna().mean()
print(f"\nmerged panel rows: {len(merged)}  | VMT coverage: {cov:.1%} (2013-2023 only)")
print("VMT summary (DVMT total, per county-year):")
print(vmt['dvmt_total'].describe()[['min', '50%', 'mean', 'max']].round(0).to_string())
print("\nsample (Pulaski 05119, Little Rock):")
print(merged[merged.fips=='05119'][['year','fatal_crashes','dvmt_total','vmt_annual','fatal_per_100m_vmt']].tail(4).to_string(index=False))
