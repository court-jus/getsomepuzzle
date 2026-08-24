# Quantity Constraint

The Quantity constraint (`QA`) fixes the exact **total number of cells** of a
given colour across the whole grid: in the solved puzzle, exactly `count`
cells must hold `color`.

It is a *global* rule — no anchor cell, no line, no group. It is the only
constraint in the `global` family (`families.dart` maps `'QA' → 'global'`).

## Syntax

`QA:color.count` (slug:color.count). `color` is a digit (`1` = black,
`2` = white, `3` = purple); `count` is the target number of cells of that
colour.

`QA:1.5` — exactly 5 black cells in the whole grid.

## Parameter generation

`generateAllParameters` emits `(color, count)` for every domain colour, with
`1 ≤ count < width * height - 1` (never the full grid, and never 0).

## Semantics

### verify

- Complete puzzle: valid iff the count of `color` cells equals `count`.
- Incomplete puzzle: valid iff `have ≤ count` (target not already exceeded)
  **and** `have + reachableFree ≥ count` — where `reachableFree` counts only
  free cells that still have `color` in their options (a cell that has pruned
  `color` can never raise the count).

### apply

- No free cells → `null` (nothing to do).
- `have > count` → `Impossible`.
- `have == count` — count already reached: prune `color` from every free
  cell that still has it in options (complexity 0). If no free cell still
  has `color` as an option, the count stays at target and the constraint is
  satisfied — return `null`, **not** `Impossible` (same domain-3 trap as
  SH Level 2: an already-pruned option must not be reported as a
  contradiction).
- `count - have == freeCells.length` — the remaining free cells exactly match
  the remaining need: they must all take `color`. Force the first free cell
  (`SetValue`, complexity 0); if that cell has already excluded `color`
  (3-colour puzzles), the target is unreachable → `Impossible`.

### isCompleteFor

`verify` holds, `have == count`, and no free cell still has `color` in its
options — once the count is reached and no free cell can take the colour,
the count can never change and `apply()` can never fire again.

## Implementation

**Location**: `lib/getsomepuzzle/constraints/quantity.dart`

`QuantityConstraint extends Constraint` (not `CellsCentricConstraint` — it has
no anchor). Fields: `color` (CellValue), `count` (int).

- **`slug`** → `'QA'`
- **`serialize()`** → `'QA:${cellValueToString(color)}.$count'`
- **`toString()`** → `'<color> = <count>'`
- **`referencedColors`** → `{color}` (the target colour, explicitly).
- **`rotated(...)`** — identity: purely global data, returns a fresh clone
  of self (the count and colour are position-independent).

Registered in `constraintRegistry` (`lib/getsomepuzzle/constraints/registry.dart`)
with `fromParams: QuantityConstraint.new`. `QA` is the last strict onboarding
introducer (`OnboardingPhase(index: 8, introducing: 'QA', ...)`).

## Display

`QuantityWidget` (`lib/widgets/constraints/quantity.dart`) renders the
constraint in the **top bar above the grid** (`lib/widgets/puzzle.dart`), not
inside a cell — like the other global constraints (`FM`, `GC`, `SH`, `BB`).
It shows the target count for the colour plus the live actual count.

l10n: `constraintQuantity` (name), `constraintExplainQA` (first-contact
help). Editor entry: `showQuantityDialog`
(`lib/widgets/create_page/dialogs/quantity_dialog.dart`), which reuses the
shared `showColorCountDialog` body — a colour picker plus a count slider.

## Tests

- `test/constraints_test.dart` — `QuantityConstraint.verify` (complete exact
  count, wrong count, count exceeded, reachable, unreachable).
- `test/is_complete_test.dart` — `isCompleteFor` (not complete while the
  count is unreached or a free cell can still take the colour).
- `test/find_all_moves_test.dart` — single forced move on `10` + `QA:1.1`;
  redundant-constraint dedup behaviour.
- `test/generator_test.dart` — `generateAllParameters` sanity and
  verify-after-generation.
- `test/rotation_test.dart` — identity under four rotations.
- `test/contributors_test.dart` — QA listed among a move's contributors.
