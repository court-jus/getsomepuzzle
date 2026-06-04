# Neighbor Count Constraint

New constraint type "Neighbor Count" (slug NC).

Serialized as `NC:4.1.2` (slug:cellIdx.color.count), it means the cell at index 4 must have
exactly 2 orthogonal neighbors of color 1 (black).

This is a cell-centric constraint: it is displayed inside or adjacent to the target cell, and
its deductions are entirely local. Despite its simple wording ("this cell has N neighbors of
color X"), the constraint produces rich forcing patterns, especially at the extremes (NC=0 acts
as an isolator; NC=maxNeighbors forces full adjacency) and interacts strongly with GS and FM.

## Syntax

`NC:4.1.2` — cell 4 must have exactly 2 black neighbors.
`NC:0.2.1` — cell 0 (top-left corner, max 2 neighbors) must have exactly 1 white neighbor.
`NC:7.1.0` — cell 7 must have zero black neighbors (all neighbors are white or the cell is
             on the border).

Valid counts range from 0 to the number of orthogonal neighbors of that cell (2 for corners,
3 for edges, 4 for interior cells). The generator must enforce this: `count ≤ neighborCount(idx)`.

## Display

A drawn cross with the background color matching the color of the constraint and the border color
in the opposite color. Inside the cross the "count" of the constraint is written.

## Gameplay notes

NC has an asymmetry that makes it tactically interesting:

- **NC = 0**: the cell is a "color isolator" — no neighbor of that color is allowed. Equivalent
  to DF applied to all neighbors simultaneously. Very constraining, often solvable by pure
  propagation.
- **NC = maxNeighbors**: all neighbors must be that color. Strong forcing, rare in practice.
- **NC = k, intermediate**: the constraint waits until enough neighbors are resolved, then fires.
  The timing of this firing is non-obvious and requires the player to track partial counts.

NC interacts naturally with GS: if a cell has NC:idx.color.0, it cannot belong to a same-color
group with any neighbor, effectively capping the group size at 1 for that color at that location.
Combined with FM, NC can block specific local patterns more precisely than the motif alone.

## Implementation

### Constraint class

**Location**: `lib/getsomepuzzle/constraints/neighbor_count.dart`

`NeighborCountConstraint` extends `CellsCentricConstraint` and stores
`indices` (a single-element list with the target cell index), `color`,
and `count`.

- **`slug`** → `'NC'`
- **`serialize()`** → `'NC:${indices.first}.$color.$count'`
- **`toString()`** → `'$count'` (the displayed digit)
- **`toHuman(puzzle)`** → human-readable description used in hint
  messages.

#### `verify(Puzzle)`

```text
neighbors = puzzle.getNeighbors(idx)
colorNeighbors = count of neighbors with value == color
freeNeighbors  = count of neighbors with value == 0

if puzzle.complete:
  return colorNeighbors == count
if colorNeighbors > count:                       return false
if colorNeighbors + freeNeighbors < count:       return false
return true
```

In words: violated *now* if the count already exceeds the target, or
unreachable in the future if even painting every free neighbor with
`color` cannot reach the target. Otherwise the state is still valid.

#### `apply(Puzzle)`

Returns `null` if all neighbors are filled (no deduction left), and
otherwise checks four cases in order:

1. **Too many** — `colorNeighbors > count` → `Move(..., isImpossible: this)`.
2. **Saturated** — `colorNeighbors == count` → first free neighbor is
   forced to the opposite color.
3. **Unreachable** — `colorNeighbors + freeNeighbors < count` →
   `Move(..., isImpossible: this)`.
4. **Full need** — `colorNeighbors + freeNeighbors == count` → first
   free neighbor is forced to `color`.

Otherwise `null` (constraint active but not yet forcing).

Each call returns a single move; the solver loop reapplies until the
constraint produces no further moves, which is consistent with the rest
of the codebase.

#### `isCompleteFor(Puzzle)`

```dart
@override
bool isCompleteFor(Puzzle puzzle) {
  if (!verify(puzzle)) return false;
  final myNeighbors = puzzle.getNeighbors(indices.first);
  return myNeighbors.every((i) => puzzle.cellValues[i] != 0);
}
```

NC is monotone: once all the target cell's neighbors are filled, they
stay filled, so no future move can revive the deduction.

#### `generateAllParameters(width, height, domain, excludedIndices)`

For each cell, compute the actual neighbor count from grid geometry
(2 for corners, 3 for edges, 4 for interior). For each domain color
and each `count ∈ [0, neighbors)`, emit `'$idx.$color.$count'`.

`count == neighbors` is intentionally excluded — saturating every
neighbor with the same color is rarely satisfied by random grids and
the upstream generator filter would discard the candidates anyway.

### Registry

`lib/getsomepuzzle/constraints/registry.dart`:

```dart
(slug: 'NC', label: 'Neighbor count', fromParams: NeighborCountConstraint.new),
```

### Generator

NC is enumerated by `generateAllParameters` like every other registered
constraint type. The parameter space is `O(width × height × |domain| ×
maxNeighbors)` — manageable at typical grid sizes; no special pruning is
needed beyond the solution-validity filter applied by the generator
itself.

### Widget

**Location**: `lib/widgets/neighbor_count.dart`

The constraint is rendered as a cross over the target cell, with the
background color matching the constraint color and the border in the
opposite color. The count digit sits inside the cross. The widget is
overlaid via a `Stack` on top of the cell, so multiple NC constraints
on the same cell stack rather than push grid layout — consistent with
how GS and PA render their in-cell indicators.

The hint highlight follows the GS pattern: when an NC constraint is
highlighted, the arrow points from the target cell to the free
neighbor being forced.

### Localization

ARB key `constraintNeighborCount` is present in `lib/l10n/app_en.arb`,
`app_fr.arb`, and `app_es.arb`. The help texts in `assets/help.*.md`
include the description of the constraint.

### Tests

`test/constraints_test.dart` exercises:

- complete puzzle, correct / incorrect count → `verify` true / false
- partial puzzle, possible vs unreachable → `verify` true / false
- `apply` saturated → free neighbor forced to opposite
- `apply` full need → free neighbor forced to color
- `apply` impossible (too many, unreachable)
- `apply` no deduction → `null`
- `isCompleteFor` only when every neighbor is filled
- `serialize` / `deserialize` round-trip
- `generateAllParameters` cardinality on corner / edge / interior cells
- NC:0 interaction with GS where the propagation chain replaces a force
  round.
