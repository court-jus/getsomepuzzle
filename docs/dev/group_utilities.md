# Group & connectivity utilities

**File**: `lib/getsomepuzzle/utils/groups.dart`

Shared helpers for connected-component and reachability reasoning on the puzzle
grid. Every connectivity-flavoured constraint (`GS`, `LT`, `GC`, `SY`, `CH`) and
several complicities (`GSQA`, `GSAll`) build on these functions instead of
re-implementing their own traversal. All traversals use 4-connectivity via
`puzzle.getNeighbors(idx)`.

The file is organised in three layers: a generic flood-fill core, same-colour
group extraction, and "merge graph" reachability (colour-or-free traversal).

## Generic flood fill

The two primitives every other traversal in the codebase is written against.

```dart
Set<int> floodFill(
  Puzzle puzzle,
  Iterable<int> starts,
  bool Function(int idx) canTraverse,
)
```

Multi-source flood fill. All `starts` are visited **unconditionally** (even when
`canTraverse` would reject them — callers like `reachableComponentSize` seed
from a cell whose own value differs from the traversal predicate), then the
fill expands through neighbors for which `canTraverse` returns true. Returns
the visited set.

```dart
bool canReach(
  Puzzle puzzle,
  Iterable<int> starts,
  bool Function(int idx) isTarget,
  bool Function(int idx) canTraverse,
)
```

Reachability variant with early exit: true iff a cell satisfying `isTarget` is
reachable from `starts` through `canTraverse` cells. `isTarget` is also tested
on the start cells themselves (a start can be its own target — e.g. a cell
lying on both borders of a 1-wide grid, which `CH` relies on). Empty `starts`
returns false.

Neither primitive prescribes a visit order (internally a LIFO stack); no caller
may depend on it.

**Direct users**: `GroupSize.apply` (growth-capacity check), `SymmetryConstraint.apply`
(look-ahead merge closure), `ChainConstraint._isBlocked`/`._hasCompletePath`,
`GSQA._hypotheticalMergedSize`, `GSAll` (anchor component, `_addWithMerges`), and
every helper below.

Edge-case contracts (multi-source merge, non-traversable start, start-as-target,
empty starts) are pinned by `test/utils_flood_fill_test.dart`.

## Same-colour groups

```dart
List<List<int>> getGroups(Puzzle puzzle)
```

The connected components of same-valued filled cells (free cells form no
group; singletons count). Each component is a sorted `List<int>`. Built by
unioning per-cell neighbourhoods (`getMyColorGroup`) rather than flood fill.

**Cached**: the result is memoised in `Puzzle.cachedGroups` and invalidated by
`Cell.onMutate` whenever any cell's value or options change
(`lib/getsomepuzzle/model/puzzle.dart`). Callers in hot loops can therefore
call `getGroups` repeatedly without cost between moves.

**Users**: `GS`, `LT`, `SY`, `SH`, `SYFM` complicity, the grid widget
(`lib/widgets/puzzle.dart`), and `Puzzle` itself.

```dart
Set<int> getMyColorGroup(Puzzle puzzle, int idx)
```

Building block of `getGroups`: `idx` plus its **direct** same-valued
neighbours (not a full component — one BFS layer only). Empty set for a free
cell. Not used outside `getGroups`.

```dart
List<List<int>> getColorGroups(Puzzle puzzle, int color)
```

`getGroups` filtered to components of value `color`. **Users**: `GC`.

## Virtual groups

```dart
List<List<int>> toVirtualGroups(Puzzle puzzle)
```

For each value V in `{0} ∪ domain`, the connected components of the subgraph
of cells whose value is V or 0, anchored on at least one cell whose value is
exactly V. A virtual group of colour V is the maximal set of cells that could
end up in a single V-coloured group after colouring some free cells. A free
cell may belong to several virtual groups (one per colour it can reach, plus
the free-only component).

**Users**: `LT` (can all letter cells still live in one same-colour group?).

## Merge-graph reachability

The "merge graph" of colour C spans every cell whose value is C **or 0**:
the cells a C-group could still grow through. The helpers below answer
feasibility and articulation-point questions on that graph; all are thin
wrappers around `floodFill`/`canReach`.

```dart
int reachableComponentSize(Puzzle puzzle, int seed, int color)
```

Size of the merge-graph component containing `seed` (seed included even when
its own value differs). Upper bound on the size any group through `seed` can
reach. **Users**: `GS` (infeasible-colour detection).

```dart
bool blockingDisconnectsMembers(
  Puzzle puzzle, int blocked, int color, List<int> members)
```

True iff removing `blocked` from the merge graph makes at least one of
`members` unreachable from `members.first` — i.e. `blocked` is an articulation
point of every merge path and must take `color`. Vacuously true when `members`
were not mutually reachable to begin with (callers must ensure they are).
**Users**: `LT`.

```dart
bool blockingShrinksReachableBelow(
  Puzzle puzzle, int blocked, int color, int seed, int minSize)
```

Sibling of the previous helper, with a size threshold instead of named
members: true iff removing `blocked` leaves fewer than `minSize` cells
reachable from `seed`. Detects cells lying on every growth path of a group
that must reach `minSize`. **Users**: `GS`.

```dart
bool canMergeGroups(Puzzle puzzle, List<int> groupA, List<int> groupB)
```

True iff `groupA` and `groupB` (same colour, otherwise false) are connected in
the merge graph — they can still end up as one group. Early-exits on first
contact. **Users**: `GC`, `calculateMinGroups`.

```dart
int calculateMinGroups(Puzzle puzzle, int color)
```

Minimum number of `color` groups the grid can end with: Union-Find over the
current colour groups, uniting every pair for which `canMergeGroups` holds,
then counting roots. O(groups²) calls to `canMergeGroups`. **Users**: `GC`
(both `apply` and the grayout check).

## Group-boundary scans

Simple linear scans (no traversal) used by `GC`:

```dart
List<int> getFreeCellsWithoutNeighborColor(Puzzle puzzle, int color)
```

Free cells with no `color` neighbour — the candidate seeds for a **new**
group. The set is monotone decreasing as the grid fills, which `GC`'s
grayout relies on.

```dart
List<int> getCellsThatMergeColorGroups(Puzzle puzzle, int color)
```

Free cells adjacent to **two or more distinct** `color` groups — colouring one
merges them (decreasing the group count by at least one).

## Out of scope

`generator/prefill/path.dart` contains the one remaining hand-rolled flood
fill: it traverses a raw solution `List<int>` (no `Puzzle` instance, manual
neighbour arithmetic), so it cannot use these helpers without widening their
API to a neighbour callback for a single call site.
