# Constraint Complicity System

## Problem

The solver's propagation loop (`applyConstraintsPropagation`) iterates each constraint individually until no single constraint can make progress (fixed point). However, some deductions require **combining information from multiple constraints**. These cross-constraint deductions are called **complicities**.

Example: a LetterGroup (LT) requiring connectivity across rows + a ForbiddenMotif (FM) blocking vertical adjacency of a color → forces the LT group's color. Neither constraint alone can deduce this.

## Architecture

### Integration in the propagation loop

Complicities act as a **second level** in the propagation loop:

```
while (true) {
  // Level 1: exhaust individual constraint deductions (current fixed point)
  while (any individual constraint produces a move) { apply it }

  // Level 2: try complicities
  move = tryComplicities()
  if (move != null) { apply it; continue → back to level 1 }

  // Truly stuck
  break
}
```

A complicity is only tried when individual constraints are exhausted. If it unlocks a cell, control returns to level 1 (which may cascade further).

### Abstract class

```dart
abstract class Complicity {
  /// Try to deduce a move by combining constraints.
  Move? apply(Puzzle puzzle);
}
```

### Auto-detection

At puzzle construction time, scan the constraint list and instantiate relevant complicities. For example, if the puzzle has both LT and FM constraints, add a `ConnectivityMotifComplicity`.

## Complicity: LT + FM (Connectivity × Motif)

### Reasoning

- LT requires two cells to be **same color** and **connected** by a path of that color
- If the cells are on **different rows**, any connecting path must include at least one **vertical step** (two same-color cells stacked vertically)
- If FM forbids vertical adjacency of color X (e.g., FM:2.2 forbids two vertical 2s), then color X **cannot form a vertical step**
- Therefore the LT group **cannot be color X** → it must be the other color

Same logic applies horizontally: if LT cells are on different columns, the path needs a horizontal step.

### Implementation

```dart
class ConnectivityMotifComplicity extends Complicity {
  @override
  Move? apply(Puzzle puzzle) {
    final ltConstraints = puzzle.constraints.whereType<LetterGroup>();
    final fmConstraints = puzzle.constraints.whereType<ForbiddenMotif>();

    for (final lt in ltConstraints) {
      // Skip if LT color is already determined
      final knownColors = lt.indices
          .map((i) => puzzle.cellValues[i])
          .where((v) => v != 0);
      if (knownColors.isNotEmpty) continue;

      final rows = lt.indices.map((i) => i ~/ puzzle.width).toSet();
      final cols = lt.indices.map((i) => i % puzzle.width).toSet();

      for (final color in puzzle.domain) {
        bool blocked = false;

        if (rows.length > 1) {
          blocked = fmConstraints.any((fm) => fm.blocksVertical(color));
        }
        if (!blocked && cols.length > 1) {
          blocked = fmConstraints.any((fm) => fm.blocksHorizontal(color));
        }

        if (blocked) {
          final forcedColor = puzzle.domain.where((c) => c != color).first;
          for (final idx in lt.indices) {
            if (puzzle.cellValues[idx] == 0) {
              return Move(idx, forcedColor, lt);
            }
          }
        }
      }
    }
    return null;
  }
}
```

### ForbiddenMotif helper methods

`blocksVertical(color)`: returns true **only** if the motif is exactly `[[C],[C]]` (height 2, width 1, both cells = color). This is the only pattern that guarantees ANY vertical step of color C matches the forbidden motif.

Taller motifs (e.g. `[[C],[C],[C]]`) don't qualify: two adjacent Cs don't match a 3-tall pattern. Wider motifs (e.g. `[[C,C],[C,C]]`) don't qualify: a vertical step in one column doesn't require the adjacent column to also be C.

`blocksHorizontal(color)`: same logic — only `[[C,C]]` (height 1, width 2).

### Impact analysis (2026-04-15)

Out of 709 unsolved puzzles (`0:0_100` in `assets/default.txt`):
- **27** match the LT+FM complicity pattern (LT spanning rows/cols + FM:CC or FM:C.C blocking that direction for a color)
- Of those 27, **9 are fully solved** once the complicity forces the LT color (all 9 need the force phase after the complicity unlocks the first cells)
- **18 remain stuck** — the complicity alone isn't enough; they likely need additional complicities or deeper reasoning

Scripts used for this analysis: `bin/analyze_unsolved.dart` and `bin/verify_complicity.dart`.

## Complicity: PA + FM (Parity × Motif monotonicity)

### Reasoning

A ForbiddenMotif of size 2 using the two domain colors forces a **single axis** to be monotone — rows for a horizontal FM, columns for a vertical FM. The orthogonal axis is unconstrained (under `FM:1.2`, a grid like `222 / 222 / 212` is valid even though row 2 is not monotone).

- `FM:12` (horizontal, motif `[[1,2]]`): `1→2` going right is forbidden, so each **row** reads `2* 1*` (some 2s, then some 1s).
- `FM:21` → **rows** are `1* 2*`.
- `FM:2.1` (vertical, motif `[[2],[1]]`): `2→1` going down is forbidden, so each **column** reads `1* 2*`.
- `FM:1.2` → **columns** are `2* 1*`.

A ParityConstraint on a side of length `n` says `count(odd) == count(even)`. With domain `{1, 2}` this means `count(1) == count(2) == n/2`.

Combining both on the same axis (a horizontal FM with a `left`/`right`/`horizontal` PA side, or a vertical FM with `top`/`bottom`/`vertical`): the side is a contiguous slice of a monotone sequence, so it is itself monotone. The parity fixes its composition at exactly `n/2` of each color. Monotonicity + composition = the full assignment: the first `n/2` cells are the "first" color of the pattern, the last `n/2` are the "second".

Neither constraint alone makes this deduction:
- `ForbiddenMotif.apply()` only fires when a value is about to close the forbidden motif with an already-filled neighbor — it never derives the monotone property.
- `ParityConstraint.apply()` only deduces a cell when one color's count has already reached `n/2` on the side.

Example: `v2_12_4x7_2000000000000000002000000000_PA:1.bottom;FM:122;FM:2.1;PA:19.top` — a puzzle a human solves by pure propagation, but which currently requires 6 force rounds in the solver.

### Plan

#### New file: `lib/getsomepuzzle/constraints/complicities/pafm.dart`

```dart
class PAFMComplicity extends Complicity {
  @override String serialize() => "PAFMComplicity";

  @override
  bool isPresent(Puzzle puzzle) {
    // True iff:
    //   - domain == {1, 2}
    //   - at least one FM has a 2-cell motif with two distinct colors
    //   - at least one PA has a side aligned with that FM's direction
  }

  @override
  Move? apply(Puzzle puzzle) {
    // For each PA, for each matching FM direction, for each aligned side:
    //   1. Collect the side's cell indices in order.
    //   2. Skip if length is 0 or odd (defensive — PA generator guarantees even).
    //   3. Expected values: first half = pattern.first, second half = pattern.second.
    //   4. Return Move(idx, expected) on the first empty cell that matches.
    // Return null if nothing to deduce.
  }
}
```

Helpers:
- `_horizontalPattern(ForbiddenMotif fm) → (int, int)?` — returns `(first, second)` for motif `[[a,b]]` with `a≠b`, both non-zero: `(b, a)` (rows read `b* a*`). Returns null for any other motif shape.
- `_verticalPattern(ForbiddenMotif fm)` — same for motif `[[a],[b]]`.
- `_isHorizontalSide(String)` / `_isVerticalSide(String)` — classify PA sides.
- `_domainIsOneTwo(Puzzle)` — guard: parity's odd/even split matches color counting only when domain is `{1, 2}`.

#### Register the complicity

Add `PAFMComplicity()` to `allComplicities` in `lib/getsomepuzzle/constraints/complicities/registry.dart`.

#### Tests in `test/complicities_test.dart`

1. **Detection — vertical case**: puzzle with `FM:2.1` + `PA:N.top` → `complicities` contains exactly one `PAFMComplicity`.
2. **Apply — vertical**: on a 3x3 puzzle with `FM:2.1` (columns are `1* 2*`) and `PA:8.top` (col 2 rows 0-1, length 2), `apply()` returns a move setting cell 2 to `1` (first half of the side).
3. **Apply — horizontal**: on a puzzle with `FM:12` (rows are `2* 1*`) and a `PA:X.right` of length 2, `apply()` sets the first cell of the right side to `2`.
4. **Negative case**: puzzle with `FM:2.1` but only `PA:X.left` (horizontal PA, vertical FM) → `isPresent` returns `false`.
5. **Negative case — same-color FM**: `FM:22` does not qualify (LT+FM territory, not PA+FM).

### Impact analysis (to run after implementation)

Re-run `bin/analyze_unsolved.dart` and `bin/verify_complicity.dart` (adapted for PAFM) against `assets/default.txt` to count how many of the 709 unsolved puzzles this complicity unlocks, and how many become fully solvable when combined with the force phase.

## Future complicities

- **SY + FM**: symmetry maps a cell to another; if FM forbids the pattern formed by both, the color is forced
- **LT + GS**: the connection path has a minimum length; combined with group size limits, this can force boundaries
- **GS + GS**: adjacent groups with constrained sizes compete for space
- **SH + GS**: the mandatory shape for a color gives us the size of every group in that color. If a GS constraint gives a different size, we know that it has the opposite color