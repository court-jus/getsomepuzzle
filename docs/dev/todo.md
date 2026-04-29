# TODO

## Cleanup default.txt

Remove uninteresting "gift" puzzles from the default collection.

### Removal criteria

1. **Trivial puzzles**: only 1 constraint type AND 0 force rounds AND >50% pre-filled cells

## Solver improvements

### GroupSize: path-based propagation — boundary rule

The positive rule ("cell on every completion path must be group color") is
implemented via `blockingShrinksReachableBelow`. The dual is still missing:
"a cell adjacent to ALL possible size-`size` completions must be the
opposite color." The blocking-BFS predicate doesn't capture this. Likely
needs explicit enumeration of size-`size` completions (or a dual flow
argument).

### Complexity: distinguish propagation difficulty levels

Currently, all propagation moves are treated equally (0 complexity contribution). But some propagation moves are trivial ("group is complete, close borders") while others require subtle topological reasoning ("all growth paths go through this cell"). 

When implementing advanced propagation (like path-based GroupSize), we should introduce **propagation difficulty tiers**:
- **Tier 0**: Direct/obvious (close borders, single exit, value forced by single constraint)
- **Tier 1**: Multi-constraint interaction or spatial reasoning (path invariants, merge avoidance)
- **Tier 2**: Complex deductions that most players would use force/guessing for

Each tier would contribute differently to complexity. The exact weights need calibration through **human playtesting sessions**: present puzzles to a player, ask them to rate difficulty of each move, and use that feedback to tune the tier weights.

### GroupSize: color-independent deductions for size 1

Current `GS.apply()` handles empty cells for merge-too-big (if a neighbor's group ≥ size, cell is opposite), but for `size == 1` there is a stronger deduction: the neighbors of the cell must always be the opposite color regardless of which color the cell itself is. Both possible colors lead to the same conclusion for neighbors.

**Example**: GS:0.1 on an empty cell at (1,1). Whether (1,1) is black or white, it must be isolated, so (1,2) and (2,1) must be the other color. Since there are only 2 colors, if both lead to "neighbor is opposite", we can deduce neighbor values without knowing the center value.

More generally, for any GS constraint where the cell is empty: if setting the cell to color A implies neighbor X must be value V, AND setting the cell to color B also implies neighbor X must be value V, then we can set X = V by propagation alone (no force needed).

This is currently partially handled by the merge-too-big check on empty cells (if a neighbor already has a colored group of size ≥ 1, the cell is forced opposite). But when the GS=1 cell has no colored neighbors yet, the direct deduction "all neighbors must be opposite" is still missing.

**Partial progress from merge-too-big**: puzzle `v2_12_4x3_000010000022_GS:4.4;GS:0.4;FM:01.22;GS:3.1` went from 4 force rounds (cplx=46) to 3 force rounds (cplx=36). Full GS=1 deduction could reduce further.

### Multi-constraint combination deductions

Some deductions require combining two constraints simultaneously. For example:
- **PA + FM**: parity says two cells are different, FM eliminates one arrangement → determines both cells
- **GS + FM**: GS constrains group boundaries, which creates a forbidden motif → determines a cell

These "combination deductions" should be implemented as propagation (not force) but assigned a **higher complexity weight** than single-constraint propagation, because the player needs to hold two rules in mind simultaneously.

**Complexity tier proposal:**
- Tier 0 (weight ~0): Single constraint direct deduction (e.g., "group full, close borders")
- Tier 1 (weight ~2): Advanced single-constraint deduction (e.g., GS merge-too-big, GS=1 neighbors)
- Tier 2 (weight ~5): Multi-constraint combination (e.g., PA+FM, GS+FM combos)
- Force round (weight 10): Hypothesis + contradiction (current)

These weights would replace the flat "force_rounds × 10" in the complexity formula, giving a more granular score.

**Verified examples:**
- `6x4` puzzle: PA:20.left + FM:212 combo deduces (1,4)=N and (2,4)=B — currently counted as 1 force round
- `4x5` puzzle: GS:19.1 + FM:01.12 combo deduces (4,5)=N — currently counted as 1 force round

### Constraint-specific complexity weights

Some constraints are inherently easier to reason about than others, even within the same type. For example, among Forbidden Motifs:
- **Easy**: two same-color cells (e.g., FM:11, FM:22, FM:1.1, FM:2.2) — trivially "no two adjacent same-color"
- **Medium**: two different-color cells (e.g., FM:12, FM:2.1) — slightly harder to track
- **Hard**: larger or mixed motifs (e.g., FM:122, FM:211.122) — requires more spatial reasoning

The rule diversity component of complexity could be refined to weight not just the number of distinct types but also the inherent difficulty of specific constraint patterns within each type.

### Shape ↔ GroupSize redundancy

When a puzzle has a SH constraint (e.g., `SH:111`), the shape implicitly constrains group size for that color. Consider adding logic to detect and leverage this redundancy:
- If SH and GS both constrain the same color, GS is redundant (SH implies it).
- Could skip GS verification/apply for groups already covered by SH.
- Could warn puzzle creators when both constraints are present for the same color.
- Note: SH only constrains one color. A puzzle with `SH:111` still allows white groups of any size, so a `GS` on a white cell is NOT redundant.

### Hint constraint: prioritize useful constraints

Baseline ranking by propagation usefulness is in place (candidates tested
with `applyConstraintsPropagation()`, useful first, ranking refreshed on
each interaction). Remaining ideas:
- Rank candidates by how many new cells they allow deducing (pick the one
  that gives the most progress).
- Weight by constraint type simplicity (FM/PA easier to understand than
  SY/LT for most players).

### Hint constraint: per-cell constraint contribution score

When the puzzle is already fully solvable by propagation (baseline fills all cells), current ranking reports 0 useful constraints. The button stays enabled and the player can still request a constraint — they just get one from the non-useful tail (a redundant constraint, picked first-come-first-served from the shuffled list).

**Idea:** For each empty cell, trace which constraints participate in its resolution during propagation. A constraint that contributes to resolving many cells is "broadly helpful". A cell that is only resolved through a long chain of deductions could benefit from a more direct constraint. This would replace the random tail-pick with something targeted.

**Challenge:** Propagation is a chain — constraint A deduces cell X, which enables constraint B to deduce cell Y. Attributing credit requires tracing the dependency graph of the propagation loop. This would require modifying `applyConstraintsPropagation()` to record which constraint resolved each cell, then building a dependency graph to compute per-constraint contribution scores.

### Planned: human calibration session

Run a session where the solver presents individual deduction steps to a human player who rates their difficulty (easy/medium/hard). Use this data to:
1. Classify which propagation patterns belong to which tier
2. Validate that force rounds correlate with perceived difficulty
3. Tune complexity formula weights accordingly

## Generator: equilibrium failure blacklist

`pickTarget` and `rankTargets` (`lib/getsomepuzzle/generator/equilibrium.dart`)
already accept a `blacklistedKeys` parameter, but the worker
(`worker_io.dart`) currently passes the empty set. When a target is
unreachable in practice (e.g. a complex pair on a `3x3` grid) the loop
keeps retrying until the global `maxTime` budget runs out.

**Plan:** track per-target `failureCount` in the worker. After N consecutive
failures (5 is the value used in early sketches) add the target's `key` to
a session blacklist passed to `pickTarget` so the loop falls back to the
next-deepest gap. Reset on successful generation or on warm-up.

## QOL

* Allow saving a puzzle in its current state.
* Allow sharing a puzzle, from scratch or from its current state.
* Allow opening the app directly with a puzzle (link for the web, intent for android, cli argument for desktop)

## UI

* When showing that a cell can be deduced thanks to a constraint and that constraint is DF, the name of the constraint is not shown.
