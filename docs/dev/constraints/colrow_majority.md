# Column/Row majority

This constraint enforces a strict ordering of colors by count in a row or
column. The first color in the ordering must have more cells than the second,
which must have more than the third, etc. Ties are not allowed — the ordering
is absolute, same as MJ's majority requirement.

## Serialization

Serialized as JC (for column) and JR (for row) with two fields:
* the column (or row) index
* the colors order (from most present to least present, digits = color indices)

For example, to say that there are more white cells than black cells in column 2
we would have the constraint `JC:2.21`. To say (in domain 3) that there are more
white than purple than black in row 3 we would have `JR:3.231`.

The separator between the index and the color order is a dot (`.`), which
differs from the colon separator used by other LineCentricConstraints.

## Semantics

### Majority floor

The "majority floor" for a line of length N with D domain colors is
`N ~/ D` (integer division). The leading color must reach at least
`floor(N/D) + 1` cells to hold a strict lead over every other color.

### Domain 2

JC/JR is strictly equivalent to MJ applied to a full row or column. The first
color in the ordering must have a strict majority (> half the cells). If there
are N cells, the first color needs at least `floor(N/2) + 1`.

### Domain 3

The ordering is total across all domain colors. Each color must have strictly
more cells than all colors that follow it in the ordering. The first color needs
at least `floor(N/3) + 1` cells. No minority color may exceed `floor(N/3)`
cells.

### Completion and verification

* **isCompleteFor**: returns true when the leading color has a count strictly
  greater than all other colors combined (`firstCount > N - firstCount`).
  This means the ordering is already satisfied regardless of how free cells
  resolve. Also returns true when the line is fully filled and verify passes.
* **verify**: performs three reachability checks on incomplete lines:
  1. The first color can still reach its minimum (`firstCount + firstReachable > floor(N/D)`).
  2. No minority color has already exceeded the majority floor.
  3. For each consecutive pair in the ordering, the upper color's maximum
     reachable count is still strictly above the lower color's current count.
  For complete lines, checks that the ordering holds strictly (no ties).
* **apply**: four deduction paths, tried in order:
  1. `Impossible` — a minority color already exceeds the majority floor.
  2. `Impossible` — the first color can no longer reach its minimum.
  3. `SetValue` — remaining free cells are exactly enough for the first color
     to reach its target; all must become the first color.
  4. `RemoveOption` — a minority color has hit the majority floor ceiling,
     so it is pruned from remaining free cells to prevent further growth.

## Visual representation

JC/JR uses **concentric circles** rendered in the sidebar (same position as
RC/CC — outside the grid, facing the constrained row or column).

* The outer circle is colored from the most present color.
* Inner circles are colored from less present colors, nesting inward.
* Circle size matches the RC/CC circle style (`cellSize * 0.7`).
* Standard constraint state colors apply: grayout when complete, red when
  invalid, highlight color when hinted.

## conflictsWith

JC/JR conflicts with any `LineCentricConstraint` that targets the same
row or column **on the same axis**. Concretely:
* JC conflicts with CC, CT, and other JC on the same column.
* JR conflicts with RC, RT, and other JR on the same row.
* JC does **not** conflict with RC, RT, or JR (different axis).
* JR does **not** conflict with CC, CT, or JC (different axis).

The check: `other is LineCentricConstraint` and both operate on the same axis
(both row-based or both column-based) and `other.getIdx() == this.getIdx()`.

This prevents redundant constraints on the same line and is enforced at
generation time (the generator rejects candidates that conflict with
already-placed constraints) and at editor time (the user cannot add a
constraint that would conflict).

## generateAllParameters

For each row (JR) or column (JC), generate all permutations of the domain
colors. Domain 2: 2 permutations per line. Domain 3: 6 permutations per line.
No filtering on color orderings — "on génère tout".

Conflict filtering against existing constraints is not currently performed
in `generateAllParameters`; it is left to the caller (the generator/editor)
to reject invalid candidates.

## Rotation

* JC at column `c` on a (W, H) grid rotates to JR at row `c` on the
  rotated (H, W) grid.
* JR at row `r` on a (W, H) grid rotates to JC at column `(H-1-r)` on the
  rotated (H, W) grid.

The color ordering is preserved unchanged across rotation.

## Implementation

JC and JR each extend `LineCentricConstraint`, sharing the same base as
RC, CC, RT, and CT. The majority target formula is factored into a shared
utility function (`majorityTarget`) also used by MJ.

Both constraint classes and their widgets are complete and registered in the
constraint registry and UI registry. Editor dialogs for domain 2 are provided
for both JC and JR. The constraint explanation in the new-constraint dialog
shares a single descriptive string between JC and JR. Localization keys are
added for English, French, and Spanish.
