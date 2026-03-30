#!/usr/bin/env julia
"""
Analyze the 7 pairs of R(5,5,42) graphs at edit distance 1.
These pairs differ by exactly one edge — understanding why both
are K₅-free could reveal structural constraints.
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    half = read_g6_file(catalog_path)
    n = length(half)

    println("=" ^ 70)
    println("Analysis of Close Pairs in R(5,5,42)")
    println("=" ^ 70)

    # Find all pairs at small edit distance
    println("\n─── Pairs at edit distance ≤ 5 ───")
    close_pairs = Tuple{Int,Int,Int}[]
    for i in 1:n
        for j in (i+1):n
            d = 0
            for r in 1:42
                d += count_ones(half[i].rows[r] ⊻ half[j].rows[r])
            end
            d >>= 1  # undirected
            if d <= 5
                push!(close_pairs, (i, j, d))
            end
        end
    end

    sort!(close_pairs, by=x->x[3])
    for (i, j, d) in close_pairs
        println("\n  Pair ($i, $j), edit distance = $d")

        # Find the differing edges
        diff_edges = Tuple{Int,Int}[]
        for u in 1:42
            xor_row = half[i].rows[u] ⊻ half[j].rows[u]
            while xor_row != UInt64(0)
                v = trailing_zeros(xor_row) + 1
                xor_row &= xor_row - UInt64(1)
                if v > u
                    push!(diff_edges, (u, v))
                end
            end
        end
        println("    Differing edges: $diff_edges")

        for (u, v) in diff_edges
            # In graph i: is (u,v) present?
            has_i = has_edge(half[i], u, v)
            has_j = has_edge(half[j], u, v)
            println("    Edge ($u,$v): graph $i=$(has_i ? "red" : "blue"), graph $j=$(has_j ? "red" : "blue")")

            # How many common neighbors of u,v?
            cn_i = count_ones(common_neighbors(half[i], u, v))
            cn_j = count_ones(common_neighbors(half[j], u, v))
            println("    Common neighbors: graph $i=$cn_i, graph $j=$cn_j")

            # Check: what K₅ would be created if we flipped this edge?
            # In graph i, if we flip (u,v), we'd get graph j (for d=1 pairs)
            # Both are K₅-free, so the flip is "safe"

            # How many K₄ contain both u and v?
            cn_mask_i = common_neighbors(half[i], u, v)
            k4_count = 0
            w_mask = cn_mask_i
            while w_mask != UInt64(0)
                w = trailing_zeros(w_mask) + 1
                w_mask &= w_mask - UInt64(1)
                x_mask = cn_mask_i & half[i].rows[w] & ~((UInt64(1) << w) - UInt64(1))
                k4_count += count_ones(x_mask)
            end
            println("    K₄ containing {u,v} in graph $i: $k4_count")
        end

        # Degree comparison at differing vertices
        for (u, v) in diff_edges
            di_u = degree(half[i], u)
            dj_u = degree(half[j], u)
            di_v = degree(half[i], v)
            dj_v = degree(half[j], v)
            println("    Degrees at $u: g$i=$di_u, g$j=$dj_u; at $v: g$i=$di_v, g$j=$dj_v")
        end
    end

    # Extension analysis for close pair graphs
    println("\n─── Extension Tension for Close Pairs ───")
    for (i, j, d) in close_pairs[1:min(5, length(close_pairs))]
        t_i = extension_tension(half[i])
        t_j = extension_tension(half[j])
        @printf("  Pair (%d,%d) d=%d: tension_i=%d, tension_j=%d\n", i, j, d, t_i, t_j)
    end

    println("\n" * "=" ^ 70)
end

main()
