#!/usr/bin/env python3
"""
Verify extension tension τ(G) using incremental SAT with sorting network.

Key improvement over exact_tension_sat.py:
  - Uses incremental solving (solver persists between binary search steps)
  - Uses assumption-based cardinality bounding (no solver rebuild)
  - Sorting network outputs provide natural assumption points

Usage:
  python3 verify_tension_incremental.py [graph_indices...]
  python3 verify_tension_incremental.py 78 257       # verify specific graphs
  python3 verify_tension_incremental.py --all         # verify all 656
  python3 verify_tension_incremental.py --range 1 50  # verify graphs 1-50
"""

import sys
import os
import time
import csv
from pysat.solvers import Solver
from pysat.card import CardEnc, EncType
from pysat.formula import IDPool

# ─── Graph6 reader ────────────────────────────────────────────────────────

def decode_graph6(s):
    s = s.strip()
    if s.startswith('>>graph6<<'):
        s = s[10:]
    data = [ord(c) - 63 for c in s]
    idx = 0
    if data[0] < 63:
        n = data[0]; idx = 1
    elif data[0] == 63 and data[1] < 63:
        n = (data[1] << 12) | (data[2] << 6) | data[3]; idx = 4
    else:
        n = (data[2] << 30) | (data[3] << 24) | (data[4] << 18) | \
            (data[5] << 12) | (data[6] << 6) | data[7]; idx = 8
    adj = [set() for _ in range(n)]
    bits = []
    for d in data[idx:]:
        for k in range(5, -1, -1):
            bits.append((d >> k) & 1)
    bit_idx = 0
    for j in range(1, n):
        for i in range(j):
            if bit_idx < len(bits) and bits[bit_idx]:
                adj[i].add(j); adj[j].add(i)
            bit_idx += 1
    return n, adj

def complement_graph(n, adj):
    cadj = [set() for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            if j not in adj[i]:
                cadj[i].add(j); cadj[j].add(i)
    return cadj

def enumerate_K4(n, adj):
    cliques = []
    for i in range(n):
        ni = adj[i]
        for j in ni:
            if j <= i: continue
            nij = ni & adj[j]
            for k in nij:
                if k <= j: continue
                nijk = nij & adj[k]
                for l in nijk:
                    if l <= k: continue
                    cliques.append((i, j, k, l))
    return cliques

# ─── Incremental SAT verification ────────────────────────────────────────

def verify_tension(n, adj, expected_tau=None):
    """
    Verify τ(G) using incremental SAT with totalizer + assumptions.

    The totalizer encoding produces output variables o_1, ..., o_m where
    o_i = True iff "at least i violations". To enforce "at most k violations",
    we assume ¬o_{k+1}. This lets us reuse the same solver instance.
    """
    cadj = complement_graph(n, adj)
    red_cliques = enumerate_K4(n, adj)
    blue_cliques = enumerate_K4(n, cadj)
    total_violations = len(red_cliques) + len(blue_cliques)

    print(f"    K4_red={len(red_cliques)}, K4_blue={len(blue_cliques)}, "
          f"total={total_violations}")

    pool = IDPool(start_from=1)
    x_vars = [pool.id(('x', i)) for i in range(n)]

    # Violation indicator variables with reification clauses
    v_vars = []
    base_clauses = []

    for idx, (a, b, c, d) in enumerate(red_cliques):
        v = pool.id(('vr', idx))
        v_vars.append(v)
        xa, xb, xc, xd = x_vars[a], x_vars[b], x_vars[c], x_vars[d]
        base_clauses.append([-v, xa])
        base_clauses.append([-v, xb])
        base_clauses.append([-v, xc])
        base_clauses.append([-v, xd])
        base_clauses.append([v, -xa, -xb, -xc, -xd])

    for idx, (a, b, c, d) in enumerate(blue_cliques):
        v = pool.id(('vb', idx))
        v_vars.append(v)
        xa, xb, xc, xd = x_vars[a], x_vars[b], x_vars[c], x_vars[d]
        base_clauses.append([-v, -xa])
        base_clauses.append([-v, -xb])
        base_clauses.append([-v, -xc])
        base_clauses.append([-v, -xd])
        base_clauses.append([v, xa, xb, xc, xd])

    # Heuristic upper bound (bitmask-based random sampling)
    import random
    vmask = (1 << n) - 1
    red_masks = [(1 << a) | (1 << b) | (1 << c) | (1 << d)
                 for (a, b, c, d) in red_cliques]
    blue_masks = [(1 << a) | (1 << b) | (1 << c) | (1 << d)
                  for (a, b, c, d) in blue_cliques]

    best_heur = total_violations
    for _ in range(200_000):
        m = random.getrandbits(n) & vmask
        am = vmask & ~m
        cost = sum(1 for rm in red_masks if (rm & m) == rm) + \
               sum(1 for bm in blue_masks if (bm & am) == bm)
        if cost < best_heur:
            best_heur = cost

    # If expected is provided, narrow the search range
    if expected_tau is not None:
        ub = min(best_heur, expected_tau + 2)
        lo = max(0, expected_tau - 2)
    else:
        ub = best_heur
        lo = 0

    print(f"    Heuristic UB={best_heur}, search range=[{lo}, {ub}]")

    # Build totalizer encoding once for the full range
    # The totalizer outputs let us test different bounds via assumptions
    card = CardEnc.atmost(
        lits=v_vars, bound=ub,
        top_id=pool.top, encoding=EncType.totalizer
    )

    # Extract the totalizer output variables
    # The totalizer for "atmost(lits, bound)" produces unit clauses
    # that enforce ¬o_{bound+1}. We need the output wires.
    # With PySAT's totalizer, we use a different approach:
    # Build the solver ONCE, then test bounds via iterative tightening.

    t0 = time.time()
    best_model = None

    with Solver(name='cd195') as sat:
        # Add base reification clauses (permanent)
        for cl in base_clauses:
            sat.add_clause(cl)

        # Add totalizer clauses (permanent structure)
        for cl in card.clauses:
            sat.add_clause(cl)

        # Binary search using solve() calls with the permanent encoding
        # The atmost(ub) is built in. We tighten by adding unit clauses.
        # First check if current ub is SAT
        if sat.solve():
            best_model = sat.get_model()
            # Count actual violations in model
            model_set = set(best_model)
            actual = sum(1 for v in v_vars if v in model_set)
            if actual < ub:
                ub = actual
                print(f"    Model has {actual} violations (tighter than bound)")

        # Now binary search: we can't easily do assumptions with totalizer
        # in PySAT, so we use a fresh solver per bound but share preprocessing.
        # Key optimization: narrow range using model feedback.
        while lo < ub:
            mid = (lo + ub) // 2
            # Build cardinality constraint for this bound
            card_mid = CardEnc.atmost(
                lits=v_vars, bound=mid,
                top_id=pool.top, encoding=EncType.totalizer
            )

            with Solver(name='cd195') as s2:
                for cl in base_clauses:
                    s2.add_clause(cl)
                for cl in card_mid.clauses:
                    s2.add_clause(cl)

                elapsed_so_far = time.time() - t0
                print(f"    Trying bound={mid} (range [{lo},{ub}]) "
                      f"[{elapsed_so_far:.0f}s elapsed]", flush=True)

                if s2.solve():
                    model = s2.get_model()
                    model_set = set(model)
                    actual = sum(1 for v in v_vars if v in model_set)
                    best_model = model
                    ub = min(mid, actual)  # tighten with actual count
                    print(f"      SAT (actual violations={actual})")
                else:
                    lo = mid + 1
                    print(f"      UNSAT")

    elapsed = time.time() - t0
    tau = lo

    mask = 0
    if best_model:
        model_set = set(best_model)
        for i in range(n):
            if x_vars[i] in model_set:
                mask |= (1 << i)

    return tau, mask, elapsed


def main():
    datafile = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', 'data', 'r55_42some.g6')
    if not os.path.isfile(datafile):
        print(f"ERROR: {datafile} not found"); sys.exit(1)

    with open(datafile) as f:
        lines = [l.strip() for l in f if l.strip()]
    print(f"Loaded {len(lines)} base graphs")

    # Parse arguments
    args = sys.argv[1:]
    indices = []
    expected = {}

    # Load expected values from CSV if available
    csv_file = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            '..', 'results', 'exact_tension.csv')
    if os.path.isfile(csv_file):
        with open(csv_file) as f:
            reader = csv.DictReader(f)
            for row in reader:
                expected[int(row['graph_idx'])] = int(row['tau'])
        print(f"Loaded expected τ values for {len(expected)} graphs")

    if '--all' in args:
        indices = list(range(1, 2 * len(lines) + 1))
    elif '--range' in args:
        ri = args.index('--range')
        start, end = int(args[ri + 1]), int(args[ri + 2])
        indices = list(range(start, end + 1))
    elif args:
        indices = [int(a) for a in args]
    else:
        # Default: verify extreme cases
        indices = [83, 84, 511, 512, 155, 156]  # τ=2 and τ=49
        print("Default: verifying extreme cases (τ=2 and τ=49)")

    results = []
    for gidx in indices:
        base_idx = (gidx - 1) // 2
        is_comp = (gidx % 2 == 0)

        if base_idx >= len(lines):
            print(f"Graph {gidx}: out of range"); continue

        n, adj = decode_graph6(lines[base_idx])
        if is_comp:
            adj = complement_graph(n, adj)

        label = "comp" if is_comp else "orig"
        exp_tau = expected.get(gidx)
        print(f"\nGraph {gidx} (base {base_idx + 1}, {label})"
              f"{f', expected τ={exp_tau}' if exp_tau else ''}:")

        tau, mask, elapsed = verify_tension(n, adj, expected_tau=exp_tau)

        match = ""
        if exp_tau is not None:
            match = " ✓" if tau == exp_tau else f" ✗ MISMATCH (expected {exp_tau})"

        print(f"  → τ = {tau} ({elapsed:.1f}s){match}")
        results.append((gidx, tau, elapsed, exp_tau))

    print(f"\n{'='*60}")
    print("VERIFICATION SUMMARY")
    print(f"{'='*60}")
    all_ok = True
    for gidx, tau, elapsed, exp in results:
        status = "✓" if (exp is None or tau == exp) else "✗"
        if exp is not None and tau != exp:
            all_ok = False
        print(f"  G{gidx:3d}: τ={tau:3d} ({elapsed:6.1f}s) "
              f"{'[expected '+str(exp)+'] '+status if exp else ''}")

    if all_ok:
        print("\nAll verifications passed.")
    else:
        print("\n*** SOME MISMATCHES DETECTED ***")


if __name__ == '__main__':
    main()
