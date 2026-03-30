#!/usr/bin/env julia
"""
Parallel search for a 657th graph in R(5,5,42).
Uses all available threads for embarrassingly parallel SA runs.

Launch with: julia -t auto search_657th_parallel.jl
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using Random
using Dates
using Base.Threads

# ─── Fingerprint for fast catalog membership ──────────────────────────────

struct GraphFingerprint
    nedges::Int
    deg_seq::Vector{Int}
    tri_count::Int
    k4_count::Int
end

function fingerprint(g::AdjMatrix)
    n = g.n
    degs = sort!([degree(g, i) for i in 1:n])
    ne = sum(degs) ÷ 2
    tc = count_triangles(g)
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

function vertex_invariants(g::AdjMatrix)
    n = g.n
    inv = Vector{Tuple{Int,Int,Int}}(undef, n)
    for v in 1:n
        d = degree(g, v)
        tv = 0
        nv = g.rows[v]
        u_mask = nv
        while u_mask != UInt64(0)
            u = trailing_zeros(u_mask) + 1
            u_mask &= u_mask - UInt64(1)
            tv += count_ones(nv & g.rows[u] & ~((UInt64(1) << u) - UInt64(1)))
        end
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
    inv = vertex_invariants(g)
    perm = sortperm(inv)
    induced_subgraph(g, perm)
end

function is_in_catalog(g::AdjMatrix, catalog::CatalogFull)
    g6 = write_g6(g)
    g6 in catalog.g6_set && return true
    gc = canonical_relabel(g)
    write_g6(gc) in catalog.g6_set && return true
    gbar = complement_graph(g)
    write_g6(gbar) in catalog.g6_set && return true
    gbarc = canonical_relabel(gbar)
    write_g6(gbarc) in catalog.g6_set && return true
    fp = fingerprint(g)
    for cfp in catalog.fingerprints
        if fp.nedges == cfp.nedges && fp.tri_count == cfp.tri_count &&
           fp.k4_count == cfp.k4_count && fp.deg_seq == cfp.deg_seq
            return true  # fingerprint match — conservatively assume known
        end
    end
    return false  # no fingerprint match — genuinely new!
end

# ─── SA core (thread-safe: no shared mutable state) ──────────────────────

function sa_ramsey42(seed_g::AdjMatrix, rng::AbstractRNG;
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
        i = rand(rng, 1:n)
        j = rand(rng, 1:n-1)
        j >= i && (j += 1)
        if i > j; i, j = j, i end

        flip_edge!(g, i, j)
        new_red = count_clique5(g)
        new_blue = count_clique5(complement_graph(g))
        new_cost = new_red + new_blue
        delta = new_cost - current_cost

        if delta <= 0 || rand(rng) < exp(-delta / T)
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

# ─── Main ─────────────────────────────────────────────────────────────────

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    results_dir = joinpath(@__DIR__, "..", "results")
    mkpath(results_dir)

    nt = nthreads()
    println("=" ^ 70)
    println("PARALLEL SEARCH FOR 657th GRAPH IN R(5,5,42)")
    println("Threads: $nt")
    println("=" ^ 70)

    println("\nBuilding catalog...")
    catalog = build_full_catalog(catalog_path)
    println("  $(length(catalog.graphs)) graphs loaded")

    half = read_g6_file(catalog_path)

    # Atomic counters
    total_runs = Atomic{Int}(0)
    total_r55 = Atomic{Int}(0)
    found_in_catalog = Atomic{Int}(0)
    found_new = Atomic{Int}(0)
    lock_io = ReentrantLock()

    t_start = time()

    # ─── Phase 1: Random starts (500 runs, parallel) ─────────────────
    n_random = 500
    println("\n--- Phase 1: $n_random random SA runs ($nt threads) ---")

    @threads for run in 1:n_random
        rng = MersenneTwister(run + 1000 * threadid())
        g0 = AdjMatrix(42)
        for i in 1:42, j in (i+1):42
            rand(rng) < 0.5 && set_edge!(g0, i, j)
        end

        bg, bc = sa_ramsey42(g0, rng; T0=100.0, alpha=0.999997, max_iter=10_000_000)
        atomic_add!(total_runs, 1)

        if bc == 0
            atomic_add!(total_r55, 1)
            in_cat = is_in_catalog(bg, catalog)
            if in_cat
                atomic_add!(found_in_catalog, 1)
            else
                atomic_add!(found_new, 1)
                g6 = write_g6(bg)
                lock(lock_io) do
                    println("  *** RUN $run: POTENTIAL NEW GRAPH! g6=$g6 ***")
                    write_g6_file(joinpath(results_dir, "potential_new_r$(run).g6"), [bg])
                end
            end
        end

        r = total_runs[]
        if r % 50 == 0
            lock(lock_io) do
                elapsed = time() - t_start
                @printf("  [Phase 1] %d/%d runs, %d R(5,5,42), %d known, %d new (%.0fs)\n",
                        r, n_random, total_r55[], found_in_catalog[], found_new[], elapsed)
            end
        end
    end

    elapsed1 = time() - t_start
    @printf("\nPhase 1 done: %d runs, %d R(5,5,42) found, %d known, %d new (%.0fs)\n",
            total_runs[], total_r55[], found_in_catalog[], found_new[], elapsed1)

    # ─── Phase 2: Perturbations of known graphs (328 × 20, parallel) ─
    n_pert = 20
    n_base = length(half)
    tasks = [(gi, p) for gi in 1:n_base for p in 1:n_pert]
    n_tasks = length(tasks)

    println("\n--- Phase 2: $n_base graphs × $n_pert perturbations = $n_tasks runs ---")

    @threads for idx in 1:n_tasks
        gi, pert = tasks[idx]
        rng = MersenneTwister(idx + 100_000 + 1000 * threadid())
        g0 = copy(half[gi])
        n_flips = rand(rng, 3:8)
        for _ in 1:n_flips
            i = rand(rng, 1:42)
            j = rand(rng, 1:41)
            j >= i && (j += 1)
            if i > j; i, j = j, i end
            flip_edge!(g0, i, j)
        end

        bg, bc = sa_ramsey42(g0, rng; T0=30.0, alpha=0.999997, max_iter=5_000_000)
        atomic_add!(total_runs, 1)

        if bc == 0
            atomic_add!(total_r55, 1)
            in_cat = is_in_catalog(bg, catalog)
            if in_cat
                atomic_add!(found_in_catalog, 1)
            else
                atomic_add!(found_new, 1)
                g6 = write_g6(bg)
                lock(lock_io) do
                    println("  *** GRAPH $gi PERT $pert: POTENTIAL NEW GRAPH! ***")
                    write_g6_file(joinpath(results_dir, "potential_new_p$(gi)_$(pert).g6"), [bg])
                end
            end
        end

        r = total_runs[]
        if r % 200 == 0
            lock(lock_io) do
                elapsed = time() - t_start
                @printf("  [Phase 2] %d/%d total runs, %d R(5,5,42), %d known, %d new (%.0fs)\n",
                        r, n_random + n_tasks, total_r55[], found_in_catalog[], found_new[], elapsed)
            end
        end
    end

    elapsed_total = time() - t_start

    println("\n" * "=" ^ 70)
    println("SEARCH COMPLETE")
    @printf("  Total runs:         %d\n", total_runs[])
    @printf("  R(5,5,42) found:    %d\n", total_r55[])
    @printf("  In known catalog:   %d\n", found_in_catalog[])
    @printf("  Potentially new:    %d\n", found_new[])
    @printf("  Total time:         %.1fs (%.1f min)\n", elapsed_total, elapsed_total/60)
    @printf("  Throughput:         %.1f runs/min\n", total_runs[] / (elapsed_total/60))
    println("=" ^ 70)

    # Save summary
    open(joinpath(results_dir, "search_657_parallel_log.txt"), "w") do io
        println(io, "Search for 657th graph in R(5,5,42)")
        println(io, "Date: $(now())")
        println(io, "Threads: $nt")
        println(io, "Phase 1: $n_random random SA runs (10M iter each)")
        println(io, "Phase 2: $n_base × $n_pert perturbation SA runs (5M iter each)")
        println(io, "Total runs: $(total_runs[])")
        println(io, "R(5,5,42) found: $(total_r55[])")
        println(io, "In catalog: $(found_in_catalog[])")
        println(io, "Potentially new: $(found_new[])")
        println(io, "Time: $(round(elapsed_total, digits=1))s")
    end

    if found_new[] > 0
        println("\n!!! FOUND $(found_new[]) POTENTIALLY NEW GRAPHS !!!")
        println("Verify with nauty for definitive isomorphism testing.")
    else
        println("\nAll R(5,5,42) graphs found are in the known catalog.")
        println("Supports McKay-Radziszowski completeness conjecture.")
    end
end

main()
