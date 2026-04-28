# Puzzle generation

This document describes the implemented generation pipeline. Three layers
work together:

1. **Single-puzzle generation** — `lib/getsomepuzzle/generator/generator.dart`,
   the core "grid → constraints" greedy algorithm.
2. **Equilibrium bias** — `lib/getsomepuzzle/generator/equilibrium.dart`
   (with a dedicated doc: see [`equilibrium.md`](equilibrium.md)). Steers
   the per-iteration target toward the most under-represented bin across
   four independent axes.
3. **Post-generation polishing** — CLI tools (`bin/trace_score.dart`,
   `bin/filter_score.dart`, `bin/polish.dart`) that score puzzles by
   deduction elegance and reject or repair the weakest ones.

## 1. Core greedy algorithm

The generator is "grid → constraints": it starts from a concrete solved
grid, then collects the constraints that characterise it best.

### 1.1. Pipeline

1. **Build a random solution grid.** Each cell is filled with a random domain
   value (`{1, 2}`). Special case for the `SH` (Shape) constraint: when SH
   is required or pushed by the equilibrium target, the grid is pre-seeded
   with a valid Shape motif before completion, so a Shape constraint will
   always be satisfiable.

2. **Pre-fill a few cells.** A random ratio in `[0.8, 1.0]` decides what
   fraction of cells stays empty for the player; the others are locked
   (`readonly`) at their solution value. So 0–20 % of the grid is given
   as hints.

3. **Enumerate every valid constraint.** For each registered slug
   (`FM, PA, GS, LT, QA, SY, DF, SH, CC, GC, NC`), `generateAllParameters`
   yields every parametric instance for the grid dimensions; the generator
   keeps only the ones that **verify against the solution grid**. This is
   the "true" constraint set for that solution.

4. **Sort the candidates.** Random shuffle, then a stable sort that pushes
   `prioritySlugs` (= `requiredRules ∪ preferredSlugs`) to the front and
   breaks ties by a global usage counter (rare slugs first). `requiredRules`
   is what the user demanded; `preferredSlugs` is what the equilibrium /
   warm-up targeting *would like* to see, but never strictly enforces.

5. **Greedy cherry-picking.** While the puzzle is not fully determined:
   - Pop the next candidate.
   - Clone the puzzle and `solve()` (propagation + force, no backtracking)
     to get `ratio_before`.
   - Add the candidate to the clone and `solve()` again to get
     `ratio_after`.
   - If `ratio_after < ratio_before`, the constraint is "useful" and is
     kept.
   - After each accepted constraint, the remaining candidates are
     reshuffled and re-sorted by *local* usage (favouring diversity
     within the puzzle).

6. **Finalisation.**
   - If the residual ratio reaches 0: the puzzle is fully determined by
     its constraints.
   - If `0 < ratio ≤ kMaxAcceptableRatio` (= 0.25): fill the remaining
     cells with the known solution as readonly hints.
   - Otherwise: discard.
   - Final gate: `Puzzle.isDeductivelyUnique()` — `solve()` must close
     the puzzle from the readonly cells. This replaced the old
     `countSolutions() == 1` check (which relied on backtracking) and is
     stricter: every shipped puzzle is solvable by the in-game hint
     system, with no guessing required.

### 1.2. Why this design

- **Solution known by construction.** The grid is the input, so every
  candidate constraint is trivially satisfiable; no global feasibility
  check is needed.
- **The solver doubles as the metric.** A constraint's "usefulness" is
  measured by how much the solver's free-cell ratio drops when it is
  added. Generation and resolution stay tightly coupled.
- **No backtracking anywhere.** Neither in the constraint selection
  loop nor in the final uniqueness check. The pipeline is easy to
  parallelise (each attempt is independent) and easy to debug.
- **Required / banned slugs are upstream filters**, not last-mile
  rejections.

### 1.3. Known limitations

- **The random grid decides everything.** A bland 50/50 grid will not
  produce an elegant `SY` or `SH` puzzle even if such a puzzle exists at
  those dimensions.
- **The usefulness metric is coarse.** `ratio_before − ratio_after` does
  not distinguish a constraint that unlocks one trivial cell from one
  that triggers a cascade or that interacts with another constraint.
- **Greedy without regret.** A constraint accepted early can shadow a
  more elegant later candidate. Section 3 below describes the
  post-generation polish that mitigates this.
- **The 0.25 ratio cap is a fallback.** When constraints don't determine
  everything, hints fill the gap — visually heavier puzzles.
- **Bias toward "soft" solutions.** Random 50/50 grids rarely have
  notable structure, which under-uses structural constraints
  (`GS`, `SY`, `SH`, `GC`).

## 2. Equilibrium

`bin/generate.dart` invokes the generator inside a per-iteration loop
that rebalances the corpus across four axes (slug, number of types,
pair of types, size). The full description lives in
[`equilibrium.md`](equilibrium.md). In short: every iteration picks the
most under-represented `(axis, category)`, configures the generator
accordingly, and lets the greedy algorithm produce a puzzle for that
target.

## 3. Post-generation scoring and polishing

The greedy algorithm has no notion of *deduction elegance*. A
post-generation pass scores each puzzle by the shape of its
solver trace and either filters or repairs the weakest puzzles.

### 3.1. Trace score (`bin/trace_score.dart`)

`Puzzle.solveExplained()` already returns a list of `SolveStep`s tagged
with the responsible constraint and the deduction kind (`propagation` or
`force`). From that trace, `scorePuzzle()` computes:

| Metric | Definition |
|---|---|
| `switch_ratio` | Fraction of prop→prop transitions where the responsible constraint changes (proxy for interleaved deductions / aha-chains). |
| `cascade_ratio` | Length of the longest single-constraint cascade ÷ total propagation steps (penalises a single "overwhelming" constraint, e.g. FM:12). |
| `force_ratio` | Number of force steps ÷ total steps. |
| `force_depth` | Sum and max of propagation depths inside force steps (deeper force = harder to do mentally). |
| `diversity` | Constraints that contributed at least once ÷ total constraints declared. |
| `start_ok` | 1 if at least one propagation step precedes the first force, 0 otherwise — guarantees a starting point. |
| `needs_backtrack` | 1 if propagation+force don't close the puzzle → disqualified. With `isDeductivelyUnique()` enforced at generation time, this should always be 0 on shipped puzzles. |

Combined score:

```
forcePenalty = forceSteps == 0
             ? 0
             : 3 + 2 · forceDepthAvg + 1.5 · forceDepthMax

score = 40 · switch_ratio
      − 40 · cascade_ratio
      − forcePenalty
      + 20 · diversity
      + 20 · start_ok
```

The penalty on force steps is no longer a flat `−20 · force_ratio` — it
weighs the *depth* of each force round, since shallow force is easier
on the player than deep force.

### 3.2. Validation against player ratings

`bin/rating_correlation.dart` cross-references the score with the
liked/neutral/disliked ratings stored in `stats/stats.txt`. On the
1277-play sample collected so far:

| Rating | n | mean score | cascade_ratio | switch_ratio |
|---|---|---|---|---|
| **Liked** | 404 | **48.9** | **0.22** | **0.59** |
| Neutral | 858 | 46.3 | 0.26 | 0.57 |
| **Disliked** | 15 | **34.7** | **0.47** | **0.38** |

A `score ≥ 40` filter keeps 79 % of liked puzzles and removes 73 % of
disliked. `cascade_ratio` is the strongest single signal — most disliked
puzzles are dominated by a `FM:12` / `FM:21` propagating across the
whole grid.

### 3.3. Filtering (`bin/filter_score.dart`)

S1 — rejection sampling. Reads puzzle lines, scores each one with
`scorePuzzle()`, and emits only those that meet the threshold (default
40). Per-puzzle timeout (default 15 s) protects against pathological
solver behaviour. Stats on rejection rate are reported on stderr.

### 3.4. Polishing (`bin/polish.dart`)

S2 — local-search polish. For each input puzzle, tries random mutations
that

1. preserve uniquely-deductive solvability, **and**
2. improve the trace score.

Greedy best-improvement loop until no mutation helps or the iteration /
candidate / time budget is exhausted. Output: improved puzzles plus a
summary of the mutations applied.

These two tools are intentionally separate from the generator inner
loop: post-processing is opt-in and runs offline on collections, not on
every interactive generation.

## 4. Future directions

The bigger ideas explored during the trace-score design are tracked as
TODOs in [`todo.md`](todo.md):

- Extend the score by separating "true C2" interleaving from accidental
  switches (would need a second solver pass).
- Detect *meta-inferences* (`M`): a new constraint logically implied by
  the existing ones, independent of the grid (e.g. `FM:112 + FM:122`
  implies `FM:102`).
- Theme-first generation: pick a thematic skeleton (`SY`, `SH`,
  FM-duo, …) and search for a grid that makes it uniquely solvable —
  the inverse of the current grid-first approach.
- Local search on the joint `(grid, constraint set)` space, with a
  tunable quality function that combines trace score, parsimony, and
  starting-point guarantees.

These are not blocking the current pipeline. The combination of
greedy generation + equilibrium bias + post-generation polish covers
the practical needs for the corpus shipped today.
