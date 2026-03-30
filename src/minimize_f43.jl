#!/usr/bin/env julia
"""
Module C: Minimize f(43) = minimum number of monochromatic K₅ in any
2-coloring of K₄₃.

Strategy:
1. Exhaustive search over circulant graphs on Z₄₃
2. Simulated annealing from best circulant seeds
3. Simulated annealing from Exoo variations

f(43) = 0 iff R(5,5) > 43.
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using Random

# ─── Circulant exhaustive search ───────────────────────────────────────────

"""
Search all circulant graphs on Z₄₃ with connection set S ⊂ {1,...,21}.
For each, count total monochromatic K₅ = red_K₅ + blue_K₅.
Return the best found.
"""
function search_circulants(n::Int=43)
    max_d = n ÷ 2  # = 21 for n=43
    best_total = typemax(Int)
    best_S = Int[]
    best_red = 0
    best_blue = 0
    count_checked = 0

    # We only need to check subsets up to complement symmetry:
    # S and {1,...,21}\S give complement colorings, so f_S = f_{compl(S)}
    # We iterate over all 2^21 = 2097152 subsets, but skip if |S| > 10
    # (by complement symmetry, |S| and |21-S| give same total K₅ count)

    total = 1 << max_d
    println("Searching all $total circulant colorings of K_$n...")

    for mask in UInt32(0):(UInt32(total) - UInt32(1))
        S = Int[]
        for bit in 1:max_d
            if (mask >> (bit - 1)) & UInt32(1) == UInt32(1)
                push!(S, bit)
            end
        end

        # Skip empty set (no red edges) — complement handles it
        isempty(S) && continue

        g = circulant_graph(n, S)
        red = count_clique5(g)
        blue = count_clique5(complement_graph(g))
        total_k5 = red + blue
        count_checked += 1

        if total_k5 < best_total
            best_total = total_k5
            best_S = copy(S)
            best_red = red
            best_blue = blue
            @printf("  [%7d] S=%s → red=%d, blue=%d, total=%d\n",
                    count_checked, string(S), red, blue, total_k5)
        end

        if count_checked % 500_000 == 0
            @printf("  ... checked %d / %d\n", count_checked, total)
        end
    end

    println("\n✓ Best circulant: S = $best_S")
    println("  Red K₅ = $best_red, Blue K₅ = $best_blue, Total = $best_total")
    return best_S, best_total, best_red, best_blue
end

# ─── Simulated annealing ───────────────────────────────────────────────────

"""
    sa_minimize_K5(n::Int; seed_g=nothing, T0=50.0, alpha=0.9999, max_iter=10_000_000)

Simulated annealing to minimize total monochromatic K₅ in a 2-coloring of K_n.
Move: flip a single edge color (= flip edge in the graph).
"""
function sa_minimize_K5(n::Int;
        seed_g::Union{Nothing, AdjMatrix}=nothing,
        T0::Float64=50.0,
        alpha::Float64=0.99999,
        max_iter::Int=20_000_000,
        verbose::Bool=true)

    # Initialize
    if seed_g === nothing
        g = circulant_graph(n, [1, 2, 7, 10, 12, 13, 14, 16, 18, 20, 21])
    else
        g = copy(seed_g)
    end

    red = count_clique5(g)
    blue = count_clique5(complement_graph(g))
    current_cost = red + blue
    best_cost = current_cost
    best_g = copy(g)

    T = T0
    n_edges = n * (n - 1) ÷ 2
    accepted = 0
    improved = 0

    if verbose
        @printf("SA start: red=%d, blue=%d, total=%d, T0=%.1f\n", red, blue, current_cost, T0)
    end

    for iter in 1:max_iter
        # Random edge to flip
        i = rand(1:n)
        j = rand(1:n-1)
        j >= i && (j += 1)
        if i > j
            i, j = j, i
        end

        # Compute delta: count K₅ involving edge (i,j) before and after flip
        # Before flip:
        old_k5_ij = _count_clique5_through_edge(g, i, j)

        flip_edge!(g, i, j)

        # After flip:
        new_k5_ij = _count_clique5_through_edge(g, i, j)

        # Also count in complement for the "blue" side
        # Flipping in g means flipping in complement too
        # Before flip (now g is flipped, so complement before = complement of current minus the flip)
        # Simpler: just recount
        # For efficiency, we count K₅ through (i,j) in both g and complement
        gc_ij_old = _count_indset5_through_edge_fast(g, i, j)  # this is blue K₅ now

        # The old blue count through (i,j) was the K₅ in complement before flip
        # After flip of (i,j) in g, the complement has (i,j) flipped too
        # So: old state had edge (i,j) = X, new state has edge (i,j) = !X
        # Red K₅ through (i,j): before=old_k5_ij_before, after=new_k5_ij
        # But we already flipped, so we need to think carefully...

        # Let's just recount the total — it's fast enough for K₅ on 43 vertices
        new_red = count_clique5(g)
        new_blue = count_clique5(complement_graph(g))
        new_cost = new_red + new_blue

        delta = new_cost - current_cost

        if delta <= 0 || rand() < exp(-delta / T)
            current_cost = new_cost
            accepted += 1
            if new_cost < best_cost
                best_cost = new_cost
                best_g = copy(g)
                improved += 1
                if verbose && (best_cost <= 10 || improved % 100 == 0)
                    @printf("  iter=%d: NEW BEST total=%d (red=%d, blue=%d) T=%.4f\n",
                            iter, best_cost, new_red, new_blue, T)
                end
                best_cost == 0 && break
            end
        else
            # Reject: undo flip
            flip_edge!(g, i, j)
        end

        T *= alpha
    end

    final_red = count_clique5(best_g)
    final_blue = count_clique5(complement_graph(best_g))
    if verbose
        @printf("\nSA result: red=%d, blue=%d, total=%d\n", final_red, final_blue, best_cost)
        @printf("  accepted=%d, improved=%d\n", accepted, improved)
    end

    return best_g, best_cost, final_red, final_blue
end

# Helper: count K₅ containing a specific edge
function _count_clique5_through_edge(g::AdjMatrix, u::Int, v::Int)
    if !has_edge(g, u, v)
        return 0
    end
    # K₅ through (u,v): find 3 more vertices each connected to both u,v and to each other
    common = g.rows[u] & g.rows[v]
    count = 0
    w_mask = common
    @inbounds while w_mask != UInt64(0)
        w = trailing_zeros(w_mask) + 1
        w_mask &= w_mask - UInt64(1)
        cwx = common & g.rows[w]
        x_mask = cwx & ~((UInt64(1) << w) - UInt64(1))
        while x_mask != UInt64(0)
            x = trailing_zeros(x_mask) + 1
            x_mask &= x_mask - UInt64(1)
            y_mask = cwx & g.rows[x] & ~((UInt64(1) << x) - UInt64(1))
            count += count_ones(y_mask)
        end
    end
    return count
end

function _count_indset5_through_edge_fast(g::AdjMatrix, u::Int, v::Int)
    # This would count independent sets of size 5 containing u,v
    # = K₅ in complement through (u,v)
    # For now, not used — we recount globally
    return 0
end

# ─── Main ──────────────────────────────────────────────────────────────────

function main()
    println("=" ^ 70)
    println("MODULE C: Minimization of f(43)")
    println("=" ^ 70)

    # Phase 1: Exhaustive circulant search
    println("\n─── Phase 1: Exhaustive Circulant Search ───")
    t1 = @elapsed begin
        best_S, best_total, best_red, best_blue = search_circulants(43)
    end
    @printf("Time: %.1fs\n", t1)

    # Phase 2: SA from best circulant
    println("\n─── Phase 2: Simulated Annealing from Best Circulant ───")
    seed = circulant_graph(43, best_S)
    t2 = @elapsed begin
        best_g, best_cost, final_red, final_blue = sa_minimize_K5(43;
            seed_g=seed, T0=100.0, alpha=0.999995, max_iter=5_000_000)
    end
    @printf("Time: %.1fs\n", t2)

    # Phase 3: SA from Exoo's Cyclic(43)
    println("\n─── Phase 3: Simulated Annealing from Exoo's Cyclic(43) ───")
    exoo = exoo_cyclic43()
    t3 = @elapsed begin
        best_g2, best_cost2, final_red2, final_blue2 = sa_minimize_K5(43;
            seed_g=exoo, T0=100.0, alpha=0.999995, max_iter=5_000_000)
    end
    @printf("Time: %.1fs\n", t3)

    # Phase 4: Multiple random restarts
    println("\n─── Phase 4: Random Restart SA (5 runs) ───")
    global_best = min(best_cost, best_cost2)
    global_best_g = best_cost <= best_cost2 ? best_g : best_g2

    for run in 1:5
        # Random initial coloring (Erdős-style: each edge red with probability p)
        g0 = AdjMatrix(43)
        for i in 1:43, j in (i+1):43
            if rand() < 0.5
                set_edge!(g0, i, j)
            end
        end
        bg, bc, br, bb = sa_minimize_K5(43;
            seed_g=g0, T0=200.0, alpha=0.999995, max_iter=5_000_000, verbose=false)
        @printf("  Run %d: total=%d (red=%d, blue=%d)\n", run, bc, br, bb)
        if bc < global_best
            global_best = bc
            global_best_g = bg
        end
    end

    println("\n" * "=" ^ 70)
    @printf("FINAL RESULT: f(43) ≤ %d\n", global_best)
    println("=" ^ 70)

    # Save best graph
    results_dir = joinpath(@__DIR__, "..", "results")
    mkpath(results_dir)
    write_g6_file(joinpath(results_dir, "best_K43_coloring.g6"), [global_best_g])
    open(joinpath(results_dir, "f43_result.txt"), "w") do io
        rk5 = count_clique5(global_best_g)
        bk5 = count_clique5(complement_graph(global_best_g))
        println(io, "f(43) <= $(rk5 + bk5)")
        println(io, "red_K5 = $rk5")
        println(io, "blue_K5 = $bk5")
        println(io, "graph6 = $(write_g6(global_best_g))")
    end
    println("Results saved to $results_dir/")
end

main()
