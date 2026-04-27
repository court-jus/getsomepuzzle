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

## Solving Algorithm

The solver uses two levels of deduction. **Backtracking is intentionally not
implemented:** the project-wide convention is that *a puzzle is valid iff
`solve()` (propagation + force) reaches `ratio == 0` from its readonly
cells*. Any puzzle that would require backtracking to be solved is
considered invalid by definition — players use the same deductive solver
in-game, so a non-deductive puzzle wouldn't be solvable for them anyway.
See `Puzzle.isDeductivelyUnique()` for the validity check used everywhere.

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

Select a random subset of cells (controlled by a ratio parameter, typically 80-100% of cells left empty) and lock their values from the solution. These become the puzzle's given cells.

### Step 3: Enumerate Valid Constraints

For each constraint type (FM, PA, GS, LT, QA, SY, DF, SH), generate all possible parameter combinations for the grid dimensions. Filter to keep only constraints that are satisfied by the target solution.

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
  constraints. Verify `isDeductivelyUnique()` (always true at ratio=0) and
  export.
- If 0 < ratio ≤ 0.25: fill remaining cells from the known solution as
  readonly hints, then verify `isDeductivelyUnique()` on the augmented
  puzzle. If `solve()` still leaves cells free *with* the hints, the
  puzzle isn't deductively solvable even with help — discard.
- If ratio > 0.25: too under-determined. Discard and retry.

There is no `countSolutions()` / backtracking unicity check. The
`isDeductivelyUnique()` test is sufficient because reaching `ratio == 0`
through propagation + force mechanically implies a single completion
(every cell was deductively determined, leaving no ambiguity).

### Retry Strategy

The worker retries generation with new random grids until the requested number of puzzles is produced or the time limit is reached.

## Complexity Scoring

Complexity measures how hard a puzzle is to solve, on a scale of 0 to 100.

### Formula

Complexity is the sum of three components, on a 0–100 scale:

```
complexity = force_score + rule_diversity + emptiness
```

**Force score (0–90):** The solver first applies constraint propagation, then repeatedly forces one cell at a time (testing each value, detecting contradictions) and re-propagates. Each "force round" determines one cell that could not be found by propagation alone.

```
force_score = min(90, force_rounds * 10)
```

If the puzzle isn't deductively solvable (force itself can't close it):
complexity = 100. Such puzzles are no longer produced by the generator —
they would fail `isDeductivelyUnique()` — but legacy entries with
`cplx=100` survive in `assets/default.txt` and are tagged this way.

**Rule diversity (0–4):** Number of distinct constraint types in the puzzle.

| Distinct types | Score |
|---------------|-------|
| 1 | 0 |
| 2 | 1 |
| 3 | 2 |
| 4–5 | 3 |
| 6+ | 4 |

**Emptiness (0–6):** Proportion of free (non pre-filled) cells, scaled to 0–6.

```
emptiness = round(free_cells / total_cells * 6)
```

A fully empty grid scores 6, a 50% pre-filled grid scores 3.

### Interpretation

| Range | Difficulty | Meaning |
|-------|-----------|---------|
| 0–9 | Trivial | Solved by propagation alone, few rule types |
| 10–29 | Easy | 1–2 force rounds, moderate diversity |
| 30–59 | Medium | 3–5 force rounds |
| 60–90 | Hard | 6–9 force rounds, high diversity |
| 100 | (legacy) | Not deductively solvable — only present in legacy entries; the current generator rejects these |

### Rationale

The dominant factor is force rounds (up to 90 points), because each round represents a point where the player must hypothesize ("what if this cell is black?") and reason by contradiction. Rule diversity adds a small bonus because juggling multiple constraint types increases cognitive load. Emptiness contributes marginally because a mostly-empty grid offers fewer starting anchors for deduction.

## Background Execution

Puzzle generation runs in a background isolate (native platforms) or via chunked async execution (web) to keep the UI responsive. Progress is communicated via message passing (`SendPort`/`ReceivePort` on native, `StreamController` on web).

## Custom Collection Storage

Generated puzzles are stored in:
- **Native**: `ApplicationDocumentsDirectory/getsomepuzzle/custom.txt` (one puzzle per line, appended)
- **Web**: `SharedPreferences` key `"custom_puzzles"` (string list)

The "My puzzles" collection in the UI loads from this local storage instead of bundled assets.
