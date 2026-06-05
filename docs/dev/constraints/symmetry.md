# Symmetry Constraint

The Symmetry constraint (slug SY) requires the connected group containing a given **anchor
cell** to be symmetric under a specified axis.

Serialized as `SY:idx.axis` where `idx` is the anchor cell index and `axis` is one of five
symmetry types:

| Axis | Icon | Description |
|------|------|-------------|
| 1    | `⟍`  | Diagonal (top-left to bottom-right) |
| 2    | `\|`  | Vertical mirror |
| 3    | `⟋`  | Anti-diagonal (top-right to bottom-left) |
| 4    | `―`  | Horizontal mirror |
| 5    | `🞋`  | Point symmetry (180° rotation) |

The constraint is **colour-agnostic**: it only requires geometric symmetry, not a specific
cell value. The anchor cell's eventual colour propagates symmetrically through its group.

## Syntax

`SY:7.2` — the group containing cell 7 must be vertically symmetric.
`SY:12.5` — the group containing cell 12 must be point-symmetric.

## Implementation

**File**: `lib/getsomepuzzle/constraints/symmetry.dart`

`SymmetryConstraint` extends `CellsCentricConstraint` with:
- `indices` — a single-element list holding the anchor cell index
- `axis` — the symmetry axis (1–5)

### `computeSymmetry(Puzzle, cellidx)` → `int?`

Returns the mirror of `cellidx` under the constraint's axis and anchor, or `null` if the
mirror falls outside the grid.

### `verify(Puzzle)` → `bool`

Returns `false` when any cell in the anchor's group has a mirror that is:
- out of bounds, **or**
- already coloured a different value than the group.

Returns `true` when the anchor is uncoloured or has no group yet (insufficient information).

### `apply(Puzzle)` → `Move?`

Three phases of deduction, triggered once the anchor has a colour:

**Phase 1 — Mirror the group.** Every cell in the anchor's group forces its mirror to the
same colour (complexity 1). If any mirror is out of bounds or already a different colour,
the constraint is impossible.

**Phase 2 — Frontier rules.** For every cell adjacent to the group:
- **Free neighbour**: if setting it to the group colour would require its mirror to also
  be in the group, but the mirror is out of bounds or already a different colour, the
  neighbour must not become the group colour — remove that option (complexity 2).
- **Coloured neighbour** (not in group): its mirror must also be outside the group.
  If the mirror is already coloured the group colour, the frontier cell contradicts the
  symmetry → impossible. If the mirror is free, it must not become the group colour
  (complexity 2).

**Phase 3 — Look-ahead (complexity 3).** A free cell adjacent to the group whose mirror
is also free may still be impossible to colour with the group colour. If colouring it
would pull a closure of reachable same-colour cells into the group, and any cell in that
closure has its mirror out of bounds or already a different colour, the neighbour must
not become the group colour.

**Anchor-free path (2-colour domain).** When the anchor is still free, a coloured
neighbour forces the neighbour's mirror to the same colour directly — because on a
binary domain the anchor's eventual value cannot escape the same logic regardless of
which colour it picks.

### `isCompleteFor(Puzzle)` → `bool`

Returns `true` when `verify` passes and every cell in the anchor's group has no free
neighbour (the group is fully closed and cannot grow).

### `generateAllParameters(width, height, domain, excludedIndices)`

Generates every `(idx, axis)` pair for all cells and all 5 axes: O(width × height × 5)
parameters.

### Rotation

90° CW rotation remaps axes: `⟍↔⟋`, `|↔―`, `🞋` stays invariant. The anchor cell is
rotated through `rotateIdx90CW`.

## Display

**File**: `lib/widgets/symmetry.dart`

Rendered as the axis icon (`⟍`, `|`, `⟋`, `―`, `🞋`) drawn with `CustomPainter` inside the
anchor cell, with a border indicating validity state (green/transparent, deepOrange on
violation, highlightColor when highlighted).

## Complicity

**File**: `lib/getsomepuzzle/constraints/complicities/syfm.dart` — `SYFMComplicity`

SY and FM interact on the frontier: a cell that must be symmetric to a frontier cell
cannot host a forbidden motif that would be incompatible with the group colour.

## Generator integration

### Pre-fill: `preFillSy`

**File**: `lib/getsomepuzzle/generator/prefill/sy.dart`

Full pipeline documented in `docs/dev/prefill_sy.md`. Activate when equilibrium's profile
axis picks `ProfileCategory.syBased`. Summary:

1. Sample N seed cells from the grid interior, well-separated.
2. Assign each seed a feasible SY axis (one with room to grow).
3. Grow symmetric islands by adding cells in mirrored pairs, maintaining a forbidden
   halo around other islands to prevent merging.
4. Fill background with one colour, islands with the opposite.
5. Attach one SY constraint per seed island.
6. Bipartite disambiguation cascade: strategic seed reveals → island-cell reveals →
   guardrail constraints (GC/QA → other).

### Equilibrium profile

SY has its own profile category (`ProfileCategory.syBased`) with a 5 % target share in
`kTargetProfile`. When picked, `_resolveTarget` flips `syBasedScenario = true` on the
generator config, which routes through `preFillSy` instead of the regular flow.

### Guard-rail constraints

The `preFillSy` guard-rail pool excludes SY (already the dominant constraint) and SH
(two shape-flavoured constraints would compete). LT is included but filtered: candidates
whose anchors span more than one island are discarded (they would force a merge that
breaks symmetry). All other standard slugs (CH, GC, CC, RC, QA, GS, PA, NC, DF, EY, FM)
are available.

### 2-colour by design

`preFillSy` always builds a 2-colour grid (black background / white islands, or vice
versa). The binary background/island model is intrinsic — there is no 3-colour variant
of SY-based generation.

## Tests

Located in `test/constraints_test.dart`:

- `SymmetryConstraint.verify` — out-of-bounds and colour-mismatch detection
- `SymmetryConstraint.apply` — mirror forcing, frontier rules, look-ahead
- `SymmetryConstraint.generateAllParameters` — full enumeration
- Rotation round-trip
