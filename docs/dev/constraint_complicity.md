# Constraint Complicity System

## Problem

The solver's propagation loop iterates each constraint individually
until no single constraint can make progress (fixed point). However,
some deductions require **combining information from multiple
constraints**. These cross-constraint deductions are called
**complicities**.

Example: a `LetterGroup` (LT) requiring connectivity across rows + a
`ForbiddenMotif` (FM) blocking vertical adjacency of a color → forces
the LT group's color. Neither constraint alone can deduce this.

## Architecture

### Class hierarchy

The shared base class `CanApply` lives in
`lib/getsomepuzzle/constraints/constraint.dart`:

```dart
abstract class CanApply {
  Move? apply(Puzzle puzzle);
  String serialize();
}

class Constraint extends CanApply { /* … */ }
abstract class Complicity extends CanApply {
  bool isPresent(Puzzle puzzle);
}
```

`Move.givenBy` and `Move.isImpossible` are typed as `CanApply?`, so the
solver and the hint system treat both kinds of sources uniformly.

### Integration in the propagation loop

Complicities act as a **second level** in the propagation loop:

```
Move? Puzzle.apply() {
  for (c in constraints) { if (m = c.apply(this)) return m; }   // level 1
  for (c in complicities) { if (m = c.apply(this)) return m; }  // level 2
  return null;
}
```

A complicity is only tried when individual constraints are exhausted.
If it unlocks a cell, the outer propagation loop calls `apply()` again
and constraints get another chance with the freshly placed cell.

### Auto-detection

At puzzle construction time `Puzzle._detectComplicities()` instantiates
every entry in `complicities/registry.dart` and keeps the ones whose
`isPresent(this)` returns `true`. We pay the detection cost once, then
`apply()` only iterates the relevant subset. `clone()` re-runs the
detection so an exploratory clone never depends on the parent's
references.

### Complexity weight

A complicity move carries a `Move.complexity` weight on the same 0–5
scale as constraint moves (see `docs/dev/complexity.md`). Combination
deductions are tier 3 by default — they require the player to hold
two rules in mind at once, which is heavier than any single-constraint
deduction except articulation/enumeration.

> **TODO — revisit per-complicity weights.** Both LT+FM and PA+FM
> currently use weight 3 for consistency, but they are almost certainly
> not equivalent in practice. PA+FM requires the player to derive
> monotonicity from a 2-cell FM and combine it with a parity count, a
> two-step argument; LT+FM is closer to a one-step "this colour can't
> bridge". Once 3-4 complicities ship, calibrate weights against
> playtesting data (or the human-rating session described in
> `docs/dev/todo.md`) — the relative ordering matters more than the
> absolute number.

### UI hooks

`Move.givenBy.isHighlighted` is only valid when `givenBy is Constraint`.
The hint system (`game_model.dart`) type-checks before assigning
`isHighlighted` or `isValid`. The constraint-name lookup
(`main.dart::_constraintName`) falls back to `givenBy.serialize()` for
sources it doesn't recognise — so a complicity hint shows e.g.
"LTFMComplicity" rather than an empty string.

## Complicity: LT + FM (Connectivity × Motif)

### Reasoning

- LT requires two cells to be **same colour** and **connected** by a
  path of that colour.
- If the cells are on **different rows**, any connecting path must
  include at least one **vertical step** (two same-colour cells
  stacked vertically).
- If FM forbids vertical adjacency of colour X (e.g. `FM:2.2` forbids
  two vertical 2s), then colour X **cannot form a vertical step**.
- Therefore the LT group **cannot be colour X** → it must be the
  other colour.

Same logic applies horizontally: if LT cells are on different
columns, the path needs a horizontal step.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/ltfm.dart`.

`_blocksVertical(fm, color)` is true **only** if the motif is exactly
`[[C],[C]]` — the only pattern that guarantees ANY vertical step of
colour C matches the forbidden motif. Taller motifs (e.g.
`[[C],[C],[C]]`) don't qualify: two adjacent Cs don't match a 3-tall
pattern. Wider motifs (e.g. `[[C,C],[C,C]]`) don't qualify either: a
vertical step in one column doesn't require the adjacent column to
also be C. `_blocksHorizontal` is the same logic rotated 90°.

### Impact analysis (2026-04-15, on the complicities branch)

Out of 709 unsolved puzzles (`0:0_100` in `assets/default.txt`):

- **27** match the LT+FM complicity pattern (LT spanning rows/cols +
  `FM:CC` or `FM:C.C` blocking that direction for a colour).
- Of those 27, **9** are fully solved once the complicity forces the
  LT colour (all 9 still need the force phase after the complicity
  unlocks the first cells).
- **18** remain stuck — the complicity alone isn't enough; they
  likely need additional complicities or deeper reasoning.

Numbers should be re-measured against current `assets/default.txt`
once more complicities ship.

## Complicity: PA + FM (Parity × Motif filtering)

### Reasoning

A `ParityConstraint` on a side of length `n` fixes the side's
composition: when the domain is `{1, 2}`, exactly `n/2` cells are
coloured 1 and `n/2` coloured 2.

For each PA side we **enumerate every balanced colouring** of the
free cells and **drop those that would violate any
`ForbiddenMotif`** anywhere on the grid (in interaction with the
already-coloured cells, including the side's free cells filled by
the simulation). Any free cell that takes the same value across
*every* surviving configuration is forced.

The classical 2-cell-mixed-FM case (`FM:12` makes rows read `2* 1*`,
etc.) is a special case: only the monotone configuration survives,
so every empty cell is forced. But the same enumeration handles much
more:

- **3+ cell FMs** (`FM:1.2.2`, `FM:11.21.11`, …) — partial filtering
  rather than monotonicity. The force fires only on cells where every
  survivor agrees; chained reasoning (another constraint colouring
  one side cell) typically collapses survivors to a single one.
- **FMs with wildcards** (`0` cells in the motif) — the pattern can
  bind via the wildcard against an already-coloured cell off the
  side. Example: 3×3 grid, cell 7 = 1, `FM:12.01` (motif
  `[[1,2],[0,1]]`) forbids the 2×2 pattern with `1` at the bottom
  right. With `PA:5.left` on cells `[3, 4]`, the config `(3=1, 4=2)`
  matches the motif at top-left (1, 0) — wildcard cell 6, fixed cell
  7 = 1 — so it's rejected. Only `(3=2, 4=1)` survives → cell 3
  forced to 2.
- **Multiple FMs** participate jointly in the filter, so combinations
  no single FM catches alone are still pruned.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/pafm.dart`. The
enumerator generates every k-combination of "1" positions among the
free cells of a PA side, instantiates each on a clone, calls
`ForbiddenMotif.verify` for every FM, and keeps the configurations
no FM rejects. Force fires when at least one free cell is
unanimously valued across all survivors. If zero configurations
survive, the complicity returns an `isImpossible` move.

### Domain and side-length bounds

- Domain must be exactly `{1, 2}` (parity-as-colour-counter).
- Side length is capped at 10 cells (`C(10, 5) = 252`
  configurations). Longer sides are skipped — they don't appear on
  grids up to 10×10 anyway, since a side of length `n` requires
  `n + 1 ≤ width` (or height).

## Complicity: SH + GS (Shape ↔ Group size)

### Reasoning

A `ShapeConstraint` mandates a specific shape for every group of its
colour, which fixes that colour's group size to `shapeSize`. A
`GroupSize` constraint (`GS:idx.N`) says "the group containing cell
`idx` has exactly `N` cells".

If `shapeSize ≠ N`, the cell at `idx` cannot be the SH's colour — its
group would never satisfy the shape. The opposite colour is forced.

If two SH constraints (one per colour) both disagree with the same
GS, the cell can take neither colour: the complicity reports an
impossibility.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/shgs.dart`. For each
GS we look up `shapeSizeByColor` and exclude every colour whose
shape size disagrees with `gs.size`. One excluded colour → force the
remaining one; all colours excluded → return an `isImpossible` move.

The complicity skips GS anchors that are already coloured: if the
existing colour disagrees with both SH and GS, the regular
`SH.verify`/`GS.verify` paths already catch the contradiction.

## Complicity: SY + FM (Symmetry × Motif)

### Reasoning

`SymmetryConstraint` requires that the anchor's connected group be
symmetric under a given axis (rotated, mirrored, or central). When a
free cell A joins the anchor's group by being coloured the anchor
colour `C`, `SY.apply` then forces A's symmetric A' to also be `C`.
That second placement is what creates leverage with FM.

If hypothesising `A = C` (and consequently `A' = C`) introduces a
forbidden motif anywhere on the grid, the hypothesis is invalid: A
cannot be `C` → A must be the opposite colour.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/syfm.dart`. For each
SY constraint with a coloured anchor:

1. Compute the anchor's current group.
2. Walk its frontier (free cells adjacent to any group member).
3. For each frontier cell A, compute its mirror A' via
   `SymmetryConstraint.computeSymmetry`. Skip when A' is out of
   bounds, equal to A (cell on the symmetry axis), or already filled
   with the opposite colour (SY's own apply already handles those).
4. Hypothesise `A = C` and `A' = C` on a clone, then test every
   `ForbiddenMotif.verify`. If any returns false, force A to opposite.

### Restriction to the group's frontier

The SY-driven mirror force binds only when A actually joins the
anchor's group: a far-away `A = C` would form a separate group and
the SY argument would not apply. Restricting to cells adjacent to
the current group keeps the hypothesis tight.

### Concrete example

```
3×3, anchor at (1,1) = 1, axis 4 (horizontal mirror through row 1).
FM:1.1.1 forbids three vertical 1s.
Free neighbour cell 1 (above anchor) → mirror = cell 7 (below).
Hypothesis: cell 1 = 1, cell 7 = 1, anchor cell 4 = 1.
Column 1 reads 1, 1, 1 → FM:1.1.1 violated.
Therefore cell 1 must be 2.
```

## Complicity: LT + GS (Letter group × Group size)

### Reasoning

A `LetterGroup` requires every listed cell to end up in the same
connected group when the puzzle is solved. The group must therefore
include every LT cell *plus* enough path cells to connect them — at
least `max_pairwise_manhattan(LT cells) + 1` cells. That bound is
tight for any **collinear** LT (all cells on a single row or column);
it's a conservative lower bound otherwise.

When a `GroupSize` constraint is anchored on a cell that's also part
of an LT, the group's size is fixed at `gs.size`. Two consequences:

1. **Impossibility** — `gs.size < lower_bound` makes the puzzle
   unsatisfiable.
2. **Path force** — for a *collinear* LT (any number of cells on the
   same row or column) with `gs.size == lower_bound`, the connecting
   path is the unique straight line from the smallest to the largest
   LT cell along the alignment axis. Every cell on that line must
   take the LT colour. Requires the LT colour to be known (any line
   cell already coloured); without it we only know the line cells
   share a colour but not which one.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/ltgs.dart`. The lower
bound `max_pairwise_manhattan + 1` is cheap and catches the
impossibility case. The collinear branch enumerates the row/column
segment from the smallest to the largest LT cell, finds the LT
colour from any already-coloured cell on the line, and forces the
next empty one to that colour. Cells that already belong to
`lt.indices` are skipped — `LetterGroup.apply` handles them as soon
as the LT colour is known, so the complicity strictly adds value
on the *path* cells between the LT cells.

### Known limitation: non-collinear LTs with aligned subsets

When the LT cells are *not* all collinear but a subset is — or when
`LetterGroup.apply` has already forced an articulation cell `X` that
ends up aligned with an LT cell `P` — the segment `X..P` could in
principle be forced too. The current implementation does not handle
this case: it would need to compute the "effective LT cell set" from
the current connected group and reason about every minimum Steiner
tree. Left as a future improvement; in many puzzles propagation
chains pick up the missing cells anyway.

### Interaction with `LetterGroup.apply`

`LetterGroup.apply` already detects articulation points (cells whose
removal would disconnect the LT cells) and forces them to the LT
colour. That deduction does **not** know about size limits, so it
treats long detour paths as valid alternatives — meaning a "must
pass through cell X" inference only fires when X is structurally
unique. LT+GS together restricts the path length to `gs.size`,
which is what makes the line force kick in even when looser paths
exist on the grid.

## Complicity: GS + GS (Group sizes competing)

### Reasoning

Two `GroupSize` constraints anchored on adjacent cells with
different target sizes can never share a group: a single group has a
single size, so the two targets cannot both hold simultaneously. By
contrapositive, the two anchor cells must end up in separate groups,
which on a 2-colour grid means they take **different colours**.

Two consequences:

1. **Forced opposite colour** — when one anchor is already coloured
   and the other is empty, the empty one must take the opposite
   colour. `GroupSize.apply` would only enforce this once its own
   group reaches its target size; the complicity catches it as soon
   as the colour mismatch is observable.
2. **Impossibility** — both anchors coloured the same colour means
   they share a group with two conflicting target sizes. The verify
   side of `GS` would eventually reject this state, but the
   complicity surfaces it explicitly at apply time.

When **both** anchors are still empty the complicity knows the two
must end up different colours but cannot pick a specific value yet —
it returns null and waits for a later step (any other constraint
colouring one of them) to fire.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/gsgs.dart`. The
implementation is a quadratic scan over `GS` constraints: for each
pair with mismatched sizes it checks 4-adjacency between the
anchors, then handles the four colouring cases (both empty, one
coloured, the other coloured, both coloured).

### Limitations

- **Direct adjacency only.** Two GSs at distance 2 (or beyond) with
  mismatched sizes also constrain the cells between them, but the
  reasoning needs to consider how a path of same-colour cells could
  bridge them. Not yet implemented.
- **No transitive chaining.** Three or more GSs forming a clique of
  pairwise mismatches on a 2-colour grid would be jointly
  unsatisfiable; the current code only handles pairwise contradictions.

## Complicity: GS + (anything) — group sealing enumeration

`GSAllComplicity` filters survivors against **every** constraint of
the puzzle, so the same code captures GS+FM, GS+PA, GS+SY, GS+QA, …
uniformly.

### Reasoning

A coloured `GroupSize` anchor pins the final size of the anchor's
group. We **enumerate every way to seal off** a connected group of
exactly `gs.size` cells around the anchor:

- Each step picks the canonical (lowest-indexed) free cell adjacent
  to the current group and branches: *include* (the cell joins the
  group, plus any same-colour cells reachable from it via already-
  coloured `c`-cells — merging separate groups together) or *seal*
  (the cell is committed to the opposite colour, closing it as a
  border).
- A branch terminates when the group reaches the target size: every
  remaining frontier cell auto-seals (else the group would grow
  beyond the target).

Every "sealing" survivor is a pair `(group, sealed)`. We drop the
ones whose simulated state violates **any** constraint of the
puzzle (FMs, other GSs, parity, …) — full constraint-set
verification keeps the survivor set sound when the seal accidentally
overgrows another constraint's group.

A free cell is forced to `c` when it lies in **every** survivor's
`group`, and to opposite when it lies in **every** survivor's
`sealed`. Otherwise it stays undetermined.

Why this works where neither `GroupSize.apply` nor the FMs alone do:
the apply side of GS only seals borders once the current group has
already reached the target size, so it can't anticipate which cells
must take the colour during growth. By exploring every way to
finish the group **and** filtering by the motifs as if the seal
were already in place, the complicity catches the configurations
that would later collapse to a single force chain.

### Concrete examples

**GS+FM**:

```
3×3 grid with cells 6=2, 7=1, 8=1.
GS:8.3 — group of cell 8 must have size 3.
FM:12.01 forbids the 2×2 pattern:
  1 2
  ? 1

Current group of cell 8: {7, 8}. Two candidate expansions:

  expansion {4} →  group {4, 7, 8}, sealed {1, 3, 5}
                   simulated row 1 = `1 2 _` and row 2 = `2 1 1`
                   → motif at top-left (1, 1) matches → REJECTED

  expansion {5} →  group {5, 7, 8}, sealed {2, 4}
                   no motif match → SURVIVES

Only one survivor: cell 5 ends up in `group` (every survivor) →
forced to 1.
```

**GS+PA** (no FM involved):

```
5×2 grid with cells 6=2, 9=2.
PA:5.right covers row-1 cells [6, 7, 8, 9] with parity 2/2.
GS:9.2 — group of cell 9 must have size 2.

Trying to expand the group via cell 8 makes cell 8 = 2; together
with the pre-coloured cell 6 = 2 the right side has three 2s,
breaking PA. Only the {4, 9} expansion survives → cell 4 forced
to 2 (sealed border 8 cascades from GS.apply afterwards).
```

**Empty anchor — try-each-colour**:

```
3×3 grid with cells 2=1, 4=1, 6=1.
GS:8.2 — cell 8 empty, group must have size 2.

If cell 8 = 1, every connected expansion of size 2 merges with
the existing 1-clusters and overshoots the target → no surviving
sealing. If cell 8 = 2, two expansions ({5, 8} and {7, 8}) survive.
Therefore cell 8 must be 2.
```

### Implementation

See `lib/getsomepuzzle/constraints/complicities/gsall.dart`. The
gap `gs.size - |currentGroup|` is bounded at 6 to keep the
recursion tractable; with merges the actual number of decisions is
often much smaller.

### Soundness checks

The simulation seals the frontier with the opposite colour, which
can interact with **any** other constraint. Calling `verify` on
every constraint of the puzzle (not just FMs) is what keeps the
survivor enumeration sound — without it, the seal can spuriously
look fine to the FMs while breaking another GS or a parity side.

## Complicity: FM + FM (motif synthesis)

### Reasoning

Two `ForbiddenMotif`s with the same shape that differ in **exactly
one cell**, where the two values cover the entire domain, can be
combined into a stronger forbidden motif: the combined motif has a
**wildcard at the diverging position**.

Example: `FM:2.2.1` + `FM:1.2.1` → synthesized `FM:0.2.1`. Either
top value is forbidden when the bottom two cells read `(2, 1)`, so
the combined statement is "any cell on top, with `2` in the middle
and `1` at the bottom, is forbidden — anywhere a 3-cell vertical
window fits".

The synthesized motif **keeps its original dimensions**. It is not
equivalent to a smaller motif (e.g. it is *not* `FM:2.1`, which
would also fire on rows where the original FMs could not have:
the synthesized FM still requires the full pattern window to fit
inside the grid).

### Why a complicity (not a constraint)

The synthesized motifs are not added to `puzzle.constraints` —
they would clutter the player's view of the puzzle, and the
deduction itself is what the player is meant to make. By routing
the deduction through a complicity, future hint-UI work can label
the move "deduced by combining two forbidden motifs" without
exposing a synthetic constraint.

### Implementation

See `lib/getsomepuzzle/constraints/complicities/fmfm.dart`. At
`isPresent` time the complicity scans pairs of FMs and synthesizes
all combined motifs (iterated to a fixed point — a synthesized FM
can in turn combine with another existing FM). The pool is capped
at 50 entries to guard against blow-up. At apply time each
synthesized FM is run through `ForbiddenMotif.apply`; on a hit, the
move is re-attributed to the complicity itself (tier 4 weight) so
the synthetic FM stays internal.

### Concrete example

```
3-wide × 4-tall grid. FMs: FM:2.2.1, FM:1.2.1.
Synthesis: FM:0.2.1 — "(?, 2, 1) vertical is forbidden" on rows
where a 3-cell window fits.

Pre-colour cell 6 = 1 (row 2, col 0). The synthesized FM finds the
window at column 0, rows 0–2: any (?, 2, 1) below the top cell.
The middle of that window (cell 3, row 1) cannot be 2 → forced to 1.
```

## Future complicities

(None planned at the moment — open question whether more pairwise
combinations are worth implementing or if the existing eight
already cover the common puzzle patterns.)
- **SH + GS**: the mandatory shape for a colour gives the size of
  every group of that colour. If a GS constraint disagrees, the GS
  must be the opposite colour.
