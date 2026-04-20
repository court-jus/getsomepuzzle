# Group Count Constraint

The Group Count constraint (GC) specifies the exact number of connected groups of a given color that must appear in the solved puzzle.

## Syntax

`GC:2.5` means: the solution must contain exactly 5 groups of color 2 (white).

## Implementation

### Constraint Class

**Location**: `lib/getsomepuzzle/constraints/group_count.dart`

The `GroupCountConstraint` class extends `Constraint` with:
- `color` - the color value to count groups for (1=black, 2=white)
- `count` - the target number of groups

#### verify(Puzzle)

Validates the puzzle state:
- Returns `true` if puzzle is complete and group count matches target
- Returns `true` if incomplete but possibly valid:
  - If `currentCount > count`: checks if groups can still merge using `calculateMinGroups()`
  - If `currentCount < count`: checks if new groups can still be created using `getFreeCellsWithoutNeighborColor()`
- Returns `false` if contradiction detected

#### apply(Puzzle)

Performs deductions based on current puzzle state. Four cases:

1. **Too many groups** (`currentCount > count`):
   - If `minGroups > count` → contradiction (`isImpossible`)
   - If exactly one cell can merge groups → force color that cell

2. **Not enough groups** (`currentCount < count`):
   - If `candidates + currentCount < count` → contradiction
   - If `candidates + currentCount == count` → force color all candidates

3. **Exact count** (`currentCount == count`):

   Two opposite effects are possible on free cells:
   - Coloring a "candidate" (free cell with no color neighbor) locally adds a
     new group → count goes up.
   - Coloring a "merge-cell" (free cell adjacent to 2+ same-color groups)
     fuses groups → count goes down.

   These effects are **asymmetric** over time:
   - The set of candidates only shrinks: coloring other cells can only add
     color neighbors, never remove them.
   - The set of merge-cells can grow: colouring a candidate creates a new
     group, which can later make another free cell adjacent to two groups.

   Consequently the only sound local deduction is:
   - If `candidates` is empty → every merge-cell must be forced to opposite.
     No new group can ever form, so a merge would drop the count below target
     with no way to compensate.

   The symmetric rule ("force candidates when no merge-cell exists") is
   **not** valid: even when no merge-cell exists right now, colouring a
   candidate can itself produce a merge-cell later (the new group may be
   rejoined to an existing one via intermediate cells), bringing the count
   back to target.

   When `candidates` is non-empty, no local deduction is attempted; the
   constraint defers to force/backtracking.

4. **Complete puzzle** - handled by `verify()`

### Helper Functions

From `lib/getsomepuzzle/utils/groups.dart`:
- `getColorGroups(puzzle, color)` - returns all groups of a color
- `calculateMinGroups(puzzle, color)` - minimum groups possible after merging
- `getFreeCellsWithoutNeighborColor(puzzle, color)` - cells that can start new groups
- `getCellsThatMergeColorGroups(puzzle, color)` - cells adjacent to multiple groups

### Widget

**Location**: `lib/widgets/group_count.dart`

Renders as a box with:
- Link icon (representing connected groups)
- Numeric count value
- Text color matching constraint color
- Border color: green (valid), deepOrange (invalid), highlightColor (highlighted)

### Registration

Registered in `lib/getsomepuzzle/constraints/registry.dart`:
```dart
(slug: 'GC', label: 'Group count', fromParams: GroupCountConstraint.new),
```

## Tests

Located in `test/constraints_test.dart`:
- `GroupCountConstraint.verify` - validation logic
- `GroupCountConstraint.apply` - deduction cases
- `GroupCountConstraint.generateAllParameters` - parameter generation