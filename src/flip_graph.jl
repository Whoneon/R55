#!/usr/bin/env julia
"""
Analysis of the flip graph of R(5,5,42).

The flip graph F_k has:
  - Vertices: the 328 base graphs in R(5,5,42)
  - Edges: pairs (G_i, G_j) with edit distance ≤ k

We compute:
  - Connected components at various thresholds k
  - Percolation threshold k* (minimum k for connectivity)
  - Degree distribution of F_k
  - Diameter and radius
  - Clustering coefficient
  - Adjacency spectrum of F_k
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using LinearAlgebra

function compute_edit_distances(graphs::Vector{AdjMatrix})
    n = length(graphs)
    D = zeros(Int, n, n)
    for i in 1:n
        for j in (i+1):n
            d = 0
            for r in 1:42
                d += count_ones(graphs[i].rows[r] ⊻ graphs[j].rows[r])
            end
            d >>= 1  # undirected
            D[i, j] = d
            D[j, i] = d
        end
    end
    D
end

function connected_components(adj::AbstractMatrix{Bool})
    n = size(adj, 1)
    visited = falses(n)
    components = Vector{Vector{Int}}()

    for start in 1:n
        visited[start] && continue
        comp = Int[]
        stack = [start]
        visited[start] = true
        while !isempty(stack)
            v = pop!(stack)
            push!(comp, v)
            for u in 1:n
                if adj[v, u] && !visited[u]
                    visited[u] = true
                    push!(stack, u)
                end
            end
        end
        push!(components, comp)
    end
    components
end

function graph_diameter(adj::AbstractMatrix{Bool})
    n = size(adj, 1)
    # BFS from each vertex
    max_dist = 0
    eccentricities = zeros(Int, n)

    for start in 1:n
        dist = fill(-1, n)
        dist[start] = 0
        queue = [start]
        head = 1
        while head <= length(queue)
            v = queue[head]
            head += 1
            for u in 1:n
                if adj[v, u] && dist[u] == -1
                    dist[u] = dist[v] + 1
                    push!(queue, u)
                end
            end
        end
        ecc = maximum(d for d in dist if d >= 0)
        eccentricities[start] = ecc
        max_dist = max(max_dist, ecc)
    end

    diameter = maximum(eccentricities)
    radius = minimum(eccentricities)
    return diameter, radius, eccentricities
end

function clustering_coefficient(adj::AbstractMatrix{Bool})
    n = size(adj, 1)
    cc_sum = 0.0
    cc_count = 0
    for v in 1:n
        neighbors = findall(adj[v, :])
        k = length(neighbors)
        k < 2 && continue
        triangles = 0
        for i in 1:k
            for j in (i+1):k
                if adj[neighbors[i], neighbors[j]]
                    triangles += 1
                end
            end
        end
        cc_sum += 2.0 * triangles / (k * (k - 1))
        cc_count += 1
    end
    cc_count == 0 ? 0.0 : cc_sum / cc_count
end

function main()
    catalog_path = joinpath(@__DIR__, "..", "data", "r55_42some.g6")
    results_dir = joinpath(@__DIR__, "..", "results")
    fig_dir = joinpath(@__DIR__, "..", "paper", "figures")
    mkpath(fig_dir)

    println("=" ^ 70)
    println("FLIP GRAPH ANALYSIS OF R(5,5,42)")
    println("=" ^ 70)

    half = read_g6_file(catalog_path)
    n = length(half)
    println("Loaded $n base graphs")

    # Compute full distance matrix
    println("\nComputing edit distance matrix...")
    t = @elapsed D = compute_edit_distances(half)
    @printf("Done in %.2fs\n", t)

    # Basic distance statistics
    dists = [D[i,j] for i in 1:n for j in (i+1):n]
    println("\nDistance statistics:")
    @printf("  Min: %d, Max: %d, Mean: %.1f, Median: %d\n",
            minimum(dists), maximum(dists),
            sum(dists)/length(dists), sort(dists)[length(dists)÷2])

    # Analyze flip graph at various thresholds
    println("\n─── Flip Graph F_k at various thresholds ───")
    println()
    @printf("  %5s  %5s  %6s  %5s  %6s  %8s  %6s\n",
            "k", "#comp", "largest", "isol.", "edges", "diam", "clust")
    println("  " * "-"^55)

    thresholds = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 50, 75, 100,
                  150, 200, 250, 300, 350, 400, 450, 500]

    # Data for paper
    flip_data = []

    for k in thresholds
        adj = D .<= k
        for i in 1:n; adj[i,i] = false; end

        comps = connected_components(adj)
        ncomp = length(comps)
        largest = maximum(length(c) for c in comps)
        isolated = count(c -> length(c) == 1, comps)
        nedges = sum(adj) ÷ 2

        # Diameter only if connected
        if ncomp == 1
            diam, radius, _ = graph_diameter(adj)
            diam_str = @sprintf("%d (r=%d)", diam, radius)
        else
            diam_str = "∞"
        end

        cc = clustering_coefficient(adj)

        @printf("  %5d  %5d  %6d  %5d  %6d  %8s  %.4f\n",
                k, ncomp, largest, isolated, nedges, diam_str, cc)

        push!(flip_data, (k=k, ncomp=ncomp, largest=largest,
                          isolated=isolated, nedges=nedges, cc=cc))
    end

    # Find percolation threshold
    println("\n─── Percolation Threshold ───")
    for k in 1:maximum(D)
        adj = D .<= k
        for i in 1:n; adj[i,i] = false; end
        comps = connected_components(adj)
        if length(comps) == 1
            println("  k* = $k (minimum threshold for connectivity)")

            # Compute diameter at k*
            diam, radius, eccs = graph_diameter(adj)
            println("  Diameter at k*: $diam, Radius: $radius")

            # Degree distribution at k*
            degs = [count(adj[v, :]) for v in 1:n]
            @printf("  Degree range: [%d, %d], mean: %.1f\n",
                    minimum(degs), maximum(degs), sum(degs)/n)
            break
        end
    end

    # Detailed analysis at k=1 (the close pairs)
    println("\n─── Flip Graph at k=1 (single-edge flips) ───")
    adj1 = D .<= 1
    for i in 1:n; adj1[i,i] = false; end
    comps1 = connected_components(adj1)
    non_isolated = filter(c -> length(c) > 1, comps1)
    println("  Components with >1 vertex: $(length(non_isolated))")
    for (ci, comp) in enumerate(non_isolated)
        println("  Component $ci: vertices $(comp) (size $(length(comp)))")
    end

    # Spectrum of F_k at percolation threshold
    println("\n─── Spectral Analysis ───")
    # Use a moderate threshold where the graph is connected
    for k in [50, 100, 200]
        adj_k = Float64.(D .<= k)
        for i in 1:n; adj_k[i,i] = 0.0; end
        eigs = sort(eigvals(Symmetric(adj_k)), rev=true)
        @printf("  F_%d: λ₁=%.2f, λ₂=%.2f, gap=%.2f, λₙ=%.2f\n",
                k, eigs[1], eigs[2], eigs[1]-eigs[2], eigs[end])
    end

    # Save flip graph data for paper
    open(joinpath(fig_dir, "flip_graph.dat"), "w") do io
        println(io, "k ncomp largest isolated nedges cc")
        for d in flip_data
            @printf(io, "%d %d %d %d %d %.6f\n",
                    d.k, d.ncomp, d.largest, d.isolated, d.nedges, d.cc)
        end
    end

    # Save component sizes at k=4 (interesting intermediate)
    open(joinpath(fig_dir, "flip_components_k4.dat"), "w") do io
        adj4 = D .<= 4
        for i in 1:n; adj4[i,i] = false; end
        comps4 = connected_components(adj4)
        sizes = sort([length(c) for c in comps4], rev=true)
        println(io, "rank size")
        for (i, s) in enumerate(sizes)
            println(io, "$i $s")
        end
    end

    println("\n" * "=" ^ 70)
    println("Results saved to $fig_dir/flip_graph.dat")
    println("=" ^ 70)
end

main()
