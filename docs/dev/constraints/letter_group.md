# Letter Group Constraint

The Letter Group constraint (`LT`) assigns a *letter* to a set of cells and
requires that all cells sharing that letter end up in the **same connected
group of a single colour**. Two cells carrying different letters can never
belong to the same group, so distinct letters repel each other.

This is the routing primitive behind path-based puzzles — see
[`path_based.md`](../path_based.md) for the generation pipeline that builds
topologies around it.

## Syntax

`LT:A.3.7` (slug:letter.idx.idx…) means cells `3` and `7` carry the letter
`A` and must share one same-colour group. A letter may anchor any number of
cells: `LT:B.0.4.9`.

## Display

The letter is drawn as text inside each member cell, in the colour the cell
ends up taking (`to_flutter.dart` → `_textWidget(constraint.letter, …)`).

### Letter `I` is excluded

The label `I` is **never produced**: rendered inside a cell it is visually
indistinguishable from the vertical-symmetry (`SY`) glyph. The label loop in
`generateAllParameters` simply `continue`s on the `'I'` slot (`l == 8`,
charCode 73), so the sequence is `A, B, …, H, J, K, …`. On small grids `I`
was already out of reach, but `maxLetters = size ~/ 5` could otherwise
surface it from `size ≥ 45` (e.g. a 9×5 grid). The exclusion is asserted by
a regression test in `test/generator_test.dart`.

## Implementation

### Constraint Class

**Location**: `lib/getsomepuzzle/constraints/letter_group.dart`

`LetterGroup` extends `CellsCentricConstraint`. Fields: `letter` (String),
`indices` (the cells carrying that letter).

- **`slug`** → `'LT'`
- **`serialize()`** → `'LT:$letter.${indices.join(".")}'`
- **`rotated(...)`** — re-maps each index 90° clockwise, keeping the letter.
- **`verify(Puzzle)`** — Aggregation in `Puzzle` guarantees a single
  `LetterGroup` per letter, so `indices` already lists every cell sharing it
  (`addConstraint`/`prependConstraint` apply the same merge-on-add mechanism
  to same-axis `PA` constraints — see [`parity.md`](parity.md)).
  Returns `false` when two fixed members hold different colours (unreachable),
  or when a complete state splits the members across more than one group, or
  when a foreign-letter cell shares a member's group. A reachable-but-partial
  state returns `true`.
- **`apply(Puzzle)`** — Five layered deductions:
  1. Every member must take the group colour; an opposite-coloured member is
     a contradiction.
  2. A foreign-letter cell touching the group cannot take the group colour
     (it would merge two letters).
  3. Feasibility: the members must all fit one *virtual group* of group
     colour + empty cells, else `isImpossible`.
  4. Articulation points: any empty cell whose blocking would disconnect the
     members must take the group colour (complexity 4).
  5. Free neighbours of the group that also touch another letter's
     same-colour cells cannot take the group colour.
- **`isCompleteFor(Puzzle)`** — `verify` holds, all members are coloured and
  form a single group, and no foreign-letter cell is reachable from that group
  through cells of value `groupColor` or `free` (a `canReach` flood). Once the
  members are linked and no other letter can still be bridged in, no `apply`
  branch can fire again; the flood's traversable set only shrinks as cells are
  coloured, so the criterion is monotone. Free neighbours no longer block
  grayout as long as they cannot reach another letter.
- **`generateAllParameters(width, height, domain, excludedIndices)`** — emits
  two-cell `letter.idx1.idx2` triples for every ordered cell pair and every
  letter `0..maxLetters-1` (`maxLetters = max(1, size ~/ 5)`), skipping the
  `'I'` slot.

### Registry

`lib/getsomepuzzle/constraints/registry.dart`:

```dart
(
  slug: 'LT',
  label: 'Letter',
  fromParams: LetterGroup.new,
  generateAllParameters: LetterGroup.generateAllParameters,
),
```

### Widget

Rendered as cell-centric text by `to_flutter.dart`; there is no dedicated
widget file — the shared `_textWidget` draws the single letter.

### Tests

- `test/generator_test.dart` — `generateAllParameters` cardinality and the
  `'I'`-exclusion regression test.
- `test/letter_group_aggregation_test.dart` — per-letter aggregation into a
  single `LetterGroup` instance.
