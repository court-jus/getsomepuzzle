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

## Future complicities

- **PA + FM**: a 2-cell mixed-colour FM forces a monotone axis;
  combined with a parity side, the side's full assignment is fixed.
  Detailed plan in `docs/dev/constraint_complicity.md` history (commit
  `231a473`) — yet to be re-implemented on master.
- **SY + FM**: symmetry maps a cell to another; if FM forbids the
  pattern formed by both, the colour is forced.
- **LT + GS**: the connection path has a minimum length; combined
  with group-size limits this can force boundaries.
- **GS + GS**: adjacent groups with constrained sizes compete for
  space.
- **SH + GS**: the mandatory shape for a colour gives the size of
  every group of that colour. If a GS constraint disagrees, the GS
  must be the opposite colour.
