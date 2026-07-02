# PDCG — current implementation

This document describes the implemented Propagation-Driven Constructive
Generator (PDCG). The full design rationale lives in
[`vision.md`](vision.md) and the detailed analysis in
[`refinement.md`](refinement.md).

## 1. Architecture

The PDCG replaces the core "random grid → enumerate constraints →
greedy solve-ratio loop" pipeline (see [`generator.md`](../generator.md)
§ 1) with an **incremental seed-first, constraint-later** approach:

```
1. Seed: place a few readonly cells (centre-biased, random values)
2. Reference: run solve() once → partial `cachedSolution` projection
3. Loop: pick free cell → generate candidates → clone+propagate → accept
   (fallback: gentle force on the target, else block the cell)
4. Post-processing: reject unless the puzzle is fully closed, stamp
   `scenario:pdcg`, export
```

There is **no backing solution grid**: the reference the parameters are
derived from is the (partial) `solve()` projection of the current
seed + constraint set, refreshed after every accepted constraint or
forced cell.

It lives in `lib/getsomepuzzle/generator/generator.dart` as a
`GenerationStrategy.pdcg` code path inside `_generateOneTimed`, by
delegating to `_generateOnePdcg`.

### 1.1. What gets reused

| Component | Usage |
|-----------|-------|
| `GeneratorConfig` | Same config object; added `int pdcgSeedSize` and `int pdcgForceDepth` fields |
| `GenerationRejectReason` | Added `pdcgStalled`; reuses `ratioTooHigh`, `cancelled`, `attemptStalled` |
| `Puzzle.clone()` | Tentative constraint addition |
| `propagateToFixpoint()` | Core satisfiability oracle |
| `maxStall` watchdog | Same no-progress idiom as the classic loop |
| `_finalize()` | Post-loop `solveExplained`, `classifyTrace`, `lineExport` |

### 1.2. What is new

- `_generateOnePdcg()` — the main function
- `_enumerateConstraintsForCellPdcg()` — slug-by-slug candidate generation
  for a given target cell (FM and BB candidates are grid-global; the
  other slugs anchor on the target or its neighbours)
- `_forceCellPdcg()` — gentle force: tries each domain value on the
  target via clone + propagate; if exactly one survives it becomes a
  readonly cell
- `_neighbours()`, `_sideCells()`, `_eyeSeen()` — small helpers
- `_puzzleFromSolution()` — builds a temporary Puzzle from a flat
  `List<CellValue>` state for group queries and `verify` probes (built
  once per enumeration call and shared across slugs)
- Slug ordering in the main loop: deficit-weighted when the equilibrium
  provides `slugDeficitScores`, otherwise round-robin over the 13-slug
  priority list

## 2. Pipeline

### 2.1. Reference solution

The seed cells receive **random** values. `cachedSolution` is then set
from a `solve()` run (propagation + force, no backtracking) — with no
constraints yet this is just the seed plus free cells. It is refreshed
after every accepted constraint / forced cell, so it converges toward a
full grid as the constraint set grows.

Because the reference is partial, candidate parameters are only
*truthful for the determined cells*: counts (NC, RC, CC, EY, QA, GC)
reflect the determined portion, and SY/PA candidates are emitted
without any reference check. Candidates are therefore speculative by
design — the clone-and-propagate acceptance test is what keeps the
constraint set consistent, and `_finalize`'s deductive-uniqueness check
guarantees the emitted puzzle is valid.

### 2.2. Seed placement

5 cells by default (`pdcgSeedSize`, clamped to `[3, size]`). The grid
centre is `(centreRow, centreCol) = ((h-1)/2, (w-1)/2)`. All cell
indices are sorted by Manhattan distance from centre; the closest
`seedSize` cells are set to a random domain value with
`readonly = true`.

### 2.3. Main loop

**Bounds**: `iterations < size × 2`, the `maxStall` no-progress
watchdog (`attemptStalled`), and `shouldStop`. Progress is reported via
`onProgress` (iteration count over `maxIter`, probe free-cell ratio)
and accept-gap telemetry via `onStallStats`.

Each iteration:

1. **Probe** — clone `pu` and run `propagateToFixpoint()` to see which
   cells the current constraints resolve. If the probe contradicts,
   abandon (`pdcgStalled`). If the probe is `complete`, break.

2. **Pick target** — collect free cells from the probe that aren't
   in the `blocked` set. Sort by (most determined neighbours first,
   then closest to centre). Pick the first one.

3. **Generate candidates** — call `_enumerateConstraintsForCellPdcg`
   which generates one `Constraint` object per valid parameter for
   each allowed slug.

4. **Test candidates** — group candidates by slug. Order the slugs by
   corpus deficit (`slugDeficitScores`, most under-represented first,
   tie-break by static priority) when the equilibrium provides the
   map; otherwise round-robin starting at `iter % 13` in the priority
   list. For each slug in this order, test its candidates on a clone +
   `propagateToFixpoint()`. Accept the first candidate whose clone
   reduces the free-cell count. If accepted, graft the constraint onto
   `pu` and refresh `cachedSolution` (via `solve()` if the clone is
   not complete).

5. **Fallback** — if no candidate was accepted and `pdcgForceDepth > 0`,
   try the gentle force on the target (`_forceCellPdcg`): if exactly
   one domain value survives propagation, set it as a readonly cell
   and refresh `cachedSolution`. Otherwise add the target to `blocked`
   and try another cell next iteration.

LT candidates always use the letter `A`: `Puzzle.addConstraint`
aggregates same-letter LT instances, so every accepted pair merges
into one growing connected group instead of scattering trivial 2-cell
groups.

### 2.4. Slug priority order

```
DF → FM → NC → RC → CC → PA → GS → SY → LT → EY → QA → GC → BB
```

Used as the round-robin base list and as the tie-break for
deficit-weighted ordering.

### 2.5. Post-processing

After the main loop:

- **Closure check**: run `solve()` on a clone. If `ratio > 0.25`,
  reject with `ratioTooHigh`; if `0 < ratio ≤ 0.25`, reject with
  `pdcgStalled`. There is no hint-filling fallback: `cachedSolution`
  comes from the same deterministic `solve()` as the check, so any
  cell free here is also unknown there — the constraints (plus seed
  and forced cells) must close the puzzle entirely.
- **Marqueur**: stamp `pu.generationScenario = 'pdcg'` so the emitted
  line carries the authoritative `scenario:pdcg` suffix
  (`detectPuzzleProfile` court-circuits on it; without it the puzzle
  would be counted as `classic` and the equilibrium's pdcg bucket
  would never fill).
- **Finalise**: delegate to `_finalize()` (same as the existing
  generator): `solveExplained()`, `classifyTrace()`, `lineExport()`.

## 3. Equilibrium and CLI integration

- `ProfileCategory.pdcg` is a profile-axis category with a 2 % target
  share (`kTargetProfile`). `generationBucket` keeps it in its own
  bucket; `detectPuzzleProfile` recognises the `scenario:pdcg`
  marqueur.
- `ProfileTarget(pdcg)` resolves to a per-attempt
  `GenerationStrategy.pdcg` override in the worker
  (`_ResolvedTarget.strategy`, applied as
  `attemptStrategy ?? params.strategy`), and `_resolveScenario`
  reports `pdcg` with top priority.
- `pdcg` is a valid `--strategy` value in `bin/generate.dart` but is
  **not** in the default rotation: strategies are assigned round-robin
  across workers, so listing it by default would dedicate ~1/4 of the
  pool to PDCG against its 2 % corpus target. The equilibrium routes
  attempts to it by itself.

## 4. Why this design

- **No constraint modification.** The existing `Constraint` subclasses
  are unchanged. The PDCG uses the same `createConstraint` factory and
  the same `propagateToFixpoint()` protocol.
- **Self-contained.** All new code is inside `_generateOnePdcg` and its
  helpers. The existing generator paths are untouched.
- **Speculative candidates, validated acceptance.** Deriving truthful
  parameters without a resolved grid would need a different
  satisfiability model; instead the candidates are cheap guesses and
  the clone+propagate test (plus `_finalize`) filters them.

## 5. Known limitations

- **Limited slug support.** 13 of the ~20 registered slugs. SH, CH,
  IM, MJ, RT, CT are excluded (SH would need its motif painted as seed
  cells; the others mostly require domain > 2 or expensive parameter
  enumeration).
- **Small grid ceiling.** Works well up to ~10×10. Beyond that the
  per-iteration cost rises (FM/BB enumerate parameters over the whole
  grid, and each candidate test is a clone + propagate), and the
  simple seed strategy doesn't close the puzzle reliably. See
  `next_steps.md` P7.
- **No QA gating.** QA tends to brute-force the endgame; see
  `next_steps.md` P9.
