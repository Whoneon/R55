#!/usr/bin/env python3
"""
Exact computation of extension tension τ(G) for all 656 R(5,5,42) extremal graphs.

τ(G) = min over all N ⊆ V(G) of:
    #{K₄ in G[N]} + #{I₄ in G[N̄]}

Uses Google OR-Tools CP-SAT solver for exact binary optimization.
Linear encoding: y[k] = AND(x[a],x[b],x[c],x[d]) via 5 linear constraints.
"""

import sys
import os
import time
import csv
from ortools.sat.python import cp_model

# ─── Graph6 reader ────────────────────────────────────────────────────────

def decode_graph6(s):
    """Decode a graph6 string into an adjacency matrix (list of sets)."""
    s = s.strip()
    if s.startswith('>>graph6<<'):
        s = s[10:]

    data = [ord(c) - 63 for c in s]
    idx = 0

    if data[0] < 63:
        n = data[0]
        idx = 1
    elif data[0] == 63 and data[1] < 63:
        n = (data[1] << 12) | (data[2] << 6) | data[3]
        idx = 4
    else:
        n = (data[2] << 30) | (data[3] << 24) | (data[4] << 18) | \
            (data[5] << 12) | (data[6] << 6) | data[7]
        idx = 8

    adj = [set() for _ in range(n)]
    bits = []
    for d in data[idx:]:
        for k in range(5, -1, -1):
            bits.append((d >> k) & 1)

    bit_idx = 0
    for j in range(1, n):
        for i in range(j):
            if bit_idx < len(bits) and bits[bit_idx]:
                adj[i].add(j)
                adj[j].add(i)
            bit_idx += 1

    return n, adj


def complement_graph(n, adj):
    cadj = [set() for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            if j not in adj[i]:
                cadj[i].add(j)
                cadj[j].add(i)
    return cadj


# ─── K₄ enumeration ──────────────────────────────────────────────────────

def enumerate_K4(n, adj):
    """Enumerate all K₄ subsets as sorted 4-tuples."""
    cliques = []
    for i in range(n):
        ni = adj[i]
        for j in ni:
            if j <= i:
                continue
            nij = ni & adj[j]
            for k in nij:
                if k <= j:
                    continue
                nijk = nij & adj[k]
                for l in nijk:
                    if l <= k:
                        continue
                    cliques.append((i, j, k, l))
    return cliques


# ─── CP-SAT formulation ──────────────────────────────────────────────────

def exact_tension_cpsat(n, adj, time_limit=60, num_workers=2):
    """
    Compute exact τ(G) using CP-SAT with linear AND encoding.

    For each red K₄ (a,b,c,d):
        y ≤ x[a], y ≤ x[b], y ≤ x[c], y ≤ x[d]  (y=0 if any absent)
        y ≥ x[a] + x[b] + x[c] + x[d] - 3         (y=1 if all present)

    For each blue I₄ (a,b,c,d):
        z ≤ 1-x[a], z ≤ 1-x[b], z ≤ 1-x[c], z ≤ 1-x[d]
        z ≥ (4 - x[a] - x[b] - x[c] - x[d]) - 3
    """
    cadj = complement_graph(n, adj)
    red_cliques = enumerate_K4(n, adj)
    blue_cliques = enumerate_K4(n, cadj)

    model = cp_model.CpModel()

    x = [model.new_bool_var(f'x{i}') for i in range(n)]

    objectives = []

    # Red K₄s
    for k, (a, b, c, d) in enumerate(red_cliques):
        y = model.new_bool_var(f'r{k}')
        model.add(y <= x[a])
        model.add(y <= x[b])
        model.add(y <= x[c])
        model.add(y <= x[d])
        model.add(y >= x[a] + x[b] + x[c] + x[d] - 3)
        objectives.append(y)

    # Blue I₄s
    for k, (a, b, c, d) in enumerate(blue_cliques):
        z = model.new_bool_var(f'b{k}')
        # z = AND(NOT x[a], NOT x[b], NOT x[c], NOT x[d])
        # z ≤ 1 - x[i] for each i
        model.add(z + x[a] <= 1)
        model.add(z + x[b] <= 1)
        model.add(z + x[c] <= 1)
        model.add(z + x[d] <= 1)
        # z ≥ 1 - x[a] + 1 - x[b] + 1 - x[c] + 1 - x[d] - 3
        #   = 4 - x[a] - x[b] - x[c] - x[d] - 3
        #   = 1 - x[a] - x[b] - x[c] - x[d]
        model.add(z >= 1 - x[a] - x[b] - x[c] - x[d])
        objectives.append(z)

    model.minimize(sum(objectives))

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = time_limit
    solver.parameters.num_workers = num_workers

    status = solver.solve(model)

    if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        tau = int(solver.objective_value)
        mask = 0
        for i in range(n):
            if solver.value(x[i]):
                mask |= (1 << i)
        degree = bin(mask).count('1')
        is_optimal = (status == cp_model.OPTIMAL)
        return tau, mask, degree, is_optimal, solver.wall_time
    else:
        return -1, 0, 0, False, 0.0


# ─── Main ─────────────────────────────────────────────────────────────────

def main():
    datafile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', 'data', 'r55_42some.g6')
    if not os.path.isfile(datafile):
        print(f"ERROR: Data file not found: {datafile}")
        sys.exit(1)

    with open(datafile) as f:
        lines = [l.strip() for l in f if l.strip()]

    print(f"Loaded {len(lines)} base graphs")

    # Parse optional args
    time_limit = 120
    num_workers = 2
    start_idx = 0
    if len(sys.argv) > 1:
        time_limit = int(sys.argv[1])
    if len(sys.argv) > 2:
        num_workers = int(sys.argv[2])
    if len(sys.argv) > 3:
        start_idx = int(sys.argv[3])

    print(f"Settings: time_limit={time_limit}s, workers={num_workers}, start={start_idx}")

    outfile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '..', 'results', 'exact_tension.csv')
    os.makedirs(os.path.dirname(outfile), exist_ok=True)

    # Resume support: read existing results
    existing = {}
    if os.path.isfile(outfile) and start_idx == 0:
        with open(outfile) as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('optimal') == 'True':
                    existing[int(row['graph_idx'])] = row

    mode = 'a' if existing else 'w'
    all_taus = []
    non_optimal = 0

    with open(outfile, mode, newline='') as csvf:
        writer = csv.writer(csvf)
        if not existing:
            writer.writerow(['graph_idx', 'is_complement', 'base_idx', 'tau',
                             'best_mask_hex', 'degree_new_vertex', 'optimal',
                             'time_s'])

        for i, line in enumerate(lines):
            n, adj = decode_graph6(line)
            cadj = complement_graph(n, adj)

            for j, (gadj, is_comp) in enumerate([(adj, False), (cadj, True)]):
                gidx = 2 * i + j + 1
                if gidx <= start_idx:
                    continue
                if gidx in existing:
                    tau = int(existing[gidx]['tau'])
                    all_taus.append(tau)
                    continue

                label = "comp" if is_comp else "orig"

                tau, mask, deg, optimal, wtime = exact_tension_cpsat(
                    n, gadj, time_limit=time_limit, num_workers=num_workers)

                all_taus.append(tau)
                opt_str = "OPT" if optimal else "FEAS"
                if not optimal:
                    non_optimal += 1

                print(f"Graph {gidx:3d}/656 (base {i+1:3d}, {label}): "
                      f"τ = {tau:3d}, deg = {deg:2d}, {opt_str} ({wtime:.1f}s)")

                writer.writerow([gidx, is_comp, i + 1, tau,
                                 f'{mask:011x}', deg, optimal, f'{wtime:.1f}'])
                csvf.flush()

    # Summary
    if all_taus:
        print(f"\n{'=' * 60}")
        print(f"SUMMARY: {len(all_taus)} graphs, {non_optimal} non-optimal")
        print(f"{'=' * 60}")
        print(f"  min τ = {min(all_taus)}")
        print(f"  max τ = {max(all_taus)}")
        print(f"  mean τ = {sum(all_taus) / len(all_taus):.2f}")

        if len(all_taus) >= 2:
            sorted_taus = sorted(all_taus)
            mid = len(sorted_taus) // 2
            median = (sorted_taus[mid - 1] + sorted_taus[mid]) / 2 if len(sorted_taus) % 2 == 0 else sorted_taus[mid]
            print(f"  median τ = {median:.1f}")

        from collections import Counter
        dist = Counter(all_taus)
        print("\nDistribution:")
        for tau_val in sorted(dist):
            cnt = dist[tau_val]
            print(f"  τ = {tau_val:3d}: {cnt:3d} graphs "
                  f"({100.0 * cnt / len(all_taus):.1f}%)")

    print(f"\nResults saved to {outfile}")


if __name__ == '__main__':
    main()
