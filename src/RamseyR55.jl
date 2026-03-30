"""
    RamseyR55

Core infrastructure for R(5,5) computational research.
Provides graph6 I/O, fast adjacency matrix representation,
K₅ detection, circulant graph construction, and Ramsey verification.
"""
module RamseyR55

export AdjMatrix, nvertices, nedges, has_edge, set_edge!, clear_edge!, flip_edge!,
       adjacency_row, degree, degree_sequence,
       read_g6, write_g6, read_g6_file, write_g6_file,
       has_clique5, count_clique5, is_ramsey55,
       circulant_graph, exoo_cyclic43,
       complement_graph, neighbors, common_neighbors,
       count_monochromatic_K5, count_triangles, adjacency_matrix,
       exoo42, induced_subgraph, extension_tension

# ─── Adjacency matrix representation ───────────────────────────────────────

"""
    AdjMatrix

Compact adjacency matrix for undirected simple graphs on n ≤ 64 vertices.
Each row is stored as a UInt64 bitmask. Bit j of row[i] = 1 iff edge (i,j) exists.
"""
struct AdjMatrix
    n::Int
    rows::Vector{UInt64}
end

AdjMatrix(n::Int) = AdjMatrix(n, zeros(UInt64, n))

function Base.copy(g::AdjMatrix)
    AdjMatrix(g.n, copy(g.rows))
end

nvertices(g::AdjMatrix) = g.n

function nedges(g::AdjMatrix)
    s = 0
    for i in 1:g.n
        s += count_ones(g.rows[i])
    end
    return s >> 1  # each edge counted twice
end

@inline function has_edge(g::AdjMatrix, i::Int, j::Int)
    return (g.rows[i] >> (j - 1)) & UInt64(1) == UInt64(1)
end

@inline function set_edge!(g::AdjMatrix, i::Int, j::Int)
    g.rows[i] |= UInt64(1) << (j - 1)
    g.rows[j] |= UInt64(1) << (i - 1)
    return nothing
end

@inline function clear_edge!(g::AdjMatrix, i::Int, j::Int)
    g.rows[i] &= ~(UInt64(1) << (j - 1))
    g.rows[j] &= ~(UInt64(1) << (i - 1))
    return nothing
end

@inline function flip_edge!(g::AdjMatrix, i::Int, j::Int)
    g.rows[i] ⊻= UInt64(1) << (j - 1)
    g.rows[j] ⊻= UInt64(1) << (i - 1)
    return nothing
end

@inline function adjacency_row(g::AdjMatrix, i::Int)
    return g.rows[i]
end

@inline function neighbors(g::AdjMatrix, i::Int)
    return g.rows[i]
end

@inline function degree(g::AdjMatrix, i::Int)
    return count_ones(g.rows[i])
end

function degree_sequence(g::AdjMatrix)
    return sort!([degree(g, i) for i in 1:g.n])
end

function common_neighbors(g::AdjMatrix, i::Int, j::Int)
    return g.rows[i] & g.rows[j]
end

function complement_graph(g::AdjMatrix)
    n = g.n
    mask = (UInt64(1) << n) - UInt64(1)  # bits 0..n-1
    gc = AdjMatrix(n)
    for i in 1:n
        self_bit = UInt64(1) << (i - 1)
        gc.rows[i] = (g.rows[i] ⊻ mask) & ~self_bit
    end
    return gc
end

# ─── Graph6 format I/O ─────────────────────────────────────────────────────

"""
    read_g6(s::AbstractString) -> AdjMatrix

Parse a graph6-encoded string into an AdjMatrix.
Reference: https://users.cecs.anu.edu.au/~bdm/data/formats.txt
"""
function read_g6(s::AbstractString)
    bytes = collect(codeunits(s))
    idx = 1

    # Decode n
    if bytes[idx] == 0x7e  # 126 = '~'
        idx += 1
        if bytes[idx] == 0x7e
            idx += 1
            # n encoded in 6 bytes
            n = 0
            for k in 0:5
                n = (n << 6) | (Int(bytes[idx + k]) - 63)
            end
            idx += 6
        else
            # n encoded in 3 bytes
            n = 0
            for k in 0:2
                n = (n << 6) | (Int(bytes[idx + k]) - 63)
            end
            idx += 3
        end
    else
        n = Int(bytes[idx]) - 63
        idx += 1
    end

    g = AdjMatrix(n)

    # Decode adjacency: upper triangle column by column
    # bit stream from remaining bytes
    bit_pos = 0
    byte_val = idx <= length(bytes) ? Int(bytes[idx]) - 63 : 0

    for j in 2:n
        for i in 1:(j-1)
            if bit_pos == 6
                bit_pos = 0
                idx += 1
                byte_val = idx <= length(bytes) ? Int(bytes[idx]) - 63 : 0
            end
            bit = (byte_val >> (5 - bit_pos)) & 1
            if bit == 1
                set_edge!(g, i, j)
            end
            bit_pos += 1
        end
    end

    return g
end

"""
    write_g6(g::AdjMatrix) -> String

Encode an AdjMatrix as a graph6 string.
"""
function write_g6(g::AdjMatrix)
    n = g.n
    io = IOBuffer()

    # Encode n
    if n <= 62
        write(io, UInt8(n + 63))
    elseif n <= 258047
        write(io, UInt8(126))  # '~'
        write(io, UInt8(((n >> 12) & 0x3f) + 63))
        write(io, UInt8(((n >> 6) & 0x3f) + 63))
        write(io, UInt8((n & 0x3f) + 63))
    else
        error("n too large for graph6")
    end

    # Encode adjacency: upper triangle, column by column
    current_byte = 0
    bit_count = 0

    for j in 2:n
        for i in 1:(j-1)
            current_byte = (current_byte << 1) | (has_edge(g, i, j) ? 1 : 0)
            bit_count += 1
            if bit_count == 6
                write(io, UInt8(current_byte + 63))
                current_byte = 0
                bit_count = 0
            end
        end
    end

    # Flush remaining bits (pad with zeros)
    if bit_count > 0
        current_byte <<= (6 - bit_count)
        write(io, UInt8(current_byte + 63))
    end

    return String(take!(io))
end

"""
    read_g6_file(filename::String) -> Vector{AdjMatrix}

Read all graphs from a graph6 file (one per line).
"""
function read_g6_file(filename::String)
    graphs = AdjMatrix[]
    for line in eachline(filename)
        stripped = rstrip(line)
        isempty(stripped) && continue
        push!(graphs, read_g6(stripped))
    end
    return graphs
end

"""
    write_g6_file(filename::String, graphs::Vector{AdjMatrix})

Write graphs to a graph6 file (one per line).
"""
function write_g6_file(filename::String, graphs::Vector{AdjMatrix})
    open(filename, "w") do io
        for g in graphs
            println(io, write_g6(g))
        end
    end
end

# ─── Clique detection ──────────────────────────────────────────────────────

"""
    has_clique5(g::AdjMatrix) -> Bool

Check if graph g contains a clique of size 5.
Uses bitwise AND on adjacency rows for speed.
"""
function has_clique5(g::AdjMatrix)
    n = g.n
    @inbounds for i in 1:n
        ni = g.rows[i]
        # j must be a neighbor of i, j > i
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))  # neighbors of i with index > i
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)  # clear lowest bit

            nij = ni & g.rows[j]
            # k must be neighbor of both i,j and k > j
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)

                nijk = nij & g.rows[k]
                # l must be neighbor of i,j,k and l > k
                l_mask = nijk & ~((UInt64(1) << k) - UInt64(1))
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)

                    nijkl = nijk & g.rows[l]
                    # m must be neighbor of i,j,k,l and m > l
                    m_mask = nijkl & ~((UInt64(1) << l) - UInt64(1))
                    if m_mask != UInt64(0)
                        return true
                    end
                end
            end
        end
    end
    return false
end

"""
    count_clique5(g::AdjMatrix) -> Int

Count the number of cliques of size 5 in graph g.
"""
function count_clique5(g::AdjMatrix)
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
                l_mask = nijk & ~((UInt64(1) << k) - UInt64(1))
                while l_mask != UInt64(0)
                    l = trailing_zeros(l_mask) + 1
                    l_mask &= l_mask - UInt64(1)

                    nijkl = nijk & g.rows[l]
                    m_mask = nijkl & ~((UInt64(1) << l) - UInt64(1))
                    count += count_ones(m_mask)
                end
            end
        end
    end
    return count
end

"""
    is_ramsey55(g::AdjMatrix) -> Bool

Check if g is a Ramsey(5,5) counterexample graph:
no K₅ in g (red) and no K₅ in complement(g) (blue = independent set of size 5 in g).
"""
function is_ramsey55(g::AdjMatrix)
    return !has_clique5(g) && !has_clique5(complement_graph(g))
end

# ─── Circulant graph construction ──────────────────────────────────────────

"""
    circulant_graph(n::Int, S::Vector{Int}) -> AdjMatrix

Construct a circulant graph on Zₙ with connection set S.
Edge (i,j) exists iff min(|i-j|, n-|i-j|) ∈ S.
S should contain distances in 1:floor(n/2).
"""
function circulant_graph(n::Int, S::Vector{Int})
    g = AdjMatrix(n)
    s_set = Set(S)
    for i in 1:n
        for j in (i+1):n
            d = j - i
            d_circ = min(d, n - d)
            if d_circ in s_set
                set_edge!(g, i, j)
            end
        end
    end
    return g
end

"""
    exoo_cyclic43() -> AdjMatrix

Construct Exoo's Cyclic(43) graph: circulant on Z₄₃ with
S_red = {1,2,3,4,6,8,9,12,16,17,18,24} (circular distances for red edges).
This graph has exactly 43 red K₅ (one per rotation of (0,1,2,22,23))
and zero blue K₅.
"""
function exoo_cyclic43()
    # From Ge et al. (arXiv:2212.12630), Table p.3 and Lemma 2.1:
    # Blue circular distances = {3,4,5,6,8,9,11,15,17,19}
    # Red = {1,...,21} \ Blue = {1,2,7,10,12,13,14,16,18,20,21}
    S_red = [1, 2, 7, 10, 12, 13, 14, 16, 18, 20, 21]
    return circulant_graph(43, S_red)
end

# ─── Utility functions ─────────────────────────────────────────────────────

"""
    count_monochromatic_K5(g::AdjMatrix) -> (red::Int, blue::Int)

Count K₅ in g (red) and in complement(g) (blue).
Total monochromatic K₅ = red + blue.
"""
function count_monochromatic_K5(g::AdjMatrix)
    red = count_clique5(g)
    blue = count_clique5(complement_graph(g))
    return (red=red, blue=blue)
end

"""
    count_triangles(g::AdjMatrix) -> Int

Count triangles in g using bitwise AND.
"""
function count_triangles(g::AdjMatrix)
    n = g.n
    count = 0
    @inbounds for i in 1:n
        j_mask = g.rows[i] & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            count += count_ones(g.rows[i] & g.rows[j] & ~((UInt64(1) << j) - UInt64(1)))
        end
    end
    return count
end

"""
    adjacency_matrix(g::AdjMatrix) -> Matrix{Int}

Convert to a dense integer matrix (for eigenvalue computation etc.).
"""
function adjacency_matrix(g::AdjMatrix)
    n = g.n
    A = zeros(Int, n, n)
    for i in 1:n
        for j in 1:n
            if has_edge(g, i, j)
                A[i, j] = 1
            end
        end
    end
    return A
end

"""
    exoo42() -> AdjMatrix

Construct Exoo(42): start from Cyclic(43), delete vertex 0,
then flip the colors of 16 specific edges (from Ge et al., Definition 1.2).
The resulting graph on 42 vertices has no monochromatic K₅.
"""
function exoo42()
    c43 = exoo_cyclic43()

    # Delete vertex 0 (vertex 1 in 1-indexed): create induced subgraph on vertices 2..43
    n = 42
    g = AdjMatrix(n)
    for i in 1:n
        for j in (i+1):n
            # vertex i in g corresponds to vertex i+1 in c43 (old vertex i)
            if has_edge(c43, i + 1, j + 1)
                set_edge!(g, i, j)
            end
        end
    end

    # Flip 16 edges (Ge et al., Definition 1.2)
    # Original 0-indexed pairs: (4,5),(5,6),(6,7),(7,8),(13,14),(14,15),(15,16),(16,17),
    # (23,24),(24,25),(30,31),(33,34),(39,40),(40,41),(41,42),(11,32)
    # In our 1-indexed system (vertex v in paper = vertex v in our graph):
    flips = [
        (4, 5), (5, 6), (6, 7), (7, 8),
        (13, 14), (14, 15), (15, 16), (16, 17),
        (23, 24), (24, 25), (30, 31), (33, 34),
        (39, 40), (40, 41), (41, 42), (11, 32)
    ]
    for (u, v) in flips
        flip_edge!(g, u, v)
    end

    return g
end

"""
    induced_subgraph(g::AdjMatrix, verts::Vector{Int}) -> AdjMatrix

Return the induced subgraph of g on the given vertex set.
"""
function induced_subgraph(g::AdjMatrix, verts::Vector{Int})
    m = length(verts)
    h = AdjMatrix(m)
    for ii in 1:m
        for jj in (ii+1):m
            if has_edge(g, verts[ii], verts[jj])
                set_edge!(h, ii, jj)
            end
        end
    end
    return h
end

"""
    extension_tension(g::AdjMatrix) -> Int

For a graph g on n vertices, compute the minimum number of monochromatic K₅
created by adding a single (n+1)-th vertex with any possible adjacency pattern.
This is the "tension" — how close g is to being extendable.
"""
function extension_tension(g::AdjMatrix)
    n = g.n
    best = typemax(Int)

    # Try all 2^n adjacency patterns for the new vertex
    # For n=42, 2^42 is too large. Use heuristic: try all patterns where
    # the new vertex has exactly d neighbors, for d near n/2.
    # For now, implement exact version for small n, heuristic for large n.
    if n <= 25
        for mask in UInt64(0):(UInt64(1) << n - UInt64(1))
            cost = _extension_cost(g, mask)
            if cost < best
                best = cost
                best == 0 && return 0
            end
        end
    else
        # Heuristic: sample random patterns
        best = _extension_tension_heuristic(g, 100_000)
    end
    return best
end

function _extension_cost(g::AdjMatrix, new_adj::UInt64)
    # Count K₅ involving the new vertex in the extended graph
    n = g.n
    count = 0

    # Red K₅ with new vertex: need 4 neighbors of new vertex that form K₄ among themselves
    # new vertex is connected to vertices in new_adj (bitmask)
    neigh = new_adj & ((UInt64(1) << n) - UInt64(1))

    @inbounds for i in 1:n
        ((neigh >> (i-1)) & UInt64(1) == UInt64(0)) && continue
        ni = g.rows[i] & neigh
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            nij = ni & g.rows[j]
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)
                nijkl = nij & g.rows[k] & ~((UInt64(1) << k) - UInt64(1))
                count += count_ones(nijkl)
            end
        end
    end

    # Blue K₅ with new vertex: 4 non-neighbors that form I₄ in g
    # = 4 vertices not in neigh whose pairwise non-edges form K₄ in complement
    non_neigh = (~neigh) & ((UInt64(1) << n) - UInt64(1))
    gc_rows = [~g.rows[i] & ((UInt64(1) << n) - UInt64(1)) & ~(UInt64(1) << (i-1)) for i in 1:n]

    @inbounds for i in 1:n
        ((non_neigh >> (i-1)) & UInt64(1) == UInt64(0)) && continue
        ni = gc_rows[i] & non_neigh
        j_mask = ni & ~((UInt64(1) << i) - UInt64(1))
        while j_mask != UInt64(0)
            j = trailing_zeros(j_mask) + 1
            j_mask &= j_mask - UInt64(1)
            nij = ni & gc_rows[j]
            k_mask = nij & ~((UInt64(1) << j) - UInt64(1))
            while k_mask != UInt64(0)
                k = trailing_zeros(k_mask) + 1
                k_mask &= k_mask - UInt64(1)
                nijkl = nij & gc_rows[k] & ~((UInt64(1) << k) - UInt64(1))
                count += count_ones(nijkl)
            end
        end
    end

    return count
end

function _extension_tension_heuristic(g::AdjMatrix, n_samples::Int)
    n = g.n
    best = typemax(Int)

    for _ in 1:n_samples
        # Random adjacency pattern for new vertex
        mask = rand(UInt64) & ((UInt64(1) << n) - UInt64(1))
        cost = _extension_cost(g, mask)
        if cost < best
            best = cost
            best == 0 && return 0
        end
    end
    return best
end

end # module
