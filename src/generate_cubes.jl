#!/usr/bin/env julia
"""
Custom cube generator for R(5,5,43) SAT instance.

march_cu crashes on our 2M-clause CNF, so we generate cubes ourselves
using domain knowledge:

Strategy: partition by fixing the adjacency of vertex 1 (edges 1-2, 1-3, ..., 1-43).
These are variables 1..42 in our encoding.
Vertex 1 has 42 possible neighbors, so fixing all of them gives 2^42 cubes — too many.

Better: fix edges of vertices 1 and 2 (partially).
Or: use the structure of R(5,5) — we know the degree should be ~20,
so we only need cubes where vertex 1 has degree 18-24.

Approach:
1. Fix vertex 1's full adjacency (42 variables) → 2^42 cubes (too many)
2. Fix vertex 1's adjacency + degree constraint → ~C(42,20) ≈ 10^11 (still too many)
3. Fix vertices 1,2,3 partial adjacency with pruning → manageable

Actually, the best approach for BOINC: fix the first K variables
and let CaDiCaL handle the rest. We calibrate K so each cube takes
~10-60 minutes. From our tests:
- K=20 sparse vars: ~60s (timeout)
- K=400 consecutive: ~2s (too easy, trivial propagation)

The key insight: use EDGE variables for a specific vertex pair.
Fix all edges involving vertices {1,2,...,m} for some small m.
This gives a structured partition.
"""

using Printf

function edge_var(i::Int, j::Int, n::Int)
    # Same mapping as sat_encoding.jl
    return (i - 1) * n - i * (i + 1) ÷ 2 + j
end

function generate_cubes_by_vertex(n::Int, n_fixed_vertices::Int, outfile::String)
    # Fix all edges among the first m vertices AND between first m and the rest
    # Variables to fix: all edges (i,j) where i ≤ m
    # Number of such edges: m*(m-1)/2 + m*(n-m) = m*(2n-m-1)/2
    m = n_fixed_vertices
    n_fix = m * (2*n - m - 1) ÷ 2

    println("Cube generation for R(5,5,$n)")
    println("  Fixing all edges involving vertices 1..$m")
    println("  Variables fixed per cube: $n_fix")
    println("  Total cubes: 2^$n_fix = $(BigInt(2)^n_fix)")

    if n_fix > 30
        println("  WARNING: 2^$n_fix > 10^9 cubes — too many for enumeration")
        println("  Use depth-limited generation instead")

        # Generate only cubes at a given depth
        generate_cubes_depth_limited(n, m, outfile, max_cubes=100_000)
        return
    end

    # Enumerate all 2^n_fix combinations
    vars_to_fix = Int[]
    for i in 1:m
        for j in (i+1):n
            push!(vars_to_fix, edge_var(i, j, n))
        end
    end

    @assert length(vars_to_fix) == n_fix

    total = 1 << n_fix
    open(outfile, "w") do io
        for mask in 0:(total-1)
            print(io, "a ")
            for (k, var) in enumerate(vars_to_fix)
                if (mask >> (k-1)) & 1 == 1
                    print(io, var, " ")
                else
                    print(io, -var, " ")
                end
            end
            println(io, "0")
        end
    end

    println("  Generated $total cubes → $outfile")
end

function generate_cubes_depth_limited(n::Int, m::Int, outfile::String;
                                       max_cubes::Int=100_000)
    # Instead of fixing ALL edges of vertices 1..m,
    # fix only edges of vertex 1 to all others (42 vars)
    # plus edges of vertex 2 to vertices 3..n (41 vars)
    # etc., but stop when we have enough variables

    # Calibration target: each cube should take ~10-30 min on CaDiCaL
    # From tests: ~30 structured variables → ~30s-few min

    # Strategy: fix edges of vertex 1 completely (42 vars)
    # This gives 2^42 ≈ 4×10^12 cubes — way too many
    # But with degree pruning (vertex 1 should have degree 18-24),
    # we get C(42,18)+...+C(42,24) ≈ 10^11 — still too many

    # Better: fix edges (1,j) for j=2..22 (21 vars) = 2^21 ≈ 2M cubes
    # Each cube restricts half of vertex 1's adjacency
    # This should be enough for CaDiCaL to handle each in ~minutes

    n_fix = min(21, n - 1)  # fix first 21 edges of vertex 1
    vars = [edge_var(1, j, n) for j in 2:(n_fix+1)]

    total = 1 << n_fix
    println("  Depth-limited: fixing $n_fix edges of vertex 1")
    println("  Total cubes: $total")

    open(outfile, "w") do io
        for mask in 0:(total-1)
            print(io, "a ")
            for (k, var) in enumerate(vars)
                if (mask >> (k-1)) & 1 == 1
                    print(io, var, " ")
                else
                    print(io, -var, " ")
                end
            end
            println(io, "0")
        end
    end

    println("  Generated $total cubes → $outfile")
    println("  Estimated time per cube: test with CaDiCaL")
end

function main()
    outdir = joinpath(@__DIR__, "..", "results", "sat")
    mkpath(outdir)

    println("=" ^ 70)
    println("CUBE GENERATION FOR R(5,5,43)")
    println("=" ^ 70)

    # Generate cubes: fix first 21 edges of vertex 1
    # This gives 2^21 = 2,097,152 cubes
    outfile = joinpath(outdir, "cubes_v1_21.icnf")
    generate_cubes_by_vertex(43, 1, outfile)

    # Also generate a small test set (fix first 10 edges)
    println("\n--- Small test set (2^10 = 1024 cubes) ---")
    vars10 = [edge_var(1, j, 43) for j in 2:11]
    test_file = joinpath(outdir, "cubes_test_1024.icnf")
    open(test_file, "w") do io
        for mask in 0:1023
            print(io, "a ")
            for (k, var) in enumerate(vars10)
                if (mask >> (k-1)) & 1 == 1
                    print(io, var, " ")
                else
                    print(io, -var, " ")
                end
            end
            println(io, "0")
        end
    end
    println("  Generated 1024 test cubes → $test_file")

    println("\n" * "=" ^ 70)
    println("Next: test a few cubes with CaDiCaL to calibrate timing")
    println("  cadical r55_43_plain.cnf <assumptions from cube>")
    println("=" ^ 70)
end

main()
