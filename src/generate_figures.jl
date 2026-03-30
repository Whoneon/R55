#!/usr/bin/env julia
"""
Generate data files for paper figures from R(5,5,42) analysis.
Outputs CSV/dat files that can be plotted with pgfplots in LaTeX.
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using LinearAlgebra

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    fig_dir = joinpath(@__DIR__, "..", "paper", "figures")
    mkpath(fig_dir)

    half = read_g6_file(catalog_path)
    println("Loaded $(length(half)) base graphs")

    # ─── 1. Degree distribution histogram ─────────────────────────────
    println("1. Degree distribution...")
    deg_counts = Dict{Int,Int}()
    for g in half
        for v in 1:42
            d = degree(g, v)
            deg_counts[d] = get(deg_counts, d, 0) + 1
        end
    end
    open(joinpath(fig_dir, "degree_hist.dat"), "w") do io
        println(io, "degree count")
        for d in sort(collect(keys(deg_counts)))
            println(io, "$d $(deg_counts[d])")
        end
    end

    # ─── 2. Edge count distribution ───────────────────────────────────
    println("2. Edge count distribution...")
    edge_counts = Dict{Int,Int}()
    for g in half
        ne = nedges(g)
        edge_counts[ne] = get(edge_counts, ne, 0) + 1
    end
    open(joinpath(fig_dir, "edge_hist.dat"), "w") do io
        println(io, "edges count")
        for ne in sort(collect(keys(edge_counts)))
            println(io, "$ne $(edge_counts[ne])")
        end
    end

    # ─── 3. Triangle count distribution ───────────────────────────────
    println("3. Triangle count distribution...")
    tri_vals = [count_triangles(g) for g in half]
    tri_counts = Dict{Int,Int}()
    for t in tri_vals
        tri_counts[t] = get(tri_counts, t, 0) + 1
    end
    open(joinpath(fig_dir, "triangle_hist.dat"), "w") do io
        println(io, "triangles count")
        for t in sort(collect(keys(tri_counts)))
            println(io, "$t $(tri_counts[t])")
        end
    end

    # ─── 4. Spectral data (eigenvalue 1 and gap) ─────────────────────
    println("4. Spectral data...")
    lambda1_vals = Float64[]
    gap_vals = Float64[]
    for g in half
        A = Float64.(adjacency_matrix(g))
        eigs = sort(eigvals(Symmetric(A)), rev=true)
        push!(lambda1_vals, eigs[1])
        push!(gap_vals, eigs[1] - eigs[2])
    end
    open(joinpath(fig_dir, "spectral.dat"), "w") do io
        println(io, "index lambda1 gap")
        for i in 1:length(half)
            @printf(io, "%d %.6f %.6f\n", i, lambda1_vals[i], gap_vals[i])
        end
    end

    # ─── 5. Edit distance distribution (sample for histogram) ────────
    println("5. Edit distance distribution...")
    n = length(half)
    dist_counts = Dict{Int,Int}()
    for i in 1:n
        for j in (i+1):n
            d = 0
            for r in 1:42
                d += count_ones(half[i].rows[r] ⊻ half[j].rows[r])
            end
            d >>= 1
            # Bin by 10s for histogram
            bin = (d ÷ 10) * 10
            dist_counts[bin] = get(dist_counts, bin, 0) + 1
        end
    end
    open(joinpath(fig_dir, "edit_distance_hist.dat"), "w") do io
        println(io, "distance_bin count")
        for d in sort(collect(keys(dist_counts)))
            println(io, "$d $(dist_counts[d])")
        end
    end

    # ─── 6. K₄ count distribution ────────────────────────────────────
    println("6. K4 count distribution...")
    k4_vals = Int[]
    for g in half
        k4 = 0
        @inbounds for i in 1:42
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
        push!(k4_vals, k4)
    end
    k4_counts = Dict{Int,Int}()
    for k in k4_vals
        k4_counts[k] = get(k4_counts, k, 0) + 1
    end
    open(joinpath(fig_dir, "k4_hist.dat"), "w") do io
        println(io, "k4count count")
        for k in sort(collect(keys(k4_counts)))
            println(io, "$k $(k4_counts[k])")
        end
    end

    # ─── 7. Lambda1 vs spectral gap scatter ──────────────────────────
    # Already in spectral.dat

    # ─── 8. Degree sequence diversity ─────────────────────────────────
    println("7. Degree sequence diversity...")
    deg_seqs = [degree_sequence(g) for g in half]
    unique_seqs = unique(deg_seqs)
    seq_sizes = Dict{Vector{Int},Int}()
    for ds in deg_seqs
        seq_sizes[ds] = get(seq_sizes, ds, 0) + 1
    end
    open(joinpath(fig_dir, "degseq_classes.dat"), "w") do io
        println(io, "class_id size mean_degree")
        for (i, (ds, cnt)) in enumerate(sort(collect(seq_sizes), by=x->-x[2]))
            md = sum(ds) / length(ds)
            @printf(io, "%d %d %.2f\n", i, cnt, md)
        end
    end

    println("\nAll figure data saved to $fig_dir/")
    println("Files: degree_hist.dat, edge_hist.dat, triangle_hist.dat,")
    println("       spectral.dat, edit_distance_hist.dat, k4_hist.dat,")
    println("       degseq_classes.dat")
end

main()
