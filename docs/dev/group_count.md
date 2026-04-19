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
   - If no new groups can be created (`candidates == 0`) → force cells that would merge to opposite color

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