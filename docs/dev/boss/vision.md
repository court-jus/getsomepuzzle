# Propagation-Driven Constructive Generation (PDCG)

## Problem

The current generator builds a **random solution grid first**, then enumerates
constraints that happen to verify against it. This works well up to ~10×10
but has fundamental limits:

- **The random grid decides everything.** A bland 50/50 grid rarely produces
  elegant structural constraints (`SY`, `SH`, `GC`). Themed pre-fills
  (`path`, `sh`, `sy`, `bb`) mitigate this but require explicit scenario
  selection.
- **Solver cost scales with grid size.** The greedy loop clones the puzzle
  and runs `solve()` (propagation + force) for every candidate — on a 30×20
  grid (600 cells) this is prohibitively expensive.
- **No guarantee the trace is elegant.** `removeUselessRules` and polish
  tools compensate, but the generation itself does not optimise for
  deductive interleaving.
- **Hard limit on grid size.** Beyond ~12×12 the random-grid approach
  generates too few useful constraints; the acceptance rate collapses.

## Vision

Invert the pipeline: build the **deductive trace first**, let the grid
emerge from the constraints.

**Starting state**: completely free grid, no constraints.

**Core loop**: add one constraint that fires on the current partial state,
apply its deduction, repeat until the grid is fully determined.

This is the same mechanism the in-editor solver uses (add a constraint,
watch green-border cells appear). The generator does it deliberately:

```
State = all cells free, no constraints

while State has free cells:
    1. Pick a free cell `c` that we want to resolve next
    2. Find a constraint that influences `c` and is satisfiable
       (propagation doesn't hit Impossible)
    3. Add it to the puzzle → run propagation
    4. The new semi-resolved State has more determined cells
    5. Repeat

Result: a puzzle whose deductive trace is exactly the order
        constraints were added → solvable by construction
```

### Key difference from the current generator

| Aspect | Current (grid-first) | Proposed (trace-first) |
|---|---|---|
| Source of truth | Random filled grid | Semi-resolved state |
| Constraint selection | solve() ratio delta | "fires on current state" |
| Backtracking | None (in greedy loop) | None (choose only constraints that work) |
| Solvability proof | solve() at end | By construction |
| Grid size limit | ~12×12 practical | Potentially 30×20+ |
| Deductive elegance | Post-hoc polish | Built-in (interleaving by design) |
| Force handling | solve() finds it | Optional: detect contradictions |
| Constraint ordering | sortConstraintsByDifficulty | Natural construction order |

## Algorithm sketch

### 1. State representation

A `Puzzle` in a semi-resolved state: some cells determined (via previous
constraint deductions), others free with their full option set. This is
exactly what `propagateToFixpoint()` produces.

```
State = { cells: [...], constraints: [...] }
  • determined cells have a value and empty options
  • free cells have no value, full domain options
  • all constraints in the list are satisfied by SOME completion
    of the current state (not necessarily unique — yet)
```

### 2. Constraint selection strategy

Pick a free cell, then pick a constraint that:

1. **References the cell** — directly (NC, DF, GS, PA, SY) or via
   line/column (CC, RC) or globally (QA, GC, FM).
2. **Is satisfiable** — adding it and running `propagateToFixpoint()`
   does NOT return `Impossible`.
3. **Adds information** — propagation determines at least one new cell
   (preferably the targeted one, or unlocks a cascade).

Selection order matters. Desirable heuristics:

- **Island-first**: place a structural anchor (SY, SH, GS, LT) early to
  give the puzzle a visible identity, then add guardrails (NC, PA, RC, QA).
- **Local closure**: target cells whose neighbourhood is already partially
  determined — NC and DF fire naturally there.
- **Diversity**: track which constraint slugs have been used, prefer
  untouched ones.
- **Cascade budgeting**: prefer constraints whose propagation determines
  2-5 cells (a satisfying "aha" step) rather than 50 (overwhelming) or 0
  (wasted turn).

### 3. Satisfiability without a solution grid

The current generator calls `verify(solvedGrid)` on every candidate. Without
a pre-filled solution, we need a different soundness check.

**Option A — Propagation-only soundness** (simplest):
After tentatively adding a constraint, run `propagateToFixpoint()`.
If it hits `Impossible`, the constraint is invalid for the current state →
discard, try another. If no constraint targeting cell `c` passes this test,
the puzzle is stuck — back up (pick a different previous constraint or
different target cell).

**Option B — Solve-with-force soundness** (more expensive):
Run `solve()` (propagation + force, no backtracking) on a clone after
adding the constraint. If `solve()` completes without contradiction, the
constraint is valid. This catches cases where the constraint doesn't
propagate directly but enables a force step later.

Option A is preferred for the core loop: it guarantees every deduction in
the player's trace is pure propagation. The player never needs force.
Option B can supplement in a second pass to make the puzzle harder.

### 4. Two-tier difficulty model

**Tier 1 — Pure propagation (the core idea)**:
Every constraint fires via `apply()` only. The player's entire solve trace
consists of green-border steps — a "pure reasoning" puzzle.

**Tier 2 — Gentle force (optional extension)**:
When propagation plateaus, the generator intentionally creates a choice
point: "this cell could be either colour, but one leads to contradiction".
Verified by cloning, setting the cell, running propagation, checking for
contradiction. The resulting `RemoveOption` (isForce: true) becomes the
player's next step.

The force depth is controllable: the generator can reject force deductions
deeper than a threshold (e.g. forceDepth ≤ 2) to keep puzzles approachable.

### 5. Ordering and diversity

The constraint addition order IS the puzzle's deductive skeleton. Good
puzzles have:

- **High switch_ratio**: constraints from different slugs alternate.
  The generator can enforce this by cycling through slug categories.
- **Low cascade_ratio**: no single constraint floods the grid. If a
  constraint would determine > N cells at once, the generator pauses
  and interleaves another constraint first.
- **Visible opening**: the first constraint should produce an "aha"
  moment — ideally 2-3 cells in a localised area that the player can
  immediately verify.

### 6. Scaling to 30×20

The semi-resolved state never requires a full-grid solve. Each iteration:

1. Runs `propagateToFixpoint()` — O(cells × constraints) average case.
2. Constraint `apply()` methods are local (NC: neighbourhood; DF: pair;
   FM: motif window; CC/RC: single line).

On a 30×20 grid, propagation hits most constraints near-determined
neighbourhoods. The expensive full-grid operations (solve, force, groups
enumeration in GS/SH) are either not needed (Tier 1) or bounded to
local regions.

Crucially, there is **no point in the pipeline where the entire 600-cell
grid is solved from scratch**. The state evolves incrementally.

## Concrete flow

```
Grid: 30×20 (600 cells), 2 colours
Constraints available: FM, PA, RC, CC, NC, DF, GS, QA, GC, SY, SH, EY, ...

State: all free

Iteration 1:
  1. Place an anchor: SY(anchor=(15,10), axis=horizontal)
  2. Add SY → propagateToFixpoint()
  3. SY.apply fires: detects that cell (15,11) must be mirror of (15,9)
     which is free → no fire yet
  4. SY needs at least one coloured neighbour to anchor → this constraint
     alone determines nothing
  5. → Bad pick: no information added. Roll back.

Iteration 1 (retry):
  1. Place a simple constraint first: NC(anchor=(15,10), count=3, color=black)
  2. Add NC → propagateToFixpoint()
  3. NC is on a currently-empty neighbourhood → no fire yet
  4. → Need something that fires on empty grid. Try QA, RC, CC, FM.
  5. QA(black, 300): "exactly 300 black cells in the grid"
  6. 600 cells total, 300 black → on a 2-colour domain this means
     exactly half. No free cell has value yet → no fire.
     (Fair: QA only fires when the count is met or deficit == free.)

Observations: on a completely empty grid, most constraints don't fire.
This is expected — we need constraints that interact with grid structure.

Better first iteration:
  1. RC(row=10, color=black, count=15): "row 10 has 15 black cells"
  2. Row 10 has 30 cells, 15 must be black → no fire yet (free cells
     are 30, deficit 15 ≠ 30).
  3. Pair with NC or DF that target specific cells.
  4. DF(10×15_10×14): "cell at (10,15) and (10,14) differ"
  5. Add DF → no fire (both free).
  6. FM: "no 1-2-1 pattern in the grid" — globally true on empty grid.
     FM.apply only fires when a pattern is *almost* present (one cell
     away). On empty grid → no fire.

The generator needs a "seed" — something that fills a few cells.
Options:
  A) Randomly pre-fill 5-10 cells (like the current generator but
     much fewer — just enough to seed deductions).
  B) Start with a small pattern (SH, motif) that defines a local area.
  C) Use a QA/CC/RC that sets a count = 1 or count = free-1, which
     fires immediately.

Option C is cleanest. For example:
  RC(row=10, color=black, count=1):
    Row 10 has 30 cells. Exactly 1 must be black, 29 white.
    → All cells in row 10 get RemoveOption(black) except...
    No wait, 29 cells of white + 1 cell of black. The constraint
    doesn't know which cell is the black one.

Actually: with count=1 and 30 free cells, deficit = 1, free = 30.
RC applies: since count != free AND deficit != free, no fire.

What if we set count = 29 and black?
    count = 29, free = 30, deficit = 29 ≠ 30 → no fire.
    Even count = 30: count ≥ free but deficit (count - current) = 30 - 0 = 30
    = free (30) → SetValue(free_cell[0], black). That DOES fire!

So: RC(row=10, black, count=30) → fires immediately: all 30 cells must be black.
Similarly CC(col=15, white, count=30) → all 30 cells in column 15 are white.

Combined: RC(row=10, black, 30) + CC(col=15, white, 30) →
  cell(10,15) = both black AND white → Impossible → contradiction!

So the generator must avoid contradictory pairs. Solution: propagate after
each constraint and reject contradictions.

A better seed approach — multi-step:

1. Place an FM that fires on empty grid via wildcards...
   Actually FM `1.2` (1 cell) forbids pattern [[1],[2]] vertically or
   [[1,2]] horizontally — it just says "no cell 1 next to cell 2".
   In a 2-colour domain, this forbids... well, every cell is either
   black or white, and 1 and 2 are both colours. [[1,2]] would appear
   at every boundary between black and white cells. This fires when
   the grid has at least one black next to one white... but on empty
   grid, FM doesn't even look because it can't match any pattern.

Ah, FM.apply looks for positions where the motif minus one cell matches.
On completely empty grid, no pattern can match at all, so FM never fires.

So the real entry point for the propagation-driven generator is:

**Seed phase**: place 3-8 randomly-chosen cell values with their
`readonly = true`. These are the "given" cells the player starts with.
This is much fewer than the current generator's 0-25% — just enough to
give FM, NC, DF, PA something to "bite" on.

With a small seed:
- DF fires between a set cell and its free neighbour (RemoveOption)
- NC fires when a cell's neighbourhood has enough determined neighbours
- FM fires when only one cell remains to complete a forbidden pattern
- PA fires when one side has reached its per-colour target

After seeded cells are placed:

4. RC/CC fire when line deficit matches free cells or line count is met
5. QA fires when global deficit matches free cells
6. GC fires when group count is above/below target
7. SY fires when the anchor's group has at least one coloured member
8. GS fires when the anchor's group approaches the target size
9. EY fires when the eye's line of sight is partially determined

Once 1-2 constraints are in place and have determined a few more cells,
the propagation cascade begins naturally.

### Seed strategies

**Uniform random**: Same as current generator but with fewer pre-filled
cells (say 1-5% instead of 0-25%). Just enough to break the grid's
symmetry and give constraints a starting point.

**Pattern seed**: Place a predefined aesthetic pattern (a cross, a spiral,
a 2×2 checkerboard) in the grid centre. This provides structure for SH,
SY, PA, and FM constraints simultaneously.

**Constraint seed**: Place a constraint that IS the seed — for example,
a Shape constraint whose motif paints the first cells. The SH constraint's
`verify` against the (still-empty) grid is vacuously true, and once the
motif's cells are placed as readonly, SH.apply can expand them.

## Summary

The propagation-driven generator replaces the expensive "random grid →
solve() → ratio compare" loop with an incremental, trace-first approach:

```
1. Seed: place 3-15 readonly cells
2. Loop:
   a. Find a promising free cell (priority: near determined cells,
      part of an interesting region, untouched area)
   b. Enumerate constraints that reference this cell
   c. Filter to those that pass the satisfiability check
   d. Pick the best one (diversity, cascade size, local effect)
   e. Add it → run propagation → update state
   f. If the added constraint enables other constraints that didn't
      fire before, those are tried automatically on next propagate()
3. Verify: optional solve() for final validation
```

Key advantages for 30×20:
- No full-grid solve during iteration
- Local operations only (neighbourhoods, lines, windows)
- Trace IS the puzzle → no post-hoc ordering needed
- Natural interleaving → high switch_ratio
- Controllable difficulty (pure propagation vs gentle force)

Open questions to resolve:
- Optimal seed size and strategy
- Satisfiability check: propagation-only or solve-with-force?
- Constraint selection heuristic: which cell to target next?
- How to handle multi-cell constraints (SH, GS, SY) in the selection?
- Integration with the equilibrium system (corpus-level diversity)
- Integration with the existing PuzzleGenerator interface
