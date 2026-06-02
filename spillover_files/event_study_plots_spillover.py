"""
event_study_plots_spillover.py

Parses 10 C&S-A spillover event-study tables from csdid_v3_spillover.log
and generates publication-quality PNGs in navy/gold palette.
"""

import re
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

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

LOG_PATH = '/mnt/user-data/uploads/csdid_v3_spillover.log'
with open(LOG_PATH, 'r') as f:
    log_text = f.read()

SPECS = [
    ('fatal_primaryplus_reg',   'Fatal crashes',            'Primary+ REG (log_pop + poverty)'),
    ('alcohol_primaryplus_reg', 'Alcohol-involved crashes', 'Primary+ REG (log_pop + poverty)'),
    ('fatal_dripw',             'Fatal crashes',            'DRIPW (log_pop only)'),
    ('alcohol_dripw',           'Alcohol-involved crashes', 'DRIPW (log_pop only)'),
    ('fatal_nocov',             'Fatal crashes',            'No covariates'),
    ('alcohol_nocov',           'Alcohol-involved crashes', 'No covariates'),
    ('fatal_rural',             'Fatal crashes',            'Rural subsample (pop < 20k)'),
    ('alcohol_rural',           'Alcohol-involved crashes', 'Rural subsample (pop < 20k)'),
    ('fatal_urban',             'Fatal crashes',            'Urban subsample (pop >= 20k)'),
    ('alcohol_urban',           'Alcohol-involved crashes', 'Urban subsample (pop >= 20k)'),
]
VALID_TAGS = set(tag for tag, _, _ in SPECS)

# Stata prints "-.062925" (no leading zero). Handle that:
NUM = r'(-?(?:\d+\.\d*|\.\d+|\d+)|\.)'


def find_spec_blocks():
    blocks = {}
    spec_positions = []
    for m in re.finditer(r'^SPEC:\s*(\S+)\s*\|', log_text, re.MULTILINE):
        tag = m.group(1)
        if tag in VALID_TAGS:
            spec_positions.append((m.start(), tag))
    spec_positions.append((len(log_text), None))

    for i in range(len(spec_positions) - 1):
        start, tag = spec_positions[i]
        end = spec_positions[i + 1][0]
        blocks[tag] = log_text[start:end]
    return blocks


def parse_event_study(block_text):
    es_start = block_text.find('Event Study:Dynamic effects')
    if es_start == -1:
        return []
    after = block_text[es_start:]
    next_block = after.find('ATT by Periods', 10)
    section = after[:next_block] if next_block > 0 else after

    row_re = re.compile(
        r'^\s*T([mp])(\d+)\s*\|\s*'
        + NUM + r'\s+' + NUM + r'\s+' + NUM + r'\s+' + NUM,
        re.MULTILINE
    )
    coefs = []
    for m in row_re.finditer(section):
        sign_char, t_num, coef, se, z, pval = m.groups()
        event_time = int(t_num) * (-1 if sign_char == 'm' else 1)
        try:
            coef_f = float(coef) if coef != '.' else None
            se_f = float(se) if se != '.' else None
            pval_f = float(pval) if pval != '.' else None
        except ValueError:
            continue
        coefs.append((event_time, coef_f, se_f, pval_f))
    coefs.sort(key=lambda x: x[0])
    return coefs


def parse_att_simple(block_text):
    m = re.search(
        r'Average Treatment Effect on Treated.*?'
        r'^\s*ATT\s*\|\s*'
        + NUM + r'\s+' + NUM + r'\s+' + NUM + r'\s+' + NUM,
        block_text, re.DOTALL | re.MULTILINE
    )
    if not m:
        return None
    try:
        return {'coef': float(m.group(1)),
                'se': float(m.group(2)),
                'pval': float(m.group(4))}
    except (ValueError, TypeError):
        return None


def plot_event_study(ax, coefs, att_info, title_main, title_sub, ylabel):
    if not coefs:
        ax.text(0.5, 0.5, 'No data parsed', transform=ax.transAxes,
                ha='center', va='center', color=RED, fontsize=11)
        ax.set_title(f'{title_main} - {title_sub}')
        return

    times = [c[0] for c in coefs]
    betas = [c[1] for c in coefs]
    ses   = [c[2] for c in coefs]
    ci_lo = [(b - 1.96*s) if (b is not None and s is not None) else None
             for b, s in zip(betas, ses)]
    ci_hi = [(b + 1.96*s) if (b is not None and s is not None) else None
             for b, s in zip(betas, ses)]

    plot_data = [(t, b, lo, hi) for t, b, lo, hi
                 in zip(times, betas, ci_lo, ci_hi) if b is not None]
    if not plot_data:
        return
    pt, pb, plo, phi = zip(*plot_data)

    ax.axvspan(min(pt) - 0.5, -0.5, color=MUTED, alpha=0.05, zorder=0)
    ax.axvspan(-0.5, max(pt) + 0.5, color=GOLD, alpha=0.06, zorder=0)
    ax.fill_between(pt, plo, phi, color=MUTED, alpha=0.25,
                    zorder=2, linewidth=0)
    ax.plot(pt, pb, color=NAVY, linewidth=1.8, zorder=4)
    ax.scatter(pt, pb, color=GOLD, s=50, zorder=5,
               edgecolors=NAVY, linewidth=0.9)

    ax.axhline(0, color=NAVY, linewidth=0.6, alpha=0.5, zorder=1)
    ax.axvline(-0.5, color=GOLD, linewidth=1.4, linestyle='--',
               alpha=0.85, zorder=3)

    ax.set_xlabel('Event time (years since first wet neighbor)',
                  fontsize=9.5)
    ax.set_ylabel(f'ATT: {ylabel}', fontsize=9.5)
    ax.xaxis.set_major_locator(mticker.MultipleLocator(1))
    ax.set_xlim(min(pt) - 0.5, max(pt) + 0.5)

    att_str = ''
    if att_info:
        sig = '***' if att_info['pval'] < 0.01 else \
              '**'  if att_info['pval'] < 0.05 else \
              '*'   if att_info['pval'] < 0.10 else ''
        att_str = (f'  |  Overall ATT = {att_info["coef"]:+.2f} '
                   f'({att_info["se"]:.2f}){sig}')
    ax.set_title(f'{title_main}: {title_sub}{att_str}', pad=8,
                 fontsize=10.5)

    y_top = max(phi)
    y_bot = min(plo)
    y_range = y_top - y_bot
    if y_range > 0:
        ax.text(-3, y_top + 0.10 * y_range, 'PRE', color=MUTED,
                fontweight='bold', fontsize=9, ha='center', alpha=0.7)
        ax.text(3, y_top + 0.10 * y_range, 'POST', color=GOLD,
                fontweight='bold', fontsize=9, ha='center', alpha=0.9)
    ax.grid(True, axis='y', alpha=0.4, zorder=0)


# ── Run ─────────────────────────────────────────────────────
os.makedirs('/home/claude/spillover_plots', exist_ok=True)

blocks = find_spec_blocks()
print(f'Found {len(blocks)} valid spec blocks')

parsed = {}
print('\nParsing:')
for tag, ylabel, sub_title in SPECS:
    if tag not in blocks:
        print(f'  MISSING: {tag}')
        continue
    coefs = parse_event_study(blocks[tag])
    att = parse_att_simple(blocks[tag])
    parsed[tag] = {'coefs': coefs, 'att': att,
                   'ylabel': ylabel, 'sub_title': sub_title}
    s = f'ATT={att["coef"]:+.3f} (p={att["pval"]:.3f})' if att else 'ATT=FAILED'
    print(f'  {tag}: {len(coefs)} coefs, {s}')

# Individual plots
print('\nIndividual plots:')
for tag, ylabel, sub_title in SPECS:
    if tag not in parsed:
        continue
    d = parsed[tag]
    headline = 'Fatal crashes' if 'fatal' in tag else 'Alcohol-involved crashes'
    fig, ax = plt.subplots(figsize=(9, 5))
    plot_event_study(ax, d['coefs'], d['att'],
                     headline, sub_title, ylabel)
    fig.tight_layout()
    out = f'/home/claude/spillover_plots/spillover_v3_{tag}_event.png'
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f'  {out}')

# Grid
fig, axes = plt.subplots(5, 2, figsize=(14, 20))
for i, (tag, ylabel, sub_title) in enumerate(SPECS):
    if tag not in parsed:
        continue
    d = parsed[tag]
    headline = 'Fatal' if 'fatal' in tag else 'Alcohol'
    plot_event_study(axes[i // 2, i % 2], d['coefs'], d['att'],
                     headline, sub_title, ylabel)
fig.suptitle('Spillover Event Studies: All C&S-A Specifications',
             fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.992])
fig.savefig('/home/claude/spillover_plots/spillover_v3_grid_all.png',
            dpi=180, bbox_inches='tight')
plt.close(fig)
print('\nGrid plot saved')

# Rural vs urban
fig, axes = plt.subplots(2, 2, figsize=(13, 9))
comp = [('fatal_rural', 'Fatal crashes', 'RURAL'),
        ('fatal_urban', 'Fatal crashes', 'URBAN'),
        ('alcohol_rural', 'Alcohol-involved crashes', 'RURAL'),
        ('alcohol_urban', 'Alcohol-involved crashes', 'URBAN')]
for i, (tag, ylabel, geo) in enumerate(comp):
    if tag not in parsed:
        continue
    d = parsed[tag]
    outcome = 'Fatal' if 'fatal' in tag else 'Alcohol'
    plot_event_study(axes[i // 2, i % 2], d['coefs'], d['att'],
                     outcome, geo + ' subsample', ylabel)
fig.suptitle('Spillover Heterogeneity: Rural vs. Urban (Primary+ REG)',
             fontsize=14, fontweight='bold', color=NAVY, y=0.995)
fig.tight_layout(rect=[0, 0, 1, 0.975])
fig.savefig('/home/claude/spillover_plots/spillover_v3_rural_urban_comparison.png',
            dpi=200, bbox_inches='tight')
plt.close(fig)
print('Rural/urban comparison saved')
print('\nDone.')
