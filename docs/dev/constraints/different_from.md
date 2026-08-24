# Different From Constraint

The Different From constraint (`DF`) links two orthogonally adjacent cells and
requires them to hold **different values** in the solved puzzle.

It is **colour-agnostic** — it constrains the *relationship* between the two
cells, not any specific colour. `referencedColors` returns the empty set (same
as `PA`, `GS`, `LT`, `SY`).

`families.dart` maps `'DF' → 'local'` (alongside `FM`, `NC`, `EY`).

## Syntax

`DF:idx.direction` (slug:anchorIdx.direction). `idx` is the anchor cell; the
partner is its immediate neighbour:

- `right` — the cell at `idx + 1` (same row, next column);
- `down` — the cell at `idx + width` (next row, same column).

`DF:5.right` — cells 5 and 6 must differ. `DF:1.down` on a 4-wide grid — cells
1 and 5 must differ.

## Parameter generation

`generateAllParameters` emits every `right` pair (for `col < width - 1`) and
every `down` pair (for `row < height - 1`), then applies a domain-dependent
readonly filter (`excludedIndices` = the set of readonly/prefilled cells when
the generator calls us):

- **2-colour domain**: a DF where ONE side is readonly collapses the other
  side instantly (`removeOption: readonly.value` leaves a single option) —
  the deduction is trivial, so only pairs with **both sides free** are kept.
- **3+ colours**: the same DF leaves the free cell with 2 options — a proper
  partial deduction and real gameplay — so pairs with one readonly side are
  kept. Pairs where **both** cells are readonly are still dropped: they
  either violate `verify(solved)` (same values) or are trivially satisfied
  (different values, no propagation possible).

## Semantics

### verify

- Either cell free → `true` (relationship not yet determined).
- Both filled → `true` iff the values differ.

### apply

- Both cells filled:
  - same value → `Impossible`;
  - different values → `null` (satisfied).
- Exactly one cell filled: prune the filled cell's value from the free
  cell's options (`RemoveOption`, complexity 0), guarded on the option
  still being present — re-emitting a `removeOption` for an already-pruned
  colour is a no-op the solve loop would livelock on (only reachable on
  3+ colour domains; on 2 colours a prune collapses the cell to a value).

### isCompleteFor

`verify` holds and the two cells' option sets are disjoint — the values can
never become equal, so the constraint is decided even before both cells are
filled.

## Rotation

`rotated` remaps the pair 90° clockwise and **re-anchors** it:

- `right` at idx (pairs `(c, r)` with `(c+1, r)`) becomes `down` at the
  rotated idx — the pair is now vertical, anchored at the top cell.
- `down` at idx (pairs `(c, r)` with `(c, r+1)`) becomes `right` at the
  rotation of the original `down` neighbour (`idx + width`) — the pair is now
  horizontal, re-anchored on the left cell.

So `right ↔ down` under each rotation, and four rotations return to the
original anchor and direction.

## Implementation

**Location**: `lib/getsomepuzzle/constraints/different_from.dart`

`DifferentFromConstraint extends CellsCentricConstraint` (anchor stored in
`indices.first`). Fields: `direction` (String, `'right'` or `'down'`).

- **`slug`** → `'DF'`
- **`serialize()`** → `'DF:${indices.first}.$direction'`
- **`toString()`** → `'≠'`; **`toHuman()`** → `'<idx+1> ≠ <nidx+1>'`.
- **`getNeighborIndex(width)`** — `idx + 1` for `right`, `idx + width` for
  `down`.

Registered in `constraintRegistry` (`lib/getsomepuzzle/constraints/registry.dart`)
with `fromParams: DifferentFromConstraint.new`. `DF` is introduced in
onboarding phase 6 (after `EY`, before `LT`).

## Display

Unlike most constraints, `DF` has **no in-cell widget**: `cell.dart` excludes
`DifferentFromConstraint` (like `ImplicationConstraint`) from in-cell widget
rendering, so it does not shrink the other in-cell widgets. Instead it is
drawn as a `≠` glyph by the `DifferentFromPainter` overlay
(`lib/widgets/different_from_painter.dart`), painted in
`puzzle_grid_stack.dart` between the cell table and the
`MajorityZonePainter` overlay.

l10n: `constraintDifferentFrom` (name), `constraintExplainDF`
(first-contact help). Editor entry: `showDifferentFromDialog`
(`lib/widgets/create_page/dialogs/different_from_dialog.dart`), which skips
the dialog entirely when only one direction is valid (edge cells) and
otherwise asks the player to pick a direction.

## Tests

- `test/constraints_test.dart` — `DifferentFromConstraint.verify` (different
  values valid, same values invalid), `apply` no-op-livelock regression for
  already-pruned colours.
- `test/is_complete_test.dart` — `isCompleteFor` (not complete while cells
  are empty or a shared option remains).
- `test/rotation_test.dart` — direction cycles via anchor shift; both
  `5.right` and `1.down` return to themselves after four rotations.
- `test/registry_test.dart` — `collapseMergedRules` leaves unmapped slugs
  like `DF` unchanged.
