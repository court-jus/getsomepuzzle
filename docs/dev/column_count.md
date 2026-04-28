# Column Count Constraint

The Column Count constraint (`CC`) specifies how many cells of a given color must
appear in a specific column.

## Syntax

`CC:2.1.3` (slug:idx.color.value) means column `2` (the third column) contains
exactly `3` cells of color `1` (black).

## Display

A digit displayed above the column, outside the grid, inside a greyed circle.
The digit color matches the constraint color.

## Implementation

### Constraint Class

**Location**: `lib/getsomepuzzle/constraints/column_count.dart`

`ColumnCountConstraint` extends `Constraint` (not `CellsCentricConstraint`,
since it is tied to a whole column rather than a specific cell).

Fields: `columnIdx` (int), `color` (int), `count` (int).

- **`slug`** → `'CC'`
- **`serialize()`** → `'CC:$columnIdx.$color.$count'`
- **`toString()`** → `'$count'` (the displayed digit)
- **`verify(Puzzle)`** — Fetches the column via `puzzle.getColumns()[columnIdx]`,
  counts cells with value `color`. If the puzzle is complete: checks exact
  equality. Otherwise: rejects if the current count already exceeds `count`,
  or if the free cells in the column can no longer reach `count`.
- **`apply(Puzzle)`** — Three deductions:
  - If the placed `color` cells already equal `count` → remaining free cells
    in the column take the opposite value.
  - If the remaining free cells exactly match the deficit → they all take
    `color`.
  - If the placed `color` cells already exceed `count` → returns `Move(...,
    isImpossible: this)`.
- **`isCompleteFor(Puzzle)`** — `verify(puzzle)` is true and the column has no
  free cells.
- **`generateAllParameters(width, height, domain)`** — for each column, each
  domain color, each valid count `1..height-1`, yields `'$col.$color.$count'`.

The shape mirrors `QuantityConstraint`, restricted to a single column.

### Registry

`lib/getsomepuzzle/constraints/registry.dart`:

```dart
(slug: 'CC', label: 'Column count', fromParams: ColumnCountConstraint.new),
```

### Generator integration

`lib/getsomepuzzle/generator/generator.dart` enumerates `'CC'` parameters via
`ColumnCountConstraint.generateAllParameters` like every other registered
constraint type.

### Widget

**Location**: `lib/widgets/column_count.dart`

`ColumnCountWidget` renders the digit inside a greyed circle, with text color
matching the constraint color (black for 1, white for 2 — same convention as
`quantity.dart`).

`lib/widgets/puzzle.dart` places a row of these widgets between the top
constraint bar and the grid, aligned with `adjustedCellSize` so each indicator
sits centered above its column. Columns without a `CC` constraint use an empty
spacer of equal width.

The highlight / hint-arrow logic in `puzzle.dart` includes a `CC` branch: when
the highlighted constraint is a `CC`, the arrow points from the indicator
above the column to the relevant cell.

### Tests

**Location**: `test/column_count_test.dart`

Covers `verify` (complete and partial puzzles, exceeded count),
`apply` (both deduction directions and the impossible case), serialize /
deserialize round-trip, and `generateAllParameters` cardinality.
