#!/usr/bin/env julia
"""
Module B: Structural analysis of the 656 R(5,5,42) extremal graphs.

Computes:
- Degree sequences and statistics
- Triangle counts
- K₄ counts
- Spectral properties (eigenvalues of adjacency matrix)
- Self-complementarity check
- Which graphs are circulant
- Edit distances between graphs
"""

include("RamseyR55.jl")
using .RamseyR55
using LinearAlgebra
using Printf

# ─── Load catalog ──────────────────────────────────────────────────────────

function load_full_catalog(path::String)
    half = read_g6_file(path)
    full = AdjMatrix[]
    for g in half
        push!(full, g)
        push!(full, complement_graph(g))
    end
    return full, half
end

# ─── Analysis functions ────────────────────────────────────────────────────

function count_K4(g::AdjMatrix)
    n = g.n
    count = 0
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
                count += count_ones(l_mask)
            end
        end
    end
    return count
end

"""Count K₅-minus-edge (K₅−e) subgraphs in g: 5 vertices with exactly 9 edges."""
function count_near_K5(g::AdjMatrix)
    n = g.n
    count = 0
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
                nijk = nij & g.rows[k]
                # l connected to i,j,k: l in nijk, l > k
                l_mask = nijk & ~((UInt64(1) << k) - UInt64(1))
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)
                    # {i,j,k,l} is a K₄. Now find m connected to exactly 3 of {i,j,k,l}, m > l
                    nijkl = nijk & g.rows[l]
                    # m in nijkl and m > l: these are K₅ (all 4 connections)
                    # We want m connected to exactly 3 of i,j,k,l
                    # m not in nijkl but in (ni|nj|nk|nl) minus itself...
                    # Simpler: m connected to 3 out of 4, so m in exactly one of
                    # {nij&nk, nij&nl, nik&nl, njk&nl} minus nijkl
                    for (a, b, c, d) in [(ni, g.rows[j], g.rows[k], g.rows[l])]
                        abc = a & b & c
                        abd = a & b & d
                        acd = a & c & d
                        bcd = b & c & d
                        all4 = abc & d
                        exactly3 = (abc | abd | acd | bcd) & ~all4 & ~((UInt64(1) << l) - UInt64(1))
                        # Remove i,j,k,l themselves
                        for v in (i, j, k, l)
                            exactly3 &= ~(UInt64(1) << (v-1))
                        end
                        count += count_ones(exactly3)
                    end
                end
            end
        end
    end
    # Each K₅−e is counted multiple times depending on which K₄ we start from
    # A K₅−e has exactly one missing edge. The 4 vertices connected to the
    # "central" structure... actually this overcounts. Let's use a simpler approach.
    # For now, just return the raw count (we'll normalize later or use a cleaner method)
    return count
end

function eigenvalues_sorted(g::AdjMatrix)
    A = Float64.(adjacency_matrix(g))
    ev = eigvals(Symmetric(A))
    return sort(ev, rev=true)
end

function edit_distance(g1::AdjMatrix, g2::AdjMatrix)
    @assert g1.n == g2.n
    d = 0
    for i in 1:g1.n
        d += count_ones(g1.rows[i] ⊻ g2.rows[i])
    end
    return d >> 1  # each differing edge counted twice
end

function is_circulant(g::AdjMatrix)
    n = g.n
    # A circulant graph has the property that row[i] is a cyclic shift of row[1]
    # Check: for all i, adj(i,j) depends only on (j-i) mod n
    ref = g.rows[1]
    for i in 2:n
        # Rotate ref by (i-1) positions
        shift = i - 1
        # rotated = (ref >> shift) | (ref << (n - shift)) restricted to n bits
        mask = (UInt64(1) << n) - UInt64(1)
        rotated = ((ref >> shift) | (ref << (n - shift))) & mask
        if g.rows[i] != rotated
            return false
        end
    end
    return true
end

# ─── Main analysis ─────────────────────────────────────────────────────────

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    println("=" ^ 70)
    println("MODULE B: Structural Analysis of R(5,5,42) Extremal Graphs")
    println("=" ^ 70)

    full, half = load_full_catalog(catalog_path)
    println("Loaded $(length(half)) graphs + $(length(half)) complements = $(length(full)) total\n")

    # ── Degree statistics ──────────────────────────────────────────────
    println("─── Degree Statistics ───")
    deg_stats = []
    for (i, g) in enumerate(half)
        ds = degree_sequence(g)
        push!(deg_stats, (min=ds[1], max=ds[end], mean=sum(ds)/length(ds),
                          seq=ds, nedges=nedges(g)))
    end

    min_degs = [s.min for s in deg_stats]
    max_degs = [s.max for s in deg_stats]
    mean_degs = [s.mean for s in deg_stats]
    edge_counts = [s.nedges for s in deg_stats]

    @printf("  Min degree:  range [%d, %d], mean %.2f\n", minimum(min_degs), maximum(min_degs), sum(min_degs)/length(min_degs))
    @printf("  Max degree:  range [%d, %d], mean %.2f\n", minimum(max_degs), maximum(max_degs), sum(max_degs)/length(max_degs))
    @printf("  Mean degree: range [%.2f, %.2f], mean %.2f\n", minimum(mean_degs), maximum(mean_degs), sum(mean_degs)/length(mean_degs))
    @printf("  Edge count:  range [%d, %d], mean %.1f\n\n", minimum(edge_counts), maximum(edge_counts), sum(edge_counts)/length(edge_counts))

    # Degree sequence histogram
    deg_seqs_unique = Dict{Vector{Int}, Int}()
    for s in deg_stats
        deg_seqs_unique[s.seq] = get(deg_seqs_unique, s.seq, 0) + 1
    end
    println("  Unique degree sequences: $(length(deg_seqs_unique))")
    for (seq, cnt) in sort(collect(deg_seqs_unique), by=x->x[2], rev=true)[1:min(5, length(deg_seqs_unique))]
        println("    count=$cnt: min=$(seq[1]) max=$(seq[end]) edges=$(sum(seq)÷2)")
    end

    # ── Triangle and K₄ counts ─────────────────────────────────────────
    println("\n─── Subgraph Counts ───")
    tri_counts = Int[]
    k4_counts = Int[]
    for g in half
        push!(tri_counts, count_triangles(g))
        push!(k4_counts, count_K4(g))
    end
    @printf("  Triangles: range [%d, %d], mean %.1f\n", minimum(tri_counts), maximum(tri_counts), sum(tri_counts)/length(tri_counts))
    @printf("  K₄ count:  range [%d, %d], mean %.1f\n\n", minimum(k4_counts), maximum(k4_counts), sum(k4_counts)/length(k4_counts))

    # ── Circulant check ────────────────────────────────────────────────
    println("─── Circulant Check ───")
    n_circ = 0
    circ_indices = Int[]
    for (i, g) in enumerate(half)
        if is_circulant(g)
            n_circ += 1
            push!(circ_indices, i)
        end
    end
    println("  Circulant graphs in catalog: $n_circ / $(length(half))")
    if n_circ > 0
        println("  Indices: $circ_indices")
    end

    # Check if Exoo(42) is in the catalog (by graph6 encoding)
    exoo = exoo42()
    exoo_g6 = write_g6(exoo)
    exoo_comp_g6 = write_g6(complement_graph(exoo))
    found_exoo = false
    for (i, g) in enumerate(half)
        g6 = write_g6(g)
        if g6 == exoo_g6 || g6 == exoo_comp_g6
            println("  Exoo(42) found in catalog at index $i")
            found_exoo = true
            break
        end
    end
    if !found_exoo
        println("  Exoo(42) NOT found in catalog by exact g6 match (may be isomorphic to one)")
    end

    # ── Spectral analysis ──────────────────────────────────────────────
    println("\n─── Spectral Analysis ───")
    all_eigs = []
    for g in half
        push!(all_eigs, eigenvalues_sorted(g))
    end

    # Largest eigenvalue
    lambda1 = [ev[1] for ev in all_eigs]
    lambda2 = [ev[2] for ev in all_eigs]
    lambda_n = [ev[end] for ev in all_eigs]
    @printf("  λ₁ (largest):  range [%.4f, %.4f], mean %.4f\n", minimum(lambda1), maximum(lambda1), sum(lambda1)/length(lambda1))
    @printf("  λ₂ (second):   range [%.4f, %.4f], mean %.4f\n", minimum(lambda2), maximum(lambda2), sum(lambda2)/length(lambda2))
    @printf("  λₙ (smallest): range [%.4f, %.4f], mean %.4f\n\n", minimum(lambda_n), maximum(lambda_n), sum(lambda_n)/length(lambda_n))

    # Spectral gap
    gaps = lambda1 .- lambda2
    @printf("  Spectral gap (λ₁-λ₂): range [%.4f, %.4f], mean %.4f\n", minimum(gaps), maximum(gaps), sum(gaps)/length(gaps))

    # ── Edit distance matrix (sample) ──────────────────────────────────
    println("\n─── Edit Distances (full 328×328) ───")
    n_half = length(half)
    dist_matrix = zeros(Int, n_half, n_half)
    for i in 1:n_half
        for j in (i+1):n_half
            d = edit_distance(half[i], half[j])
            dist_matrix[i, j] = d
            dist_matrix[j, i] = d
        end
    end

    # Statistics on edit distances
    all_dists = [dist_matrix[i,j] for i in 1:n_half for j in (i+1):n_half]
    @printf("  Min edit distance: %d\n", minimum(all_dists))
    @printf("  Max edit distance: %d\n", maximum(all_dists))
    @printf("  Mean edit distance: %.2f\n", sum(all_dists)/length(all_dists))
    @printf("  Median edit distance: %d\n\n", sort(all_dists)[length(all_dists)÷2])

    # Histogram of edit distances
    println("  Edit distance histogram:")
    hist = Dict{Int,Int}()
    for d in all_dists
        hist[d] = get(hist, d, 0) + 1
    end
    for d in sort(collect(keys(hist)))
        @printf("    d=%3d: %d pairs\n", d, hist[d])
    end

    # ── Extension tension (sample) ─────────────────────────────────────
    println("\n─── Extension Tension (sample, 100k random patterns per graph) ───")
    sample_size = min(20, length(half))
    for i in 1:sample_size
        t = extension_tension(half[i])
        @printf("  Graph %3d: min K₅ from random extension = %d\n", i, t)
    end

    # ── Save results ───────────────────────────────────────────────────
    results_dir = joinpath(@__DIR__, "..", "results")
    mkpath(results_dir)

    # Save eigenvalues
    open(joinpath(results_dir, "eigenvalues.csv"), "w") do io
        println(io, "graph_idx," * join(["ev_$i" for i in 1:42], ","))
        for (i, ev) in enumerate(all_eigs)
            println(io, "$i," * join([@sprintf("%.8f", e) for e in ev], ","))
        end
    end

    # Save degree sequences
    open(joinpath(results_dir, "degree_sequences.csv"), "w") do io
        println(io, "graph_idx," * join(["d_$i" for i in 1:42], ","))
        for (i, s) in enumerate(deg_stats)
            println(io, "$i," * join(string.(s.seq), ","))
        end
    end

    # Save subgraph counts
    open(joinpath(results_dir, "subgraph_counts.csv"), "w") do io
        println(io, "graph_idx,edges,triangles,K4")
        for i in 1:length(half)
            println(io, "$i,$(edge_counts[i]),$(tri_counts[i]),$(k4_counts[i])")
        end
    end

    # Save edit distance matrix
    open(joinpath(results_dir, "edit_distances.csv"), "w") do io
        for i in 1:n_half
            println(io, join(dist_matrix[i, :], ","))
        end
    end

    println("\n✓ Results saved to $(results_dir)/")
    println("=" ^ 70)
end

main()
