# Row Count Constraint

New constraint type "Row Count" (slug RC).

Serialized as `RC:1.2.3` (slug:idx.color.count), it means row "idx" contains "count" cells
of color "color". The example above means there are 3 white cells in the second row (index 1).

This constraint is the horizontal counterpart of `ColumnCountConstraint` (CC). Its implementation
is a direct mirror of CC along the other axis. The real gameplay value emerges when RC and CC
constraints coexist in the same puzzle, creating a nonogram-like system of crossed deductions.

## Syntax

`RC:0.1.2` — row 0 contains exactly 2 black cells.
`RC:2.2.1` — row 2 contains exactly 1 white cell.

## Display

The constraint is represented by a digit displayed to the **left** of the corresponding row
(outside the grid), inside a greyed circle. The digit color matches the constraint color
(black text for color 1, white text on dark background for color 2), mirroring the CC widget
style.

## Gameplay notes

RC alone has the same deductive power as CC. Their combination is qualitatively different:
cross-referencing a row count and a column count can pin individual cells by elimination,
exactly as in nonogram/picross puzzles. A puzzle with several RC and CC constraints may be
entirely solvable by propagation, with zero force rounds, yet feel satisfying because the
player must hold two dimensions in mind simultaneously.

RC + CC pairs should be weighted as a single combined constraint type by the generator's
diversity score to avoid over-awarding rule_diversity when both are present.

## Implementation notes (completed)

### ✅ 1. `RowCountConstraint` class

**File**: `lib/getsomepuzzle/constraints/row_count.dart`

- Extends `LineCentricConstraint` (base class shared with `ColumnCountConstraint`)
  - Base class `LineCentricConstraint` in `lib/getsomepuzzle/constraints/base_line_constraint.dart`
  - Handles `verify()`, `apply()`, `isCompleteFor()`, `serialize()`, `toString()`
- Fields: `rowIdx` (int), inherited `color` (int), inherited `count` (int)
- Implements:
  - `slug` → `'RC'`
  - `getIdx()` → returns `rowIdx`
  - `getLine(Puzzle)` → `puzzle.getRows()[getIdx()]`
  - `toHuman(Puzzle)` → `'Row ${getIdx() + 1}: $count'`

### ✅ 2. Registered in `registry.dart`

**File**: `lib/getsomepuzzle/constraints/registry.dart`

- Import added: `import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';`
- Entry added to `constraintRegistry` (alphabetical order, between PA and GS):
  ```dart
  (
    slug: 'RC',
    label: 'Row count',
    fromParams: RowCountConstraint.new,
    generateAllParameters: RowCountConstraint.generateAllParameters,
  ),
  ```

### ✅ 3. Generator integration

**File**: `lib/getsomepuzzle/generator/generator.dart`

- No manual integration needed — generator uses `generateAllParameters()` from registry dynamically
- Verified: generated 3 puzzles with `--require RC`, all containing valid RC constraints
- Note: `generateAllParameters` uses signature `(width, height, domain, excludedIndices)`

### ✅ 4. Display widget (left-side bar)

**File**: `lib/widgets/row_count.dart` (new)

- `RowCountWidget` created, mirrors `ColumnCountWidget` style exactly
- Displays digit in greyed circle, color matches constraint color

**File**: `lib/widgets/puzzle.dart`

- Left-side RC bar implemented:
  - Grid area wrapped in `Row` with two children:
    - Left `Column`: RC indicators (one `RowCountWidget` per row, or `SizedBox` if no RC)
    - Right `Column`: existing CC row + grid
  - Map `rcByRow` built similar to `ccByColumn`
  - `constraintIsInTopBar` updated: RC is NOT included (displayed on left side, not in top bar)
  - Left-side RC widgets receive `_constraintKey` when highlighted

### ✅ 5. `to_flutter.dart` mapping

**File**: `lib/getsomepuzzle/constraints/to_flutter.dart`

- Import added for `RowCountConstraint` and `RowCountWidget`
- Mapping added: `if (constraint is RowCountConstraint) return _rowCountWidget(...)`
- `_rowCountWidget` function created at end of file

### ✅ 6. Help text (localization)

**Files**: `lib/l10n/app_en.arb`, `app_fr.arb`, `app_es.arb`

English:
- `"constraintRowCount": "cells per row"`
- `"constraintExplainRC": "A circled number to the left of a row tells how many cells of that color must appear in this specific row."`

French:
- `"constraintRowCount": "cells per row"`
- `"constraintExplainRC": "Un nombre dans un cercle à gauche d'une ligne indique combien de cellules de cette couleur doivent apparaître dans cette ligne précise."`

Spanish:
- `"constraintRowCount": "células por fila"`
- `"constraintExplainRC": "Un número dentro de un círculo a la izquierda de una fila indica cuántas celdas de ese color deben aparecer en esa fila específica."`

Regenerated with `flutter gen-l10n`.

### ✅ 7. Tests

**File**: `test/row_count_test.dart` (new)

All tests pass (19 tests):
- `verify` complete: correct/incorrect → true/false
- `verify` partial reachable: count not exceeded → true
- `verify` partial unreachable: `have + free < count` → false
- `apply` — color saturated: free cells become opposite
- `apply` — free cells == remaining need: forced to color
- `apply` impossible: count exceeded → isImpossible
- `serialize` round-trip
- `generateAllParameters`: correct count
- `isCompleteFor`: row filled + verify true
- RC + CC interaction: unique solution by propagation alone

## Generator diversity note

RC and CC are semantically siblings. Consider treating them as a single family in the
constraint diversity shuffle (lower re-use penalty between RC and CC than between two
entirely different types), so the generator naturally proposes RC+CC combinations
rather than doubling up on one axis.

## Changes since original document

- ✅ `RowCountConstraint` now extends `LineCentricConstraint` (base class shared with CC)
  - `getIdx()` and `getLine(Puzzle)` replace direct field access
  - Inherited fields: `color`, `count` (from `LineCentricConstraint`)
- ✅ `generateAllParameters` takes `excludedIndices` parameter (for DF support)
- ✅ Registry uses tuple-like structure with named fields
- ✅ Generator uses registry dynamically (no manual integration needed)
- ✅ UI: RC displayed in left-side bar (not in top bar)
- ✅ `to_flutter.dart` mapping implemented
- ✅ `toHuman()` method implemented
- ✅ Tests implemented per CLAUDE.md invariants
- Note: `constraintIsInTopBar` keeps its name (RC handled separately in left bar)
