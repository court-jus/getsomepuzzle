# Grayout Constraints

## Overview

During the playing phase, when a constraint becomes useless (fully satisfied with no further deductions possible AND still valid), it is grayed out to visually indicate it is complete.

**Important:** Only constraints that are both **valid** (`verify(puzzle) == true`) AND **complete** can be grayed out. Invalid constraints (those that have been violated) remain visible with their invalid styling.

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

**File:** `lib/getsomepuzzle/constraints/groups.dart`

Complete when all indexed cells are filled with the same color, forming a connected group, AND the group has no free neighbors (fully bordered).

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

Returns `false` - checking all shape variants is more expensive.

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

Complete when the target count is reached AND no more groups can be added (i.e., no free cells without a neighbor of the constrained color).

#### 2.9 `ColumnCountConstraint`

**File:** `lib/getsomepuzzle/constraints/column_count.dart`

Complete when column is fully filled.

#### 2.10 `DifferentFromConstraint`

**File:** `lib/getsomepuzzle/constraints/different_from.dart`

Complete when BOTH cells are filled (can verify difference).

### 3. UI Update

**File:** `lib/getsomepuzzle/constraints/to_flutter.dart`

Updated constraint rendering to gray out complete constraints:

```dart
final bool shouldGrayOut = constraint.isComplete && constraint.isValid;
final fgcolor = shouldGrayOut
    ? Colors.grey
    : (constraint.isHighlighted
          ? highlightColor
          : (constraint.isValid ? defaultColor : Colors.redAccent));
```

Complete constraints display with a grey foreground color instead of green (valid/highlighted) or red (invalid).