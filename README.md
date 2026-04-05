# R(5,5) Computational Study

Computational tools and results for the Ramsey number R(5,5).

**Paper:** *A computational study of R(5,5)* — see `paper/r55_computational.tex`

## Summary of results

- **656 extremal graphs** in R(5,5,42) (328 base + 328 complements), cataloged by McKay--Radziszowski
- **Extension tension** τ(G) computed for all 656 graphs: min=2, max=49, mean=27.3
  - τ=2 proven optimal by SAT (CaDiCaL + totalizer cardinality encoding)
  - Two graphs (G₄₂, G₂₅₆) achieve τ=2: the closest any R(5,5,42) graph comes to admitting a one-vertex extension. Their optimal neighbor sets force exactly two monochromatic K₅, sharing three vertices each.
- **SAT Modulo Symmetries** (SMS) cube-and-conquer for R(5,5,43)
  - 11 canonical cubes at cutoff 50; 4483 at cutoff 70
  - smsg is 12–170× faster than CaDiCaL on symmetry-reduced cubes
- **march_cu bug fix**: critical use-after-realloc in microsat.c (14 derived pointers not updated after DB realloc)

## Repository structure

```
src/                          # Julia and Python source code
  RamseyR55.jl                # Core module: graph6 I/O, bitmask adjacency, K₅ counting
  analyze_656.jl              # Structural analysis of 656 extremal graphs
  exact_tension.jl            # Extension tension τ(G): fast heuristic (multi-start local search)
  exact_tension_sat.py        # Extension tension τ(G): exact SAT verification (PySAT + CaDiCaL)
  exact_tension_cpsat.py      # Extension tension τ(G): CP-SAT formulation (alternative)
  exact_tension_maxsat.py     # Extension tension τ(G): MaxSAT formulation (alternative)
  sat_encoding.jl             # DIMACS CNF encoder for R(5,5,n)
  sms_encoding.py             # SMS encoding
  flip_graph.jl               # Flip graph analysis
  minimize_f43.jl             # f(43) minimization via circulant search + SA
  lehav_extension.jl          # Lehav extension theorem implementation
  search_657th.jl             # SA search for new R(5,5,42) graphs
  make_cube_cnf.sh            # Convert SMS cubes to standalone CNF files
data/
  r55_42some.g6               # 328 base R(5,5,42) graphs in graph6 format
results/
  exact_tension.csv           # τ(G) for all 656 graphs (with optimal N)
  wcnf/                       # WCNF instances for SAT verification
  sat/                        # SAT/SMS cube data (cubes, timing)
paper/
  r55_computational.tex       # Paper source
  r55_computational.pdf       # Compiled paper
tools/
  march_cu_fixed/             # march_cu with use-after-realloc fix
  march_cu_optimized/         # + dense k-SAT optimizations
```

## Reproducing results

### Prerequisites
- Julia ≥ 1.10
- Python ≥ 3.10 with `python-sat` (`pip install python-sat`)
- smsg v2.1.0 (for SMS cubing): https://github.com/Udopia/sms
- CaDiCaL (for SAT verification): https://github.com/arminbiere/cadical

### Extension tension (all 656 graphs)

The computation is a two-stage pipeline:

1. **Heuristic bounds** (`exact_tension.jl`, Julia): multi-start local search
   with 500k random seeds, steepest-descent single-bit flips, and 2-bit
   perturbations. Runs in ~17 minutes for all 656 graphs.
2. **Exact verification** (`exact_tension_sat.py`, Python/PySAT): SAT-based
   binary search with totalizer-encoded cardinality constraints and CaDiCaL.
   Used to prove optimality for extreme cases (e.g., τ=2 in ~60s).

The heuristic and exact results agree on all verified cases.

```bash
# Step 1: compute heuristic τ(G) for all 656 graphs
julia src/exact_tension.jl
# Output: results/exact_tension.csv (~17 minutes)

# Step 2: verify extreme cases via SAT (optional, ~60s each)
# First generate WCNF files (done automatically by exact_tension.jl for graph 1)
# Then verify:
python3 src/exact_tension_sat.py  # verifies τ=2 for graphs 42, 256
```

### SMS cubing
```bash
# Generate cubes (requires smsg)
smsg -v 43 --dimacs results/sat/r55_43_sms.cnf --assignment-cutoff 50 > results/sat/cubes_sms_43.icnf
# Solve a cube
smsg -v 43 --dimacs results/sat/r55_43_sms.cnf --cube-file results/sat/cubes_sms_43.icnf --cube-line 1
```

## Citation

If you use this code or data, please cite:
```bibtex
@misc{R55study2026,
  author = {Whoneon},
  title = {A computational study of {R}(5,5)},
  year = {2026},
  url = {https://github.com/Whoneon/R55}
}
```

## License

MIT
