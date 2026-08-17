# Bounding Box Constraint

The Bounding Box constraint (`BB`) fixes the exact bounding-box dimensions every
connected group of a given color must occupy in the solved puzzle: **each group
of the color must span exactly W columns and H rows** — its smallest enclosing
axis-aligned rectangle is exactly `W×H`.

It is a *global* rule: like `GroupCount` (`GC`) it applies to **every** group of
the color, not to one anchored cell. It constrains a group's **extent, not its
fill** — a hollow connected shape that reaches all four sides of a `W×H`
rectangle satisfies `BB` even when interior cells hold other colors (e.g. the
ring `101.111.101` satisfies `BB:1.3.3`). Reasoning is always per **connected
group**, never per rectangle: two groups may even have overlapping / interlocking
bounding boxes, as long as no two same-color cells of *different* groups are
orthogonally adjacent.

## Syntax

`BB:1.3.3` (`slug:color.width.height`) means every connected group of color `1`
(black) must have a bounding box exactly **3 wide and 3 tall**. `color` is the
usual color digit (`1` black, `2` white, `3` purple). The field order is **width
then height** — `BB:1.2.3` is 2 wide and 3 tall.

⚠️ The width-first order is consistent across `serialize()` (`.$width.$height`),
`rotated()` (swaps to `.$height.$width`) and `toString()`/`toHuman()` (render
`W×H`). The internal `_bbHW` helper is the one place that returns
`(height, width)` (the matrix row-span-first convention) — keep that distinction
in mind when reading the code.

## Display

`BoundingBoxWidget` (`lib/widgets/constraints/bounding_box.dart`) renders a `W×H`
grid of empty (transparent) cells over a translucent tint of the constraint
color, inside a border that is green (valid) / deepOrange (invalid) / highlight
(highlighted), greyed out when complete-and-valid. The grid is laid out
width-first to match the syntax.

## Implementation

### Constraint Class

**Location**: `lib/getsomepuzzle/constraints/bounding_box.dart`

`BoundingBoxConstraint extends Constraint` (global scope — no anchor cell). It
stores `color` (a `CellValue`), `width` and `height`.

- **`slug`** → `'BB'`
- **`referencedColors`** → `{color}`
- **constructor** `BoundingBoxConstraint(String strParams)` — splits
  `"color.width.height"` on `.`.
- **`serialize()`** → `'BB:${cellValueToString(color)}.$width.$height'`
- **`rotated(origWidth, origHeight)`** — swaps width/height (`BB:1.2.3` →
  `BB:1.3.2`); identity after four rotations.
- **`toString()`** → `'${cellValueToString(color)} BB $width×$height'`
- **`toHuman(Puzzle)`** → `'Groups of color … must have bounding box W×H'`
- **`generateAllParameters(width, height, domain, excludedIndices)`** — every
  `2 ≤ w ≤ gridWidth − 1`, `2 ≤ h ≤ gridHeight − 1` and color. Each extent is
  bounded strictly inside the grid: the lower bound of 2 drops the no-adjacency
  `c.1.h` / `c.w.1` lines, and the upper bound of `dim − 1` drops any box that
  spans a full grid dimension (a weak rule). The generator's solve loop then
  drops the remaining non-discriminating / unsatisfiable candidates.

#### `verify(Puzzle)`

Returns `false` only when the state is broken now or has become unreachable. For
each group of `color`:

- **complete puzzle** → the box must equal `W×H` exactly;
- **box larger than target** in either dimension → broken now (monotone-sound: a
  group's box only ever grows, so it can never shrink back);
- **box smaller than target** → still valid only if the option-aware region
  reachable from the group (flood-fill through cells that are `color` or still
  have `color` in options, `_reachableBBHW`) can still span the full `W×H`
  extent. A group walled off below target → `false`.

A color with **no** group is vacuously satisfied.

#### `apply(Puzzle)`

Scans the groups of the color and returns the first applicable move; reasoning is
per connected group. Four passes:

1. **Contradiction** — a box over-large, or too small with an unreachable extent
   → `Impossible(this)`.
2. **Overshoot prune** (`complexity 2`) — a free `color`-capable cell
   orthogonally adjacent to a group cell and just outside the box, in a dimension
   already at target, would overgrow the box if colored → `RemoveOption(cell,
   color)`. (Only when that dimension is at target; a cell outside in a still-
   deficient dimension may legitimately be needed to grow.)
3. **Pinned-box edge growth** (`complexity 3`) — when the group's extent plus the
   grid borders pin the `W×H` box to a single position, the group must reach all
   four sides. The unique `color`-capable cell on a not-yet-occupied edge is
   forced (`SetValue`); an edge with no capable cell → `Impossible`.
4. **Pinned-box connectivity** (`complexity 4`) — within a pinned box, a free
   `color`-capable cell whose removal would disconnect a still-needed edge from
   the group (a cut cell, found by a hypothetical-removal flood inside the box) is
   forced (`SetValue`). If the full capable component already fails to reach all
   four edges → `Impossible` (catches connectivity dead-ends that pass 1's
   reachability flood and pass 3's edge scan both miss).

See `docs/dev/complexity.md` for the weight rationale (2 / 3 / 4 = local-spatial
/ reachability / articulation).

#### `isCompleteFor(Puzzle)`

Conservative grayout — `true` only when `verify` holds, every group already has
the exact `W×H` extent, **no** free `color`-capable cell is orthogonally adjacent
to a group cell (one could still grow or merge a box), and **no** free cell could
start a new `color` group.

### Helpers

`_bbHW` (box size as `(height, width)`), `_bounds` (min/max row and column of a
group) and `_reachableBBHW` (extent of the option-aware reachable region), all
local to the class. The pinned-box test in `apply` passes 3–4 derives the box's
only possible top-left corner from the group's extent intersected with the grid
borders, and fires only when both axes collapse to a single position.

### Registry

`lib/getsomepuzzle/constraints/registry.dart`:

```dart
(
  slug: 'BB',
  label: 'Bounding box',
  fromParams: BoundingBoxConstraint.new,
  generateAllParameters: BoundingBoxConstraint.generateAllParameters,
),
```

### Family

`families.dart` maps `'BB' → 'group-topology'` (alongside `GS`, `GC`, `SH`, `SY`,
`MJ`). See `docs/dev/families.md`.

### Rendering & Editor

`BoundingBoxConstraint` is *global* (no anchor cell), so — like `GC`, `Motif`
and `QuantityConstraint` — `BoundingBoxWidget` is rendered in the **top bar above
the grid** (`lib/widgets/puzzle.dart`, the `Wrap` of top-bar constraints), not
inside a cell via `to_flutter.dart`. It is previewed through
`constraintUIRegistry` (`lib/widgets/constraints/registry.dart`); its display
name comes from
`constraintNameForSlug` (l10n key `constraintBoundingBox`, en/es/fr). The editor
adds a `BB` via `showBoundingBoxDialog`
(`lib/widgets/create_page/dialogs/bounding_box_dialog.dart`) — color + width +
height — wired into `create_page.dart`. First-contact help text is
`constraintExplainBB` (`lib/widgets/constraints/registry.dart`), and `BB` sits in the
onboarding post-strict discovery order (auto-extended from the registry).

### Tests

`test/constraints_test.dart` — groups `BoundingBoxConstraint.verify`, `.apply`,
`.isCompleteFor` and `.generateAllParameters` cover exact / over / under boxes,
the walled-off and hollow-shape cases, the overshoot prune, the pinned-box growth
and connectivity forcing and their `Impossible` branches.
`test/rotation_test.dart` checks the width/height swap and four-fold identity.

## Not yet implemented

- **Forced growth on a non-pinned box** — `apply` only forces edge/connectivity
  cells once the `W×H` box position is uniquely pinned (the group sits against
  grid borders). When the box can still slide, no growth move is emitted.
- **Merge-specific pruning** — a cell that would merge two same-color groups into
  an over-large box is pruned only when it also overshoots a pinned box (pass 2);
  the general forced-merge case is left to the backtracking solver.
