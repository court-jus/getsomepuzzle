# Algorithmic Architecture

This document describes the key algorithmic decisions in Get Some Puzzle: puzzle generation, solving, and complexity scoring.

## Puzzle Data Format

Puzzles are stored as single-line strings:

```
v2_12_3x3_100000000_FM:11;PA:8.top;GS:0.1_0:0_5
│   │  │   │         │                    │   │
│   │  │   │         │                    │   └─ complexity (0-100)
│   │  │   │         │                    └─ solutions (unused, always 0:0)
│   │  │   │         └─ constraints (semicolon-separated)
│   │  │   └─ cell values (0=empty, 1=black, 2=white)
│   │  └─ dimensions (width x height)
│   └─ domain (digits representing valid values)
└─ version
```

## Constraint Types

| Slug | Name | Description |
|------|------|-------------|
| FM | Forbidden Motif | A 2D pattern that must NOT appear in the grid |
| PA | Parity | Equal count of black/white cells on one side of a cell |
| GS | Group Size | Connected same-color group must have exact size |
| LT | Letter Group | Cells with same letter must be in one connected group |
| QA | Quantity | Total count of a color in the entire grid |
| SY | Symmetry | Group must be symmetric along a specified axis |
| DF | Different From | Two adjacent cells must have different colors |
| SH | Shape | One color's group(s) must match a mandatory 2D shape |
| CC | Column Count | A given column must contain exactly N cells of a color |
| GC | Group Count | The grid must contain exactly N connected groups of a color |
| NC | Neighbor Count | A given cell must have exactly N orthogonal neighbors of a color |
| RC | Row Count | A given row must contain exactly N cells of a color |

## Solving Algorithm

The solver uses two levels of deduction. **Backtracking is intentionally not
implemented:** the project-wide convention is that *a puzzle is valid iff
`solveExplained()` (propagation + force) produces a trace that completes
the puzzle from its readonly cells*. Any puzzle that would require
backtracking to be solved is considered invalid by definition — players use
the same deductive solver in-game, so a non-deductive puzzle wouldn't be
solvable for them anyway. The helper `Puzzle.isDeductivelyUnique()` wraps
`solve()` and remains available for one-shot checks outside the generation
pipeline.

### Level 1: Constraint Propagation

Each constraint's `apply()` method examines the current grid and returns the first cell value it can logically determine. The solver loops, applying one move at a time, until no constraint can determine anything new.

This is the cheapest level. Puzzles solvable entirely by propagation are the easiest.

### Level 2: Forced Deduction (Force)

For each free cell, the solver tentatively sets each possible value, then runs constraint propagation with **auto-check** (verifying all constraints after each step). If a value leads to a constraint violation, that value is eliminated. When only one option remains, the cell is determined.

This is more expensive: it requires cloning the puzzle and running propagation for each candidate value. Puzzles requiring force are harder because the player must reason by contradiction.

The `autoCheck` flag is critical: after each propagation step inside force, ALL constraints are verified via `verify()`. Without this, the solver cannot detect indirect contradictions (e.g., a forbidden motif appearing as a side effect of constraint propagation).

### Solving Loop

```
solve():
  1. Run propagation until stuck
  2. Loop (up to 20 iterations):
     a. Run force → may determine cells
     b. Run propagation → may determine more cells
     c. If neither made progress, stop
  3. Return true iff every cell is determined and all constraints satisfied
```

If `solve()` returns false, the puzzle isn't deductively solvable — either
under-constrained (multiple completions) or contradictory. There is no
backtracking fallback.

## Puzzle Generation

The generator (ported from Python `generate.py`) creates puzzles through this process:

### Step 1: Random Solution

Create an empty grid and fill each cell with a random domain value (1 or 2). This is the target solution.

### Step 2: Pre-fill Cells

Select a random subset of cells (controlled by a ratio parameter, randomly drawn in `[0.75, 1.0]`, so 75–100% of cells stay empty for the player) and lock the remaining cells' values from the solution. These become the puzzle's given cells. Up to 25% of the grid may thus be provided as readonly hints.

### Step 3: Enumerate Valid Constraints

For each constraint type (FM, PA, GS, LT, QA, SY, DF, SH, CC, GC, NC, RC), generate all possible parameter combinations for the grid dimensions. Filter to keep only constraints that are satisfied by the target solution.

### Step 4: Iterative Constraint Selection

Starting with one constraint, iteratively try adding each candidate:

```
for each candidate constraint:
  1. Clone the puzzle (with all constraints added so far)
  2. Solve the clone → compute ratio of free cells (ratio_before)
  3. Add the candidate constraint to the clone
  4. Solve again → compute new ratio (ratio_after)
  5. If ratio_after < ratio_before: keep the constraint
```

After each successful addition, remaining candidates are reshuffled with priority given to less-used constraint types (to encourage diversity).

### Step 5: Finalization

- If the solved ratio reaches 0: the puzzle is fully determined by its
  constraints.
- If 0 < ratio ≤ 0.25: fill remaining cells from the known solution as
  readonly hints.
- If ratio > 0.25: too under-determined. Discard and retry.

The final validity gate uses `solveExplained()` on the puzzle (with any
hint cells now locked as readonly). The trace is replayed on a clone; the
puzzle is accepted only when `replay.complete && replay.check().isEmpty`,
meaning the solver reached the unique completion deductively. This single
`solveExplained()` call also produces the `SolveStep` trace used to
classify the puzzle's difficulty level (see `lib/getsomepuzzle/level.dart`
and `docs/dev/levels.md`) — no additional solve is required.

There is no `countSolutions()` / backtracking uniqueness check. The replay
check is sufficient: reaching a complete, violation-free state through
propagation and force mechanically implies a single completion (every cell
was deductively determined, leaving no ambiguity).

### Retry Strategy

The worker retries generation with new random grids until the requested number of puzzles is produced or the time limit is reached.

## Constraint Ordering

The order in which constraints appear in a puzzle's constraint list is
significant. `Puzzle.apply()` iterates the list in order on every solver
step and returns the first deduction it finds, so earlier constraints
get first dibs on any cell they can determine. `lineExport` serialises
constraints in list order, so the on-disk representation round-trips
through `Puzzle(...)` with the order preserved.

Two APIs on `Puzzle` let maintenance tooling and the generator reshape
that order:

- **`prependConstraint(c)`** — insert at index 0 so `apply()` consults
  `c` before any pre-existing constraint. Used by `Puzzle.simplify` when
  grafting an "indispensable" candidate onto a puzzle that is already
  dominated by a high-complexity constraint (e.g. `--require SH`): the
  cheaper deduction must run first, otherwise the dominant constraint
  fires first and the easier deduction never surfaces. Honours the
  LetterGroup-aggregation contract from `addConstraint` (one entry per
  letter).
- **`sortConstraintsByDifficulty(steps)`** — reorder constraints by the
  *minimum* `Move.complexity` each contributed in `steps` (ascending,
  ties broken lexicographically on `serialize()`). Steps with empty
  `constraint` (force) and steps credited to Complicity instances are
  ignored. Constraints that contributed nothing to `steps` are pushed
  to the tail via a `1 << 30` sentinel rank. Side effect: drops
  `cachedComplexity` because reordering changes the trace `apply()`
  produces and thus the per-move complexities.

The hint system in `addConstraint` mode picks the front of
`availableHintConstraints`, so reordering directly affects which
constraints the player sees first. `bin/recompute.dart`,
`bin/dedup_puzzles.dart`, and `bin/aggregate_player_stats.dart` run
`sortConstraintsByDifficulty` over the trace they already computed for
classification, so shipped puzzles carry the easier-first ordering on
disk.

`PuzzleGenerator.generateOne` also calls
`sortConstraintsByDifficulty` before returning the serialised line, so
freshly generated puzzles ship with the same easier-first contract as
the maintenance-tool output. When the easing loop ran (`simplify`),
the sort uses `SimplifyResult.finalSteps` rather than the pre-simplify
trace — it is a fresher signal that accounts for any constraint
grafted by `prependConstraint` during easing, which would not appear
in the earlier trace.

## Complexity Scoring

Complexity measures how hard a puzzle is to solve, on a scale of 0 to 100.
The detailed per-constraint weight table and the current formula are
documented in `docs/dev/complexity.md`. The summary is:

```
complexity = forceScore + ruleDiversity + emptiness   (clamped 0..100)

forceScore  = sum(move.complexity for propagation moves)
            + sum(5 + 5 * move.forceDepth for force moves)
            (clamped to 0..90)
```

`move.complexity` is a 0–5 weight assigned by each constraint's `apply()`
reflecting estimated player effort (trivial counting = 0, articulation
point reasoning or combinatorial probing = 4–5).

`ruleDiversity` (0–4) rewards multi-constraint puzzles. `emptiness` (0–6)
reflects the proportion of cells left for the player to deduce.

If the puzzle is not deductively solvable, complexity is forced to 100.
Such puzzles are no longer produced by the generator but may survive in
the legacy corpus files (see `docs/dev/levels.md` for the bucket
`indetermine`).

## Background Execution

Puzzle generation runs in a background isolate (native platforms) or via chunked async execution (web) to keep the UI responsive. Progress is communicated via message passing (`SendPort`/`ReceivePort` on native, `StreamController` on web).

## Custom Collection Storage

Generated puzzles are stored in:
- **Native**: `ApplicationDocumentsDirectory/getsomepuzzle/custom.txt` (one puzzle per line, appended)
- **Web**: `SharedPreferences` key `"custom_puzzles"` (string list)

The "My puzzles" collection in the UI loads from this local storage instead of bundled assets.
