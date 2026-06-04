# Parity Constraint

The Parity constraint (`PA`) anchors on one cell and requires the cells on a
given **side** of that anchor (along its row or column) to hold as many even
values as odd values. Only sides with an even number of cells can carry the
constraint — an odd-sized side can never balance.

## Syntax

`PA:12.top` (slug:anchorIdx.side). The `side` parameter takes six values:

- `left`, `right`, `top`, `bottom` — one balanced side of the anchor;
- `horizontal` — `left` **and** `right`, each balanced independently;
- `vertical` — `top` **and** `bottom`, each balanced independently.

`_getSideCells` builds one independent cell list per direction, so the
axis-wide variants are exactly the conjunction of their two halves:
`vertical ⟺ top ∧ bottom`, `horizontal ⟺ left ∧ right`.

## Same-axis merging

Because of that conjunction, two `PA` constraints sharing an **anchor** and
an **axis** are a single constraint in disguise: `top` + `bottom` is
`vertical`, and a half-side next to its axis-wide form (`vertical` +
`bottom`) is redundant. `Puzzle.addConstraint` / `prependConstraint`
(`lib/getsomepuzzle/model/puzzle.dart`) merge them on every add — parse,
generation and simplification paths alike — the same mechanism as the
per-letter `LetterGroup` aggregation (see
[`letter_group.md`](letter_group.md)). The invariant is **one `PA` per
(anchor, axis)**; cross-axis pairs (`left` + `top`) and distinct anchors
stay separate.

The side algebra lives in `ParityConstraint.mergeSides(a, b)`
(`lib/getsomepuzzle/constraints/parity.dart`): returns the merged side for
same-axis inputs, `null` otherwise.

`canonicalPuzzleKey` re-serializes every rotation-orbit member from a parsed
`Puzzle`, so a legacy line carrying the split form and its merged rewrite
share one stats key (see the canonical-key section of
[`puzzle_orientation.md`](../puzzle_orientation.md)).

## Implementation

**Location**: `lib/getsomepuzzle/constraints/parity.dart`

`ParityConstraint` extends `CellsCentricConstraint`. Fields: `indices` (the
single anchor index), `side` (String).

- **`slug`** → `'PA'`
- **`serialize()`** → `'PA:${indices.first}.$side'`
- **`rotated(...)`** — re-maps the anchor 90° clockwise and rotates the side
  (`left→top`, `top→right`, `horizontal→vertical`, …).
- **`verify(Puzzle)`** — for each side list: `false` once one parity exceeds
  half the side (the target is unreachable), or when a fully-filled side is
  unbalanced; reachable-but-incomplete states return `true`.
- **`apply(Puzzle)`** — when one parity reaches half the side, the remaining
  free cells must take the other parity; both-parities-over-half is
  `isImpossible`. Complexity weight scales with the longest side covered
  (2 cells → 0, 4 → 1, 6+ → 2).
- **`isCompleteFor(Puzzle)`** — `verify` holds and every side cell is filled.
- **`generateAllParameters(...)`** — emits each side value whose cell count
  is even and non-zero; the axis-wide variants require both halves valid.

### Display

`toString()` maps the side to an arrow glyph (`⬅ ⮕ ⬆ ⬇ ⬌ ⬍`) drawn in the
anchor cell.

### Tests

- `test/parity_merge_test.dart` — `mergeSides` truth table, merge through
  `addConstraint`/`prependConstraint`, non-merge cases (cross-axis, distinct
  anchors).
- `test/canonical_test.dart` — split form and merged form share a canonical
  key.
