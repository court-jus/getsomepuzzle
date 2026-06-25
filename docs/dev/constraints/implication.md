# Implication Constraint

The Implication constraint (`IM`) is a directional link between two cells: **if
the source cell is a given color, the target cell must be that color too**. The
arrow points from source to target and shows which cell drives the deduction.

The implication's contrapositive is also exploited — *target ≠ color ⇒ source
cannot be that color* — and that holds on grids with any number of colors, not
only 2-color grids.

## Syntax

`IM:2.5.1` (`slug:src.tgt.color`) means: if cell `2` (0-based) is color `1`
(black), then cell `5` must also be black. `src`/`tgt` are flat cell indices,
`color` is the usual color digit (`1` black, `2` white, `3` purple).

## Display

A curved arrow drawn from the source cell center to the target cell center, as a
**background overlay** (not inside a cell). The arrow color reflects the
constraint color for quick identification (black → dark grey, purple → purple,
otherwise light grey); it turns to the highlight color when highlighted and to
semi-transparent grey on grayout. `ImplicationWidget`
(`lib/widgets/constraints/implication.dart`) is only a `→` placeholder used by
the UI registry for previews — the real rendering is the painter (see below).

## Implementation

### Constraint Class

**Location**: `lib/getsomepuzzle/constraints/implication.dart`

`ImplicationConstraint` extends `CellsCentricConstraint`. It stores the two cell
indices in the inherited `indices` list (`indices.first` = source,
`indices[1]` = target, also exposed as `targetIdx`) and the constraint `color`
(a `CellValue`).

- **`slug`** → `'IM'`
- **`referencedColors`** → `{color}`
- **constructor** `ImplicationConstraint(String strParams)` — splits on `.`,
  parses the two indices and `color` via `cellRepresentationToValue`.
- **`serialize()`** → `'IM:${indices.first}.${indices[1]}.${cellValueToString(color)}'`
- **`toString()`** → `'${src+1} → ${tgt+1} (${cellValueToString(color)})'` (1-based)
- **`toHuman(Puzzle)`** → `'$src(${cellValueToString(color)}) → $tgt'` (1-based,
  color digit — same convention as `column_count` / `majority`)
- **`rotated(origWidth, origHeight)`** — rotates both indices with
  `rotateIdx90CW`, keeps the color.
- **`verify(Puzzle)`** — returns `false` only when the implication is broken or
  unreachable:
  - both cells determined → broken iff `src == color && tgt != color`;
  - source determined to `color` while the target's options no longer contain
    `color` → unreachable.
  Otherwise reachable (a source that is `≠ color` or still free is vacuously
  satisfiable). A source *forced* to `color` is always already a determined
  value — the cell model collapses a single-option cell to its value (see
  `Cell.removeOption`), so there is no free-but-forced state to test separately.
- **`apply(Puzzle)`** — three deductions:
  - both determined and `src == color && tgt != color` → `Impossible(this)`;
  - **forward**: `src == color` → `SetValue(tgt, color)`, or `Impossible` if the
    target can no longer be `color`;
  - **contrapositive**: target determined and `≠ color` → `RemoveOption(src,
    color)` (no-op if already pruned).
- **`isCompleteFor(Puzzle)`** — `true` (grayout) when the constraint can never
  fire again: `verify` holds *and* (source determined a different color, or
  source can never be `color`, or target is already `color`).
- **`generateAllParameters(width, height, domain, excludedIndices)`** — every
  ordered `(src, tgt)` pair with `src != tgt`, neither excluded, and Manhattan
  distance ≤ 4, times each non-free domain color. The distance cap keeps arrows
  short and legible.

### Registry

`lib/getsomepuzzle/constraints/registry.dart`:

```dart
(
  slug: 'IM',
  label: 'Implication',
  fromParams: ImplicationConstraint.new,
  generateAllParameters: ImplicationConstraint.generateAllParameters,
),
```

### Family

`lib/getsomepuzzle/constraints/families.dart` maps `'IM' → 'implication'`, and
`implication` is the first entry of `kConstraintFamilies`. It is its own
deduction family (directional color link). See `docs/dev/families.md`.

### Generator integration

Enumerated like every other registered type via
`ImplicationConstraint.generateAllParameters` in
`lib/getsomepuzzle/generator/generator.dart`.

### Rendering

**Painter**: `lib/widgets/implication_painter.dart` — `ImplicationPainter`
draws, for each `ImplicationConstraint`, a cubic Bézier from source to target
center (curving toward the grid interior) with a filled arrowhead, applying the
color / highlight / grayout styling described under **Display**.

**Stacking**: the shared `PuzzleGridStack` (`lib/widgets/puzzle_grid_stack.dart`,
used by both the game `lib/widgets/puzzle.dart` and the editor
`lib/widgets/create_page/create_page.dart`) builds, inside the grid `Stack`:
1. a `CellBackgroundPainter` (`lib/widgets/cell_background_painter.dart`) that
   paints every cell's fill color behind the grid — the per-cell `DecoratedBox`
   in `cell.dart` no longer carries a fill, so arrows can sit *between* the cell
   fill and the cell borders/content;
2. the `ImplicationPainter` overlay (only when the puzzle has any `IM`);
3. the `Table` of cells (now transparent-filled);
4. the `DifferentFromPainter` / `MajorityZonePainter` overlays.

Centralising this order in `PuzzleGridStack` keeps the game and editor from
drifting apart (the editor once lost its cell backgrounds because only
`puzzle.dart` was updated when `IM` moved colouring into the painter).

`cell.dart` excludes `ImplicationConstraint` (like `DifferentFromConstraint`)
from in-cell widget rendering, so it does not shrink the other in-cell widgets.

### Editor

`lib/widgets/create_page/dialogs/implication_dialog.dart` — `showImplicationDialog`
asks for the source cell, target cell and color, fully localized via
`AppLocalizations` (en/es/fr). Wired into `create_page.dart` and
`new_constraint_dialog.dart`.

### Tests

**Location**: `test/constraints_test.dart` — groups
`ImplicationConstraint.verify`, `.apply` and `.isCompleteFor` cover the broken /
unreachable / reachable states, the forward and contrapositive deductions on
both 2- and 3-color grids, the `Impossible` cases, and the grayout signal.
`test/families_test.dart` / `test/equilibrium_test.dart` assert the resulting
six-family composition count (156), and `test/onboarding_test.dart` includes
`IM` in the slug set.
