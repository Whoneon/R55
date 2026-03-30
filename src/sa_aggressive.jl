#!/usr/bin/env julia
"""
Aggressive SA for f(43): longer runs, multiple seeds from top circulants,
and perturbation-based restarts.
"""

include("RamseyR55.jl")
using .RamseyR55
using Printf
using Random

function sa_minimize(n::Int, seed_g::AdjMatrix;
        T0::Float64, Tmin::Float64, alpha::Float64, max_iter::Int,
        perturbation_size::Int=5, restart_threshold::Int=500_000)

    g = copy(seed_g)
    current_cost = let r = count_clique5(g), b = count_clique5(complement_graph(g)); r + b end
    best_cost = current_cost
    best_g = copy(g)
    T = T0
    stale = 0

    for iter in 1:max_iter
        i = rand(1:n)
        j = rand(1:n-1)
        j >= i && (j += 1)
        if i > j; i, j = j, i end

        flip_edge!(g, i, j)
        new_red = count_clique5(g)
        new_blue = count_clique5(complement_graph(g))
        new_cost = new_red + new_blue
        delta = new_cost - current_cost

        if delta <= 0 || rand() < exp(-delta / T)
            current_cost = new_cost
            if new_cost < best_cost
                best_cost = new_cost
                best_g = copy(g)
                stale = 0
                @printf("  iter=%8d: BEST=%d (r=%d,b=%d) T=%.6f\n",
                        iter, best_cost, new_red, new_blue, T)
                best_cost == 0 && return best_g, best_cost
            end
        else
            flip_edge!(g, i, j)
        end

        T = max(Tmin, T * alpha)
        stale += 1

        # Perturbation restart: if stuck, perturb best solution
        if stale > restart_threshold
            g = copy(best_g)
            for _ in 1:perturbation_size
                pi = rand(1:n)
                pj = rand(1:n-1)
                pj >= pi && (pj += 1)
                flip_edge!(g, min(pi,pj), max(pi,pj))
            end
            current_cost = let r = count_clique5(g), b = count_clique5(complement_graph(g)); r + b end
            T = T0 * 0.5  # reheat
            stale = 0
        end
    end

    return best_g, best_cost
end

function main()
    println("=" ^ 70)
    println("AGGRESSIVE SA for f(43)")
    println("=" ^ 70)

    # Top circulant seeds with 43 K₅
    seeds = [
        ([1, 4, 5, 6, 7, 8, 9, 12, 14, 17], "best circulant (blue=43)"),
        ([1, 2, 7, 10, 12, 13, 14, 16, 18, 20, 21], "Exoo (red=43)"),
    ]

    # Also try near-optimal circulants
    # From the search: several with total=43 exist. Try variations.
    # Add a few hand-picked candidates with small asymmetric K₅ counts
    push!(seeds, ([1, 3, 4, 7, 8, 9, 10, 11, 12], "circulant (473 total)"))

    global_best = typemax(Int)
    global_best_g = AdjMatrix(43)

    for (S, name) in seeds
        println("\n─── Seed: $name ───")
        g0 = circulant_graph(43, S)
        r0 = count_clique5(g0)
        b0 = count_clique5(complement_graph(g0))
        @printf("  Start: red=%d, blue=%d, total=%d\n", r0, b0, r0+b0)

        bg, bc = sa_minimize(43, g0;
            T0=50.0, Tmin=0.01, alpha=0.999998,
            max_iter=10_000_000, perturbation_size=3, restart_threshold=1_000_000)

        @printf("  Final: total=%d\n", bc)
        if bc < global_best
            global_best = bc
            global_best_g = bg
        end
    end

    # Also try 10 random starts with long runs
    println("\n─── Random Restarts (10 runs) ───")
    for run in 1:10
        g0 = AdjMatrix(43)
        # Balanced random: ~50% red
        for i in 1:43, j in (i+1):43
            rand() < 0.5 && set_edge!(g0, i, j)
        end
        bg, bc = sa_minimize(43, g0;
            T0=200.0, Tmin=0.01, alpha=0.999998,
            max_iter=10_000_000, perturbation_size=5, restart_threshold=2_000_000)
        r = count_clique5(bg)
        b = count_clique5(complement_graph(bg))
        @printf("  Run %2d: total=%d (r=%d, b=%d)\n", run, bc, r, b)
        if bc < global_best
            global_best = bc
            global_best_g = bg
        end
    end

    println("\n" * "=" ^ 70)
    r = count_clique5(global_best_g)
    b = count_clique5(complement_graph(global_best_g))
    @printf("FINAL: f(43) ≤ %d  (red=%d, blue=%d)\n", global_best, r, b)
    println("=" ^ 70)

    # Save
    results_dir = joinpath(@__DIR__, "..", "results")
    mkpath(results_dir)
    write_g6_file(joinpath(results_dir, "best_K43_aggressive.g6"), [global_best_g])
    open(joinpath(results_dir, "f43_aggressive.txt"), "w") do io
        println(io, "f(43) <= $global_best")
        println(io, "red_K5 = $r, blue_K5 = $b")
        println(io, "graph6 = $(write_g6(global_best_g))")
    end
end

main()
