# Rectangular Groups Constraint

The Rectangular Groups constraint (`RE`) marks a single cell. In the solved puzzle,
the connected same-colour group containing that cell must be a **non-square
rectangle**: the group fills its own bounding box exactly — no holes, no
indentation — and its width differs from its height.

`RE` constrains the **fill, not the extent**. Unlike `BB` (which fixes the exact
`W×H` extent of every group of a colour, allowing hollow shapes), `RE` accepts a
solid rectangle of *any non-square* size: a `1×2` group satisfies `RE` just as
a `3×4` one does, while a `1×1` or `2×2` group never does. The rule is
anchored — it applies only to the group of
the marked cell, never to other same-colour groups in the grid.

`RE` is colour-agnostic (`referencedColors` is empty) and belongs to the
`group-topology` family.

## Syntax

`RE:idx`, for example `RE:5`. `idx` is the zero-based index of the marked cell in
the serialized v2 line. A constraint carries exactly one index.

## Semantics

### verify

Returns `false` only when the state is broken now or has become unreachable:

- **free anchor** → valid iff the puzzle is incomplete (a free cell has no group
  yet; on a complete puzzle this branch is defensive, since every cell is
  coloured);
- **anchor with no group** → same defensive `!puzzle.complete` fallback;
- otherwise, for every cell inside the group's bounding box (`_bounds`):
  - **complete puzzle** → the cell must have the group's colour, else `false` (a
    hole breaks the rectangle);
  - **incomplete puzzle** → a set cell of a different colour breaks the box now →
    `false`; a free cell must still carry the colour in its options, otherwise
    the box can never fill → `false`.

- **square bounding box** → rejected unless the group can still grow out of
  squareness. On a complete puzzle a square box is always `false`; on an
  incomplete one it passes only if the box still has a fillable free cell or a
  free neighbour of the group still carries the colour. A square box spanning
  the whole grid can never grow → always `false`.

### apply

Returns `null` while the anchor is free. Otherwise, on the group of the marked
cell, two passes:

1. **Fill the box, or fail** (`complexity 1`). Scan the bounding box row-major:
   a set cell of another colour, or a free cell that can never take the group's
   colour, → `Impossible(this)`. The first free box cell → `SetValue` to the
   group's colour.
   A square box that is full and cannot grow (no free neighbour still carrying
   the colour) is unrecoverable → `Impossible(this)`.
2. **Prune overhanging expansions** (`complexity 2`). After pass 1 the box is
   full, so every free neighbour of the group lies *outside* the box. Colouring
   such a neighbour would expand the box; simulate the expanded box, and if it
   newly includes a cell that is set to a different colour or is free but
   colour-pruned, the expansion can never form a rectangle → `RemoveOption(
   neighbour, colour)`. Expansions that overhang only fillable free cells stay
   legal — the group may legitimately grow there.
   A growth that would make the box square while spanning the whole grid can
   never grow out of squareness → `RemoveOption(neighbour, colour)`.

`apply` never forces growth: a group that is already a non-square rectangle
satisfies `RE`, so there is nothing to force until the puzzle provides a reason.

### isCompleteFor

Conservative grayout — `true` only when the anchor is coloured, `verify` holds,
every bounding-box cell is set to the group's colour (box full, no holes), and
no free neighbour of the group still carries the colour in its options (the
group is closed: it can neither grow nor merge), and the bounding box is not
square (a square box is never a final shape, even while it could still grow).

## Display

`RectangularGroupsWidget` renders a small blue rectangle in the cell's top-right
corner: length 1/3 of the cell, short side 1/4, 5% margin from the corner.
Default colour is the theme blue (`PuzzleColors.mandatory`); red
(`PuzzleColors.constraintInvalid`) appears only in the invalid state; grey when
grayed out; the highlight colour while highlighted. The marker is cell-anchored,
routed through `constraintToFlutter` and sized at `cellSize / count` where
`count` is the number of constraint markers sharing the cell.

## Integration

- Model: `lib/getsomepuzzle/constraints/rectangular_groups.dart`
- Engine registry: `lib/getsomepuzzle/constraints/registry.dart`
  (`slug: 'RE'`, `fromParams: RectangularGroupsConstraint.new`)
- Render routing: `lib/getsomepuzzle/constraints/to_flutter.dart`
  (`_rectangularGroupsWidget`)
- Widget: `lib/widgets/constraints/rectangular_groups.dart`
- UI registry: `lib/widgets/constraints/registry.dart` — preview built from
  `RectangularGroupsConstraint('0')`, display name `constraintRectangularGroups`,
  first-contact help `constraintExplainRE`
- Localization: `constraintRectangularGroups` and `constraintExplainRE`
  (en/es/fr)
- Editor: `lib/widgets/create_page/create_page.dart`,
  `_pickAndAddConstraint` case `'RE'` — adds
  `RectangularGroupsConstraint('$cellIdx')` on the tapped cell, no dialog.

## Family

`families.dart` maps `'RE' → 'group-topology'` (alongside `GS`, `GC`, `IS`, `SH`,
`SY`, `MJ`, `BB`, `SZ`). See `docs/dev/families.md`.

## Tests

`test/rectangular_groups_test.dart` — `verify` (non-square rectangle passes,
square group fails, white hole in the bounding box fails, fillable incomplete
box → true, colour-pruned box cell → false, free anchor → true); `apply`
(box-fill `SetValue`, wrong-colour cell inside the box → `Impossible`, full
square box without growth options → `Impossible`, overhang prune
`RemoveOption`, growth into a whole-grid square pruned, fillable expansion left
alone, free anchor → null); `isCompleteFor` (full closed non-square rectangle →
true, square group → false, open neighbour → false, partial
box → false); serialization (`RE:5` round-trip, `createConstraint` parse),
`generateAllParameters` (one param per cell) and `rotated` (anchor index remapped
90° CW).

## Not yet implemented

- **No reachability / articulation tiers** — deductions are capped at
  `complexity 2` (direct fill, local-spatial prune). Unlike `BB`, there is no
  pinned-box or cut-cell pass; a non-square rectangle of any size satisfies
  `RE`, so there
  is no target extent to pin against.
- **No cross-constraint reasoning** — each `RE` reasons only about its own
  group. Two `RE` anchors whose groups would have to merge (or a future merge
  that would turn a rectangle non-rectangular) are left to the backtracking
  solver.
