# R(5,5) Project — Results Summary
## Date: 2026-03-28

## Infrastructure (Module A) — COMPLETE

- Julia 1.12.5, BitMatrix representation, graph6 I/O
- K₅ detection: 656 graphs verified in 0.013s
- Cyclic(43) verified: 43 red K₅, 0 blue K₅
- Correct S_red = {1,2,7,10,12,13,14,16,18,20,21} (11 circular distances)
- Exoo(42) verified: 0 monochromatic K₅

## Structural Analysis (Module B) — COMPLETE

### Key findings on the 656 R(5,5,42) graphs:

| Property | Value |
|----------|-------|
| Degree range | [19, 22] for all graphs |
| Mean degree | ~20.34 |
| Edge count | [423, 430], mean 427.2 |
| Triangles | [1296, 1352], mean 1328.6 |
| K₄ count | [1099, 1209], mean 1168.8 |
| Unique degree sequences | 97 out of 328 |
| **Circulant graphs** | **0 out of 328** |
| λ₁ (largest eigenvalue) | [20.18, 20.52] |
| Spectral gap | [14.56, 15.24], mean 14.91 |
| Min edit distance | 1 (7 pairs) |
| Max edit distance | 515 |
| Mean edit distance | 414.26 |
| Extension tension | 64-81 (100k random samples) |

### Close pair analysis:
- 7 pairs at edit distance 1, ALL differ by edge (37,38) or (35,36)
- ~15 pairs at distance 4, pattern: {a, a+1, b, b+1} quadrilateral flips
- Constant 8 common neighbors at each differing edge
- 12-13 K₄ through each differing edge

## f(43) Minimization (Module C) — COMPLETE

### Exhaustive circulant search (2^21 = 2,097,152 colorings):
- **Best: S = {1,4,5,6,7,8,9,12,14,17}, total = 43 K₅ (0 red + 43 blue)**
- This is the complement of Exoo's construction (43 red + 0 blue)
- Multiple circulants achieve exactly 43

### Simulated annealing:
- SA from best circulant: cannot improve below 43
- SA from Exoo: cannot improve below 43
- SA from random: converges to ~160-440 (far worse)
- Aggressive SA (10M iterations, perturbation restarts): still 43

### Result: **f(43) ≤ 43** (robust local minimum)

## Lehav Extension (Module D) — COMPLETE

### Phase 1: Vertex duplication
- 27,552 candidates (656 graphs × 42 vertices), 0 valid R(5,5,43) graphs

### Phase 2: Backtracking with K₄ constraint pruning
- **All 656 graphs tested**: 0 feasible extensions for ANY graph
- For each G₄₂ ∈ R(5,5,42), the red K₄ and blue I₄ constraints
  make it impossible to assign edges for a 43rd vertex without
  creating a monochromatic K₅
- Execution time: ~170s total (avg 0.26s/graph)

### Conclusion: R(5,5,42) cannot be extended to R(5,5,43)
This is consistent with R(5,5) = 43 and reproduces Lehav's result
(arXiv:2411.04267) using Julia bitwise computation.

## Next Steps

1. Begin LaTeX document (Module E)
