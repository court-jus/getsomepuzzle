# Majority Constraint

Constraint slug `MJ`. Serialised as
`MJ:r0.c0.r1.c1.color` — the rectangular zone delimited by rows
`r0..r1` and columns `c0..c1` must contain a strict majority of cells
of `targetColor` (more than half the cells in the zone).

A puzzle can carry several MJ constraints over overlapping or disjoint
zones, building a system of local inequalities on the affected cells.

## Syntax

- `MJ:0.0.1.2.1` — the 2×3 rectangle (rows 0–1, columns 0–2) must have
  more black cells (colour 1) than white. 6 cells → black needs ≥ 4.
- `MJ:0.0.2.0.2` — the first column (rows 0–2, column 0) must have more
  white cells (colour 2) than black. 3 cells → white needs ≥ 2.

**Zone size**: any size, odd or even. The target is always
`floor(zoneSize / 2) + 1`:
- Even zone (e.g. 6 cells): target = 4 (strict majority over 3 each).
- Odd zone (e.g. 5 cells): target = 3 (majority of 5, since 3 > 2).

## Display

MJ is rendered as a **dotted rectangle border** inset slightly inside
the zone's bounding box. No icon or digit — the dotted border alone
identifies the constrained zone.

- **Style**: dotted, same stroke thickness as the readonly cell border.
- **Position**: inset from the zone's outer edge (base 6 px) so the
  border sits inside the zone rather than overlapping cell grid lines.
  When two zones would draw **overlapping borders** (see Conflicts
  below), the inset is increased per zone so their borders nest at
  distinct depths instead of coinciding.
- **Corners**: square (matches the grid's rectilinear aesthetic and
  distinguishes MJ from readonly cell highlights, which use rounded
  borders).
- **Fill**: none (cells stay fully visible). A faint tinted fill is
  reserved for the highlighted state only.
- **Colour** encodes constraint state:
  - **Neutral** — `targetColor` (black for colour 1, white for
    colour 2). The border colour itself tells the player which colour
    must dominate, replacing the need for an icon.
  - **Valid** — green (zone complete and majority holds).
  - **Invalid** — red (zone complete but majority violated, or
    impossible state).
  - **Highlighted** — `highlightColor` (low-opacity tinted fill while
    the constraint is being hinted).
  - **Grayout** — grey / semi-transparent (constraint complete, no
    further deductions; see `grayout.md`).

MJ is rendered exclusively as a grid overlay; it does **not** appear in
the top constraint bar. The hint arrow originates from the **centre of
the zone** when MJ is highlighted.

The editor's constraint-type picker previews MJ as a single cell with a
dotted border (a size-1 majority zone) — see
`_MajorityPreviewPainter` in
`lib/widgets/create_page/dialogs/constraint_type_picker.dart`.

## Border conflicts

Two MJ zones whose dashed borders would be drawn **on top of each
other** are hard to read. This happens only when the rectangles share a
**flush edge on the same side** — same top row (`r0 == r0`), same bottom
row (`r1 == r1`), same left column (`c0 == c0`) or same right column
(`c1 == c1`) — **and** overlap along that edge (perpendicular extent
overlaps). Both borders then inset to the same place. By contrast, mere
adjacency (a shared grid line with the zones on opposite sides) insets
the borders into distinct cells, and a corner-only touch makes the
borders simply cross; neither is a conflict.

`MajorityConstraint.conflictsWith(other)` encodes exactly this predicate
and is the single source of truth, reused three ways:

- **Rendering** (`MajorityZonePainter`) — nests conflicting borders at
  distinct insets so they stay readable (acceptable for user-authored
  puzzles, which can still contain conflicts).
- **Generation** — the generator (`generator.dart`) and `Puzzle.simplify`
  reject a candidate MJ that conflicts with any already-placed
  constraint, so newly generated puzzles never contain a conflict.
- **Corpus cleanup** — `bin/cleanup_collections.dart --mj-conflict`
  (part of the default passes) drops existing corpus puzzles that carry
  a conflicting MJ pair.

## Gameplay deductions

MJ tracks "this colour must hold at least `target`" inside the zone.

### Native deductions

1. **Free cells == remaining need** — when
   `freeCount == target - currentCount` (just enough free cells to
   reach majority), every free cell must be `targetColor`. This is the
   **only** deduction MJ produces on its own.
2. **Opposite colour takes the lead** — when
   `oppositeCount > zoneSize - target` (i.e. the opposite colour
   already reaches `floor(zoneSize/2) + 1`), the state is impossible.

### Undeduced states

Two common states produce no deduction:

- **Target already has majority** (`currentCount >= target`) — the
  zone is already satisfied; future cells can take either colour.
- **More than enough space** (`currentCount + freeCount > target`) —
  the target colour has room to grow without every free cell being
  forced.

### Cross-constraint interactions

- **Overlapping MJ zones** — each zone is an inequality with slack;
  the solver and the player must reason about worst-case bounds rather
  than solving a linear system. Example: zone A requires black
  majority in `{cells 0–5}`, zone B requires white majority in
  `{cells 3–8}` — the overlap `{cells 3–5}` is contested and the
  allocation usually forces specific cells outside the overlap to
  compensate.
- **QA synergy** — QA constrains the total count of a colour on the
  whole grid, MJ constrains the local count. Together they bound the
  count everywhere else: `globalTarget - zoneTarget` cells of the
  target colour must go outside the zone, and the free cells outside
  must accommodate them.

## Implementation pointers

- **`lib/getsomepuzzle/constraints/majority.dart`** —
  `MajorityConstraint` (fields `r0`, `c0`, `r1`, `c1`, `targetColor`).
  - `indicesFor(int width)` returns the sorted list of cell indices
    inside the rectangle (row-major, cached after first call).
  - `zoneSize = (r1 - r0 + 1) * (c1 - c0 + 1)` and
    `target = zoneSize ~/ 2 + 1`.
  - `serialize()` → `'MJ:$r0.$c0.$r1.$c1.$targetColor'`.

  `verify` checks:
  - on a complete puzzle, `targetColorCount >= target`;
  - otherwise still-reachable iff
    `targetColorCount + freeCount >= target` **and**
    `oppositeCount <= zoneSize - target`.

  `apply` returns:
  - `isImpossible` when `oppositeCount > zoneSize - target` or
    `currentCount + freeCells.length < target`;
  - `Move(freeCells.first, targetColor, complexity: 0)` when
    `currentCount + freeCells.length == target` (every free cell must
    be `targetColor`);
  - `null` otherwise.

  `isCompleteFor` returns `true` iff `verify(puzzle)` holds and every
  cell of the zone is non-free (monotone: once the zone is filled, no
  future move can change it).

  `conflictsWith(other)` returns `true` (overriding the base `false`)
  when `other` is another `MajorityConstraint` whose borders would draw
  on top of this one — see **Border conflicts** below.

- **`generateAllParameters(width, height, domain, excludedIndices)`** —
  enumerates every axis-aligned rectangle with three upfront filters:
  - `zoneSize < 3` excluded (no strict majority on 1 or 2 cells);
  - single-row / single-column zones excluded (they overlap too much
    with RC / CC);
  - zones covering more than 60 % of the grid excluded (they overlap
    too much with QA; this also subsumes the full-grid case).

  Surviving sweet spots: 2×2, 2×3, 3×3, 3×4 rectangles.

- **`lib/getsomepuzzle/constraints/registry.dart`** — registered
  between GC and NC.

- **`lib/widgets/majority.dart`** — `MajorityZonePainter` (a
  `CustomPainter`) renders the dotted rectangle. Base inset 6 px,
  `strokeWidth` matching the readonly cell border, dashed path effect.
  MJ widgets live in the grid's `Stack` layer on top of the grid but
  below cell tap targets. Before drawing, the painter computes a
  **nesting level** per zone by greedy graph-colouring of the conflict
  graph (`conflictsWith`): conflicting zones get distinct levels and
  their inset grows by a `cellSize`-scaled step per level (capped at
  `cellSize * 0.45`), so overlapping borders nest at different depths
  instead of coinciding. Non-conflicting zones keep the base 6 px inset
  and simply cross visually.

- **`lib/widgets/create_page/create_page.dart`** — MJ zones are
  authored via a **two-tap mode** (analogous to LetterGroup): first
  tap opens a colour dialog and enters zone mode, second tap closes
  the rectangle. A SnackBar (`createZoneTooSmall`) rejects rectangles
  with fewer than 3 cells. The AppBar title becomes
  `createSecondCorner` during zone selection; an X icon cancels.
  Tapping a cell already inside one or more MJ zones triggers
  `_showMjDeletePicker`, which lists overlapping zones by their
  `serialize()` string. Overlay rendering reuses
  `MajorityZonePainter`.

- **`lib/l10n/app_*.arb`** — `constraintMajority`,
  `constraintExplainMJ`, `createSecondCorner`, `createZoneTooSmall`
  (en/fr/es).

- **`test/majority_test.dart`** — 31 tests covering `verify`/`apply`
  branches, parity independence, serialisation, rotation, and
  `generateAllParameters` filters.

## Complexity weights

| # | Deduction | Weight |
| - | --------- | -----: |
| 1 | Free cells == remaining need → force target | 0 |
| 2 | Overlapping-zone reasoning (cross-zone inference) | 3 |

The native deduction (weight 0) is a direct counting check.
Cross-zone or MJ+QA reasoning, if implemented as a complicity, would
fall around weight 3 (typical for multi-constraint deductions).

## Design note: `indicesFor(width)` vs `CellsCentricConstraint`

`MajorityConstraint` deliberately does **not** extend
`CellsCentricConstraint`. If it did, `Puzzle.cellConstraints[idx]`
would include MJ for every cell of the zone and `CellWidget` would
fall back to rendering `'MJ'` text in every cell — visually wrong for
a zone overlay. Filtering MJ out at every consumer of
`cellConstraints` is uglier than not inheriting in the first place.

Future complicities can still reach the zone indices via the public
`indicesFor(puzzle.width)` method, which the game widget already
reuses for hint highlighting:

```dart
mjZoneHighlightIndices =
    highlightedConstraint.indicesFor(puzzle.width).toSet();
```
