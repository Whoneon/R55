#!/usr/bin/env python3
"""
Generate publication-quality figures for the R(5,5) paper.

Reads from results/metrics/ and outputs to paper/figures/.
Re-runnable: updates figures as new data arrives.

Usage: python3 src/plot_metrics.py
"""

import os
import sys
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap
from pathlib import Path

# Paths
BASE = Path(__file__).resolve().parent.parent
METRICS = BASE / "results" / "metrics"
FIGURES = BASE / "paper" / "figures"
FIGURES.mkdir(parents=True, exist_ok=True)

plt.rcParams.update({
    'font.size': 10,
    'font.family': 'serif',
    'figure.figsize': (6.5, 4),
    'figure.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.05,
    'axes.grid': True,
    'grid.alpha': 0.3,
})


def plot_time_distribution():
    """Fig 1: Heavy-tail distribution of solving times (L2 + L3)."""
    fig, axes = plt.subplots(1, 2, figsize=(6.5, 3))

    # Level 2
    l2 = pd.read_csv(METRICS / "level2_metrics.csv")
    l2_times = l2['time_s'].dropna()
    if len(l2_times) > 0:
        ax = axes[0]
        bins = np.logspace(-1, 4, 50)
        ax.hist(l2_times, bins=bins, color='#2196F3', alpha=0.8, edgecolor='white', linewidth=0.3)
        ax.set_xscale('log')
        ax.set_xlabel('Solving time (s)')
        ax.set_ylabel('Count')
        ax.set_title(f'Level 2 (cutoff 70, n={len(l2_times)})')
        ax.axvline(x=3600, color='red', linestyle='--', alpha=0.7, label='Timeout')
        # Percentiles
        p50 = np.median(l2_times)
        p99 = np.percentile(l2_times, 99)
        ax.axvline(x=p50, color='green', linestyle=':', alpha=0.7, label=f'P50={p50:.0f}s')
        ax.axvline(x=p99, color='orange', linestyle=':', alpha=0.7, label=f'P99={p99:.0f}s')
        ax.legend(fontsize=7)

    # Level 3
    l3 = pd.read_csv(METRICS / "level3_metrics.csv")
    l3_times = l3.loc[l3['time_s'].notna() & (l3['time_s'] != ''), 'time_s'].astype(float)
    if len(l3_times) > 0:
        ax = axes[1]
        bins = np.logspace(-1, 4, 50)
        ax.hist(l3_times, bins=bins, color='#FF9800', alpha=0.8, edgecolor='white', linewidth=0.3)
        ax.set_xscale('log')
        ax.set_xlabel('Solving time (s)')
        ax.set_ylabel('Count')
        ax.set_title(f'Level 3 (cutoff 90, n={len(l3_times)})')
        ax.axvline(x=1200, color='red', linestyle='--', alpha=0.7, label='Timeout')
        if len(l3_times) > 1:
            p50 = np.median(l3_times)
            p99 = np.percentile(l3_times, 99)
            ax.axvline(x=p50, color='green', linestyle=':', alpha=0.7, label=f'P50={p50:.0f}s')
            ax.axvline(x=p99, color='orange', linestyle=':', alpha=0.7, label=f'P99={p99:.0f}s')
        ax.legend(fontsize=7)

    plt.tight_layout()
    out = FIGURES / "time_distribution.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


def plot_difficulty_map():
    """Fig 2: UNSAT/TIMEOUT map across SSC indices."""
    l3 = pd.read_csv(METRICS / "level3_metrics.csv")
    if len(l3) == 0:
        return

    fig, ax = plt.subplots(figsize=(6.5, 2.5))

    # Color by result
    colors = {'UNSAT': '#4CAF50', 'TIMEOUT': '#F44336', 'ERROR': '#9E9E9E', 'SAT': '#FF9800'}
    for _, row in l3.iterrows():
        c = colors.get(row['result'], '#9E9E9E')
        ax.barh(0, 1, left=row['idx'], color=c, height=0.8, linewidth=0)

    ax.set_xlim(l3['idx'].min() - 10, l3['idx'].max() + 10)
    ax.set_ylim(-0.5, 0.5)
    ax.set_yticks([])
    ax.set_xlabel('Sub-sub-cube index')
    ax.set_title('Level 3: Difficulty map (green = UNSAT, red = TIMEOUT)')

    # Add legend
    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor='#4CAF50', label=f'UNSAT ({(l3["result"]=="UNSAT").sum()})'),
        Patch(facecolor='#F44336', label=f'TIMEOUT ({(l3["result"]=="TIMEOUT").sum()})'),
    ]
    ax.legend(handles=legend_elements, loc='upper right', fontsize=8)

    plt.tight_layout()
    out = FIGURES / "difficulty_map.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


def plot_mincheck_correlation():
    """Fig 3: MinCheck calls vs solving time."""
    l3 = pd.read_csv(METRICS / "level3_metrics.csv")
    mask = l3['time_s'].notna() & l3['mincheck_calls'].notna()
    l3f = l3[mask].copy()
    if len(l3f) < 5:
        print("[plot] Not enough MinCheck data for correlation plot")
        return

    l3f['time_s'] = pd.to_numeric(l3f['time_s'], errors='coerce')
    l3f['mincheck_calls'] = pd.to_numeric(l3f['mincheck_calls'], errors='coerce')
    l3f = l3f.dropna(subset=['time_s', 'mincheck_calls'])

    fig, ax = plt.subplots(figsize=(5, 4))
    ax.scatter(l3f['mincheck_calls'], l3f['time_s'],
               alpha=0.5, s=15, c='#2196F3', edgecolors='none')
    ax.set_xscale('log')
    ax.set_yscale('log')
    ax.set_xlabel('MinCheck calls')
    ax.set_ylabel('Solving time (s)')
    ax.set_title('MinCheck symmetry propagation vs difficulty')

    # Correlation
    log_calls = np.log10(l3f['mincheck_calls'].values)
    log_time = np.log10(l3f['time_s'].values)
    if len(log_calls) > 2:
        corr = np.corrcoef(log_calls, log_time)[0, 1]
        ax.text(0.05, 0.95, f'ρ = {corr:.2f}', transform=ax.transAxes,
                fontsize=10, va='top', ha='left',
                bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5))

    plt.tight_layout()
    out = FIGURES / "mincheck_correlation.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


def plot_tension_distribution():
    """Fig 4: Extension tension τ distribution."""
    tension_file = METRICS / "tension.csv"
    if not tension_file.exists():
        print("[plot] No tension data")
        return

    df = pd.read_csv(tension_file)
    # Use only non-complement entries (one per pair)
    df_base = df[df['is_complement'] == False].copy()

    fig, axes = plt.subplots(1, 2, figsize=(6.5, 3))

    # Histogram
    ax = axes[0]
    tau_vals = df_base['tau'].values
    bins = range(int(tau_vals.min()), int(tau_vals.max()) + 2)
    ax.hist(tau_vals, bins=bins, color='#9C27B0', alpha=0.8, edgecolor='white', linewidth=0.3)
    ax.axvline(x=2, color='red', linestyle='--', alpha=0.8, label=f'τ_min = 2')
    ax.axvline(x=49, color='blue', linestyle='--', alpha=0.8, label=f'τ_max = 49')
    ax.axvline(x=125, color='green', linestyle=':', alpha=0.6, label=f'E[random] ≈ 125')
    ax.set_xlabel('Extension tension τ(G)')
    ax.set_ylabel('Count (graph pairs)')
    ax.set_title(f'τ distribution (n={len(df_base)} pairs)')
    ax.legend(fontsize=7)

    # CDF
    ax = axes[1]
    sorted_tau = np.sort(tau_vals)
    cdf = np.arange(1, len(sorted_tau) + 1) / len(sorted_tau)
    ax.plot(sorted_tau, cdf, color='#9C27B0', linewidth=1.5)
    ax.axhline(y=0.5, color='gray', linestyle=':', alpha=0.5)
    ax.axvline(x=2, color='red', linestyle='--', alpha=0.6, label='τ_min = 2')
    ax.set_xlabel('Extension tension τ(G)')
    ax.set_ylabel('Cumulative fraction')
    ax.set_title('CDF of τ')
    ax.legend(fontsize=7)

    plt.tight_layout()
    out = FIGURES / "tension_distribution.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


def plot_level_summary():
    """Fig 5: Multi-level decomposition summary."""
    fig, ax = plt.subplots(figsize=(6, 3.5))

    levels = ['L1\n(cutoff 50)', 'L2\n(cutoff 70)', 'L3\n(cutoff 90)', 'L4\n(cutoff 110)']
    totals = [11, 4483, 5439, 0]
    unsats = [6, 4398, 0, 0]
    timeouts = [5, 85, 0, 0]

    # Get L3 current data
    l3_file = METRICS / "level3_metrics.csv"
    if l3_file.exists():
        l3 = pd.read_csv(l3_file)
        unsats[2] = (l3['result'] == 'UNSAT').sum()
        timeouts[2] = (l3['result'] == 'TIMEOUT').sum()
        remaining = totals[2] - unsats[2] - timeouts[2]
    else:
        remaining = totals[2]

    # L4
    l4_file = METRICS / "level4_metrics.csv"
    if l4_file.exists():
        l4 = pd.read_csv(l4_file)
        if len(l4) > 0:
            totals[3] = len(l4)
            unsats[3] = (l4['result'] == 'UNSAT').sum()
            timeouts[3] = (l4['result'] == 'TIMEOUT').sum()

    x = np.arange(len(levels))
    width = 0.25

    bars_unsat = ax.bar(x - width, unsats, width, label='UNSAT', color='#4CAF50', alpha=0.8)
    bars_tout = ax.bar(x, timeouts, width, label='TIMEOUT/Hard', color='#F44336', alpha=0.8)
    bars_remain = ax.bar(x + width, [0, 0, remaining, 0], width, label='In progress', color='#9E9E9E', alpha=0.5)

    ax.set_ylabel('Number of cubes')
    ax.set_xticks(x)
    ax.set_xticklabels(levels)
    ax.set_title('Progressive cubing: multi-level decomposition')
    ax.legend(fontsize=8)
    ax.set_yscale('log')
    ax.set_ylim(0.5, 10000)

    # Annotate totals
    for i, t in enumerate(totals):
        if t > 0:
            ax.text(i, max(t, 1) * 1.2, f'n={t}', ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    out = FIGURES / "level_summary.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


def plot_cumulative_progress():
    """Fig 6: Cumulative solving progress over time (from sync log)."""
    log_file = Path("/tmp/ssc_sync.log")
    if not log_file.exists():
        print("[plot] No sync log for progress plot")
        return

    times = []
    totals = []
    unsats = []
    timeouts = []

    with open(log_file) as f:
        for line in f:
            # [HH:MM] NNNN/5439 (UNSAT=N TIMEOUT=N rimanenti=N)
            import re
            m = re.match(r'\[(\d+:\d+)\]\s+(\d+)/5439.*UNSAT=(\d+).*TIMEOUT=(\d+)', line)
            if m:
                times.append(m.group(1))
                totals.append(int(m.group(2)))
                unsats.append(int(m.group(3)))
                timeouts.append(int(m.group(4)))

    if len(times) < 3:
        print("[plot] Not enough sync log entries")
        return

    fig, ax1 = plt.subplots(figsize=(6.5, 3.5))

    x = range(len(times))
    ax1.fill_between(x, unsats, alpha=0.3, color='#4CAF50', label='UNSAT')
    ax1.fill_between(x, unsats, totals, alpha=0.3, color='#F44336', label='TIMEOUT')
    ax1.plot(x, totals, color='#2196F3', linewidth=2, label='Total solved')
    ax1.axhline(y=5439, color='gray', linestyle='--', alpha=0.5, label='Target (5439)')

    # X axis: show every Nth label
    step = max(1, len(times) // 15)
    ax1.set_xticks(range(0, len(times), step))
    ax1.set_xticklabels([times[i] for i in range(0, len(times), step)], rotation=45, fontsize=7)

    ax1.set_xlabel('Time')
    ax1.set_ylabel('Cumulative SSC solved')
    ax1.set_title('Level 3 solving progress')
    ax1.legend(fontsize=8, loc='center right')

    # Rate on secondary axis
    ax2 = ax1.twinx()
    rates = [0] + [max(0, (totals[i] - totals[i-1]) * 6) for i in range(1, len(totals))]
    ax2.bar(x, rates, alpha=0.15, color='#FF9800', width=0.8)
    ax2.set_ylabel('Rate (SSC/hour)', color='#FF9800')
    ax2.tick_params(axis='y', labelcolor='#FF9800')

    plt.tight_layout()
    out = FIGURES / "solving_progress.pdf"
    plt.savefig(out)
    plt.savefig(out.with_suffix('.png'))
    print(f"[plot] {out}")
    plt.close()


if __name__ == '__main__':
    print("=" * 50)
    print("  R(5,5) Paper Figure Generator")
    print("=" * 50)

    plot_time_distribution()
    plot_difficulty_map()
    plot_mincheck_correlation()
    plot_tension_distribution()
    plot_level_summary()
    plot_cumulative_progress()

    print("\nAll figures saved to:", FIGURES)
    print("Include in LaTeX with: \\includegraphics{figures/<name>.pdf}")
