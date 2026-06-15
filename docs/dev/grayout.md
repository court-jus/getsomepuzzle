# Grayout Constraints

## Overview

During the playing phase, when a constraint becomes useless, it is grayed out
to visually indicate it is complete.

### Semantics: "no future deduction possible"

A constraint is **complete** (greyable) when, from the current state, `apply()`
will never return a non-null move **in any reachable future state** — no matter
which cells the player colours next.

This is the strict reading of "fully satisfied with no further deductions
possible". The weaker reading — "`apply()` returns null right now" — is
rejected because it causes grayout to flash in and out as the player plays
(e.g., a Quantity constraint currently in a "waiting" state could reach its
target on the next move and fire again).

Under this semantics, two classes of constraints emerge:

- **Monotone** constraints (`FM`, `GS`, `LT`, `SY`, `DF`, `CC`, `PA`, `CH`):
  their completion criterion is preserved by any future move. Once complete,
  they stay complete. They gray out meaningfully mid-game.
- **Non-monotone** constraints (`QA`, `GC`, `SH`): future play can revive
  them. They can only be grayed out once no useful move can trigger them
  again, which for `QA` and `SH` essentially means "puzzle complete", and
  for `GC` means "target reached AND no future merge is possible".

**Important:** Only constraints that are both **valid** (`verify(puzzle) ==
true`) AND **complete** can be grayed out. Invalid constraints (those that
have been violated) remain visible with their invalid styling.

## Implementation

### 1. Base `Constraint` class

**File:** `lib/getsomepuzzle/constraints/constraint.dart`

Added `isComplete` property (defaults to `false`) and `isCompleteFor(Puzzle puzzle)` method:

```dart
class Constraint {
  bool isValid = true;
  bool isHighlighted = false;
  bool isComplete = false;

  bool isCompleteFor(Puzzle puzzle) => false;
}
```

### 2. Constraint-specific implementations

Each constraint type overrides `isCompleteFor` to detect when it is complete. All implementations first check `verify(puzzle)` and return `false` if the constraint is invalid.

#### 2.1 `ParityConstraint`

**File:** `lib/getsomepuzzle/constraints/parity.dart`

Complete when all cells in the parity regions are set (no zeros remain).

#### 2.2 `GroupSize`

**File:** `lib/getsomepuzzle/constraints/groups.dart`

Complete when the indexed group is fully bordered (no empty neighbors) AND has reached the required size.

#### 2.3 `LetterGroup`

**File:** `lib/getsomepuzzle/constraints/letter_group.dart`

Complete when all indexed cells are filled with the same color, forming a
single connected group, AND no foreign-letter cell is still reachable from that
group through cells that could join it (a flood over `{groupColor ∪ free}`).
Once the members are connected and no other letter can ever merge in, no `apply`
branch can fire again. Free neighbours are allowed as long as they cannot reach
a foreign letter — the flood's traversable set only shrinks as cells are
coloured, so the criterion is monotone and grays out as soon as the letters are
linked and isolated from other letters.

#### 2.4 `SymmetryConstraint`

**File:** `lib/getsomepuzzle/constraints/symmetry.dart`

Complete when all cells in the symmetric group have been filled and the group is fully bordered (no free neighbors).

#### 2.5 `ForbiddenMotif`

**File:** `lib/getsomepuzzle/constraints/motif.dart`

Complete when the forbidden pattern can no longer appear anywhere in the grid. Checks all possible positions where the motif could be placed - if every placement is blocked by already-filled cells with conflicting values, the motif cannot appear and the constraint is useless.

**Algorithm:**
```
1. For each top-left position (row, col) where the motif fits in the grid:
   2. For each cell (mr, mc) in the motif that is non-zero:
      3. Let gridIdx = (row + mr) * width + (col + mc)
      4. Let motifValue = motif[mr][mc]
      5. If puzzle.cellValues[gridIdx] != 0 AND puzzle.cellValues[gridIdx] != motifValue:
         - This placement is BLOCKED (cell filled with wrong value)
      6. Otherwise, this placement is STILL POSSIBLE
2. If ALL placements are blocked → return true (complete)
3. Otherwise → return false
```

#### 2.6 `ShapeConstraint`

**File:** `lib/getsomepuzzle/constraints/shape.dart`

Complete only when the grid is fully filled. "All current groups closed" is
not enough: any free cell still in the grid has no color neighbour (otherwise
some group would have a free neighbour, contradicting "all closed"), so
colouring it with `color` creates a new 1-cell group. For any shape larger
than 1 cell, this new group doesn't match any variant → `apply` level 1
fires `isImpossible`. So `SH` can only be considered permanently complete
once no free cell remains.

#### 2.7 `QuantityConstraint`

**File:** `lib/getsomepuzzle/constraints/quantity.dart`

Complete only when the grid is fully filled. Unlike FM or SH, whose pattern
becomes permanently unreachable once excluded, a Quantity constraint can
always resume firing as cells are coloured: any move that brings the state
to `myValues == count` or `count - myValues == freeCells` triggers forcing
of the remaining cells. As long as any free cell remains, such a state can
be reached by future play, so QA's grayout condition is equivalent to
"puzzle complete" on top of `verify()`.

#### 2.8 `GroupCountConstraint`

**File:** `lib/getsomepuzzle/constraints/group_count.dart`

Complete only when no future play can ever trigger `apply()` again:
- `currentCount == count` (target reached), AND
- `candidates.isEmpty` (no new groups can form — the candidate set is
  monotone decreasing, so empty now means empty forever), AND
- `calculateMinGroups(puzzle, color) == currentCount` (no merge is possible
  now or in the future — `canMergeGroups` reachability only shrinks as
  cells are coloured, so equality now guarantees equality forever; this
  also implies no merge-cell can appear later).

#### 2.9 `ColumnCountConstraint`

**File:** `lib/getsomepuzzle/constraints/column_count.dart`

Complete when column is fully filled.

#### 2.10 `DifferentFromConstraint`

**File:** `lib/getsomepuzzle/constraints/different_from.dart`

Complete when BOTH cells are filled (can verify difference).

#### 2.11 `ChainConstraint`

**File:** `lib/getsomepuzzle/constraints/chain.dart`

Complete as soon as a path of already-placed target-color cells connects the
two sides (flood-fill restricted to cells of value `color`). Placed cells are
immutable, so a finished path can never be broken: the constraint is
guaranteed satisfied at the end, and no `apply` branch can ever fire again.
The criterion is monotone — CH grays out mid-game once the player finishes
any connecting path.

### 3. UI Update

**File:** `lib/getsomepuzzle/constraints/to_flutter.dart`

Constraint rendering grays out complete constraints:

```dart
final bool shouldGrayOut = constraint.isComplete && constraint.isValid;
final fgcolor = shouldGrayOut
    ? Colors.grey
    : (constraint.isHighlighted
          ? highlightColor
          : (constraint.isValid ? defaultColor : Colors.redAccent));
```

Complete constraints display with a grey foreground color instead of green (valid/highlighted) or red (invalid).

#### Background color semantics

Constraint widgets use the background to encode the constraint's nature
(`lib/getsomepuzzle/model/constants.dart`):

- `forbiddenColor` (purple) — "forbidden" constraints (FM);
- `mandatoryColor` (light blue) — "mandatory" constraints (QA, GC, SH,
  CC, RC, CT, RT, DF).

On grayout the background switches to `Colors.grey.withValues(alpha: 0.3)`.
For the grid-edge widgets (`lib/widgets/column_count.dart`,
`lib/widgets/row_count.dart`, `lib/widgets/transition.dart`) and the DF
circles (`lib/widgets/different_from_painter.dart`), **only the background
is grayed**: the digit, wave glyph, and ≠ symbol keep their normal colors.