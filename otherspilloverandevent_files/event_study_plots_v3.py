"""
event_study_plots_v3.py

Unified event-study plotting pipeline for both direct-effect
specifications (from es_*.csv files) and spillover specifications
(from csdid_v3_spillover.log). Produces publication-quality PNGs
in the navy/gold Beamer palette.

OUTPUTS:
  Individual plots for each spec (28 total: 18 direct + 10 spillover)
  Grid summaries for each analysis
  Headline comparison figures for the paper:
    - Direct-effect rural vs urban (fatal + alcohol, 2x2)
    - Spillover rural vs urban (fatal + alcohol, 2x2)
    - DIRECT vs SPILLOVER for rural alcohol (the main finding)
"""

import csv
import os
import re
import math
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# ── Palette ─────────────────────────────────────────────────
NAVY     = '#1A2744'
NAVY_MID = '#243560'
GOLD     = '#C9A84C'
MUTED    = '#8C9BB5'
OFFWHITE = '#F4F4F0'
LGRAY    = '#E8EBF2'
RED      = '#C75146'

plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 10,
    'axes.facecolor': 'white',
    'figure.facecolor': 'white',
    'axes.edgecolor': MUTED,
    'axes.labelcolor': NAVY,
    'xtick.color': NAVY,
    'ytick.color': NAVY,
    'grid.color': LGRAY,
    'grid.linewidth': 0.6,
    'axes.titlesize': 11,
    'axes.titleweight': 'bold',
    'axes.titlecolor': NAVY,
})

UPLOADS = '/mnt/user-data/uploads'
OUTDIR = '/home/claude/event_study_plots'
os.makedirs(OUTDIR, exist_ok=True)

# ═══════════════════════════════════════════════════════════
# DIRECT-EFFECT SPEC DEFINITIONS
# ═══════════════════════════════════════════════════════════
# Maps CSV filename stem -> (outcome_label, spec_label, paper_category)
DIRECT_SPECS = [
    # tag, outcome, subtitle, category
    ('fatal_primary',          'Fatal crashes',             'Primary (DRIPW + log_pop, NYT)',              'primary'),
    ('alcohol_primary',        'Alcohol-involved crashes',  'Primary (DRIPW + log_pop, NYT)',              'primary'),
    ('fatal_primaryplus',      'Fatal crashes',             'Primary+ (DRIPW + log_pop + poverty, NYT)',   'primary'),
    ('alcohol_primaryplus',    'Alcohol-involved crashes',  'Primary+ (DRIPW + log_pop + poverty, NYT)',   'primary'),
    ('fatal_primaryplus_reg',  'Fatal crashes',             'Primary+ REG (log_pop + poverty, NYT)',       'headline'),
    ('alcohol_primaryplus_reg','Alcohol-involved crashes',  'Primary+ REG (log_pop + poverty, NYT)',       'headline'),
    ('fatal_pc_primary',       'Fatal crashes per 100k',    'Primary per capita',                          'primary'),
    ('alcohol_pc_primary',     'Alcohol crashes per 100k',  'Primary per capita',                          'primary'),
    ('fatal_robA',             'Fatal crashes',             'Robust A (+ always-wet comparators)',         'robust'),
    ('alcohol_robA',           'Alcohol-involved crashes',  'Robust A (+ always-wet comparators)',         'robust'),
    ('fatal_robC',             'Fatal crashes',             'Robust C (REG, full 7 covariates)',           'robust'),
    ('alcohol_robC',           'Alcohol-involved crashes',  'Robust C (REG, full 7 covariates)',           'robust'),
    ('fatal_robD',             'Fatal crashes',             'Robust D (no covariates)',                    'robust'),
    ('alcohol_robD',           'Alcohol-involved crashes',  'Robust D (no covariates)',                    'robust'),
    ('fatal_rural',            'Fatal crashes',             'Rural subsample (pop < 20k)',                 'heterogeneity'),
    ('alcohol_rural',          'Alcohol-involved crashes',  'Rural subsample (pop < 20k)',                 'heterogeneity'),
    ('fatal_urban',            'Fatal crashes',             'Urban subsample (pop >= 20k)',                'heterogeneity'),
    ('alcohol_urban',          'Alcohol-involved crashes',  'Urban subsample (pop >= 20k)',                'heterogeneity'),
]


def read_direct_csv(tag):
    path = os.path.join(UPLOADS, f'es_{tag}.csv')
    if not os.path.exists(path):
        return None, None, None
    coefs, att, avgs = [], None, {}
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            param = row['parameter']
            try:
                coef = float(row['coef']) if row['coef'] else None
                se = float(row['se']) if row['se'] else None
                pval = float(row['pvalue']) if row['pvalue'] else None
            except ValueError:
                continue
            if param in ('Pre_avg', 'Post_avg'):
                avgs[param] = {'coef': coef, 'se': se, 'pval': pval}
            else:
                try:
                    et = int(row['event_time'])
                    coefs.append((et, coef, se, pval))
                except (ValueError, TypeError):
                    continue
    coefs.sort(key=lambda x: x[0])
    return coefs, avgs, None


# ═══════════════════════════════════════════════════════════
# SPILLOVER SPEC DEFINITIONS (parsed from log)
# ═══════════════════════════════════════════════════════════
SPILLOVER_LOG = '/mnt/user-data/uploads/csdid_v3_spillover.log'

SPILLOVER_SPECS = [
    ('fatal_primaryplus_reg',   'Fatal crashes',             'Primary+ REG (log_pop + poverty)',       'headline'),
    ('alcohol_primaryplus_reg', 'Alcohol-involved crashes',  'Primary+ REG (log_pop + poverty)',       'headline'),
    ('fatal_dripw',             'Fatal crashes',             'DRIPW (log_pop only)',                   'robust'),
    ('alcohol_dripw',           'Alcohol-involved crashes',  'DRIPW (log_pop only)',                   'robust'),
    ('fatal_nocov',             'Fatal crashes',             'No covariates',                          'robust'),
    ('alcohol_nocov',           'Alcohol-involved crashes',  'No covariates',                          'robust'),
    ('fatal_rural',             'Fatal crashes',             'Rural subsample (pop < 20k)',            'heterogeneity'),
    ('alcohol_rural',           'Alcohol-involved crashes',  'Rural subsample (pop < 20k)',            'heterogeneity'),
    ('fatal_urban',             'Fatal crashes',             'Urban subsample (pop >= 20k)',           'heterogeneity'),
    ('alcohol_urban',           'Alcohol-involved crashes',  'Urban subsample (pop >= 20k)',           'heterogeneity'),
]
SPILLOVER_VALID = set(t for t, _, _, _ in SPILLOVER_SPECS)
NUM = r'(-?(?:\d+\.\d*|\.\d+|\d+)|\.)'


def parse_spillover_log():
    with open(SPILLOVER_LOG) as f:
        log_text = f.read()
    blocks = {}
    positions = []
    for m in re.finditer(r'^SPEC:\s*(\S+)\s*\|', log_text, re.MULTILINE):
        if m.group(1) in SPILLOVER_VALID:
            positions.append((m.start(), m.group(1)))
    positions.append((len(log_text), None))
    for i in range(len(positions) - 1):
        blocks[positions[i][1]] = log_text[positions[i][0]:positions[i+1][0]]
    return blocks


def parse_spillover_coefs(block):
    es_start = block.find('Event Study:Dynamic effects')
    if es_start == -1:
        return [], {}, None
    after = block[es_start:]
    nxt = after.find('ATT by Periods', 10)
    section = after[:nxt] if nxt > 0 else after

    coefs = []
    row_re = re.compile(
        r'^\s*T([mp])(\d+)\s*\|\s*'
        + NUM + r'\s+' + NUM + r'\s+' + NUM + r'\s+' + NUM,
        re.MULTILINE)
    for m in row_re.finditer(section):
        sign, tn, c, s, _, p = m.groups()
        et = int(tn) * (-1 if sign == 'm' else 1)
        try:
            coefs.append((et,
                          float(c) if c != '.' else None,
                          float(s) if s != '.' else None,
                          float(p) if p != '.' else None))
        except ValueError:
            continue
    coefs.sort(key=lambda x: x[0])

    # Parse Pre_avg / Post_avg
    avgs = {}
    for label in ('Pre_avg', 'Post_avg'):
        m = re.search(rf'^\s*{label}\s*\|\s*' + NUM + r'\s+' + NUM
                      + r'\s+' + NUM + r'\s+' + NUM,
                      section, re.MULTILINE)
        if m:
            try:
                avgs[label] = {
                    'coef': float(m.group(1)),
                    'se': float(m.group(2)),
                    'pval': float(m.group(4))
                }
            except ValueError:
                pass

    # Overall ATT (outside Event Study section; look in full block)
    att = None
    m = re.search(
        r'Average Treatment Effect on Treated.*?'
        r'^\s*ATT\s*\|\s*' + NUM + r'\s+' + NUM + r'\s+' + NUM + r'\s+' + NUM,
        block, re.DOTALL | re.MULTILINE)
    if m:
        try:
            att = {'coef': float(m.group(1)),
                   'se': float(m.group(2)),
                   'pval': float(m.group(4))}
        except ValueError:
            pass
    return coefs, avgs, att


# ═══════════════════════════════════════════════════════════
# CORE PLOT FUNCTION
# ═══════════════════════════════════════════════════════════
def plot_event_study(ax, coefs, avgs=None, att=None,
                     title_main='', title_sub='', ylabel='',
                     event_time_limit=None, show_post_avg=True,
                     x_label='Event time (years since treatment)'):
    """
    Plot an event study onto `ax`.

    Parameters
    ----------
    coefs : list of (event_time, coef, se, pval)
    avgs : dict with 'Pre_avg' and/or 'Post_avg' entries
    att : dict with coef/se/pval for the overall ATT (shown in title)
    event_time_limit : optional int; trim to |event_time| <= limit
    """
    if not coefs:
        ax.text(0.5, 0.5, 'No data', transform=ax.transAxes,
                ha='center', va='center', color=RED, fontsize=11)
        ax.set_title(f'{title_main} - {title_sub}')
        return

    if event_time_limit is not None:
        coefs = [c for c in coefs if abs(c[0]) <= event_time_limit]

    times = [c[0] for c in coefs]
    betas = [c[1] for c in coefs]
    ses = [c[2] for c in coefs]
    ci_lo = [(b - 1.96*s) if (b is not None and s is not None) else None
             for b, s in zip(betas, ses)]
    ci_hi = [(b + 1.96*s) if (b is not None and s is not None) else None
             for b, s in zip(betas, ses)]

    pts = [(t, b, lo, hi) for t, b, lo, hi
           in zip(times, betas, ci_lo, ci_hi) if b is not None]
    if not pts:
        return
    pt, pb, plo, phi = zip(*pts)

    # Pre/post shading
    ax.axvspan(min(pt) - 0.5, -0.5, color=MUTED, alpha=0.05, zorder=0)
    ax.axvspan(-0.5, max(pt) + 0.5, color=GOLD, alpha=0.06, zorder=0)

    # CI band
    ax.fill_between(pt, plo, phi, color=MUTED, alpha=0.25,
                    zorder=2, linewidth=0)

    # Line + markers (markers colored by significance)
    ax.plot(pt, pb, color=NAVY, linewidth=1.8, zorder=4)
    for t, b, s, p in zip(times, betas, ses, [c[3] for c in coefs]):
        if b is None:
            continue
        # Gold for insignificant, filled navy for p<0.05
        if p is not None and p < 0.05:
            ax.scatter(t, b, s=55, zorder=5, color=NAVY,
                       edgecolors=NAVY, linewidth=1.2)
        else:
            ax.scatter(t, b, s=50, zorder=5, color=GOLD,
                       edgecolors=NAVY, linewidth=0.9)

    # Reference lines
    ax.axhline(0, color=NAVY, linewidth=0.6, alpha=0.5, zorder=1)
    ax.axvline(-0.5, color=GOLD, linewidth=1.4, linestyle='--',
               alpha=0.85, zorder=3)

    # Post_avg overlay as dotted horizontal line over post-period
    if show_post_avg and avgs and 'Post_avg' in avgs:
        pa = avgs['Post_avg']
        if pa['coef'] is not None:
            ax.plot([0, max(pt)], [pa['coef'], pa['coef']],
                    color=RED, linewidth=1.4, linestyle=':',
                    alpha=0.7, zorder=3,
                    label=f'Post_avg = {pa["coef"]:+.2f}')

    # Axis formatting
    ax.set_xlabel(x_label, fontsize=9.5)
    ax.set_ylabel(f'ATT: {ylabel}', fontsize=9.5)
    step = 1 if (max(pt) - min(pt)) <= 10 else 2
    ax.xaxis.set_major_locator(mticker.MultipleLocator(step))
    ax.set_xlim(min(pt) - 0.5, max(pt) + 0.5)

    # Title with overall ATT
    att_str = ''
    if att and att.get('coef') is not None:
        sig = '***' if att['pval'] < 0.01 else \
              '**'  if att['pval'] < 0.05 else \
              '*'   if att['pval'] < 0.10 else ''
        att_str = (f'  |  ATT = {att["coef"]:+.2f} '
                   f'({att["se"]:.2f}){sig}')
    ax.set_title(f'{title_main}: {title_sub}{att_str}', pad=8,
                 fontsize=10.5)

    # PRE/POST labels
    y_top = max(phi)
    y_bot = min(plo)
    y_range = max(1e-6, y_top - y_bot)
    y_annot = y_top + 0.07 * y_range
    # Place inside plot frame even with trimmed window
    if len(pt) >= 3:
        ax.text(min(pt) + (max(-1, min(pt)) - min(pt)) / 2 - 0.5,
                y_annot, 'PRE', color=MUTED, fontweight='bold',
                fontsize=9, ha='center', alpha=0.7)
        ax.text((max(pt) + 0) / 2, y_annot, 'POST',
                color=GOLD, fontweight='bold',
                fontsize=9, ha='center', alpha=0.9)

    if show_post_avg and avgs and 'Post_avg' in avgs:
        ax.legend(loc='lower right', fontsize=8, framealpha=0.9)

    ax.grid(True, axis='y', alpha=0.4, zorder=0)


# ═══════════════════════════════════════════════════════════
# PART 1: DIRECT-EFFECT PLOTS (18 specs)
# ═══════════════════════════════════════════════════════════
print('═══ DIRECT-EFFECT SPECS ═══')
direct_parsed = {}
for tag, ylabel, sub, cat in DIRECT_SPECS:
    coefs, avgs, _ = read_direct_csv(tag)
    if coefs is None:
        print(f'  SKIP {tag} (no CSV found)')
        continue
    # For direct effect, overall ATT comes from Post_avg (approximation)
    # since the ATT exports aren't in the CSVs, but your transfer doc has them
    att = avgs.get('Post_avg') if avgs else None
    direct_parsed[tag] = {'coefs': coefs, 'avgs': avgs, 'att': att,
                          'ylabel': ylabel, 'sub': sub, 'cat': cat}
    print(f'  {tag}: {len(coefs)} coefs, Post_avg={att["coef"]:+.2f}'
          if att else f'  {tag}: {len(coefs)} coefs')

# Individual plots for all direct-effect specs
print('\nWriting direct-effect individual plots...')
direct_dir = os.path.join(OUTDIR, 'direct')
os.makedirs(direct_dir, exist_ok=True)

for tag, ylabel, sub, cat in DIRECT_SPECS:
    if tag not in direct_parsed:
        continue
    d = direct_parsed[tag]
    headline = 'Fatal crashes' if 'fatal' in tag \
        else 'Alcohol-involved crashes' if 'alcohol' in tag and 'pc' not in tag \
        else 'Alcohol crashes per 100k' if 'alcohol_pc' in tag \
        else 'Fatal crashes per 100k' if 'fatal_pc' in tag \
        else 'Crashes'
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_event_study(ax, d['coefs'], avgs=d['avgs'], att=d['att'],
                     title_main=headline, title_sub=d['sub'],
                     ylabel=d['ylabel'])
    fig.tight_layout()
    out = os.path.join(direct_dir, f'direct_{tag}_event.png')
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f'  {out}')

# Direct-effect rural/urban comparison figure (HEADLINE)
fig, axes = plt.subplots(2, 2, figsize=(14, 9))
comp = [('fatal_rural',   'Fatal',   'RURAL'),
        ('fatal_urban',   'Fatal',   'URBAN'),
        ('alcohol_rural', 'Alcohol', 'RURAL'),
        ('alcohol_urban', 'Alcohol', 'URBAN')]
for i, (tag, outcome, geo) in enumerate(comp):
    if tag not in direct_parsed:
        continue
    d = direct_parsed[tag]
    plot_event_study(axes[i // 2, i % 2], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main=outcome, title_sub=geo + ' subsample',
                     ylabel=d['ylabel'], event_time_limit=5)
fig.suptitle(
    'Direct Effect: Rural vs. Urban Heterogeneity (Primary+ REG)',
    fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.975])
fig.savefig(os.path.join(OUTDIR, 'direct_rural_urban_comparison.png'),
            dpi=200, bbox_inches='tight')
plt.close(fig)
print('\nDirect rural/urban comparison saved')

# Direct-effect robustness grid (primary + robA + robC + robD, 2 outcomes = 8 panels)
fig, axes = plt.subplots(4, 2, figsize=(14, 18))
rob = [('fatal_primary',         'Primary (DRIPW, NYT)'),
       ('alcohol_primary',       'Primary (DRIPW, NYT)'),
       ('fatal_primaryplus_reg', 'Primary+ REG (headline)'),
       ('alcohol_primaryplus_reg','Primary+ REG (headline)'),
       ('fatal_robA',            'Robust A (+always-wet)'),
       ('alcohol_robA',          'Robust A (+always-wet)'),
       ('fatal_robD',            'Robust D (no covariates)'),
       ('alcohol_robD',          'Robust D (no covariates)')]
for i, (tag, sub) in enumerate(rob):
    if tag not in direct_parsed:
        continue
    d = direct_parsed[tag]
    outcome = 'Fatal' if 'fatal' in tag else 'Alcohol'
    plot_event_study(axes[i // 2, i % 2], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main=outcome, title_sub=sub,
                     ylabel=d['ylabel'], event_time_limit=6)
fig.suptitle('Direct Effect: Robustness Across Specifications',
             fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.99])
fig.savefig(os.path.join(OUTDIR, 'direct_robustness_grid.png'),
            dpi=180, bbox_inches='tight')
plt.close(fig)
print('Direct robustness grid saved')

# ═══════════════════════════════════════════════════════════
# PART 2: SPILLOVER PLOTS (10 specs)
# ═══════════════════════════════════════════════════════════
print('\n═══ SPILLOVER SPECS ═══')
spillover_blocks = parse_spillover_log()
spillover_parsed = {}
for tag, ylabel, sub, cat in SPILLOVER_SPECS:
    if tag not in spillover_blocks:
        continue
    coefs, avgs, att = parse_spillover_coefs(spillover_blocks[tag])
    spillover_parsed[tag] = {'coefs': coefs, 'avgs': avgs, 'att': att,
                             'ylabel': ylabel, 'sub': sub, 'cat': cat}
    print(f'  {tag}: {len(coefs)} coefs, '
          f'ATT={att["coef"]:+.3f} (p={att["pval"]:.3f})'
          if att else f'  {tag}: {len(coefs)} coefs')

spillover_dir = os.path.join(OUTDIR, 'spillover')
os.makedirs(spillover_dir, exist_ok=True)
print('\nWriting spillover individual plots...')
for tag, ylabel, sub, cat in SPILLOVER_SPECS:
    if tag not in spillover_parsed:
        continue
    d = spillover_parsed[tag]
    headline = 'Fatal crashes' if 'fatal' in tag else 'Alcohol-involved crashes'
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_event_study(ax, d['coefs'], avgs=d['avgs'], att=d['att'],
                     title_main=headline, title_sub=d['sub'],
                     ylabel=d['ylabel'],
                     x_label='Event time (years since first wet neighbor)')
    fig.tight_layout()
    out = os.path.join(spillover_dir, f'spillover_{tag}_event.png')
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f'  {out}')

# Spillover rural/urban comparison
fig, axes = plt.subplots(2, 2, figsize=(14, 9))
for i, (tag, outcome, geo) in enumerate([
        ('fatal_rural', 'Fatal', 'RURAL'),
        ('fatal_urban', 'Fatal', 'URBAN'),
        ('alcohol_rural', 'Alcohol', 'RURAL'),
        ('alcohol_urban', 'Alcohol', 'URBAN')]):
    if tag not in spillover_parsed:
        continue
    d = spillover_parsed[tag]
    plot_event_study(axes[i // 2, i % 2], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main=outcome, title_sub=geo + ' subsample',
                     ylabel=d['ylabel'],
                     x_label='Event time (yrs since wet neighbor)')
fig.suptitle('Spillover Effect: Rural vs. Urban Heterogeneity',
             fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.975])
fig.savefig(os.path.join(OUTDIR, 'spillover_rural_urban_comparison.png'),
            dpi=200, bbox_inches='tight')
plt.close(fig)
print('\nSpillover rural/urban comparison saved')

# ═══════════════════════════════════════════════════════════
# PART 3: DIRECT vs SPILLOVER HEADLINE COMPARISON
# ═══════════════════════════════════════════════════════════
# The paper's main theoretical finding: rural alcohol crashes show
# OPPOSITE SIGNS between direct and spillover. 2x2 figure makes
# this immediate.

fig, axes = plt.subplots(2, 2, figsize=(14, 9))

# Row 1: RURAL (direct left, spillover right)
if 'alcohol_rural' in direct_parsed:
    d = direct_parsed['alcohol_rural']
    plot_event_study(axes[0, 0], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main='DIRECT effect',
                     title_sub='Rural newly-wet counties',
                     ylabel='Alcohol-involved crashes',
                     event_time_limit=5,
                     x_label='Years since wet transition')

if 'alcohol_rural' in spillover_parsed:
    d = spillover_parsed['alcohol_rural']
    plot_event_study(axes[0, 1], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main='SPILLOVER effect',
                     title_sub='Rural dry neighbors',
                     ylabel='Alcohol-involved crashes',
                     event_time_limit=5,
                     x_label='Years since first wet neighbor')

# Row 2: URBAN (direct left, spillover right)
if 'alcohol_urban' in direct_parsed:
    d = direct_parsed['alcohol_urban']
    plot_event_study(axes[1, 0], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main='DIRECT effect',
                     title_sub='Urban newly-wet counties',
                     ylabel='Alcohol-involved crashes',
                     event_time_limit=5,
                     x_label='Years since wet transition')

if 'alcohol_urban' in spillover_parsed:
    d = spillover_parsed['alcohol_urban']
    plot_event_study(axes[1, 1], d['coefs'],
                     avgs=d['avgs'], att=d['att'],
                     title_main='SPILLOVER effect',
                     title_sub='Urban dry neighbors',
                     ylabel='Alcohol-involved crashes',
                     event_time_limit=5,
                     x_label='Years since first wet neighbor')

# Unified y-axis per row for easier comparison
for row in (0, 1):
    y_lims = []
    for col in (0, 1):
        y_lims.append(axes[row, col].get_ylim())
    y_min = min(y[0] for y in y_lims)
    y_max = max(y[1] for y in y_lims)
    axes[row, 0].set_ylim(y_min, y_max)
    axes[row, 1].set_ylim(y_min, y_max)

fig.suptitle(
    'Headline Finding: Direct vs. Spillover Effects on Alcohol-Involved Crashes',
    fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.975])
fig.savefig(os.path.join(OUTDIR, 'HEADLINE_direct_vs_spillover_alcohol.png'),
            dpi=220, bbox_inches='tight')
plt.close(fig)
print('HEADLINE figure saved: direct vs spillover, rural/urban x alcohol')

# Same thing for fatal crashes (for appendix)
fig, axes = plt.subplots(2, 2, figsize=(14, 9))
for i, (side, row_label, sources) in enumerate([
        ('direct', 'Rural',
         [('fatal_rural', 'DIRECT\nNewly-wet counties', direct_parsed),
          ('fatal_rural', 'SPILLOVER\nDry neighbors', spillover_parsed)]),
        ('direct', 'Urban',
         [('fatal_urban', 'DIRECT\nNewly-wet counties', direct_parsed),
          ('fatal_urban', 'SPILLOVER\nDry neighbors', spillover_parsed)])]):
    for j, (tag, sub, parsed_dict) in enumerate(sources):
        if tag not in parsed_dict:
            continue
        d = parsed_dict[tag]
        side_label = 'DIRECT' if j == 0 else 'SPILLOVER'
        ax = axes[i, j]
        plot_event_study(ax, d['coefs'],
                         avgs=d['avgs'], att=d['att'],
                         title_main=side_label,
                         title_sub=f'{row_label} ({"newly-wet" if j == 0 else "dry neighbors"})',
                         ylabel=d['ylabel'],
                         event_time_limit=5,
                         x_label='Event time (years)')
    # Unify y-axis across row
    y_lims = [axes[i, c].get_ylim() for c in (0, 1)]
    y_min = min(y[0] for y in y_lims)
    y_max = max(y[1] for y in y_lims)
    axes[i, 0].set_ylim(y_min, y_max)
    axes[i, 1].set_ylim(y_min, y_max)

fig.suptitle('Direct vs. Spillover Effects on Fatal Crashes (appendix)',
             fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.975])
fig.savefig(os.path.join(OUTDIR, 'direct_vs_spillover_fatal.png'),
            dpi=200, bbox_inches='tight')
plt.close(fig)
print('Fatal comparison saved')

print('\n═══ Done. Outputs in', OUTDIR, '═══')
