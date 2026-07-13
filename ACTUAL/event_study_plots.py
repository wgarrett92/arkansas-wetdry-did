"""
Publication-Quality Event-Study Plots
C&S-A Estimation: HEADLINE Specification (within-county, always-dry controls)

Produces, in ./output/:
  1. es_fatal_headline_publication.png     (standalone)
  2. es_alcohol_headline_publication.png   (standalone)
  3. es_panel_headline_publication.png      (side-by-side, for paper)

Data source: event-time coefficients exported by 02_csdid_estimation_v2.do
Section 6d ->  output/event_study_{fatal,alcohol}_headline.csv
(term,coef,se,p with terms Pre_avg Post_avg Tm.. Tp..; we plot Tm*/Tp* only).

PROVENANCE / WHY THIS SPEC: the headline is the within-county design (treated +
always-DRY never-treated controls, gvar(cohort), method(reg), notyet,
xvars(log_pop poverty_rate)) -- the only spec with clean fatal AND alcohol
pre-trends (fatal Pre_avg p=0.807, alcohol p=0.732). Promoted to headline
2026-07-01; see ANALYSIS_LOG.txt entry #13 and README "Specifications".
The previous not-yet-treated figures (primary_event_*.png, made in Stata) are
retained as Robustness D.
"""

import csv
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# ── Color palette (matching Beamer) ─────────────────────────
NAVY      = '#1A2744'
NAVY_MID  = '#243560'
GOLD      = '#C9A84C'
MUTED     = '#8C9BB5'
OFFWHITE  = '#F4F4F0'
LGRAY     = '#E8EBF2'
TEAL      = '#2A7F6F'

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

OUTDIR = 'output'
SUBTITLE = "Callaway & Sant'Anna (2021), within-county design (always-dry controls)"


# ── Load event-time coefficients from the headline CSVs ──────
def load_csv(path):
    d = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            t = row['term'].strip()
            if not (t.startswith('Tm') or t.startswith('Tp')):
                continue
            try:
                d[t] = (float(row['coef']), float(row['se']))
            except (ValueError, KeyError):
                # missing/non-numeric cell (e.g. "."): skip that term
                continue
    if not d:
        raise ValueError(f"No Tm*/Tp* event-time terms parsed from {path}")
    return d


fatal_data   = load_csv(os.path.join(OUTDIR, 'event_study_fatal_headline.csv'))
alcohol_data = load_csv(os.path.join(OUTDIR, 'event_study_alcohol_headline.csv'))


def parse_t(term):
    if term.startswith('Tm'): return -int(term[2:])
    if term.startswith('Tp'): return int(term[2:])


def prep(data, lo=-8, hi=8):
    pts = []
    for term, (c, se) in data.items():
        t = parse_t(term)
        if t is not None and lo <= t <= hi:
            ci_l, ci_h = c - 1.96*se, c + 1.96*se
            pts.append((t, c, ci_l, ci_h, (ci_l > 0) or (ci_h < 0)))
    pts.sort()
    return pts


def draw(ax, pts, ylabel):
    ts = [p[0] for p in pts]
    cs = [p[1] for p in pts]
    los = [p[2] for p in pts]
    his = [p[3] for p in pts]
    sigs = [p[4] for p in pts]

    ax.axhline(y=0, color=MUTED, lw=0.8, alpha=0.5)
    ax.axvline(x=-0.5, color=GOLD, lw=1.8, ls='--', alpha=0.7)
    ax.axvspan(-8.5, -0.5, color=MUTED, alpha=0.03)
    ax.axvspan(-0.5, 8.5, color=GOLD, alpha=0.03)

    for t, c, lo, hi, s in zip(ts, cs, los, his, sigs):
        col = TEAL if s else MUTED
        alp = 0.9 if s else 0.4
        ax.plot([t, t], [lo, hi], color=col, lw=2.0, alpha=alp,
                solid_capstyle='round', zorder=3)

    for t, c, s in zip(ts, cs, sigs):
        mc = TEAL if s else NAVY_MID
        ax.plot(t, c, 'o', color=mc, ms=6.5, mec='white', mew=1.1, zorder=5)

    ax.plot(ts, cs, color=NAVY_MID, lw=0.9, alpha=0.35, zorder=2)

    ax.set_xlabel('Years relative to wet transition', fontsize=10, labelpad=6)
    ax.set_ylabel(ylabel, fontsize=10, labelpad=6)
    ax.set_xlim(-8.6, 8.6)
    ax.xaxis.set_major_locator(mticker.MultipleLocator(1))
    ax.grid(True, axis='y', alpha=0.4, lw=0.5)
    ax.grid(False, axis='x')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_linewidth(0.5)
    ax.spines['bottom'].set_linewidth(0.5)


def add_legend(ax):
    from matplotlib.lines import Line2D
    elems = [
        Line2D([0], [0], marker='o', color='w', mfc=TEAL, ms=7,
               mec='white', mew=1.1, label='Significant (p < 0.05)'),
        Line2D([0], [0], marker='o', color='w', mfc=NAVY_MID, ms=7,
               mec='white', mew=1.1, label='Not significant'),
        Line2D([0], [0], color=GOLD, lw=1.8, ls='--',
               label='Treatment onset'),
    ]
    ax.legend(handles=elems, loc='upper left', fontsize=8,
              framealpha=0.9, edgecolor=LGRAY)


# ═══════════════════════════════════════════════════════════
# STANDALONE FIGURES
# ═══════════════════════════════════════════════════════════

# Fatal crashes
fig1, ax1 = plt.subplots(figsize=(10, 5.5))
draw(ax1, prep(fatal_data), 'ATT (fatal crashes per county-year)')
ax1.set_title('Effect of Wet Transition on Fatal Crashes',
              fontsize=13, fontweight='bold', color=NAVY, pad=14)
ax1.text(0.5, 1.02, SUBTITLE,
         transform=ax1.transAxes, fontsize=9, color=MUTED, ha='center',
         style='italic')
add_legend(ax1)
fig1.tight_layout()
fig1.savefig(os.path.join(OUTDIR, 'es_fatal_headline_publication.png'),
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig1)
print("Saved: output/es_fatal_headline_publication.png")

# Alcohol crashes
fig2, ax2 = plt.subplots(figsize=(10, 5.5))
draw(ax2, prep(alcohol_data), 'ATT (alcohol fatal crashes per county-year)')
ax2.set_title('Effect of Wet Transition on Alcohol-Involved Fatal Crashes',
              fontsize=13, fontweight='bold', color=NAVY, pad=14)
ax2.text(0.5, 1.02, SUBTITLE,
         transform=ax2.transAxes, fontsize=9, color=MUTED, ha='center',
         style='italic')
add_legend(ax2)
fig2.tight_layout()
fig2.savefig(os.path.join(OUTDIR, 'es_alcohol_headline_publication.png'),
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig2)
print("Saved: output/es_alcohol_headline_publication.png")

# ═══════════════════════════════════════════════════════════
# PANEL FIGURE (side-by-side for paper)
# ═══════════════════════════════════════════════════════════

fig3, (ax3a, ax3b) = plt.subplots(1, 2, figsize=(14, 5.5))

draw(ax3a, prep(fatal_data), 'ATT (fatal crashes)')
ax3a.set_title('(a) Fatal crashes', fontsize=11, fontweight='bold',
               color=NAVY, pad=10)
ax3a.xaxis.set_major_locator(mticker.MultipleLocator(2))
add_legend(ax3a)

draw(ax3b, prep(alcohol_data), 'ATT (alcohol crashes)')
ax3b.set_title('(b) Alcohol-involved fatal crashes', fontsize=11,
               fontweight='bold', color=NAVY, pad=10)
ax3b.xaxis.set_major_locator(mticker.MultipleLocator(2))

fig3.suptitle('Event Study: C&S-A ATT (within-county design, always-dry controls)',
              fontsize=13, fontweight='bold', color=NAVY, y=1.02)
fig3.tight_layout()
fig3.savefig(os.path.join(OUTDIR, 'es_panel_headline_publication.png'),
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig3)
print("Saved: output/es_panel_headline_publication.png")

print("\nAll HEADLINE publication figures generated (within-county always-dry).")
