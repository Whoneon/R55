#!/usr/bin/env julia
"""
SAT encoding of R(5,5,43): is there a 2-coloring of K₄₃ with no
monochromatic K₅?

Output: DIMACS CNF file for use with CaDiCaL, Kissat, or other SAT solvers.

Variables: x_{ij} for 1 ≤ i < j ≤ 43
  x_{ij} = true  → edge (i,j) is RED
  x_{ij} = false → edge (i,j) is BLUE

Clauses:
  For each 5-subset {a,b,c,d,e}:
    ¬(all 10 edges red)  → at least one blue   [no red K₅]
    ¬(all 10 edges blue) → at least one red     [no blue K₅]

Optional symmetry breaking clauses.
"""

using Printf

function edge_var(i::Int, j::Int, n::Int)
    # Map edge (i,j) with i < j to variable number 1..C(n,2)
    # Using the formula: var = (i-1)*(n - i/2) + (j - i)
    # But simpler: accumulate
    return (i - 1) * n - i * (i + 1) ÷ 2 + j
end

function generate_sat(n::Int, outfile::String; symmetry_breaking::Symbol=:none)
    nvars = n * (n - 1) ÷ 2  # C(43,2) = 903

    # Verify edge_var mapping
    @assert edge_var(1, 2, n) == 1
    @assert edge_var(n-1, n, n) == nvars

    # Count 5-subsets
    n5 = binomial(n, 5)
    nclauses_base = 2 * n5  # one "no red K₅" + one "no blue K₅" per 5-subset

    # Symmetry breaking clauses
    sb_clauses = Vector{Vector{Int}}()
    if symmetry_breaking == :degree_ordering
        # Fix: deg_red(1) ≤ deg_red(2) ≤ ... ≤ deg_red(n)
        # This is complex to encode. Simpler: fix first edge.
        # x_{1,2} = true (edge 1-2 is red) — breaks color symmetry
        push!(sb_clauses, [edge_var(1, 2, n)])
    elseif symmetry_breaking == :exoo_seed
        # Fix vertex 1's adjacency to match Exoo's construction
        # S_red = {1,2,7,10,12,13,14,16,18,20,21} (circular distances)
        # Vertex 1 (= vertex 0 in Z₄₃) is red-adjacent to vertices at
        # circular distances in S_red
        S_red = Set([1, 2, 7, 10, 12, 13, 14, 16, 18, 20, 21])
        for j in 2:n
            d = min(j - 1, n - (j - 1))  # circular distance from vertex 1
            var = edge_var(1, j, n)
            if d in S_red
                push!(sb_clauses, [var])   # force red
            else
                push!(sb_clauses, [-var])  # force blue
            end
        end
    end

    nclauses = nclauses_base + length(sb_clauses)

    println("SAT encoding of R(5,5,$n)")
    println("  Variables: $nvars")
    println("  5-subsets: $n5")
    println("  Base clauses: $nclauses_base")
    println("  Symmetry breaking: $symmetry_breaking ($(length(sb_clauses)) clauses)")
    println("  Total clauses: $nclauses")

    # Generate DIMACS CNF
    open(outfile, "w") do io
        println(io, "c SAT encoding of R(5,5,$n)")
        println(io, "c Variables: x_{ij} = edge (i,j) is red")
        println(io, "c Symmetry breaking: $symmetry_breaking")
        println(io, "p cnf $nvars $nclauses")

        # Symmetry breaking clauses first
        for cl in sb_clauses
            for lit in cl
                print(io, lit, " ")
            end
            println(io, "0")
        end

        # Generate all 5-subsets and write clauses
        edges_buf = Vector{Int}(undef, 10)

        for a in 1:n
            for b in (a+1):n
                for c in (b+1):n
                    for d in (c+1):n
                        for e in (d+1):n
                            # The 10 edges of K₅ on {a,b,c,d,e}
                            edges_buf[1]  = edge_var(a, b, n)
                            edges_buf[2]  = edge_var(a, c, n)
                            edges_buf[3]  = edge_var(a, d, n)
                            edges_buf[4]  = edge_var(a, e, n)
                            edges_buf[5]  = edge_var(b, c, n)
                            edges_buf[6]  = edge_var(b, d, n)
                            edges_buf[7]  = edge_var(b, e, n)
                            edges_buf[8]  = edge_var(c, d, n)
                            edges_buf[9]  = edge_var(c, e, n)
                            edges_buf[10] = edge_var(d, e, n)

                            # No red K₅: at least one edge is blue
                            # ¬x₁ ∨ ¬x₂ ∨ ... ∨ ¬x₁₀
                            for k in 1:10
                                print(io, -edges_buf[k], " ")
                            end
                            println(io, "0")

                            # No blue K₅: at least one edge is red
                            # x₁ ∨ x₂ ∨ ... ∨ x₁₀
                            for k in 1:10
                                print(io, edges_buf[k], " ")
                            end
                            println(io, "0")
                        end
                    end
                end
            end
        end
    end

    fsize = filesize(outfile)
    @printf("  Output: %s (%.1f MB)\n", outfile, fsize / 1e6)

    return nvars, nclauses
end

function main()
    results_dir = joinpath(@__DIR__, "..", "results", "sat")
    mkpath(results_dir)

    println("=" ^ 70)
    println("SAT ENCODING OF R(5,5,43)")
    println("=" ^ 70)

    # Version 1: No symmetry breaking
    println("\n--- Version 1: No symmetry breaking ---")
    t1 = @elapsed begin
        nv1, nc1 = generate_sat(43,
            joinpath(results_dir, "r55_43_plain.cnf");
            symmetry_breaking=:none)
    end
    @printf("Time: %.2fs\n", t1)

    # Version 2: Color symmetry breaking (fix one edge)
    println("\n--- Version 2: Color symmetry breaking ---")
    t2 = @elapsed begin
        nv2, nc2 = generate_sat(43,
            joinpath(results_dir, "r55_43_colorsym.cnf");
            symmetry_breaking=:degree_ordering)
    end
    @printf("Time: %.2fs\n", t2)

    # Version 3: Exoo seed (fix vertex 1 adjacency)
    println("\n--- Version 3: Exoo seed ---")
    t3 = @elapsed begin
        nv3, nc3 = generate_sat(43,
            joinpath(results_dir, "r55_43_exoo.cnf");
            symmetry_breaking=:exoo_seed)
    end
    @printf("Time: %.2fs\n", t3)

    # Also generate the smaller R(5,5,42) instance as a sanity check
    # (should be SAT — Exoo(42) is a solution)
    println("\n--- Sanity check: R(5,5,42) (should be SAT) ---")
    t4 = @elapsed begin
        nv4, nc4 = generate_sat(42,
            joinpath(results_dir, "r55_42_plain.cnf");
            symmetry_breaking=:none)
    end
    @printf("Time: %.2fs\n", t4)

    println("\n" * "=" ^ 70)
    println("FILES GENERATED:")
    println("  r55_43_plain.cnf     — full instance, no symmetry breaking")
    println("  r55_43_colorsym.cnf  — with color symmetry breaking")
    println("  r55_43_exoo.cnf      — with Exoo adjacency seed")
    println("  r55_42_plain.cnf     — sanity check (should be SAT)")
    println()
    println("To solve, run:")
    println("  kissat r55_43_plain.cnf")
    println("  cadical r55_43_plain.cnf")
    println("=" ^ 70)
end

main()
