# Grayout Shape Constraint

## Rationale

`ShapeConstraint.isCompleteFor` returns `true` only when the grid is fully
filled (plus `verify(puzzle) == true`). Any state with at least one free
cell is considered **incomplete**, because:

1. Under the "no future deduction" semantics adopted for grayout
   (`docs/dev/grayout.md`), a constraint is only complete when `apply()`
   cannot fire in any reachable future state.
2. If free cells remain, at most one of two sub-cases is possible:
   - A free cell has a color-1 neighbour → some existing group has a free
     neighbour → it's not closed → `apply` can still extend / constrain it.
   - No free cell has a color-1 neighbour → every free cell is a
     "candidate": colouring it with `color` creates a 1-cell group. For any
     shape with more than one cell, this new group cannot match any variant,
     so `verify` fails and `apply` level 1 fires `isImpossible`.

In both sub-cases the constraint is still producing deductions (or actively
prohibiting a move), so grayout is premature.

## Consequence

`SH` grayout is effectively equivalent to "puzzle complete". Unlike the
monotone constraints (`FM`, `GS`, `LT`, `SY`, `CC`, `DF`, `PA`), `SH` does
not gain a useful mid-game grayout. This trade-off is accepted in exchange
for the stability of the grayout indicator (no flashing as cells are
coloured).

## Implementation

```dart
@override
bool isCompleteFor(Puzzle puzzle) {
  if (!verify(puzzle)) return false;
  return puzzle.cellValues.every((v) => v != 0);
}
```

Same shape as `QuantityConstraint.isCompleteFor` for the same reasons.
