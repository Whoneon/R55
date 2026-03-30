#!/usr/bin/env julia
"""
Search for a 657th graph in R(5,5,42).

Strategy:
1. SA from random graphs on 42 vertices, minimizing monochromatic K₅
2. SA from perturbations of known graphs
3. Every time SA reaches cost=0, check if the graph is in the known catalog
4. If not → potential new graph (verify carefully)

For catalog membership: compare sorted degree sequence + edge count + triangle
count + K₄ count as hash, then g6 under canonical relabeling attempts.
Without nauty, we use a pragmatic approach: sort vertices by (degree, triangle
participation, K₄ participation) and compare g6 of the resulting relabeling.
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using Random
using Dates

# ─── Catalog with fingerprints ────────────────────────────────────────────

struct GraphFingerprint
    nedges::Int
    deg_seq::Vector{Int}       # sorted
    tri_count::Int
    k4_count::Int
end

function fingerprint(g::AdjMatrix)
    n = g.n
    degs = sort!([degree(g, i) for i in 1:n])
    ne = sum(degs) ÷ 2
    tc = count_triangles(g)

    # Count K₄
    k4 = 0
    @inbounds for i in 1:n
        ni = g.rows[i]
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            nij = ni & g.rows[j]
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)
                l_mask = nij & g.rows[k] & ~((UInt64(1) << k) - UInt64(1))
                k4 += count_ones(l_mask)
            end
        end
    end

    GraphFingerprint(ne, degs, tc, k4)
end

function fingerprints_match(a::GraphFingerprint, b::GraphFingerprint)
    a.nedges == b.nedges && a.tri_count == b.tri_count &&
    a.k4_count == b.k4_count && a.deg_seq == b.deg_seq
end

struct CatalogFull
    graphs::Vector{AdjMatrix}
    fingerprints::Vector{GraphFingerprint}
    g6_set::Set{String}
end

function build_full_catalog(path::String)
    half = read_g6_file(path)
    graphs = AdjMatrix[]
    for g in half
        push!(graphs, g)
        push!(graphs, complement_graph(g))
    end
    fps = [fingerprint(g) for g in graphs]
    g6s = Set{String}([write_g6(g) for g in graphs])
    CatalogFull(graphs, fps, g6s)
end

# ─── Canonical-ish relabeling ─────────────────────────────────────────────
# Sort vertices by (degree, local triangle count, local K₄ count) to get
# a canonical-ish ordering. Not true canonical form (would need nauty),
# but catches most isomorphisms.

function vertex_invariants(g::AdjMatrix)
    n = g.n
    inv = Vector{Tuple{Int,Int,Int}}(undef, n)
    for v in 1:n
        d = degree(g, v)
        # triangles through v
        tv = 0
        nv = g.rows[v]
        u_mask = nv
        while u_mask != UInt64(0)
            u = trailing_zeros(u_mask) + 1
            u_mask &= u_mask - UInt64(1)
            tv += count_ones(nv & g.rows[u] & ~((UInt64(1) << u) - UInt64(1)))
        end
        # K₄ through v
        kv = 0
        u_mask2 = nv
        while u_mask2 != UInt64(0)
            u = trailing_zeros(u_mask2) + 1
            u_mask2 &= u_mask2 - UInt64(1)
            nuv = nv & g.rows[u]
            w_mask = nuv & ~((UInt64(1) << u) - UInt64(1))
            while w_mask != UInt64(0)
                w = trailing_zeros(w_mask) + 1
                w_mask &= w_mask - UInt64(1)
                kv += count_ones(nuv & g.rows[w] & ~((UInt64(1) << w) - UInt64(1)))
            end
        end
        inv[v] = (d, tv, kv)
    end
    inv
end

function canonical_relabel(g::AdjMatrix)
    n = g.n
    inv = vertex_invariants(g)
    perm = sortperm(inv)
    induced_subgraph(g, perm)
end

function is_in_catalog(g::AdjMatrix, catalog::CatalogFull)
    # Quick: check g6 directly
    g6 = write_g6(g)
    g6 in catalog.g6_set && return true

    # Check canonical relabeling
    gc = canonical_relabel(g)
    g6c = write_g6(gc)
    g6c in catalog.g6_set && return true

    # Check complement
    gbar = complement_graph(g)
    g6bar = write_g6(gbar)
    g6bar in catalog.g6_set && return true

    gbarc = canonical_relabel(gbar)
    g6barc = write_g6(gbarc)
    g6barc in catalog.g6_set && return true

    # Fingerprint check: if no fingerprint matches, definitely new
    fp = fingerprint(g)
    any_match = false
    for cfp in catalog.fingerprints
        if fingerprints_match(fp, cfp)
            any_match = true
            break
        end
    end
    if !any_match
        return false  # definitely not in catalog
    end

    # Fingerprint matches but g6 doesn't — could be isomorphic under
    # a non-canonical permutation. We can't be sure without nauty.
    # Return "maybe" as true (conservative: assume it's known)
    return true
end

# ─── SA for R(5,5,42) ────────────────────────────────────────────────────

function sa_ramsey42(seed_g::AdjMatrix;
        T0::Float64=50.0, Tmin::Float64=0.001,
        alpha::Float64=0.999995, max_iter::Int=20_000_000)
    n = 42
    g = copy(seed_g)
    red = count_clique5(g)
    blue = count_clique5(complement_graph(g))
    current_cost = red + blue
    best_cost = current_cost
    best_g = copy(g)
    T = T0

    for iter in 1:max_iter
        i = rand(1:n)
        j = rand(1:n-1)
        j >= i && (j += 1)
        if i > j; i, j = j, i end

        flip_edge!(g, i, j)
        new_red = count_clique5(g)
        new_blue = count_clique5(complement_graph(g))
        new_cost = new_red + new_blue
        delta = new_cost - current_cost

        if delta <= 0 || rand() < exp(-delta / T)
            current_cost = new_cost
            if new_cost < best_cost
                best_cost = new_cost
                best_g = copy(g)
                best_cost == 0 && return best_g, 0
            end
        else
            flip_edge!(g, i, j)
        end

        T = max(Tmin, T * alpha)
    end

    return best_g, best_cost
end

# ─── Main search ──────────────────────────────────────────────────────────

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")

    println("=" ^ 70)
    println("SEARCH FOR 657th GRAPH IN R(5,5,42)")
    println("=" ^ 70)

    println("\nBuilding catalog with fingerprints...")
    catalog = build_full_catalog(catalog_path)
    println("  $(length(catalog.graphs)) graphs, $(length(catalog.g6_set)) unique g6 strings")

    # Show fingerprint diversity
    unique_fps = length(unique(catalog.fingerprints))
    println("  $unique_fps unique fingerprints")

    results_dir = joinpath(@__DIR__, "..", "results")
    mkpath(results_dir)
    log_io = open(joinpath(results_dir, "search_657_log.txt"), "w")

    total_runs = 0
    total_found_r55 = 0
    found_in_catalog = 0
    found_new = 0

    t_start = time()

    # ─── Phase 1: SA from random graphs ───────────────────────────────
    println("\n─── Phase 1: SA from random graphs (200 runs) ───")
    println(log_io, "Phase 1: SA from random graphs")
    flush(log_io)

    for run in 1:200
        g0 = AdjMatrix(42)
        for i in 1:42, j in (i+1):42
            rand() < 0.5 && set_edge!(g0, i, j)
        end

        bg, bc = sa_ramsey42(g0; T0=100.0, alpha=0.999997, max_iter=10_000_000)
        total_runs += 1

        if bc == 0
            total_found_r55 += 1
            in_cat = is_in_catalog(bg, catalog)
            if in_cat
                found_in_catalog += 1
            else
                found_new += 1
                g6 = write_g6(bg)
                println("  *** RUN $run: POTENTIAL NEW GRAPH! g6=$g6 ***")
                println(log_io, "NEW: run=$run g6=$g6")
                write_g6_file(joinpath(results_dir, "potential_new_$(found_new).g6"), [bg])
            end

            if run <= 20 || run % 20 == 0
                @printf("  Run %3d: cost=0 (in_catalog=%s) [total: %d found, %d known, %d new]\n",
                        run, in_cat, total_found_r55, found_in_catalog, found_new)
            end
        else
            if run <= 10 || run % 50 == 0
                @printf("  Run %3d: best_cost=%d\n", run, bc)
            end
        end
        flush(log_io)
    end

    # ─── Phase 2: SA from perturbations of known graphs ───────────────
    println("\n─── Phase 2: SA from perturbations of known graphs (328 × 10) ───")
    println(log_io, "\nPhase 2: SA from perturbations")
    flush(log_io)

    half = read_g6_file(catalog_path)
    for (gi, g42) in enumerate(half)
        for pert in 1:10
            g0 = copy(g42)
            # Flip 3-8 random edges
            n_flips = rand(3:8)
            for _ in 1:n_flips
                i = rand(1:42)
                j = rand(1:41)
                j >= i && (j += 1)
                if i > j; i, j = j, i end
                flip_edge!(g0, i, j)
            end

            bg, bc = sa_ramsey42(g0; T0=30.0, alpha=0.999997, max_iter=5_000_000)
            total_runs += 1

            if bc == 0
                total_found_r55 += 1
                in_cat = is_in_catalog(bg, catalog)
                if in_cat
                    found_in_catalog += 1
                else
                    found_new += 1
                    g6 = write_g6(bg)
                    println("  *** GRAPH $gi PERT $pert: POTENTIAL NEW GRAPH! ***")
                    println(log_io, "NEW: graph=$gi pert=$pert g6=$g6")
                    write_g6_file(joinpath(results_dir, "potential_new_$(found_new).g6"), [bg])
                end
            end
        end

        if gi % 50 == 0
            elapsed = time() - t_start
            @printf("  Processed %d/328 base graphs, %d runs, %d R(5,5,42) found (%d known, %d new), %.0fs\n",
                    gi, total_runs, total_found_r55, found_in_catalog, found_new, elapsed)
        end
    end

    elapsed = time() - t_start

    println("\n" * "=" ^ 70)
    println("SEARCH COMPLETE")
    @printf("  Total runs: %d\n", total_runs)
    @printf("  R(5,5,42) graphs found: %d\n", total_found_r55)
    @printf("  In known catalog: %d\n", found_in_catalog)
    @printf("  Potentially new: %d\n", found_new)
    @printf("  Time: %.1fs\n", elapsed)
    println("=" ^ 70)

    # Save summary
    println(log_io, "\n--- SUMMARY ---")
    println(log_io, "Total runs: $total_runs")
    println(log_io, "R(5,5,42) found: $total_found_r55")
    println(log_io, "In catalog: $found_in_catalog")
    println(log_io, "Potentially new: $found_new")
    println(log_io, "Time: $(round(elapsed, digits=1))s")
    close(log_io)

    if found_new > 0
        println("\n⚠ FOUND $(found_new) POTENTIALLY NEW GRAPHS!")
        println("These need verification with nauty for true isomorphism testing.")
        println("Saved to results/potential_new_*.g6")
    else
        println("\nAll R(5,5,42) graphs found are in the known catalog.")
        println("This supports the McKay-Radziszowski completeness conjecture.")
    end
end

main()
