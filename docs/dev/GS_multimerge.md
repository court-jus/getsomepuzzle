# DONE: Group Size - Multi merge

With the puzzle "v2_12_3x3_000010001_PA:0.down;GS.1.1;GS:7.6_0:0_100",
if the grid is partially solved in state "121210101", when the user
requests a hint, here is what happens:

  The constraints PA:0.down;GS.1.1;GS:7.6 are parsed by splitting on ; then on : (puzzle.dart:94-103):

  - PA:0.down → slug PA, params 0.down → ParityConstraint(idx=0, side="down"). But "down" is not a
  valid side (parity.dart:87-98 only accepts left/right/top/bottom/horizontal/vertical). The sides list
  stays empty, so verify() always returns true and apply() always returns null — dead constraint.
  - GS.1.1 → no :, slug becomes GS.1.1 → createConstraint returns null → silently ignored
  (constraint_registry.dart:38-43).
  - GS:7.6 → the only active constraint: cell 7 must belong to a group of size 6.

  Current state 121210101

  1 2 1
  2 1 0
  1 0 1
  Free cells: 5 and 7.

  findAMove() walkthrough (puzzle.dart:313)

  1. check() finds no error (Parity is a no-op; GroupSize returns !complete=true as long as c7 is empty
   — groups.dart:55-57).
  2. apply() → Parity returns null, then GroupSize on c7 enters the reachability branch
  (groups.dart:98-140):
    - emptyRegion = {7} (c5 is not a neighbor of c7).
    - Color 1: neighbors 4, 6, 8 are three singleton groups → 1 + 3 = 4 < 6 → forcedColor = 2.
    - Color 2: no color-2 neighbor → 1 + 0 = 1 < 6 → since forcedColor != null, returns Move(0,
  0, this, isImpossible: this).

  UI result (game_model.dart:306-309)

  showHelpMove enters the isImpossible != null branch:
  - GS:7.6.isValid = false (the constraint is highlighted in red).
  - hintText displays the error message, hintIsError = true.

  In plain terms: the hint tells the player that the puzzle has become unsolvable — cell 7 will never
   be able to form a group of 6 — and points to GS:7.6 as the violated constraint.


But it turns out that the solution 121211111 is valid and respects
both the partially solved state AND the GS:7.6 rule:

```
1 2 1
2 1 1
1 1 1
```
Group of c7 (value 1) = {2, 4, 5, 6, 7, 8} → size 6 ✓

## The bug in `GroupSize.apply()` (groups.dart:98-140)

The "reachability check" is too restrictive. It does a flood-fill
**only through empty cells** starting from c7:

```dart
final emptyRegion = <int>{idx};
// ... flood fill empty cells only
```

Then it adds the size of same-color groups **adjacent to that empty
region**.

For c7 in state `121210101`:
- `emptyRegion` = `{7}` alone (c5 is not directly adjacent to c7)
- Adjacent color-1 groups: `{4}`, `{6}`, `{8}` → `adjacentSize = 3`
- Total = `1 + 3 = 4 < 6` → declares color 1 impossible ❌

**What the computation misses**: c5 (empty) is adjacent to c4 and c8,
and c2 (color 1) is adjacent to c5. Coloring c5 and c7 as 1 merges
`{2}`, `{4}`, `{5}`, `{7}`, `{8}`, `{6}` → group of 6.

## Applied fix

The correct algorithm: flood-fill through **empty cells OR cells of
the target color**, starting from c7. The size of that connected
component is directly the maximum reachable group size for c7 in that
color.

- For color 1: `{7, 4, 5, 8, 2, 6}` = 6 ✓
- For color 2: `{7}` alone (all neighbors are color 1 and block the
  flood-fill) = 1 < 6 → color 2 impossible → c7 must be 1.

Code applied in `lib/getsomepuzzle/constraints/groups.dart` (the
`myColor == 0` branch of `apply()`):

```dart
int? forcedColor;
for (final color in puzzle.domain) {
  final reachable = <int>{idx};
  final queue = [idx];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    for (final nei in puzzle.getNeighbors(current)) {
      final v = puzzle.cellValues[nei];
      if ((v == 0 || v == color) && reachable.add(nei)) {
        queue.add(nei);
      }
    }
  }
  if (reachable.length < size) {
    if (forcedColor != null) {
      return Move(0, 0, this, isImpossible: this);
    }
    forcedColor = puzzle.domain.whereNot((v) => v == color).first;
  }
}
if (forcedColor != null) {
  return Move(idx, forcedColor, this);
}
```

With this fix, the hint proposes `c7 = 1` instead of declaring the
puzzle unsolvable.

## Regression test

`test/constraints_test.dart` → group `GroupSize.apply reachability` →
test `multi-merge: groups reachable via intermediate empty cell`:
reproduces the `121210101` state with `GS:7.6` and checks that
`apply()` returns `Move(idx=7, value=1)` without `isImpossible`.
