"""
Publication-Quality Event-Study Plots
C&S-A Estimation: Primary Specification (Not-Yet-Treated Only)

Produces three figures:
  1. Fatal crashes event study (standalone)
  2. Alcohol-involved fatal crashes event study (standalone)
  3. Side-by-side panel (for paper/presentation)

Data: estat event output from 02_csdid_estimation_v2.do
To use exported CSVs instead, uncomment the CSV-reading block.
"""

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

# ═══════════════════════════════════════════════════════════
# COEFFICIENTS FROM STATA (primary spec, NYT only, DRIPW)
# ═══════════════════════════════════════════════════════════

fatal_data = {
    'Tm11': (1.500, 0.791), 'Tm10': (0.500, 0.791),
    'Tm9': (3.417, 1.680), 'Tm8': (-4.250, 1.662),
    'Tm7': (1.550, 1.368), 'Tm6': (-2.413, 0.956),
    'Tm5': (-0.469, 1.764), 'Tm4': (1.944, 1.607),
    'Tm3': (0.619, 1.266), 'Tm2': (-0.190, 1.509),
    'Tm1': (1.318, 1.617),
    'Tp0': (0.462, 1.201), 'Tp1': (-2.706, 0.692),
    'Tp2': (-3.367, 1.402), 'Tp3': (-2.200, 1.881),
    'Tp4': (-0.124, 2.759), 'Tp5': (-1.139, 1.743),
    'Tp6': (0.283, 1.737), 'Tp7': (1.975, 2.380),
    'Tp8': (6.500, 3.661), 'Tp9': (-1.500, 1.225),
    'Tp10': (0.500, 1.458),
}

alcohol_data = {
    'Tm11': (2.500, 1.061), 'Tm10': (0.500, 0.791),
    'Tm9': (0.750, 0.351), 'Tm8': (-0.750, 0.415),
    'Tm7': (-0.688, 0.879), 'Tm6': (-1.275, 0.781),
    'Tm5': (0.036, 0.548), 'Tm4': (1.375, 0.954),
    'Tm3': (-0.583, 0.700), 'Tm2': (1.279, 0.867),
    'Tm1': (-0.027, 1.196),
    'Tp0': (0.427, 0.984), 'Tp1': (-1.498, 0.664),
    'Tp2': (-1.360, 0.671), 'Tp3': (-0.538, 0.979),
    'Tp4': (-0.633, 1.191), 'Tp5': (-1.822, 1.175),
    'Tp6': (-0.283, 1.095), 'Tp7': (-0.925, 1.230),
    'Tp8': (2.625, 2.253), 'Tp9': (-2.750, 1.883),
    'Tp10': (-2.500, 1.458),
}

# ── To use exported CSVs instead: ────────────────────────────
# import csv
# def load_csv(path):
#     d = {}
#     for row in csv.DictReader(open(path)):
#         t = row['term'].strip()
#         if t.startswith('Tm') or t.startswith('Tp'):
#             d[t] = (float(row['coef']), float(row['se']))
#     return d
# fatal_data = load_csv('output/event_study_fatal_nyt.csv')
# alcohol_data = load_csv('output/event_study_alcohol_nyt.csv')


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
ax1.text(0.5, 1.02, 'Callaway & Sant\'Anna (2021), not-yet-treated comparison',
         transform=ax1.transAxes, fontsize=9, color=MUTED, ha='center',
         style='italic')
add_legend(ax1)
fig1.tight_layout()
fig1.savefig('/home/claude/es_fatal_nyt_publication.png',
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig1)
print("Saved: es_fatal_nyt_publication.png")

# Alcohol crashes
fig2, ax2 = plt.subplots(figsize=(10, 5.5))
draw(ax2, prep(alcohol_data), 'ATT (alcohol fatal crashes per county-year)')
ax2.set_title('Effect of Wet Transition on Alcohol-Involved Fatal Crashes',
              fontsize=13, fontweight='bold', color=NAVY, pad=14)
ax2.text(0.5, 1.02, 'Callaway & Sant\'Anna (2021), not-yet-treated comparison',
         transform=ax2.transAxes, fontsize=9, color=MUTED, ha='center',
         style='italic')
add_legend(ax2)
fig2.tight_layout()
fig2.savefig('/home/claude/es_alcohol_nyt_publication.png',
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig2)
print("Saved: es_alcohol_nyt_publication.png")

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

fig3.suptitle('Event Study: C&S-A ATT Estimates (Not-Yet-Treated Comparison)',
              fontsize=13, fontweight='bold', color=NAVY, y=1.02)
fig3.tight_layout()
fig3.savefig('/home/claude/es_panel_publication.png',
             dpi=300, bbox_inches='tight', facecolor='white')
plt.close(fig3)
print("Saved: es_panel_publication.png")

print("\nAll publication figures generated.")
