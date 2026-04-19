# Grayout Shape Constraint - Implementation

## Overview

The `ShapeConstraint` now implements `isCompleteFor` to support the grayout feature. A Shape constraint is considered complete when it can no longer produce any deductions.

## Implementation Details

### Location

`lib/getsomepuzzle/constraints/shape.dart`

### Method: canPlaceAnyVariant

```dart
bool canPlaceAnyVariant(Puzzle puzzle) {
  final oppositeColor = puzzle.domain.whereNot((i) => i == color).first;
  final width = puzzle.width;
  final height = puzzle.height;

  for (final variant in variants) {
    final varH = variant.length;
    final varW = variant[0].length;

    for (int row = 0; row <= height - varH; row++) {
      for (int col = 0; col <= width - varW; col++) {
        bool blockedByOpposite = false;
        bool hasAtLeastOneEmpty = false;
        for (int vr = 0; vr < varH; vr++) {
          for (int vc = 0; vc < varW; vc++) {
            if (variant[vr][vc] == 0) continue;
            final cellValue =
                puzzle.cells[(row + vr) * width + (col + vc)].value;
            if (cellValue == oppositeColor) {
              blockedByOpposite = true;
            } else if (cellValue == 0) {
              hasAtLeastOneEmpty = true;
            }
          }
        }
        if (!blockedByOpposite && hasAtLeastOneEmpty) return true;
      }
    }
  }
  return false;
}
```

This method checks whether a new group can be created anywhere in the grid. It returns `true` if at least one variant can be placed with at least one empty cell (meaning a new group could form).

### Method: isCompleteFor

```dart
@override
bool isCompleteFor(Puzzle puzzle) {
  if (!verify(puzzle)) return false;

  final groups = getGroups(puzzle);

  for (final group in groups) {
    if (puzzle.cellValues[group.first] != color) continue;

    final isClosed = !group.any(
      (idx) => puzzle.getNeighbors(idx).any((n) => puzzle.cellValues[n] == 0),
    );

    if (!isClosed) return false;
  }

  if (canPlaceAnyVariant(puzzle)) return false;

  return true;
}
```

A Shape constraint is complete when all three conditions are met:

1. **Constraint is valid** - `verify(puzzle)` returns `true` (no violations)
2. **All existing groups are closed** - no free neighbors around any group of the constrained color
3. **No new group can be created** - `canPlaceAnyVariant` returns `false` (all positions where a variant could appear are either blocked by opposite color or already fully occupied by existing groups)

### Why canPlaceAnyVariant requires at least one empty cell

If a placement has no empty cells, it means all cells are already filled with the constrained color. This corresponds to an existing group, not a new one. We only care about placements that could create a **new** group, which requires at least one empty cell that could be filled with the constrained color.

## Tests

9 unit tests were added in `test/shape_utils_test.dart`:

1. Open group → returns `false`
2. Closed group with valid shape → returns `true`
3. Closed group with rotated valid shape → returns `true`
4. Multiple groups, all closed → returns `true`
5. All possible placements blocked → returns `true`
6. Can still place variant somewhere → returns `false`
7. Constraint violated → returns `false`
8. Closed group with wrong size → returns `false`
9. White shape constraint ignores black groups → returns `true`

## UI Integration

No changes required. The existing code in `lib/getsomepuzzle/constraints/to_flutter.dart` already uses:

```dart
final bool shouldGrayOut = constraint.isComplete && constraint.isValid;
```
