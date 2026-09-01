# Mirror Constraint

The Mirror constraint (`MI`) splits the grid in two along a straight line and
requires **both halves to contain the same number of cells of a chosen colour**:
the two halves are count-balanced.

It is a *global* rule — no anchor cell, no line, no group — in the same family
as the Quantity constraint (`families.dart` maps `'MI' → 'global'`).

## Syntax

`MI:color.direction`. `color` is a digit (`1` = black, `2` = white,
`3` = purple); `direction` is `H` (horizontal mirror, balancing the top half
against the bottom half) or `V` (vertical mirror, balancing the left half
against the right half).

`MI:1.H` — the top half and the bottom half must contain the same number of
black cells.

## Direction / dimension rules

- **`H` requires an even height** — the grid is split between the top
  `h/2` rows and the bottom `h/2` rows.
- **`V` requires an even width** — the grid is split between the left
  `w/2` columns and the right `w/2` columns.
- The constraint type is therefore only available on puzzles with at least
  one even dimension. On an odd×odd grid `generateAllParameters` returns
  nothing and MI is never generated.

There is **no coexistence restriction**: any number of MI constraints of any
colour and direction may share a puzzle (`conflictsWith` is not overridden).

## Parameter generation

`generateAllParameters` emits `H` for every domain colour when the height is
even, and `V` for every domain colour when the width is even. So an even×even
grid yields `2 × domain.length` parameters (e.g. `{1.H, 2.H, 1.V, 2.V}` on a
2-colour domain), an even×odd grid `domain.length` `H`-only parameters, and an
odd×even grid `domain.length` `V`-only parameters.

## Semantics

### Half geometry

- Horizontal: a cell `idx` is in the bottom half iff
  `idx >= width * (height ~/ 2)`.
- Vertical: a cell `idx` is in the right half iff
  `idx % width >= width ~/ 2`.

`height` / `width` are even whenever the constraint is used.

### verify

- While any free cell still has `color` in its options, the constraint is
  **undecided** → returns `true` (even if the current counts are unequal; a
  future cell could still rebalance them).
- A free cell with `color` pruned out of its options counts as decided (it can
  never become `color`).
- Once no live cell remains: `true` iff the two halves hold equal numbers of
  `color` cells.

### apply

Exactly two rules, checked in order (one move per `apply` call — the
propagation loop re-invokes until `null`). Both are complexity tier 1
("Local counting").

1. **Generalized saturation.** When the deficient half's deficit equals the
   number of its own free cells that still have the colour option, those cells
   must all take the colour → `SetValue` on the first such cell. (This is the
   QA-style generalization of the literal "exactly one free cell" rule: it
   fires whenever the remaining free cells in the half are *forced* to be
   colour, one cell per `apply` call. It never fires unsoundly.)
2. **Equal counts, one closed half.** When the counts are equal and one half
   has no live cells left while the other still does, every remaining live cell
   in the open half must *not* take the colour → `RemoveOption` on the first
   such cell.

There are no `Impossible` branches: the spec defines only these two rules.
A contradiction (unequal final counts) surfaces via `verify` once no live
cells remain.

### isCompleteFor

`verify` holds **and** no free cell still has `color` in its options. When
`verify` is true with no live cells, the counts are equal and `apply` can never
fire → complete.

## Implementation

**Location**: `lib/getsomepuzzle/constraints/mirror.dart`

`MirrorConstraint extends Constraint` (not `CellsCentricConstraint` — it has no
indices). Fields: `color` (CellValue), `direction` (String, `'H'`/`'V'`).

- **`slug`** → `'MI'`
- **`serialize()`** → `'MI:${cellValueToString(color)}.$direction'`
- **`toString()`** → `'<direction> <color>'` (e.g. `"H 1"`)
- **`referencedColors`** → `{color}` (the target colour, explicitly).
- **`rotated(...)`** — flips the axis: a 90° clockwise rotation turns a
  horizontal mirror into a vertical one (`H → V`, `V → H`). A 2-cycle, so
  four rotations return to the original.

Registered in `constraintRegistry` (`lib/getsomepuzzle/constraints/registry.dart`)
with `fromParams: MirrorConstraint.new` and
`generateAllParameters: MirrorConstraint.generateAllParameters`, alphabetically
between `LT` and `QA`.

## Display

`MirrorWidget` (`lib/widgets/constraints/mirror.dart`) renders the constraint
in the **top bar above the grid** (`lib/widgets/puzzle.dart`), not inside a
cell — alongside the other non-cell top-bar constraints (`QA`, `FM`, `GC`,
`BB`, `CH`, `IS`). No branch is needed in `to_flutter.dart`; that dispatcher
is used for in-cell constraint indicators, while MI has its dedicated top-bar
widget.

The icon is a mini-grid of the `01100011` pattern (the 8 bits laid out
row-major over 4 rows × 2 cols), split by a mirror line:

- **`H` form** (base): portrait, 4 rows × 2 cols, with a horizontal line
  between rows 2 and 3.
- **`V` form**: the same widget rotated 90° clockwise, so it reads landscape
  (2 rows × 4 cols) with a vertical line.

Filled cells use the chosen colour (or grey when the constraint is satisfied
and not highlighted); the mirror line uses the valid-colour highlight.

l10n: `constraintMirror` (name), `constraintExplainMI` (first-contact help),
`mirrorHorizontal` / `mirrorVertical` (direction selector labels). Editor
entry: `showMirrorDialog`
(`lib/widgets/create_page/dialogs/mirror_dialog.dart`) — a colour picker over
the full domain (no once-per-colour limit) plus two direction chips gated on
the grid dimensions (`H` disabled when the height is odd, `V` disabled when
the width is odd).

## Tests

- `test/mirror_test.dart` — serialize/parse (incl. v2-line round-trips and
  coexistence parsing), `generateAllParameters` cardinality per dimension
  parity, `verify` gating (live cells / decided balance / decided imbalance /
  pruned-option cells), both `apply` rules (generalized saturation loop,
  single-live-cell deficit, equal-counts prune, vertical orientation, null
  cases), `isCompleteFor`, coexistence of H+V and different colours, `rotated`
  axis flip + 4-fold identity, and solver smokes over v2 lines.
- `test/rotation_test.dart` — MI in the 4-fold identity per-slug group.
- `test/families_test.dart`, `test/registry_test.dart`,
  `test/constraint_icons_ui_test.dart` — guard tests that auto-cover MI.
