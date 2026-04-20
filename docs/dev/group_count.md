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

   Detecting impossibility requires more than `calculateMinGroups > count`.
   Even if the minimum achievable count is `≤ count`, the target may not be
   exactly reachable. Example: 4 isolated color-1 singletons all touching a
   single free cell, with no other free cells. That cell is the only
   merge-cell and it's adjacent to all 4 groups. Colouring it merges all 4
   into 1 → count drops from 4 to 1. Reachable counts = `{4, 1}`. Any
   target in `{2, 3}` is impossible, but `calculateMinGroups = 1` ≤ 2 or 3,
   so the old check wouldn't fire.

   Enumerate the set of counts reachable by colouring any subset of current
   merge-cells (each merge-cell = hyperedge over 2+ group indices; the
   subset's union-find yields a component count). For up to ~15 merge-cells
   this is cheap (2^k ≤ 32768 cases).

   **Direct-merge requirement.** This enumeration is sound only when every
   mergeable pair of groups has a direct merge-cell (a free cell adjacent
   to a member of each). If some pair can only be merged via a multi-step
   flood-fill path (e.g., two distant singletons with a long empty corridor
   between them), the enumeration would under-count reachable partitions
   and falsely flag the state as impossible. In that case we fall back to
   the weaker `calculateMinGroups > count` check. Concretely:

   - If every mergeable pair has a direct merge-cell AND the enumeration
     succeeds (≤ 15 merge-cells): use it.
     - If `count ∉ reachable` → contradiction (`isImpossible`).
   - Otherwise: fall back to `calculateMinGroups > count` → contradiction
     if it holds.

   **Single-merge-cell force.** When exactly one merge-cell exists, we
   cannot blindly force `color` on it. The enumeration only considers
   subsets of *current* direct merge-cells, but future merges may be
   achievable by colouring a chain of free cells that are not currently
   direct merge-cells. To force soundly, we probe: clone the puzzle,
   colour the merge-cell with `opposite`, and check `calculateMinGroups`
   on the result. If the minimum group count in that state exceeds
   `count`, the merge-cell is genuinely necessary → force `color`.
   Otherwise, another path exists and we leave the cell free.

   Example state `1100111122121202111110101121` with `GC:1.1`: cell 23
   is the only direct merge between the middle group and the singleton
   {22}, but {22} can also reach the middle group by colouring cells 21,
   14 (joining with {0,1,7}), then 2 and 3 (joining with the middle
   group). The probe confirms `calculateMinGroups` is still 1 with cell
   23 = 2, so we do *not* force cell 23.

2. **Not enough groups** (`currentCount < count`):
   - If `candidates + currentCount < count` → contradiction (even colouring
     every candidate cannot reach the target, whether candidates are
     independent or not).
   - If `candidates + currentCount == count`:
     - If two candidates are adjacent → contradiction. Colouring both merges
       them into one group, so reaching `count` isolated new groups is
       impossible.
     - Otherwise every candidate must become its own new group → force the
       first candidate to `color` (propagation repeats until all candidates
       are forced).

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

   **Direct deductions:**
   - If `candidates` is empty → every merge-cell must be forced to opposite.
     No new group can ever form, so a merge would drop the count below target
     with no way to compensate.

   The symmetric rule ("force candidates when no merge-cell exists") is
   **not** valid: colouring a candidate can itself produce a merge-cell
   later that brings the count back to target. So we cannot force candidates
   to opposite just because merge-cells are currently empty.

   **Simulation-based deductions (candidate probing):**

   When `candidates` is non-empty, probe each candidate: simulate colouring
   it with `color` on a clone, and check the minimum count achievable in
   the new state via `calculateMinGroups` (which considers multi-step
   merges through free-or-same-color flood-fill). If
   `calculateMinGroups(clone, color) > count`, the target is unreachable
   from the simulated state → force the candidate to opposite.

   Using `calculateMinGroups` (rather than the direct merge-cell enumeration
   used in the "too many groups" branch) is necessary because, after
   colouring a candidate, the resulting state often has two groups that
   can only be merged via a chain of intermediate free cells, not by a
   single merge-cell.

   Example: grid `122 / 202 / 221` with `GC:1.2`. Cell 4 is the only free
   cell and the only candidate. Colouring it with 1 produces a complete
   grid with 3 color-1 groups and no free cells; `calculateMinGroups = 3`
   (no merges possible), which exceeds target 2 → cell 4 must be 2.

4. **Complete puzzle** - handled by `verify()`

#### isCompleteFor(Puzzle)

Returns `true` when no future play can ever trigger `apply()` again. Three
conditions must hold simultaneously:

1. `verify(puzzle)` is true.
2. `currentCount == count` (target already reached).
3. `candidates.isEmpty` — since the candidate set is monotone decreasing,
   empty now means empty forever, so the count can never rise.
4. `calculateMinGroups == currentCount` — since flood-fill reachability
   through free-or-same-color cells only shrinks as cells are coloured,
   this means no merge is possible now or in any future state, so the
   count can never drop.

Condition 4 also implies that no merge-cell can appear later, so the
"forcedCells to opposite" branch of `apply` will also never fire.

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