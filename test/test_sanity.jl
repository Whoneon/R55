#!/usr/bin/env julia
"""
Sanity tests for RamseyR55 module:
1. Graph6 round-trip
2. Cyclic(43) verification (43 red K₅, 0 blue K₅)
3. Load and validate all 656 McKay-Radziszowski graphs
"""

include("../src/RamseyR55.jl")
using .RamseyR55
using Test

println("=" ^ 60)
println("RamseyR55 Sanity Tests")
println("=" ^ 60)

@testset "AdjMatrix basics" begin
    g = AdjMatrix(5)
    @test nvertices(g) == 5
    @test nedges(g) == 0

    set_edge!(g, 1, 3)
    @test has_edge(g, 1, 3)
    @test has_edge(g, 3, 1)
    @test nedges(g) == 1
    @test degree(g, 1) == 1
    @test degree(g, 3) == 1
    @test degree(g, 2) == 0

    flip_edge!(g, 1, 3)
    @test !has_edge(g, 1, 3)
    @test nedges(g) == 0

    # Build K₅
    k5 = AdjMatrix(5)
    for i in 1:5, j in (i+1):5
        set_edge!(k5, i, j)
    end
    @test nedges(k5) == 10
    @test has_clique5(k5)
    @test count_clique5(k5) == 1

    # K₄ should have no K₅
    k4 = AdjMatrix(4)
    for i in 1:4, j in (i+1):4
        set_edge!(k4, i, j)
    end
    @test !has_clique5(k4)
    @test count_clique5(k4) == 0
end

@testset "Complement" begin
    g = AdjMatrix(5)
    set_edge!(g, 1, 2)
    set_edge!(g, 3, 4)
    gc = complement_graph(g)
    @test nedges(gc) == 10 - 2  # K₅ has 10 edges, we had 2
    @test !has_edge(gc, 1, 2)
    @test !has_edge(gc, 3, 4)
    @test has_edge(gc, 1, 3)
    @test has_edge(gc, 2, 3)
end

@testset "Graph6 round-trip" begin
    # Small graph: K₄
    k4 = AdjMatrix(4)
    for i in 1:4, j in (i+1):4
        set_edge!(k4, i, j)
    end
    s = write_g6(k4)
    k4b = read_g6(s)
    @test nvertices(k4b) == 4
    @test nedges(k4b) == 6
    for i in 1:4, j in (i+1):4
        @test has_edge(k4b, i, j)
    end

    # Round-trip random-ish graph on 10 vertices
    g = AdjMatrix(10)
    set_edge!(g, 1, 5)
    set_edge!(g, 2, 7)
    set_edge!(g, 3, 8)
    set_edge!(g, 4, 9)
    set_edge!(g, 6, 10)
    s = write_g6(g)
    g2 = read_g6(s)
    @test nvertices(g2) == 10
    @test nedges(g2) == 5
    for i in 1:10, j in (i+1):10
        @test has_edge(g2, i, j) == has_edge(g, i, j)
    end
end

@testset "Circulant graph" begin
    # C₅ cycle = circulant(5, [1])
    c5 = circulant_graph(5, [1])
    @test nedges(c5) == 5
    for i in 1:5
        @test degree(c5, i) == 2
    end

    # Petersen graph = circulant(5, [2]) is just C₅ with distance 2
    # (Actually Petersen is NOT circulant, but circulant(5,[2]) = C₅)
    c5_2 = circulant_graph(5, [2])
    @test nedges(c5_2) == 5
end

@testset "Exoo Cyclic(43) — KEY SANITY CHECK" begin
    println("\n>>> Testing Exoo's Cyclic(43) construction...")
    g = exoo_cyclic43()
    @test nvertices(g) == 43

    # S_red = {1,2,7,10,12,13,14,16,18,20,21} = 11 circular distances
    # For n=43 (odd), each distance gives 2 neighbors → degree = 22
    for i in 1:43
        @test degree(g, i) == 22
    end
    println("  ✓ All vertices have degree 22")

    # Count red K₅ (cliques in g)
    red_k5 = count_clique5(g)
    println("  Red K₅ count: $red_k5")
    @test red_k5 == 43  # one per rotation of (0,1,2,22,23)

    # Count blue K₅ (cliques in complement = independent sets in g)
    gc = complement_graph(g)
    for i in 1:43
        @test degree(gc, i) == 20  # 42 - 22 = 20
    end
    blue_k5 = count_clique5(gc)
    println("  Blue K₅ count: $blue_k5")
    @test blue_k5 == 0

    println("  ✓ Cyclic(43) verified: 43 red K₅, 0 blue K₅")

    # Total edges
    @test nedges(g) == 43 * 22 ÷ 2  # = 473
    println("  ✓ Total edges: $(nedges(g))")
end

@testset "Load 656 McKay-Radziszowski graphs" begin
    catalog_file = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    if !isfile(catalog_file)
        @warn "Catalog file not found at $catalog_file — skipping"
    else
        println("\n>>> Loading R(5,5,42) catalog...")
        graphs = read_g6_file(catalog_file)
        println("  Loaded $(length(graphs)) graphs from file")
        @test length(graphs) == 328  # other 328 are complements

        # Validate all 328 + their complements
        n_valid = 0
        n_total = 0
        for (idx, g) in enumerate(graphs)
            @test nvertices(g) == 42

            # Check: no K₅ in g
            @test !has_clique5(g)

            # Check: no K₅ in complement (= no I₅ in g)
            gc = complement_graph(g)
            @test !has_clique5(gc)

            n_valid += 1
            n_total += 1

            # Also validate complement as a separate Ramsey graph
            @test nvertices(gc) == 42
            # complement of complement should also work
            # gc is in R(5,5,42) too
            n_total += 1
        end

        println("  ✓ All $n_valid graphs validated as R(5,5,42) counterexamples")
        println("  ✓ Total R(5,5,42) graphs (including complements): $n_total")

        # Report some statistics
        degs = [degree_sequence(g) for g in graphs[1:5]]
        println("  Sample degree sequences (first 5):")
        for (i, d) in enumerate(degs)
            println("    Graph $i: min=$(d[1]), max=$(d[end]), median=$(d[21])")
        end

        # Timing test
        t = @elapsed begin
            for g in graphs
                count_clique5(g)
                count_clique5(complement_graph(g))
            end
        end
        println("  K₅ verification for all 328 graphs + complements: $(round(t, digits=4))s")
    end
end

@testset "Triangle counting" begin
    # K₄ has 4 triangles
    k4 = AdjMatrix(4)
    for i in 1:4, j in (i+1):4
        set_edge!(k4, i, j)
    end
    @test count_triangles(k4) == 4

    # K₅ has C(5,3) = 10 triangles
    k5 = AdjMatrix(5)
    for i in 1:5, j in (i+1):5
        set_edge!(k5, i, j)
    end
    @test count_triangles(k5) == 10
end

@testset "Exoo(42) — Ramsey counterexample" begin
    println("\n>>> Testing Exoo(42) construction...")
    g = exoo42()
    @test nvertices(g) == 42

    red = count_clique5(g)
    blue = count_clique5(complement_graph(g))
    println("  Red K₅: $red, Blue K₅: $blue")
    @test red == 0
    @test blue == 0
    @test is_ramsey55(g)
    println("  ✓ Exoo(42) is a valid R(5,5,42) counterexample")
end

println("\n" * "=" ^ 60)
println("All sanity tests completed!")
println("=" ^ 60)
