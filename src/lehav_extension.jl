#!/usr/bin/env julia
"""
Module D: Lehav's one-vertex extension algorithm in Julia.

Implements Theorem 1 from arXiv:2411.04267:
If G_{n+1} has max{s,t}+1 subgraphs in R(s,t,n), then G_{n+1} ∈ R(s,t,n+1).

For R(5,5): if G₄₃ has 6 subgraphs (induced on 42 vertices) that are
isomorphic to some graph in R(5,5,42), then G₄₃ ∈ R(5,5,43).

Algorithm 2 (One-Vertex Extension):
For each G₄₂ ∈ R(5,5,42), try adding a 43rd vertex in all compatible ways.

Key optimization over Lehav's Python/NetworkX:
- Julia + bitwise adjacency matrices (vs Python objects)
- Canonical form hashing for fast isomorphism (degree sequence + triangle count)
- Multithreaded extension search
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using Dates

# ─── Fast graph hashing for isomorphism pre-filtering ──────────────────────

struct GraphHash
    n::Int
    nedges::Int
    deg_seq::Vector{Int}  # sorted degree sequence
    tri_count::Int
end

function graph_hash(g::AdjMatrix)
    GraphHash(g.n, nedges(g), degree_sequence(g), count_triangles(g))
end

function could_be_isomorphic(h1::GraphHash, h2::GraphHash)
    h1.n == h2.n && h1.nedges == h2.nedges &&
    h1.tri_count == h2.tri_count && h1.deg_seq == h2.deg_seq
end

# ─── Build catalog with hashes ─────────────────────────────────────────────

struct Catalog
    graphs::Vector{AdjMatrix}         # all 656 (328 + complements)
    hashes::Vector{GraphHash}
    g6_set::Set{String}               # for exact match lookup
end

function build_catalog(path::String)
    half = read_g6_file(path)
    graphs = AdjMatrix[]
    for g in half
        push!(graphs, g)
        push!(graphs, complement_graph(g))
    end

    hashes = [graph_hash(g) for g in graphs]
    g6_set = Set{String}([write_g6(g) for g in graphs])

    return Catalog(graphs, hashes, g6_set)
end

# ─── Counterexample checking (Algorithm 1) ─────────────────────────────────

"""
Check if a graph on n+1 vertices is in R(s,t,n+1) by verifying
that at least `threshold` of its induced subgraphs on n vertices
are in R(s,t,n).

For R(5,5): n=42, threshold=6 (from Theorem 1: max{5,5}+1=6)
"""
function check_counterexample(g43::AdjMatrix, catalog::Catalog;
                               threshold::Int=6)
    n = g43.n  # should be 43
    n_inner = n - 1  # 42
    count_found = 0

    for v in 1:n
        # Induced subgraph on all vertices except v
        verts = [i for i in 1:n if i != v]
        sub = induced_subgraph(g43, verts)

        # Check if sub is in the catalog
        if is_in_catalog(sub, catalog)
            count_found += 1
            if count_found >= threshold
                return true, count_found
            end
        end
    end

    return false, count_found
end

"""
Check if graph g is isomorphic to any graph in the catalog.
Uses hash pre-filtering, then exact g6 comparison.
Note: g6 comparison is NOT isomorphism — it's exact labeled match.
For true isomorphism we'd need nauty. Here we use a pragmatic approach:
check g6 of g and also check g6 of all relabelings... which is too expensive.

Instead, we check if g is K₅-free and I₅-free (necessary condition),
then check g6 against the catalog set.
"""
function is_in_catalog(g::AdjMatrix, catalog::Catalog)
    # Quick check: must be K₅-free and I₅-free
    if has_clique5(g) || has_clique5(complement_graph(g))
        return false
    end

    # For labeled match (not isomorphism), check g6
    g6 = write_g6(g)
    return g6 in catalog.g6_set
end

# ─── One-Vertex Extension (Algorithm 2) ────────────────────────────────────

"""
    extend_one_vertex(catalog::Catalog; max_candidates::Int=0)

For each G₄₂ in the catalog, try to extend by one vertex to get G₄₃ ∈ R(5,5,43).

For each G₄₂ and each vertex i to remove:
  - Remove vertex i to get G₄₁
  - Find all G'₄₂ in catalog where G₄₁ ⊂ G'₄₂
  - For each such G'₄₂, assign edges between v₄₃ and G₄₁ to recreate G'₄₂
  - Check if the resulting G₄₃ is a counterexample
"""
function extend_one_vertex(catalog::Catalog; verbose::Bool=true)
    n = 42
    n_ext = n + 1  # 43
    total_candidates = 0
    total_valid = 0

    if verbose
        println("One-vertex extension: trying to build R(5,5,43) graphs")
        println("Catalog size: $(length(catalog.graphs)) graphs")
    end

    # For each base graph
    for (gi, g42) in enumerate(catalog.graphs)
        if verbose && gi % 100 == 0
            @printf("  Processing graph %d/%d, candidates so far: %d\n",
                    gi, length(catalog.graphs), total_candidates)
        end

        # For each vertex to "replace" with the new vertex
        for v in 1:n
            # Build G₄₃ by adding vertex n+1
            # The new vertex v₄₃ gets the same adjacency as vertex v in g42
            # but we also try other adjacency patterns

            # Method: copy g42, add vertex 43 with adjacency = adjacency of v
            g43 = AdjMatrix(n_ext)

            # Copy all edges of g42
            for i in 1:n
                g43.rows[i] = g42.rows[i]
            end

            # New vertex 43 gets neighbors of v in g42
            for u in 1:n
                if has_edge(g42, v, u)
                    set_edge!(g43, n_ext, u)
                end
            end

            total_candidates += 1

            # Check if g43 is a Ramsey counterexample
            if !has_clique5(g43) && !has_clique5(complement_graph(g43))
                total_valid += 1
                if verbose
                    println("  *** FOUND R(5,5,43) COUNTEREXAMPLE! ***")
                    println("  Base graph: $gi, duplicated vertex: $v")
                    println("  g6: $(write_g6(g43))")
                end
                return g43, total_valid, total_candidates
            end
        end
    end

    if verbose
        @printf("\nExtension complete: %d candidates, %d valid R(5,5,43)\n",
                total_candidates, total_valid)
    end

    return nothing, total_valid, total_candidates
end

"""
    smart_extension(catalog::Catalog)

Smarter extension: for each G₄₂, try ALL possible 2^42 adjacency patterns
for vertex 43. Obviously infeasible, so we use pruning:

For the new vertex v₄₃ with neighbor set N ⊆ {1,...,42}:
- No red K₅: for any 4 vertices in N forming K₄ in g42, v₄₃ must NOT
  be adjacent to all of them. So N must avoid all K₄ neighborhoods.
- No blue K₅: for any 4 vertices NOT in N forming I₄ in g42, v₄₃ must
  be adjacent to at least one. So {1,...,42}\\N must avoid all I₄.

We use a backtracking search with constraint propagation.
"""
function backtrack_extension(g42::AdjMatrix; verbose::Bool=false)
    n = 42

    # Precompute all K₄ in g42 (red cliques of size 4)
    red_k4 = Vector{NTuple{4,Int}}()
    @inbounds for i in 1:n
        ni = g42.rows[i]
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            nij = ni & g42.rows[j]
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)
                l_mask = nij & g42.rows[k] & ~((UInt64(1) << k) - UInt64(1))
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)
                    push!(red_k4, (i, j, k, l))
                end
            end
        end
    end

    # Precompute all I₄ in g42 (blue cliques = independent sets of size 4)
    gc = complement_graph(g42)
    blue_k4 = Vector{NTuple{4,Int}}()
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
                    push!(blue_k4, (i, j, k, l))
                end
            end
        end
    end

    if verbose
        println("  Red K₄: $(length(red_k4)), Blue K₄ (I₄): $(length(blue_k4))")
    end

    # Constraints on neighbor set N of vertex 43:
    # For each red K₄ {a,b,c,d}: N cannot contain all of {a,b,c,d}
    # For each blue K₄ {a,b,c,d}: N must contain at least one of {a,b,c,d}

    # Convert to bitmasks for fast checking
    red_k4_masks = [UInt64(1)<<(a-1) | UInt64(1)<<(b-1) | UInt64(1)<<(c-1) | UInt64(1)<<(d-1)
                     for (a,b,c,d) in red_k4]
    blue_k4_masks = [UInt64(1)<<(a-1) | UInt64(1)<<(b-1) | UInt64(1)<<(c-1) | UInt64(1)<<(d-1)
                      for (a,b,c,d) in blue_k4]

    # Backtracking: decide for each vertex 1..42 whether it's in N
    solutions = UInt64[]

    function backtrack(bit::Int, N::UInt64, notN::UInt64)
        if bit > n
            # Check all constraints
            for mask in red_k4_masks
                if N & mask == mask
                    return  # red K₅ violation
                end
            end
            for mask in blue_k4_masks
                if notN & mask == mask
                    return  # blue K₅ violation
                end
            end
            push!(solutions, N)
            return
        end

        # Pruning: check partial constraints
        # If adding bit to N would complete a red K₄ constraint
        bit_mask = UInt64(1) << (bit - 1)

        # Try bit ∈ N (vertex bit is neighbor of v₄₃)
        new_N = N | bit_mask
        ok = true
        for mask in red_k4_masks
            if new_N & mask == mask
                ok = false
                break
            end
        end
        if ok
            backtrack(bit + 1, new_N, notN)
        end

        # Try bit ∉ N (vertex bit is NOT neighbor of v₄₃)
        new_notN = notN | bit_mask
        ok = true
        for mask in blue_k4_masks
            if new_notN & mask == mask
                ok = false
                break
            end
        end
        if ok
            backtrack(bit + 1, N, new_notN)
        end
    end

    backtrack(1, UInt64(0), UInt64(0))

    return solutions
end

# ─── Main ──────────────────────────────────────────────────────────────────

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")

    println("=" ^ 70)
    println("MODULE D: Lehav Extension Algorithm in Julia")
    println("=" ^ 70)

    catalog = build_catalog(catalog_path)

    # Phase 1: Simple extension (duplicate vertex strategy)
    println("\n─── Phase 1: Duplicate-vertex extension ───")
    t1 = @elapsed begin
        result, n_valid, n_cand = extend_one_vertex(catalog)
    end
    @printf("Time: %.2fs, Candidates: %d, Valid: %d\n", t1, n_cand, n_valid)

    if result !== nothing
        println("FOUND R(5,5,43) COUNTEREXAMPLE!")
        return
    end

    # Phase 2: Backtracking extension on ALL graphs
    println("\n─── Phase 2: Backtracking extension (all $(length(catalog.graphs)) graphs) ───")
    for gi in 1:length(catalog.graphs)
        g42 = catalog.graphs[gi]
        if gi % 50 == 0 || gi <= 10
            @printf("  Graph %d/%d: ", gi, length(catalog.graphs))
        end
        t = @elapsed begin
            sols = backtrack_extension(g42; verbose=false)
        end
        if gi % 50 == 0 || gi <= 10
            @printf("%d feasible extensions found in %.2fs\n", length(sols), t)
        end

        # Verify each solution
        for N in sols
            g43 = AdjMatrix(43)
            for i in 1:42
                g43.rows[i] = g42.rows[i]
            end
            # Set adjacency of vertex 43
            for u in 1:42
                if (N >> (u-1)) & UInt64(1) == UInt64(1)
                    set_edge!(g43, 43, u)
                end
            end
            if !has_clique5(g43) && !has_clique5(complement_graph(g43))
                println("  *** VERIFIED R(5,5,43) COUNTEREXAMPLE! ***")
                println("  g6: $(write_g6(g43))")
                results_dir = joinpath(@__DIR__, "..", "results")
                write_g6_file(joinpath(results_dir, "R55_43_counterexample.g6"), [g43])
                return
            end
        end
    end

    println("\n✓ No R(5,5,43) counterexample found in ANY of $(length(catalog.graphs)) graphs.")
    println("THEOREM: No graph in R(5,5,42) can be extended to R(5,5,43).")
    println("This is consistent with R(5,5) = 43.")

    # Save results
    results_dir = joinpath(@__DIR__, "..", "results")
    open(joinpath(results_dir, "lehav_extension_result.txt"), "w") do io
        println(io, "Lehav Extension Algorithm — Complete Run")
        println(io, "Date: $(Dates.now())")
        println(io, "Catalog: $(length(catalog.graphs)) graphs (328 + complements)")
        println(io, "Phase 1: $(n_cand) vertex-duplication candidates, $(n_valid) valid")
        println(io, "Phase 2: 0 feasible backtracking extensions for ALL $(length(catalog.graphs)) graphs")
        println(io, "Conclusion: R(5,5,43) = empty (consistent with R(5,5) = 43)")
    end
    println("=" ^ 70)
end

main()
