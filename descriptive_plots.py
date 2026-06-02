"""
Descriptive Plots for Arkansas Wet/Dry DiD Panel
Produces four figures:
  1. Raw time series: treated vs neighbor (fatal crashes)
  2. Raw time series: treated vs neighbor (alcohol-involved fatal crashes)
  3. Event-time plot: fatal crashes (treated counties, centered on transition)
  4. Event-time plot: alcohol crashes (treated counties, centered on transition)
"""

import csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from collections import defaultdict
import statistics
import math

# ── Load data ───────────────────────────────────────────────
rows = list(csv.DictReader(open('/mnt/project/arkansas_did_panel.csv')))

# ── Color palette (matching Beamer) ─────────────────────────
NAVY = '#1A2744'
NAVY_MID = '#243560'
GOLD = '#C9A84C'
MUTED = '#8C9BB5'
OFFWHITE = '#F4F4F0'
LGRAY = '#E8EBF2'
RED_ACCENT = '#C75146'

plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 10,
    'axes.facecolor': OFFWHITE,
    'figure.facecolor': 'white',
    'axes.edgecolor': MUTED,
    'axes.labelcolor': NAVY,
    'xtick.color': NAVY,
    'ytick.color': NAVY,
    'grid.color': LGRAY,
    'grid.linewidth': 0.6,
})

# ═══════════════════════════════════════════════════════════
# FIGURES 1 & 2: Raw Time Series by Group
# ═══════════════════════════════════════════════════════════

year_data = defaultdict(lambda: {
    'treated_fatal': [], 'treated_alc': [],
    'neighbor_fatal': [], 'neighbor_alc': []
})

for r in rows:
    yr = int(r['year'])
    fc = int(r['fatal_crashes'])
    ac = int(r['alcohol_fatal_crashes'])
    if r['treated_unit'] == '1':
        year_data[yr]['treated_fatal'].append(fc)
        year_data[yr]['treated_alc'].append(ac)
    elif r['neighbor_unit'] == '1':
        year_data[yr]['neighbor_fatal'].append(fc)
        year_data[yr]['neighbor_alc'].append(ac)

years = sorted(year_data.keys())

def mean_se(vals):
    m = statistics.mean(vals)
    se = statistics.stdev(vals) / math.sqrt(len(vals)) if len(vals) > 1 else 0
    return m, se

# Extract means and SEs
tf_means = [mean_se(year_data[y]['treated_fatal']) for y in years]
nf_means = [mean_se(year_data[y]['neighbor_fatal']) for y in years]
ta_means = [mean_se(year_data[y]['treated_alc']) for y in years]
na_means = [mean_se(year_data[y]['neighbor_alc']) for y in years]

def plot_time_series(ax, years, treated_ms, neighbor_ms, ylabel, title, 
                     treatment_years=None):
    t_m = [x[0] for x in treated_ms]
    t_se = [x[1] for x in treated_ms]
    n_m = [x[0] for x in neighbor_ms]
    n_se = [x[1] for x in neighbor_ms]
    
    ax.fill_between(years, [m-1.96*s for m,s in treated_ms], 
                    [m+1.96*s for m,s in treated_ms],
                    color=GOLD, alpha=0.15)
    ax.fill_between(years, [m-1.96*s for m,s in neighbor_ms],
                    [m+1.96*s for m,s in neighbor_ms],
                    color=MUTED, alpha=0.12)
    
    ax.plot(years, t_m, color=GOLD, linewidth=2.2, marker='o', markersize=4.5,
            label='Treated (newly wet)', zorder=5)
    ax.plot(years, n_m, color=NAVY_MID, linewidth=2.2, marker='s', markersize=4,
            label='Neighbor counties', zorder=5)
    
    # Shade post-2020 region for FARS discontinuity
    ax.axvspan(2020.5, max(years)+0.5, color=RED_ACCENT, alpha=0.06, zorder=0)
    ax.annotate('FARS\ndiscontinuity', xy=(2021.5, ax.get_ylim()[1]*0.92 if ax.get_ylim()[1] > 0 else 2),
                fontsize=7, color=RED_ACCENT, ha='center', style='italic')
    
    ax.set_xlabel('Year', fontsize=10)
    ax.set_ylabel(ylabel, fontsize=10)
    ax.set_title(title, fontsize=12, fontweight='bold', color=NAVY, pad=10)
    ax.legend(loc='upper left', fontsize=8, framealpha=0.9)
    ax.grid(True, axis='y', alpha=0.5)
    ax.set_xlim(min(years)-0.3, max(years)+0.3)
    ax.xaxis.set_major_locator(mticker.MultipleLocator(2))

# Figure 1: Fatal crashes time series
fig1, ax1 = plt.subplots(figsize=(10, 5))
plot_time_series(ax1, years, tf_means, nf_means,
                 'Mean Fatal Crashes per County',
                 'Fatal Crashes: Treated vs. Neighbor Counties (2008–2023)')
fig1.tight_layout()
fig1.savefig('/home/claude/fig1_fatal_timeseries.png', dpi=200, bbox_inches='tight')

# Figure 2: Alcohol crashes time series
fig2, ax2 = plt.subplots(figsize=(10, 5))
plot_time_series(ax2, years, ta_means, na_means,
                 'Mean Alcohol-Involved Fatal Crashes per County',
                 'Alcohol-Involved Fatal Crashes: Treated vs. Neighbor Counties (2008–2023)')
fig2.tight_layout()
fig2.savefig('/home/claude/fig2_alcohol_timeseries.png', dpi=200, bbox_inches='tight')


# ═══════════════════════════════════════════════════════════
# FIGURES 3 & 4: Event-Time Plots (Treated Counties)
# ═══════════════════════════════════════════════════════════

event_data = defaultdict(lambda: {'fatal': [], 'alc': []})

for r in rows:
    if r['treated_unit'] == '1' and r['cohort']:
        cohort_yr = int(r['cohort'])
        yr = int(r['year'])
        rel = yr - cohort_yr
        fc = int(r['fatal_crashes'])
        ac = int(r['alcohol_fatal_crashes'])
        event_data[rel]['fatal'].append(fc)
        event_data[rel]['alc'].append(ac)

# Trim to balanced-ish window: -8 to +8 (decent N throughout)
rel_times = sorted([t for t in event_data if -8 <= t <= 8])
fatal_es = [mean_se(event_data[t]['fatal']) for t in rel_times]
alc_es = [mean_se(event_data[t]['alc']) for t in rel_times]
ns = [len(event_data[t]['fatal']) for t in rel_times]

def plot_event_study(ax, rel_times, means_ses, ns, ylabel, title):
    means = [x[0] for x in means_ses]
    ses = [x[1] for x in means_ses]
    ci_lo = [m - 1.96*s for m, s in means_ses]
    ci_hi = [m + 1.96*s for m, s in means_ses]
    
    # Vertical line at t=0
    ax.axvline(x=-0.5, color=GOLD, linewidth=1.5, linestyle='--', alpha=0.7, 
               label='Treatment onset')
    
    # Shade pre vs post
    ax.axvspan(min(rel_times)-0.5, -0.5, color=MUTED, alpha=0.04, zorder=0)
    ax.axvspan(-0.5, max(rel_times)+0.5, color=GOLD, alpha=0.04, zorder=0)
    
    # CI band
    ax.fill_between(rel_times, ci_lo, ci_hi, color=NAVY_MID, alpha=0.15)
    
    # Line + markers
    ax.plot(rel_times, means, color=NAVY, linewidth=2, marker='o', markersize=5,
            zorder=5, label='Mean outcome')
    
    # Sample size annotation
    for t, n, m in zip(rel_times, ns, means):
        if t % 2 == 0:  # annotate every other point to reduce clutter
            ax.annotate(f'n={n}', xy=(t, m), xytext=(0, -18),
                       textcoords='offset points', fontsize=6.5, color=MUTED,
                       ha='center')
    
    ax.set_xlabel('Years Relative to Wet Transition', fontsize=10)
    ax.set_ylabel(ylabel, fontsize=10)
    ax.set_title(title, fontsize=12, fontweight='bold', color=NAVY, pad=10)
    ax.legend(loc='upper left', fontsize=8, framealpha=0.9)
    ax.grid(True, axis='y', alpha=0.5)
    ax.xaxis.set_major_locator(mticker.MultipleLocator(1))
    
    # Add pre/post labels
    ax.text(-4.5, ax.get_ylim()[1]*0.95, 'PRE', fontsize=8, color=MUTED, 
            ha='center', fontweight='bold', alpha=0.6)
    ax.text(4, ax.get_ylim()[1]*0.95, 'POST', fontsize=8, color=GOLD,
            ha='center', fontweight='bold', alpha=0.6)

# Figure 3: Event-time fatal crashes
fig3, ax3 = plt.subplots(figsize=(10, 5.5))
plot_event_study(ax3, rel_times, fatal_es, ns,
                 'Mean Fatal Crashes per County',
                 'Event Study: Fatal Crashes in Treated Counties (t=0 is Wet Transition)')
fig3.tight_layout()
fig3.savefig('/home/claude/fig3_event_fatal.png', dpi=200, bbox_inches='tight')

# Figure 4: Event-time alcohol crashes
fig4, ax4 = plt.subplots(figsize=(10, 5.5))
plot_event_study(ax4, rel_times, alc_es, ns,
                 'Mean Alcohol-Involved Fatal Crashes per County',
                 'Event Study: Alcohol-Involved Fatal Crashes in Treated Counties')
fig4.tight_layout()
fig4.savefig('/home/claude/fig4_event_alcohol.png', dpi=200, bbox_inches='tight')

# ═══════════════════════════════════════════════════════════
# FIGURE 5: Cohort composition over event time
# ═══════════════════════════════════════════════════════════

cohort_at_t = defaultdict(lambda: defaultdict(int))
for r in rows:
    if r['treated_unit'] == '1' and r['cohort']:
        cohort_yr = int(r['cohort'])
        yr = int(r['year'])
        rel = yr - cohort_yr
        if -8 <= rel <= 8:
            cohort_at_t[rel][cohort_yr] += 1

fig5, ax5 = plt.subplots(figsize=(10, 4))
cohorts_all = sorted(set(c for t in cohort_at_t for c in cohort_at_t[t]))
colors_cohort = [GOLD, '#D4A84C', '#9B7D3C', NAVY_MID, MUTED, '#6B7FA5', RED_ACCENT]

bottom = [0] * len(rel_times)
for i, c in enumerate(cohorts_all):
    vals = [cohort_at_t[t].get(c, 0) for t in rel_times]
    ax5.bar(rel_times, vals, bottom=bottom, width=0.8,
            color=colors_cohort[i % len(colors_cohort)], 
            label=f'Cohort {c}', edgecolor='white', linewidth=0.5)
    bottom = [b + v for b, v in zip(bottom, vals)]

ax5.axvline(x=-0.5, color=NAVY, linewidth=1.5, linestyle='--', alpha=0.5)
ax5.set_xlabel('Years Relative to Wet Transition', fontsize=10)
ax5.set_ylabel('Number of Counties', fontsize=10)
ax5.set_title('Cohort Composition at Each Event Time', fontsize=12, 
              fontweight='bold', color=NAVY, pad=10)
ax5.legend(loc='upper left', fontsize=7, ncol=4, framealpha=0.9)
ax5.xaxis.set_major_locator(mticker.MultipleLocator(1))
ax5.grid(True, axis='y', alpha=0.3)
fig5.tight_layout()
fig5.savefig('/home/claude/fig5_cohort_composition.png', dpi=200, bbox_inches='tight')

print("All 5 figures saved successfully.")
