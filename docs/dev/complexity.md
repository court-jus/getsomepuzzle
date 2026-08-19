# Complexity scoring

This document describes how the puzzle complexity score is computed and, in
particular, how individual deductions made by `Constraint.apply()` contribute
to that score. The design goal is that the complexity reflects how hard a
puzzle feels to a human player, not how hard it is for the solver.

## Requirements

The complexity system and the collection routing are governed by the five
criteria below.

1. Every decision made by the solver (each `CanApply` firing) carries a
   complexity score.
2. There is a clear correlation between a puzzle's complexity and its
   routing into a collection.
3. The domain size participates in the complexity computation.
4. On a domain larger than 2, a `RemoveOption` move is more complex than
   a `SetValue` move of the same tier.
5. The total number of constraints is not a criterion.

Status as of 2026-08-18:

- **1, 3, 4 and 5 hold.** Every `SetValue`/`RemoveOption` construction
  sets `complexity:` explicitly (verified by audit); `ruleDiversity`
  counts distinct constraint *types*, never instances; on a domain
  larger than 2 every propagation `RemoveOption` contributes
  [kRemoveOptionComplexityBump] extra on top of its tier (see the
  "Score formula" note below and `Puzzle.moveComplexity`); and the
  score pays a flat domain term `(domain.length − 2) *
  kDomainSizeComplexityBump` (see "Score formula"). The score is also
  **unbounded** (no 90/100 caps) so force-heavy puzzles discriminate
  past 100; [kUnsolvableComplexity] marks the not-deductively-solvable
  case. The d3 complexity bands still await human playtest data
  (see `third_color.md`); the **adaptation anchor was re-calibrated**
  on the recomputed corpus on 2026-08-19 (see the "Scale consequences"
  note below).
- **2 holds statistically, not monotonically.** Spearman correlation
  between collection index and stored cplx is ≈ 0.84 (d2) / 0.86 (d3),
  but the `advanced`/`strong`/`expert` medians overlap and invert in
  the 25–60 band (`recommendedLevelFor` in `level.dart` documents the
  non-monotonicity).

The sections below describe the current implementation; the gaps are
tracked in [Future work](#future-work).

## Move.complexity

Every `Move` returned by a constraint's `apply()` carries an integer
`complexity` weight (see `lib/getsomepuzzle/model/cell.dart`). The weight
is on a 0–5 scale, with the following meaning:

| Weight | Tier name              | Player effort                                                                  |
| -----: | ---------------------- | ------------------------------------------------------------------------------ |
|      0 | Trivial saturation     | "Counters are full / target reached" — can be read off without reasoning.      |
|      1 | Local counting         | One-step counting of cells in a row, group, neighborhood, etc.                 |
|      2 | Local spatial          | Local geometric reasoning (single move, single constraint).                    |
|      3 | Reachability / merge   | Requires thinking about what could still grow, merge, or remain reachable.    |
|      4 | Articulation / enum    | Bottleneck arguments, enumeration of all completions, articulation points.    |
|      5 | Combinatorial probing  | Constraint-internal "what if" probing across multiple candidate cells.        |

For force moves (`Move.isForce == true`), the weight is irrelevant; the
score uses `forceDepth` instead. The complexity field is set to `0` on
force moves to keep the bookkeeping simple — the scoring code branches on
`isForce` and never reads `complexity` for those.

For impossibility moves (`Move(..., isImpossible: this)`), the weight is
also irrelevant: as soon as one is observed, the puzzle is flagged as not
deductively solvable and the score is forced to 100.

## Score formula

```
forceScore  = sum(move.complexity for prop moves)
            + sum(5 + 5 * move.forceDepth for force moves)

domainBonus = (domain.length − 2) * kDomainSizeComplexityBump

complexity  = forceScore + ruleDiversity + emptiness + domainBonus
```

**The score is unbounded** — it is a plain sum of non-negative components,
with no effort cap and no total cap. This is deliberate (2026-08): the old
`0..90` effort cap and `0..100` total cap flattened every force-heavy
puzzle into the 96–100 band, destroying discrimination at the top of the
scale. With the caps removed, real 6-mad puzzles compute to 100–230 and
beyond, while easy/player/advanced puzzles keep their former values (they
never reached the caps). Fixed reference points only:

- **0** — the puzzle is already completely prefilled (no work left).
- **[kUnsolvableComplexity]** (= 100, `model/puzzle.dart`) — the puzzle is
  **not deductively solvable** (contradiction or stuck state). Since the
  score is unbounded, a *solvable* puzzle may coincidentally also sum to
  100; consumers needing certainty should check `Puzzle.cachedSolution ==
  null` rather than compare scores.

The `ruleDiversity` (0–4) and `emptiness` (0–6) components are unchanged.
With this formula a puzzle solved purely by trivial saturation contributes
0 to `forceScore` and finishes in the 0–10 band (rule diversity +
emptiness only). A puzzle that requires repeated articulation reasoning
or many force rounds accumulates effort well past the old 90-point
ceiling.

The mapping `force = 5 + 5 * forceDepth` matches the previous
implementation (`(1 + forceDepth) * 5`) so existing scores stay in the
same neighbourhood for puzzles that were already force-heavy. The new
(2026-08) contribution is the propagation tier sum, which used to be
implicitly 0.

> **Scale consequences to keep in mind.** The app surface still assumes a
> "cplx = 0–100" mental model in two places, audited as of 2026-08:
>
> - **Stats dashboard** (`model/stats.dart`) buckets by cplx ranges;
>   an explicit `101+` bucket was added for the overflow tail.
> - **Player adaptation** (`model/database.dart`) keeps its 0–100
>   `playerLevel` (still clamped there) but feeds `puzzle.cplx` into the
>   duration model `exp(cplx/59.4)` and the `level_i = 2·cplx −
>   implied(dur)` inversion.
>
> **The adaptation anchor was re-calibrated on 2026-08-19.** The old
> duration-model constants (`exp(cplx/123.8)`, calibrated on the capped
> distribution) were stale after the corpus recompute: with the
> recomputed, unclamped cplx they pinned 56 % of plays at level 0/100
> (mean level 88). Fresh constants were obtained by re-running
> `bin/analyze_stats.dart --recompute-cplx` on the recomputed corpus and
> pasting the anchored block it prints (now `exp(cplx/59.4)`, R² = 0.621,
> MAPE = 46 % — see `adapt_to_player.md`).
> - Collection *routing* (`classifyTrace`) is unaffected — it classifies
>   trace *shape*, never total cplx.

> **Domain size (requirement 3, implemented).** Every puzzle pays a flat
> `(domain.length − 2) * kDomainSizeComplexityBump` (default 5) on top
> of its score: 0 for the 2-colour baseline, +5 for 3-colour, +10 for
> 4-colour, etc. Each extra colour doubles the option-tracking load per
> free cell, hence the per-colour cost. The bonus is deliberately flat
> (puzzle-level) rather than per-move, unlike the prune bump below; it is
> added in both `computeComplexity` and `computeComplexityFromSteps`,
> and any fully-prefilled puzzle short-circuits to 0 before it applies.
> The constant lives in `model/cell.dart` next to
> [kRemoveOptionComplexityBump] for one-place re-calibration. Combined
> with the unbounded score (see above) the bonus simply lifts every
> 3-colour puzzle's score by 5 — no ceiling effects any more.

> **`RemoveOption` vs `SetValue` (requirement 4, implemented).** Every
> *propagation* `RemoveOption` on a puzzle whose domain is larger than 2
> contributes `Move.complexity + kRemoveOptionComplexityBump` (default
> bump = 1) instead of its bare tier. This is correct on a 2-colour
> domain, where a prune auto-collapses to an assignment
> (`Cell.removeOption`, `model/cell.dart`) and the two move types are
> semantically one — so there the bump stays 0. On a domain larger than
> 2 a prune leaves the cell free with residual options, which a human
> must keep tracking, hence the extra weight.
>
> The bump is applied in a single place — `Puzzle.moveComplexity`
> (`model/puzzle.dart`) — which is called by `_solveEffort` (live solve
> path) and by the `SolveStep` recorders in `solveTrace` /
> `solveTraceAsync` (trace path). Every downstream consumer
> (`computeComplexityFromSteps`, `classifyTrace`,
> `sortConstraintsByDifficulty`) reads the *recorded* step complexity,
> so hints, routing and scoring all see the same bumped value. Force
> moves are never bumped: their weight is `5 + 5 * forceDepth` and
> their recorded `complexity` stays 0. Covered by
> `test/complexity_test.dart`.

## Caching and freshness

Field `[6]` of a v2 puzzle line carries the cached complexity. `Puzzle(...)`
reads it into `cachedComplexity` at construction time;
`computeComplexity()` returns the cached value unless `force: true` is
passed. This makes the line on disk the **source of truth for the
running app** — any UI sort or level filter that calls
`computeComplexity()` will trust whatever the asset shipped.

Maintenance tools — `bin/recompute.dart`, `bin/dedup_puzzles.dart`,
`bin/aggregate_player_stats.dart`, `bin/analyze_stats.dart` — pass
`force: true` so that re-running them after a complexity-formula change
re-derives every line from scratch. The same `force` flag is used in
`test/complexity_test.dart` because the test fixtures carry stored cplx
values; the tests assert the computed value, not the loaded one.

After any change to the scoring formula or to any constraint's
`apply()` weights, run

```bash
dart run bin/recompute.dart --route assets/*.txt
```

and commit the diff — otherwise the in-app sorter and level filter will
keep using pre-change scores until the next corpus refresh. There is no
in-app cache-invalidation hook tied to solver-version bumps; freshness
is enforced at corpus-build time.

> The batch trace cache (`solve_traces.tsv`, see `bin/_trace_cache.dart`)
> stores each step's `tier` verbatim. A scoring change that alters
> recorded step values — like the domain-aware prune bump — makes
> cached traces stale for the *recompute* run itself. Delete
> `solve_traces.tsv` before re-running `recompute` after such a change;
> the cache file is gitignored and rebuilt from scratch.

## Per-constraint deduction inventory

The deductions below are the distinct branches inside each constraint's
`apply()` method. Weights reflect the player effort needed to reach the
same conclusion mentally. References point to the implementation as it
stood when this document was written; line numbers will drift.

### FM — Forbidden Motif (`constraints/motif.dart`)

| # | Deduction                                                     | Weight |
| - | ------------------------------------------------------------- | -----: |
| 1 | Submotif with a wildcard matches → fill the wildcard cell    |  size-dep. |

The motif size dictates the weight. The submotif covers
`motif.length * motif[0].length - 1` cells, so:

- 1×2 / 2×1 (e.g. `FM:11`, `FM:1.1`): weight **0** — a single visible
  same-color cell forces its neighbour.
- 1×3 / 3×1 (e.g. `FM:111`): weight **1**.
- 2×2 (e.g. `FM:11.11`): weight **2**.
- larger (3×2, 3×3, …): weight **3**.

The weight is computed once from `motif.length * motif[0].length` and
applied to every Move returned by this constraint, regardless of which
sub-position triggered.

### PA — Parity (`constraints/parity.dart`)

| # | Deduction                                                | Weight |
| - | -------------------------------------------------------- | -----: |
| 1 | Even count == half → remaining empties must be odd      |   side |
| 2 | Odd  count == half → remaining empties must be even     |   side |

The weight depends on the **largest side** covered by the constraint —
i.e. the longest run of cells on any one side of the anchor (left,
right, top, bottom). Two-side variants (`horizontal` / `vertical`)
take the max of their two sides, since the player has to scan the long
side either way.

| Largest side | Weight |
| -----------: | -----: |
|            2 |      0 |
|            4 |      1 |
|           6+ |      2 |

Rationale: with 2 cells per side, knowing one parity reads off the other
immediately; 4 cells require some counting; 6+ needs real bookkeeping.
Example: `PA:2.horizontal` on a 7-cell row has 2 cells left, 4 cells
right → weight 1.

### GS — Group Size (`constraints/groups.dart`)

| # | Deduction                                                                                       | Weight |
| - | ----------------------------------------------------------------------------------------------- | -----: |
| 1 | Empty cell next to a group already at max size → opposite color                                |      1 |
| 2 | Reachability: flood-fill of empties+sameColor < size → that color is impossible              |      3 |
| 3 | Group complete → all free neighbours become opposite (close borders)                          |      0 |
| 4 | Group has only one free neighbour → that neighbour completes the group                         |      1 |
| 5 | Extending into a free cell would merge into a too-big group → block it                         |      2 |
| 6 | Articulation point: blocking a free cell would shrink reachable component below `size`        |      4 |

Articulation reasoning (deduction 6) is the hardest tier — players rarely
spot it without explicit casework.

### LT — Letter Group (`constraints/groups.dart`)

| # | Deduction                                                                                  | Weight |
| - | ------------------------------------------------------------------------------------------ | -----: |
| 1 | Empty member of the letter must take the letter colour                                    |      0 |
| 2 | Free neighbour shared with another letter must be opposite (avoid merge)                  |      1 |
| 3 | No virtual group can connect all members → impossible                                     |  (n/a) |
| 4 | Articulation point: blocking a free cell would disconnect members                         |      4 |
| 5 | Free neighbour adjacent to a different letter's same-colour cells must be opposite        |      2 |

### QA — Quantity (`constraints/quantity.dart`)

| # | Deduction                                                                  | Weight |
| - | -------------------------------------------------------------------------- | -----: |
| 1 | `myValues == count` → all remaining empties become opposite               |      0 |
| 2 | `count - myValues == freeCells` → all empties become target value         |      0 |

Pure global counting, the easiest tier.

### SY — Symmetry (`constraints/symmetry.dart`)

| # | Deduction                                                                          | Weight |
| - | ---------------------------------------------------------------------------------- | -----: |
| 1 | Symmetric of a group member is empty → fill it with the group's colour            |      1 |
| 2 | Opposite-colour neighbour of the group → its symmetric must be opposite too        |      2 |
| 3 | Free neighbour whose symmetric is filled or out-of-bounds → must be opposite      |      2 |

### DF — Different From (`constraints/different_from.dart`)

| # | Deduction                                                                | Weight |
| - | ------------------------------------------------------------------------ | -----: |
| 1 | One cell coloured, the other empty → empty cell takes opposite colour    |      0 |

Trivial constraint by design.

### CC — Column Count (`constraints/column_count.dart`)

| # | Deduction                                                              | Weight |
| - | ---------------------------------------------------------------------- | -----: |
| 1 | `colorCount == count` → free cells in the column become opposite      |      0 |
| 2 | `count - colorCount == freeCells` → free cells become the target color |      0 |

### RT / CT — Row / Column Transition (`constraints/transition_utils.dart`)

See [`transition.md`](transition.md) for the full deduction walkthrough.

| # | Deduction                                             | Weight |
| - | ----------------------------------------------------- | -----: |
| 1 | Saturated (`t == count`): free cell forced to match neighbour | 1 |
| 2 | Full need (`t + fp == count`): free cell forced to differ  | 2 |
| 3 | Endpoint parity: one endpoint known, parity deduces the other | 3 |

Zero-transition and maximum-transition cases use the same branches
(saturated / full need) and carry the same weights — the boundary
extremes are not special-cased in the scoring.

### GC — Group Count (`constraints/group_count.dart`)

| # | Deduction                                                                                | Weight |
| - | ---------------------------------------------------------------------------------------- | -----: |
| 1 | A unique merge-cell must take `color` to keep the count from dropping below the target  |      3 |
| 2 | All candidates must separate (adjacency forbidden) → force a candidate                  |      3 |
| 3 | Simulation probe: colouring a candidate would push minGroups above target → opposite    |      4 |

`GC` deductions are intrinsically global: the player has to reason about
how many distinct groups can still appear or merge anywhere on the grid.

### NC — Neighbor Count (`constraints/neighbor_count.dart`)

| # | Deduction                                                              | Weight |
| - | ---------------------------------------------------------------------- | -----: |
| 1 | `targetColorNeighbors == count` → free neighbours become opposite      |      0 |
| 2 | `freeNeighbors == count - targetColorNeighbors` → free → target color  |      0 |

A cell looks at four neighbours and counts; trivial.

### EY — Eyes (`constraints/eyes_constraint.dart`)

| # | Deduction                                                                              | Weight |
| - | -------------------------------------------------------------------------------------- | -----: |
| 1 | Lower bound: cells in positions `0..minD-1` of a direction must be `color`            |      2 |
| 2 | Upper bound when `totalSeen == count` (eye already satisfied) — close the line        |      0 |
| 2 | Upper bound otherwise — juggling per-direction budgets across all four directions     |      3 |

The "already satisfied" case includes `count == 0` (the eye must see
nothing): closing the line of sight is just "stop seeing more". Once the
target is met or the count is zero, the player only needs to walk each
direction and force the next empty to opposite — no global bookkeeping.

The lower bound and the unsatisfied upper bound require thinking about
how much each direction can contribute to the total, which is heavier
than per-cell counting.

### SH — Shape (`constraints/shape.dart`)

| # | Deduction                                                                              | Weight |
| - | -------------------------------------------------------------------------------------- | -----: |
| 1 | Open group already matches a variant → close all free neighbours                       |      0 |
| 2 | Open group cannot fit in any variant (cell count / bbox / sub-shape) → impossible     |      2 |
| 3 | Adding a free neighbour breaks variant compatibility → block neighbour                 |      2 |
| 4 | Cell present in *every* completion enumeration → force colour                          |      4 |
| 5 | Free neighbour present in *no* completion enumeration → force opposite                 |      4 |
| 6 | Filling a free cell would merge groups into a shape that fits no variant → block      |      3 |

The completion-enumeration deductions (4 and 5) are the hardest: they
require mentally placing every variant on the grid.

### BB — Bounding Box (`constraints/bounding_box.dart`)

| # | Deduction                                                                                   | Weight |
| - | ------------------------------------------------------------------------------------------- | -----: |
| 1 | Box over-large, or too small with an unreachable extent → impossible                        |  (n/a) |
| 2 | A dimension already at target: an adjacent outside-box cell would overgrow it → block       |      2 |
| 3 | Pinned box: the unique `color`-capable cell on an unreached edge → force                     |      3 |
| 4 | Pinned box: a cut cell whose removal would sever a needed edge from the group → force        |      4 |

The "pinned box" deductions (3, 4) only fire once the group's extent plus
the grid borders force a single position for the W×H box. Forced growth on
a box that can still slide is not yet implemented.

### IM — Implication (`constraints/implication.dart`)

| # | Deduction                                                          | Weight |
| - | ------------------------------------------------------------------ | -----: |
| 1 | Source is the colour → target must be the colour (modus ponens)    |      0 |
| 2 | Target is not the colour → source can't be it (contrapositive)     |      1 |

Following the arrow forward (modus ponens) is a read-off once the source is
set, so it stays at the trivial `0`. The contrapositive (modus tollens) takes
one extra inversion step, so it is rated `1`.

## How weights are assigned in code

Each constraint's `apply()` method now sets `complexity` explicitly on the
Move it returns. The constructor default is `0`, so any deduction we
forget to label silently falls into the trivial tier (which is the
forgiving default — it understates difficulty rather than overstating it).

For impossibility moves (`Move(0, 0, this, isImpossible: this)`) we leave
the weight at 0; the scoring loop short-circuits to `complexity == 100`
the moment one is observed.

## Calibration

Weights are an educated guess, not a measurement. They should be revised
once we run human playtesting sessions (see `todo.md`, "human calibration
session"). Until then, the relative ordering is what matters: trivial
saturation < local counting < spatial / merge reasoning < articulation
and enumeration < combinatorial probing.

## Future work

- **Re-calibrate the prune bump (requirement 4, default shipped).** The
  per-prune `+1` on domain > 2 is in place via
  [kRemoveOptionComplexityBump] (`model/cell.dart`) and applied by
  `Puzzle.moveComplexity`. The default of 1 is a starting point: once
  human-playtest data exists the value itself (which may end up
  separate for plain works vs. complication tiers, or scaled by the
  residual option count) should be re-tuned in that one constant.
- **Re-calibrate the domain term (requirement 3, default shipped).**
  The flat `(domain.length − 2) * kDomainSizeComplexityBump` (+5 on
  3-colour) is implemented in `computeComplexity` /
  `computeComplexityFromSteps`. The +5 default and the linear formula
  are starting points; re-anchor the d3 bands against a 3-colour corpus
  once playtest data exists (same TODO as in `third_color.md`), and
  consider whether the term should also apply to over-prefilled
  short-circuit cases.
- **Monotone routing (requirement 2).** Either fold the cascade
  dimensions (force count, max force depth, max complicity tier, max
  prop tier) into the cplx formula so the `recommendedLevelFor`
  thresholds become derivable, or re-derive the cascade thresholds from
  the cplx distribution. Today the correlation is strong at the
  extremes but the `advanced`/`strong`/`expert` medians overlap and
  invert in the 25–60 band. See review §3 and §8.
- **Per-FM motif weighting could go finer than the 0–3 buckets above**
  (e.g. weighting same-colour vs. mixed motifs differently inside the
  same area bucket).
- Per-complicity weight calibration. PA+FM, GS+FM, LT+FM, SY+FM,
  GS+GS, SH+GS, LT+GS, GS+all are all live `Complicity` instances
  (see `constraint_complicity.md`) and currently share weight 3 by
  default. Once the calibration session described in `todo.md` runs,
  the relative ordering between them should be refined.
- The flat `5 + 5 * forceDepth` for force moves could be replaced by
  a more nuanced model once we have data on which propagation chains
  players can follow.
