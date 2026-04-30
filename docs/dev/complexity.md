# Complexity scoring

This document describes how the puzzle complexity score is computed and, in
particular, how individual deductions made by `Constraint.apply()` contribute
to that score. The design goal is that the complexity reflects how hard a
puzzle feels to a human player, not how hard it is for the solver.

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
            (clamped to 0..90)

complexity  = forceScore + ruleDiversity + emptiness   (clamped 0..100)
```

The `ruleDiversity` (0–4) and `emptiness` (0–6) components are unchanged.
With this formula a puzzle solved purely by trivial saturation contributes
0 to `forceScore` and finishes in the 0–10 band (rule diversity +
emptiness only). A puzzle that requires repeated articulation reasoning
or many force rounds saturates the 90-point ceiling.

The mapping `force = 5 + 5 * forceDepth` matches the previous
implementation (`(1 + forceDepth) * 5`) so existing scores stay in the
same neighbourhood for puzzles that were already force-heavy. The new
contribution is the propagation tier sum, which used to be implicitly 0.

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

- Per-FM motif weighting could go finer than the 0–3 buckets above (e.g.
  weighting same-colour vs. mixed motifs differently).
- Multi-constraint combination deductions (PA+FM, GS+FM, …) currently
  surface as force moves. When they migrate to propagation they should
  carry weight 3–4 to reflect the "two rules at once" effort.
- The flat `5 + 5 * forceDepth` for force moves could be replaced by a
  more nuanced model once we have data on which propagation chains
  players can follow.
