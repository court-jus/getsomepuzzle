# Shape Constraint

The Shape constraint (slug SH) requires every connected group of a given color to match one
of the rotation/mirror variants of a predefined motif.

Serialized as `SH:motif` where `motif` is a dot-separated grid (e.g. `SH:111`, `SH:20.22`).
Non-zero characters in the motif encode the constrained color (1 = black, 2 = white); zeroes
are empty cells within the motif's bounding box. The shape is invariant under 90° rotations
and horizontal mirror (8 symmetries of a rectangle).

## Syntax

`SH:111` — every black group must be exactly 3 cells in a straight line (1×3 or 3×1 or any
rotation/mirror thereof).

`SH:20.22` — every white group must match the shape `20 / 22` (an L-shape of 3 cells).

`SH:110.011` — every black group must match `110 / 011` (a zigzag of 4 cells).

## Implementation

**File**: `lib/getsomepuzzle/constraints/shape.dart`

`ShapeConstraint` extends `Motif` (which extends `Constraint`) with:
- `color` — the constrained color, inferred from the motif's non-zero values
- `variants` — all 8 rotation/mirror variants of the normalized shape
- `shapeSize` — number of occupied cells in the motif
- `motifGridSize` — total cells of the bounding box (rows × cols)

### Normalization

Shapes are canonicalized via `normalizeShape`: the lexicographically smallest among all
rotation/mirror variants. Two shapes differing only by rotation or mirror are equivalent.

### `verify(Puzzle)` → `bool`

Returns `false` when any group of the constrained color **cannot** grow into a valid shape:

- **Open group** (has a free neighbor that can still become `color`): checked via
  `_groupCanFitInSomeVariant` — three-level pre-filter (cell count, bounding box, sub-shape
  mapping onto a variant). Returns `true` as long as at least one variant could still contain
  the group after growth.
- **Closed group** (no extendable free neighbor): must match a variant exactly via
  `_groupMatchesAVariant`.

This is intentionally permissive for open groups: a partial group that has room to grow into
the correct shape is not a violation.

### `apply(Puzzle)` → `Move?`

Six levels of deduction, cheapest first:

1. **Closed group doesn't match** → `Impossible` (complexity —).
   A group that can no longer grow must already match a variant exactly.

2. **Open group already matches** → remove `color` option from border cells (complexity 0).
   The group has the right shape and correct size; any free neighbor that could still
   become `color` would overgrow the motif → must be the opposite color.

3. **Open group can't fit in any variant** → `Impossible` (complexity —).
   Cell count, bounding box, or sub-shape check fails.

4. **Extending by a neighbor breaks fit** → block that neighbor (complexity 2).
   Simulate adding the neighbor; if the extended group can't fit any variant, the
   neighbor must not become `color`.

5. **Enumerate all completions** — place the variant at every valid position covering
   the current group:
   - Cell in ALL completions → force `color` (complexity 4).
   - Neighbor in NO completion → block `color` (complexity 4).

6. **Free cell would merge groups into invalid shape** → block `color` (complexity 3).
   Colouring the cell would merge 2+ existing groups; if the merged group can't fit a
   variant, the cell must not become `color`.

### `isCompleteFor(Puzzle)` → `bool`

Returns `true` only when the grid is fully filled (`apply` could fire as long as any free
cell remains — even a single free cell coloured `color` creates a 1-cell group that fails
the shape check).

### `generateAllParameters(width, height, domain, excludedIndices)`

Returns a curated list of motif strings from `possibleMotifs` (roughly 18 base shapes
ranging from 1 to 5 cells), filtered by bounding-box fit within the grid and instantiated
for each domain color. Shapes include monomino (1), domino (2), straight triomino (3),
L-triomino (3), tetrominoes (4), and pentominoes (5).

## Display

**File**: `lib/widgets/motif.dart`

SH uses the shared `MotifWidget` (same as FM). The motif is rendered as a small grid inside
the constraint square with each occupied cell coloured by the constrained color.

## Complicity

**File**: `lib/getsomepuzzle/constraints/complicities/shgs.dart` — `SHGSComplicity`

A group that already matches the SH motif cannot be overgrown. GS (group size) and SH share
a natural cross-constraint: if a group matches SH:111 (line of 3), GS:1.3 is automatically
satisfied for that group.

## Generator integration

### Pre-fill: `preFillSh`

**File**: `lib/getsomepuzzle/generator/prefill/sh.dart`

Activated when `SH ∈ prioritySlugs` (i.e. SH is in `requiredRules` or in
`preferredSlugs`, which happens when the equilibrium profile axis picks
`ProfileTarget(sh)`).

The pre-fill builds a solved grid in three steps:

1. **Pick a motif.** Weighted random sampling from `generateAllParameters`. Weight depends
   on bounding-box size raised to an area-dependent exponent (`puzzleSize × 0.05`) so
   large grids tend to get bigger motifs, and on per-size base weights defined in
   `ShapeConstraint.baseWeights`.

2. **Place the motif.** One variant is placed at a random position that fits. All other
   cells are filled with the opposite color.

3. **Add extra occurrences.** `findAdditionalPositions` enumerates every placement of any
   variant on the grid that only overlaps opposite-color (or free) cells. Each is accepted
   with 50% probability, run until no more placements exist. This creates a grid where the
   motif appears multiple times, making the constraint non-trivial (the solver must
   distinguish which group maps to which occurrence).

The ShapeConstraint is attached to the solved grid before returning it to the main
generator loop.

### Equilibrium profile

SH has its own profile category (`ProfileCategory.sh`) with a 5 % target share in
`kTargetProfile`. The equilibrium pushes SH via `ProfileTarget(sh)`, which adds `"SH"` to
`preferredSlugs` and triggers `preFillSh`. The slug axis does **not** push SH — SH is
excluded from `slugDeficits` to avoid double-pushing (see `equilibrium.md` § "SH exclusion
from slug deficit").

### Heuristic for legacy corpus

`detectPuzzleProfile` in `equilibrium.dart` falls back to an SH-slug heuristic for legacy
puzzle lines that lack an explicit `scenario:sh` suffix: if the line contains an `SH`
constraint slug it is counted as `sh` profile.

### Guard-rail exclusion

SH is excluded from the guard-rail pool in the `preFillSy` pipeline: two shape-flavoured
constraints would compete for the same groups.

## Tests

Located in `test/constraints_test.dart`:

- `ShapeConstraint.verify` — open/closed group reachability cases
- `ShapeConstraint.apply` — each deduction level
- `ShapeConstraint.generateAllParameters` — parameter coverage
- Normalization utilities (`normalizeShape`, `shapesAreEquivalent`)
