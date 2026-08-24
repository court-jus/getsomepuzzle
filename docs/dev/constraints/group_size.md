# Group Size Constraint

The Group Size constraint (`GS`) anchors on one cell and fixes the exact size
of the **connected group** containing that cell: in the solved puzzle, the
group must have exactly `size` cells.

It is **colour-agnostic** — it constrains the *size* of the group, whatever
colour the group ends up being. `referencedColors` returns the empty set, so
the domain auto-shrink pass never treats `GS` as depending on a specific
colour (same as `PA`, `LT`, `DF`, `SY`).

`families.dart` maps `'GS' → 'group-topology'` (alongside `GC`, `SH`, `SY`,
`MJ`, `BB`).

## Syntax

`GS:idx.size` (slug:anchorIdx.size). `idx` is the anchor cell index; `size`
is the target group size. `GS:8.3` means "the connected group containing
cell 8 must have exactly 3 cells".

## Parameter generation

`generateAllParameters` emits every `(idx, size)` pair, with sizes
`1 ≤ size < maxSize`, where

```
maxSize = min(_maxGroupSizeAbsolute, max(1, (width * height * _maxGroupSizeRatio).toInt()))
```

`_maxGroupSizeRatio = 0.5`, `_maxGroupSizeAbsolute = 15` — a group never
exceeds half the grid (capped at 15).

## Semantics

### verify

- No group contains the anchor yet: valid while the puzzle is incomplete
  (the anchor's cell is free or its group is still forming).
- Puzzle complete: valid iff the anchor's group has exactly `size` cells.
- Puzzle incomplete, group exists: valid iff the group *can still* reach the
  target:
  - if some member has a growable free neighbour (a free cell that still has
    the group's colour in its options), the group must not already exceed
    `size`;
  - otherwise (no growable neighbour left) the group must already be exactly
    `size`.
  
  The growable-neighbour check is colour-aware: on a 3+-colour puzzle a free
  cell whose `myColor` option has been pruned can never join the group, so it
  does not keep the group growable.

### apply

Deductions are grouped by whether the anchor cell is still free:

**Anchor free** (`myColor == free`):
- Neighbour overshoot: any neighbour whose existing group is already `≥ size`
  prunes its colour from the anchor's options (complexity 1).
- Per-colour feasibility (`complexity: 3`), for each colour still in the
  anchor's options:
  - *Reachability*: flood-fill from the anchor through cells that have the
    colour as value or option; component smaller than `size` → prune.
  - *Mandatory-merge overshoot*: colouring the anchor absorbs every
    adjacent same-colour group; if that mass already exceeds `size` → prune;
    if it is below `size`, check whether some boundary cell can grow the
    mass without overshooting (`addition ≤ margin`); if no boundary is
    viable → prune.

**Group exists**:
- `group.length == size` — group finished: prune `myColor` from any free
  neighbour of a member (complexity 0).
- `group.length > size` — `Impossible`.
- `group.length < size`:
  - Single-exit overshoot: if the group has exactly one free neighbour and
    colouring it would merge same-colour groups whose total addition exceeds
    the remaining margin → `Impossible`; otherwise the lone exit is forced to
    `myColor` (`SetValue`, complexity 1), unless the exit's options already
    exclude it → `Impossible`.
  - No free neighbours at all → `Impossible`.
  - Boundary merge overshoot: a free neighbour whose colouring would merge
    same-colour groups with combined size `≥ margin` gets `myColor` pruned
    (complexity 2).
  - Path-based articulation (complexity 4): any empty cell whose blocking
    shrinks the reachable `myColor`/empty region below `size` lies on every
    growth path and must take `myColor` (`SetValue`); if its options exclude
    the colour → `Impossible`. This generalises the single-exit rule to
    bottlenecks several steps away.

### isCompleteFor

`verify` holds, the anchor's group is exactly `size`, and no member has a
free neighbour that still has `myColor` in its options (so `apply()` can
never fire again).

## Implementation

**Location**: `lib/getsomepuzzle/constraints/group_size.dart`

`GroupSize extends CellsCentricConstraint` (anchor stored in `indices.first`).
Fields: `size` (int).

- **`slug`** → `'GS'`
- **`serialize()`** → `'GS:${indices.first}.$size'`
- **`toString()`** → the target size; **`toHuman()`** → `'Group at <idx+1> = <size>'`.
- **`rotated(...)`** — re-maps the anchor 90° CW; size unchanged.

Group computation is shared: `getGroups` (flood-fill over equal values) from
`lib/getsomepuzzle/utils/groups.dart`, with `floodFill`,
`reachableComponentSize` and `blockingShrinksReachableBelow` backing the
articulation logic.

### Note on no-op pruning

`apply` skips colours already pruned from the anchor's options
(`if (!puzzle.cells[idx].options.contains(color)) continue;`) — re-emitting a
`removeOption` for an already-pruned colour is a no-op the solve loop would
livelock on (only reachable on 3+ colour domains).

## Display

`GroupSizeWidget` (`lib/widgets/constraints/group_size.dart`) renders inside
the anchor cell: the live `actualGroupSize` as small text over the target
`size` in large text (`"actual/target"`). The live count comes from the
per-cell `getCellGroupSize` callback wired in `lib/widgets/puzzle.dart`
(computed once per build from the shared `getGroups` flood-fill).

l10n: `constraintGroupSize` (name), `constraintExplainGS` (first-contact
help). Editor entry: `showGroupSizeDialog`
(`lib/widgets/create_page/dialogs/group_size_dialog.dart`), which reuses the
shared `showColorCountDialog` body (`lib/widgets/create_page/dialogs/shared/color_count_dialog.dart`)
— a colour picker plus a count slider.

## Tests

- `test/constraints_test.dart` — `GroupSize` apply paths (including the
  no-op-prune livelock regression on 3-colour domains).
- `test/is_complete_test.dart` — `isCompleteFor` over the group.
- `test/rotation_test.dart` — anchor rotation round-trips.
- `test/generator_test.dart` — generation with GS candidates.
- `test/complicities_test.dart` — `GSAllComplicity` tagging
  (`slugs = ('GS', 'FM')` when a single FM rejects every sealing; `('GS', '*')`
  fallback otherwise).
- `test/contributors_test.dart` — GS moves list their contributing
  constraints.
