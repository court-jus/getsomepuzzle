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

## Implementation plan

### 1. Create the `NeighborCountConstraint` class

**File**: `lib/getsomepuzzle/constraints/neighbor_count.dart`

Extends `CellsCentricConstraint` (or `Constraint` with an `idx` field — follow the pattern of
`GroupSizeConstraint` which is also cell-centric).

Fields: `idx` (int), `color` (int), `count` (int).

- **`slug`** → `'NC'`
- **`serialize()`** → `'NC:$idx.$color.$count'`
- **`toString()`** → `'$count'`

#### verify(Puzzle)

```
neighbors = puzzle.getNeighbors(idx)
colorNeighbors = neighbors.where((n) => puzzle.cellValues[n] == color).length
freeNeighbors  = neighbors.where((n) => puzzle.cellValues[n] == 0).length

if puzzle is complete:
  return colorNeighbors == count
else:
  // Not yet violated: current color count ≤ target AND
  // maximum achievable count (current + free) ≥ target
  return colorNeighbors <= count && colorNeighbors + freeNeighbors >= count
```

#### apply(Puzzle)

Four deduction cases, in order:

1. **Impossible — too many**: `colorNeighbors > count` → `isImpossible`.

2. **Impossible — unreachable**: `colorNeighbors + freeNeighbors < count` → `isImpossible`.
   (Cannot place enough color cells even using all free neighbors.)

3. **Saturated**: `colorNeighbors == count` → all free neighbors must take the opposite value.
   Return the first such free neighbor forced to `oppositeColor`.

4. **Full need**: `colorNeighbors + freeNeighbors == count` → all free neighbors must take
   `color`. Return the first such free neighbor forced to `color`.

Return `null` when none of the above applies (constraint is active but no deduction yet).

Note: `apply()` returns a single `Move` per call; the solver loop calls it repeatedly until
it returns null, so returning only the first forced cell is correct and consistent with the
rest of the codebase.

#### isCompleteFor(Puzzle)

```dart
@override
bool isCompleteFor(Puzzle puzzle) {
  if (!verify(puzzle)) return false;
  // Complete when all neighbors are filled: no future move can change the neighbor count.
  final neighbors = puzzle.getNeighbors(idx);
  return neighbors.every((n) => puzzle.cellValues[n] != 0);
}
```

This is monotone: once all neighbors are filled, they stay filled.

#### generateAllParameters(width, height, domain)

For each cell index (0..width*height-1), compute its actual neighbor count `k` from grid
geometry. For each domain color, for each valid count (0..k), generate `'$idx.$color.$n'`.

Exclude `count == k` when it would be trivially equivalent to a QA constraint on that color
(all neighbors must be color X — this is usually too strong and rarely satisfies the target
solution, so the generator's filter will discard most of them anyway; no need to special-case).

### 2. Register the constraint

**File**: `lib/getsomepuzzle/constraints/registry.dart`

- Add the import of `neighbor_count.dart`.
- Add the entry to `constraintRegistry`:
  `(slug: 'NC', label: 'Neighbor count', fromParams: NeighborCountConstraint.new)`

### 3. Integrate with the generator

**File**: `lib/getsomepuzzle/generator/generator.dart`

- Add the `'NC'` case in `_generateParamsForSlug()`:
  `return NeighborCountConstraint.generateAllParameters(width, height, domain);`

The parameter space is O(width × height × |domain| × 5) ≈ manageable for typical grid sizes.
No special pruning needed beyond the solution-validity filter already applied by the generator.

### 4. Display widget

**File**: `lib/widgets/neighbor_count.dart` (new)

`NeighborCountWidget` renders a small filled circle with the count digit inside.

- Circle color: semi-transparent grey background, digit colored as `color`
  (black text for color 1, white text for color 2).
- Size: approximately 40% of `cellSize` to avoid obscuring the cell's own fill color.
- Position: overlaid on the **bottom-right corner** of the target cell by default. If another
  corner-overlay constraint already occupies that corner (future-proofing), shift to bottom-left.

**File**: `lib/widgets/puzzle.dart` / cell rendering

NC is rendered as a cell overlay, not in the top bar. Add a `Stack` layer inside the cell
widget for each NC constraint targeting that cell. This is consistent with how GS and PA render
their in-cell indicators.

### 5. Highlight and hint arrow

**File**: `lib/widgets/puzzle.dart`

When an NC constraint is highlighted, the arrow points from the target cell to the free
neighbor being forced. This follows the existing GS highlight pattern (cell → relevant neighbor).

### 6. Help text

**File**: `lib/l10n/` (all ARB files)

Suggested wording (EN): "A small number in the corner of a cell indicates how many of its
orthogonal neighbors must be of that color."

### 7. Tests

**File**: `test/neighbor_count_test.dart` (new)

- **verify complete — correct**: all neighbors filled, color count matches → true.
- **verify complete — incorrect**: color count wrong → false.
- **verify partial — possible**: current count ≤ target, achievable with remaining free → true.
- **verify partial — impossible**: free neighbors insufficient to reach target → false.
- **apply — saturated**: color count == target, free neighbors → forced opposite.
- **apply — full need**: color + free == target → free neighbors forced to color.
- **apply impossible — too many**: color count > target → isImpossible.
- **apply impossible — unreachable**: color + free < target → isImpossible.
- **apply — no deduction**: intermediate state, no forcing yet → null.
- **isCompleteFor**: all neighbors filled + verify true → true; any free neighbor → false.
- **serialize / deserialize**: round-trip `NC:4.1.2` → object → `NC:4.1.2`.
- **generateAllParameters**: corner cell (2 neighbors) generates counts 0, 1, 2 only;
  interior cell (4 neighbors) generates counts 0..4.
- **NC:0 interaction with GS**: synthetic puzzle where NC:idx.color.0 forces a GS:idx.1
  deduction by propagation (no force round needed).

### Recommended implementation order

1. **Step 1** (class + registry) — parsable, verifiable, deductions working.
2. **Step 7** (logic tests) — covers all apply/verify branches before UI.
3. **Step 3** (generator) — NC puzzles generatable and testable end-to-end.
4. **Steps 4-5** (UI) — corner overlay and arrow.
5. **Step 6** (help text).
