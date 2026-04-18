# WIP: Column count constraint

New constraint type "Column Count" (slug CC).

Serialized as `CC:2.1.3` (slug:idx.color.value), it means column "idx" contains "value" cells
of color "color". The example above means there are 3 black cells in the third column
(index 2).

This constraint is represented by a digit displayed above the column (outside the grid),
inside a greyed circle. The digit color matches the constraint color.

## Implementation plan

### 1. Create the `ColumnCountConstraint` class

**File**: `lib/getsomepuzzle/constraints/column_count.dart`

Extends `Constraint` (not `CellsCentricConstraint`, since it's tied to a whole column rather
than to a specific cell).

Fields: `columnIdx` (int), `color` (int), `count` (int).

- **`slug`** → `'CC'`
- **`serialize()`** → `'CC:$columnIdx.$color.$count'`
- **`toString()`** → `'$count'` (the displayed digit)
- **`verify(Puzzle)`** — Fetches the column via `puzzle.getColumns()[columnIdx]`, counts cells
  with value `color`. If the puzzle is incomplete, checks current count ≤ `count`. If complete,
  checks exact equality.
- **`apply(Puzzle)`** — Deductions:
  - If the number of `color` cells in the column == `count` → remaining free cells in the
    column take the opposite value.
  - If the number of remaining free cells == `count` - already placed `color` cells → free
    cells take value `color`.
  - If the number of `color` cells > `count` → `isImpossible`.
- **`generateAllParameters(width, height, domain)`** — For each column (0..width-1), each
  domain color, each valid count (1..height-1), generate `'$col.$color.$count'`.

Reference model: `QuantityConstraint` (similar logic applied to a column instead of the entire
grid).

### 2. Register the constraint

**File**: `lib/getsomepuzzle/constraints/registry.dart`

- Add the import of `column_count.dart`.
- Add the entry to `constraintRegistry`:
  `(slug: 'CC', label: 'Column count', fromParams: ColumnCountConstraint.new)`

### 3. Integrate with the generator

**File**: `lib/getsomepuzzle/generator/generator.dart`

- Add the `'CC'` case in `_generateParamsForSlug()` (~line 362):
  `return ColumnCountConstraint.generateAllParameters(width, height, domain);`

### 4. Display widget above the grid

**File**: `lib/widgets/column_count.dart` (new)

`ColumnCountWidget` displays the digit in a greyed circle, with the text color matching
`color` (black for 1, white for 2, like `textColors` in `quantity.dart`).

**File**: `lib/widgets/puzzle.dart`

The display is specific: it must appear **above the corresponding column**, aligned with the
grid. This differs from the top bar (Wrap) used for Motif/Quantity.

- Add a row of positioned widgets between the existing Wrap (top bar) and the grid.
- For each column, display a `ColumnCountWidget` if a CC constraint exists for that column,
  otherwise an empty spacer of equal width.
- The row must align with `adjustedCellSize` so each indicator is centered above its column.

Update `constraintIsInTopBar` and `numberOfTopBarConstraints` detection to include
`ColumnCountConstraint` if needed for sizing, or handle it separately since its placement is
column-bound rather than Wrap-based.

### 5. Highlight and hint arrow

**File**: `lib/widgets/puzzle.dart`

- Add `ColumnCountConstraint` to the highlight/arrow logic (~line 140). Since CC is neither in
  the regular top bar nor inside a cell, a new case is needed: when the highlighted constraint
  is a CC, the arrow points from the widget above the column to the cell relevant to the hint.

### 6. Tests

**File**: `test/column_count_test.dart` (new)

- **verify**: complete puzzle with correct/incorrect count → true/false.
- **verify partial**: incomplete puzzle with count not yet exceeded → true.
- **apply**: deduction when all color cells are placed (free → opposite).
- **apply**: deduction when remaining free cells match exactly the remaining need.
- **apply impossible**: more color cells than count → isImpossible.
- **serialize / deserialize**: round-trip `CC:2.1.3` → object → `CC:2.1.3`.
- **generateAllParameters**: verify expected number of parameters for a given grid.

### Recommended implementation order

1. **Step 1** (class + registry) — makes the constraint parsable and verifiable.
2. **Step 6** (logic tests) — validates verify/apply before moving on.
3. **Step 3** (generator) — enables generating puzzles with CC.
4. **Steps 4-5** (UI) — display and interaction in the app.
