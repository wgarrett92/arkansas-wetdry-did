"""
Event-Study Plots for Beamer Presentation
==========================================
Reads C&S-A event-study CSVs exported from 02_csdid_estimation_v3.do
and produces publication-quality figures matching Beamer navy/gold palette.

Outputs (for Beamer figs/ directory):
  1. primary_event_studies.png  — Primary spec, fatal + alcohol
  2. rural_urban_event.png      — 2x2 grid, rural/urban x fatal/alcohol
  3. pc_event_fatal.pdf         — Per-capita fatal crashes
  4. pc_event_alcohol.pdf       — Per-capita alcohol crashes

Expects CSVs in ./output_v3/ or edit INPUT_DIR below.
Writes figures to ./figs/ (created if missing).

Usage:
  python event_study_plots_v3.py
"""

import csv
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# ── Configuration ───────────────────────────────────────────
INPUT_DIR = "output_v3"
OUTPUT_DIR = "figs"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Beamer color palette
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
    'axes.facecolor': 'white',
    'figure.facecolor': 'white',
    'axes.edgecolor': MUTED,
    'axes.labelcolor': NAVY,
    'xtick.color': NAVY,
    'ytick.color': NAVY,
    'grid.color': LGRAY,
    'grid.linewidth': 0.6,
    'axes.titleweight': 'bold',
    'axes.titlesize': 11,
})


# ── Load event-study CSV ────────────────────────────────────
def load_es(filename):
    """
    Returns dict with lists: event_time, coef, se, ci_lo, ci_hi, pvalue
    Only includes numeric event_time rows (Tm/Tp), not Pre_avg/Post_avg.
    Sorted by event_time ascending.
    """
    path = os.path.join(INPUT_DIR, filename)
    data = {'event_time': [], 'coef': [], 'se': [],
            'ci_lo': [], 'ci_hi': [], 'pvalue': []}

    with open(path) as f:
        reader = csv.DictReader(f)
        for r in reader:
            et = r['event_time']
            try:
                et_num = int(et)
            except ValueError:
                continue  # skip Pre_avg, Post_avg
            try:
                data['event_time'].append(et_num)
                data['coef'].append(float(r['coef']))
                data['se'].append(float(r['se']))
                data['ci_lo'].append(float(r['ci_lower']))
                data['ci_hi'].append(float(r['ci_upper']))
                data['pvalue'].append(float(r['pvalue']))
            except (ValueError, KeyError):
                continue

    # Sort by event_time
    order = sorted(range(len(data['event_time'])),
                   key=lambda i: data['event_time'][i])
    for k in data:
        data[k] = [data[k][i] for i in order]

    return data


# ── Plotting helper ─────────────────────────────────────────
def plot_event_study(ax, data, title, ylabel='',
                     color=NAVY, window=(-10, 10),
                     show_pretrend_shade=True):
    """Plot a single event study on given axis."""

    # Filter to window
    pts = [(t, c, lo, hi, p) for t, c, lo, hi, p in zip(
        data['event_time'], data['coef'], data['ci_lo'],
        data['ci_hi'], data['pvalue'])
        if window[0] <= t <= window[1]]

    if not pts:
        ax.text(0.5, 0.5, 'No data in window',
                ha='center', va='center', transform=ax.transAxes)
        ax.set_title(title)
        return

    ts = [p[0] for p in pts]
    coefs = [p[1] for p in pts]
    lows = [p[2] for p in pts]
    highs = [p[3] for p in pts]
    pvals = [p[4] for p in pts]

    # Pre/post shading
    if show_pretrend_shade:
        ax.axvspan(min(ts) - 0.5, -0.5, color=MUTED, alpha=0.05, zorder=0)
        ax.axvspan(-0.5, max(ts) + 0.5, color=GOLD, alpha=0.05, zorder=0)

    # Zero line
    ax.axhline(y=0, color=MUTED, linewidth=0.8, linestyle='-',
               alpha=0.6, zorder=1)

    # Treatment onset line
    ax.axvline(x=-0.5, color=GOLD, linewidth=1.5, linestyle='--',
               alpha=0.8, zorder=2)

    # Error bars (95% CI)
    ax.errorbar(ts, coefs,
                yerr=[[c - l for c, l in zip(coefs, lows)],
                      [h - c for c, h in zip(coefs, highs)]],
                fmt='none', ecolor=color, elinewidth=1.2,
                capsize=3, capthick=1.2, alpha=0.7, zorder=4)

    # Points - significant ones filled, insignificant hollow
    for t, c, p in zip(ts, coefs, pvals):
        if p < 0.05:
            ax.plot(t, c, 'o', color=color, markersize=7,
                    markeredgecolor=color, markeredgewidth=1.5, zorder=5)
        else:
            ax.plot(t, c, 'o', color='white', markersize=7,
                    markeredgecolor=color, markeredgewidth=1.5, zorder=5)

    # Pre/post labels
    ylim = ax.get_ylim()
    y_label = ylim[1] - 0.05 * (ylim[1] - ylim[0])
    ax.text(window[0] + 1, y_label, 'PRE',
            fontsize=8, color=MUTED, fontweight='bold', alpha=0.7,
            ha='left', va='top')
    ax.text(window[1] - 1, y_label, 'POST',
            fontsize=8, color=GOLD, fontweight='bold', alpha=0.8,
            ha='right', va='top')

    # Formatting
    ax.set_xlabel('Years Relative to Wet Transition', fontsize=9)
    if ylabel:
        ax.set_ylabel(ylabel, fontsize=9)
    ax.set_title(title, color=NAVY, pad=8)
    ax.grid(True, axis='y', alpha=0.4)
    ax.xaxis.set_major_locator(mticker.MultipleLocator(2))
    ax.set_xlim(window[0] - 0.5, window[1] + 0.5)


# ── FIGURE 1: Primary event studies (fatal + alcohol) ───────
def fig_primary_event_studies():
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.5))

    fatal = load_es('es_fatal_primary.csv')
    alc = load_es('es_alcohol_primary.csv')

    plot_event_study(axes[0], fatal,
                     title='Fatal Crashes',
                     ylabel='ATT (crashes per county-year)',
                     color=NAVY)
    plot_event_study(axes[1], alc,
                     title='Alcohol-Involved Fatal Crashes',
                     ylabel='ATT (crashes per county-year)',
                     color=NAVY_MID)

    fig.suptitle('Primary Specification: DRIPW + log_pop + not-yet-treated',
                 fontsize=12, fontweight='bold', color=NAVY, y=1.02)

    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, 'primary_event_studies.png')
    fig.savefig(out, dpi=220, bbox_inches='tight')
    plt.close(fig)
    print(f"  Saved: {out}")


# ── FIGURE 2: Rural vs Urban (2x2 grid) ─────────────────────
def fig_rural_urban():
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))

    rural_fatal = load_es('es_fatal_rural.csv')
    rural_alc = load_es('es_alcohol_rural.csv')
    urban_fatal = load_es('es_fatal_urban.csv')
    urban_alc = load_es('es_alcohol_urban.csv')

    # Top row: fatal crashes
    plot_event_study(axes[0, 0], rural_fatal,
                     title='Rural (pop < 20k) — Fatal Crashes',
                     ylabel='ATT',
                     color=RED_ACCENT, window=(-5, 6))
    plot_event_study(axes[0, 1], urban_fatal,
                     title='Urban (pop ≥ 20k) — Fatal Crashes',
                     ylabel='ATT',
                     color=NAVY, window=(-7, 12))

    # Bottom row: alcohol crashes
    plot_event_study(axes[1, 0], rural_alc,
                     title='Rural (pop < 20k) — Alcohol Crashes',
                     ylabel='ATT',
                     color=RED_ACCENT, window=(-5, 6))
    plot_event_study(axes[1, 1], urban_alc,
                     title='Urban (pop ≥ 20k) — Alcohol Crashes',
                     ylabel='ATT',
                     color=NAVY, window=(-7, 12))

    fig.suptitle('Rural vs. Urban Heterogeneity: Opposite-Signed Effects',
                 fontsize=13, fontweight='bold', color=NAVY, y=1.00)

    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, 'rural_urban_event.png')
    fig.savefig(out, dpi=220, bbox_inches='tight')
    plt.close(fig)
    print(f"  Saved: {out}")


# ── FIGURE 3 & 4: Per-capita outcomes ───────────────────────
def fig_per_capita():
    # Fatal pc
    fatal_pc = load_es('es_fatal_pc_primary.csv')
    fig, ax = plt.subplots(figsize=(10, 4.5))
    plot_event_study(ax, fatal_pc,
                     title='Per-Capita Event Study: Fatal Crashes',
                     ylabel='ATT (crashes per 100,000 pop)',
                     color=NAVY)
    fig.suptitle('Primary Spec, Per-Capita Outcome',
                 fontsize=11, color=MUTED, y=1.02)
    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, 'pc_event_fatal.pdf')
    fig.savefig(out, bbox_inches='tight')
    plt.close(fig)
    print(f"  Saved: {out}")

    # Alcohol pc
    alc_pc = load_es('es_alcohol_pc_primary.csv')
    fig, ax = plt.subplots(figsize=(10, 4.5))
    plot_event_study(ax, alc_pc,
                     title='Per-Capita Event Study: Alcohol-Involved Fatal Crashes',
                     ylabel='ATT (crashes per 100,000 pop)',
                     color=NAVY_MID)
    fig.suptitle('Primary Spec, Per-Capita Outcome',
                 fontsize=11, color=MUTED, y=1.02)
    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, 'pc_event_alcohol.pdf')
    fig.savefig(out, bbox_inches='tight')
    plt.close(fig)
    print(f"  Saved: {out}")


# ── Main ────────────────────────────────────────────────────
if __name__ == "__main__":
    print(f"Reading CSVs from: {INPUT_DIR}/")
    print(f"Writing figures to: {OUTPUT_DIR}/")
    print()

    print("Figure 1: Primary event studies...")
    fig_primary_event_studies()

    print("Figure 2: Rural vs Urban heterogeneity...")
    fig_rural_urban()

    print("Figure 3 & 4: Per-capita outcomes...")
    fig_per_capita()

    print()
    print("All figures saved.")
    print()
    print("Beamer usage:")
    print("  primary_event_studies.png -> figs/primary_event_studies.png")
    print("  rural_urban_event.png      -> figs/rural_urban_event.png")
    print("  pc_event_fatal.pdf         -> figs/pc_event_fatal.pdf")
    print("  pc_event_alcohol.pdf       -> figs/pc_event_alcohol.pdf")
