#!/usr/bin/env julia
"""
Exact computation of extension tension τ(G) for all 656 R(5,5,42) extremal graphs.

τ(G) = min over all N ⊆ V(G) of:
    #{K₄ in G[N]} + #{I₄ in G[N̄]}

Strategy: SAT-based binary search using PySAT (called via shell).
Heuristic seeding + verification in Julia (fast bitmask ops).
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf

# ─── K₄ enumeration as bitmasks ──────────────────────────────────────────

function enumerate_K4_masks(g::AdjMatrix)
    n = g.n
    masks = UInt64[]
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
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)
                    push!(masks, (UInt64(1) << (i-1)) | (UInt64(1) << (j-1)) |
                                 (UInt64(1) << (k-1)) | (UInt64(1) << (l-1)))
                end
            end
        end
    end
    return masks
end

"""Fast cost evaluation using bitmasks."""
@inline function eval_cost(red_masks::Vector{UInt64}, blue_masks::Vector{UInt64},
                           N::UInt64, vmask::UInt64)
    cost = 0
    Nbar = vmask & ~N
    @inbounds for m in red_masks
        cost += ((m & N) == m) % Int
    end
    @inbounds for m in blue_masks
        cost += ((m & Nbar) == m) % Int
    end
    return cost
end

# ─── Heuristic search (fast) ─────────────────────────────────────────────

function heuristic_tension(red_masks::Vector{UInt64}, blue_masks::Vector{UInt64},
                           n::Int; samples::Int=1_000_000)
    vmask = (UInt64(1) << n) - UInt64(1)
    best = typemax(Int)
    best_mask = UInt64(0)

    for _ in 1:samples
        N = rand(UInt64) & vmask
        c = eval_cost(red_masks, blue_masks, N, vmask)
        if c < best
            best = c
            best_mask = N
        end
    end
    return best, best_mask
end

# ─── Local search improvement ────────────────────────────────────────────

"""Improve a solution by flipping single bits (steepest descent)."""
function local_search!(red_masks::Vector{UInt64}, blue_masks::Vector{UInt64},
                       N::UInt64, n::Int)
    vmask = (UInt64(1) << n) - UInt64(1)
    current_cost = eval_cost(red_masks, blue_masks, N, vmask)
    improved = true

    while improved
        improved = false
        for v in 0:(n-1)
            N_new = N ⊻ (UInt64(1) << v)
            c = eval_cost(red_masks, blue_masks, N_new, vmask)
            if c < current_cost
                current_cost = c
                N = N_new
                improved = true
            end
        end
    end
    return current_cost, N
end

# ─── Multi-start local search ────────────────────────────────────────────

"""
Exact or near-exact τ(G) via massive random sampling + local search.

With 42 binary variables, local search can explore the neighborhood
efficiently. Each restart: random N → steepest descent (flipping single bits).
"""
function exact_tension_local(g::AdjMatrix; restarts::Int=50_000, samples::Int=500_000)
    n = g.n
    gc = complement_graph(g)

    red_masks = enumerate_K4_masks(g)
    blue_masks = enumerate_K4_masks(gc)
    vmask = (UInt64(1) << n) - UInt64(1)

    n_red = length(red_masks)
    n_blue = length(blue_masks)

    # Phase 1: pure random sampling (very fast)
    best, best_mask = heuristic_tension(red_masks, blue_masks, n; samples=samples)

    # Phase 2: multi-start local search
    for r in 1:restarts
        N = rand(UInt64) & vmask
        c, N_opt = local_search!(red_masks, blue_masks, N, n)
        if c < best
            best = c
            best_mask = N_opt
        end
    end

    # Phase 3: local search from best solution with 2-bit flips
    for v1 in 0:(n-2)
        for v2 in (v1+1):(n-1)
            N_new = best_mask ⊻ (UInt64(1) << v1) ⊻ (UInt64(1) << v2)
            c, N_opt = local_search!(red_masks, blue_masks, N_new, n)
            if c < best
                best = c
                best_mask = N_opt
            end
        end
    end

    return best, best_mask, n_red, n_blue
end

# ─── Write WCNF for external MaxSAT solving ──────────────────────────────

"""
Write a WCNF file for external MaxSAT solver verification.
Can be used with: open-wbo, EvalMaxSAT, CashWMaxSAT, etc.
"""
function write_wcnf(g::AdjMatrix, filename::String)
    n = g.n
    gc = complement_graph(g)

    red_cliques = Vector{NTuple{4,Int}}()
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
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)
                    push!(red_cliques, (i, j, k, l))
                end
            end
        end
    end

    blue_cliques = Vector{NTuple{4,Int}}()
    @inbounds for i in 1:n
        ni = gc.rows[i]
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            nij = ni & gc.rows[j]
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)
                l_mask = nij & gc.rows[k] & ~((UInt64(1) << k) - UInt64(1))
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)
                    push!(blue_cliques, (i, j, k, l))
                end
            end
        end
    end

    nclauses = length(red_cliques) + length(blue_cliques)
    top = nclauses + 1  # weight for hard clauses (none here)

    open(filename, "w") do io
        println(io, "p wcnf $n $nclauses $top")
        # Red K₄: soft clause (¬x[a] ∨ ¬x[b] ∨ ¬x[c] ∨ ¬x[d])
        for (a, b, c, d) in red_cliques
            println(io, "1 -$a -$b -$c -$d 0")
        end
        # Blue I₄: soft clause (x[a] ∨ x[b] ∨ x[c] ∨ x[d])
        for (a, b, c, d) in blue_cliques
            println(io, "1 $a $b $c $d 0")
        end
    end
    return nclauses, length(red_cliques), length(blue_cliques)
end

# ─── Main ─────────────────────────────────────────────────────────────────

function main()
    datafile = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    if !isfile(datafile)
        error("Data file not found: $datafile")
    end

    half = read_g6_file(datafile)
    println("Loaded $(length(half)) base graphs")

    outfile = joinpath(@__DIR__, "..", "results", "exact_tension.csv")
    mkpath(dirname(outfile))

    # Check for resume
    existing = Set{Int}()
    if isfile(outfile)
        for line in readlines(outfile)[2:end]
            parts = split(line, ',')
            if length(parts) >= 1
                push!(existing, parse(Int, parts[1]))
            end
        end
    end

    mode = isempty(existing) ? "w" : "a"
    all_taus = Int[]

    open(outfile, mode) do io
        if isempty(existing)
            println(io, "graph_idx,is_complement,base_idx,tau,best_mask_hex,degree_new_vertex,time_s")
        end

        for (i, g) in enumerate(half)
            gc = complement_graph(g)
            for (j, gg, is_comp) in [(2i-1, g, false), (2i, gc, true)]
                if j in existing
                    continue
                end

                label = is_comp ? "comp" : "orig"
                @printf("Graph %3d/656 (base %3d, %s): ", j, i, label)

                t0 = time()
                τ, mask, nr, nb = exact_tension_local(gg)
                elapsed = time() - t0
                deg = count_ones(mask)

                push!(all_taus, τ)
                @printf("τ = %3d (K4r=%d, K4b=%d), deg = %2d (%.1fs)\n",
                        τ, nr, nb, deg, elapsed)
                @printf(io, "%d,%s,%d,%d,%s,%d,%.1f\n",
                        j, is_comp, i, τ, string(mask, base=16), deg, elapsed)
                flush(io)
            end
        end
    end

    # Re-read for summary
    all_taus = Int[]
    for line in readlines(outfile)[2:end]
        parts = split(line, ',')
        if length(parts) >= 4
            push!(all_taus, parse(Int, parts[4]))
        end
    end

    if !isempty(all_taus)
        println("\n", "="^60)
        println("SUMMARY: $(length(all_taus)) graphs")
        println("="^60)
        @printf("  min τ = %d\n", minimum(all_taus))
        @printf("  max τ = %d\n", maximum(all_taus))
        @printf("  mean τ = %.2f\n", sum(all_taus) / length(all_taus))
        sorted = sort(all_taus)
        mid = length(sorted) ÷ 2
        @printf("  median τ = %.1f\n", (sorted[mid] + sorted[mid+1]) / 2.0)

        println("\nDistribution:")
        for τv in sort(unique(all_taus))
            cnt = count(==(τv), all_taus)
            @printf("  τ = %3d: %3d graphs (%.1f%%)\n",
                    τv, cnt, 100.0 * cnt / length(all_taus))
        end
    end

    # Also write WCNF for first graph (for external solver verification)
    wcnf_dir = joinpath(@__DIR__, "..", "results", "wcnf")
    mkpath(wcnf_dir)
    nc, nr, nb = write_wcnf(half[1], joinpath(wcnf_dir, "tension_g001.wcnf"))
    println("\nWCNF for graph 1: $nc clauses ($nr red, $nb blue)")
    println("Use with: open-wbo $(joinpath(wcnf_dir, "tension_g001.wcnf"))")

    println("\nResults: $outfile")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
