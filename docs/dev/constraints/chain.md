# Chain Constraint

The Chain constraint (slug CH) requires a **continuous path** of orthogonally adjacent cells
of a given `color` connecting one side of the grid to another.

Serialized as `CH:1.left.right` (slug:color.fromSide.toSide).

This is a global connectivity constraint: unlike `LetterGroup` (which connects specific named
cells) or `GroupSize` (which constrains a single group's cardinality), CH requires a
border-to-border traversal without specifying which cells participate. The player must reason
about path existence and blocking — the core mechanic of the game Hex, adapted as a logic-puzzle
constraint.

## Syntax

`CH:1.left.right` — a black (color 1) path must connect the left edge to the right edge.
`CH:2.top.bottom` — a white (color 2) path must connect the top edge to the bottom edge.

**Valid sides**: `left`, `right`, `top`, `bottom`.

**Opposite pairs**: `left↔right` and `top↔bottom` are the only pairs used — they produce the
most natural traversal puzzles. Adjacent-side pairs (e.g. `left.top`) are not generated.

**Path definition**: a sequence of orthogonally adjacent cells (4-connectivity), all of the
same `color`, where at least one cell lies on `fromSide` and at least one cell lies on
`toSide`. The path may branch, loop, or widen — it need not be a simple line.

## Implementation

**File**: `lib/getsomepuzzle/constraints/chain.dart`

`ChainConstraint` extends `Constraint` with three fields:
- `color` — the cell value (1 or 2) that forms the chain
- `fromSide` — the starting border (`left`, `right`, `top`, `bottom`)
- `toSide` — the target border

### `_borderCells(side, width, height)` → `List<int>`

Returns the cell indices on a given side:

```
left:   [0, width, 2*width, ..., (height-1)*width]
right:  [width-1, 2*width-1, ..., height*width-1]
top:    [0, 1, 2, ..., width-1]
bottom: [(height-1)*width, ..., height*width-1]
```

### `_isBlocked(Puzzle)` → `bool`

Checks whether the `color` chain is permanently severed — i.e. no path of cells that can still
take `color` connects the two sides.

Delegates to the shared `canReach` helper (`lib/getsomepuzzle/utils/groups.dart`): flood-fill
from every **passable** cell on `fromSide`, traversing passable cells only. A cell is
*passable* for the chain iff it can still become `color`: it is already `color`, **or** it is
still free *and* `color` is among its remaining options. A committed cell of any other colour
blocks the path — and so does a free cell whose `color` option has been pruned (possible only
on a 3+-colour puzzle, via another constraint's `removeOption`). If `toSide` is unreachable
through passable cells, the path is permanently blocked.

When no passable cell exists on `fromSide` (every border cell on that side is either the
wrong colour or a free cell that can no longer be `color`), the start set is empty and
`canReach` returns `false` → blocked.

When the puzzle is complete (no free cells), "passable" reduces to "already `color`", so
`_isBlocked` doubles as a final-state path check.

### `verify(Puzzle)` → `bool`

```
return !_isBlocked(puzzle)
```

`_isBlocked` already handles both the unreachable-but-incomplete case and the complete-but-no-
path case (see the note above), so `verify` collapses to a single negated call.

### `apply(Puzzle)` → `Move?`

Three deduction branches, checked in order:

1. **Impossible** — `_isBlocked(puzzle)` → `Move(isImpossible: this)`. Covers both the
   opposite-color-barrier case and the case where every cell on `fromSide` or `toSide` is
   already the opposite color.

2. **Border saturation** (complexity 1) — if exactly one free cell remains on `fromSide` (or
   `toSide`) and all other cells on that side are opposite, that cell must be the target color
   (the only possible path start/end).

3. **Forced bridge** (complexity 2) — for each free cell, simulate setting it to the opposite
   color on a clone and check `_isBlocked`. If the clone becomes blocked, the real cell must
   be the target color (it's the only bridge between path components).

Returns `null` when no deduction is possible.

### `_hasCompletePath(Puzzle)` → `bool`

Delegates to the shared `canReach` helper: flood-fill from every `fromSide` cell whose value
is **exactly** `color`, traversing only cells of value `color` (free cells do *not* count,
unlike `_isBlocked`). Returns `true` if `toSide` is reached — i.e. a finished path of
already-placed target-color cells connects the two sides.

### `isCompleteFor(Puzzle)` → `bool`

```
return verify(puzzle) && _hasCompletePath(puzzle)
```

Once a path of target-colored cells connects the two sides, the constraint is guaranteed
satisfied at the end of the game: placed cells are immutable, so the path can never be
broken. `verify` stays `true` forever, `_isBlocked` can never become `true`, and no `apply`
branch can fire again (border saturation requires all-but-one border cells opposite, which
the path's border cell contradicts; forced bridge requires `_isBlocked` on a clone, which the
intact path prevents). The completion criterion is therefore **monotone** and CH grays out
mid-game as soon as the player finishes any connecting path.

### `generateAllParameters(width, height, domain, excludedIndices)`

Generates only opposite-side pairs for each color in the domain:
```
for color in domain:
  yield '$color.top.bottom'
  yield '$color.left.right'
```

Parameter space: O(|domain| × 2) — 4 entries for a binary domain.

### Rotation

90° clockwise rotation maps sides as: `top→right→bottom→left→top`. After mapping, the
resulting pair is canonicalized to `top.bottom` / `left.right` (i.e. swapped when the raw
output would be `bottom.top` or `right.left`) so rotated constraints match the forms produced
by `generateAllParameters`.

## Display

**File**: `lib/widgets/chain.dart`

CH is displayed in the top bar (like QA, GC) as a square containing a fixed 6×6 mini-grid
with a predefined path drawn without internal borders.

- **Mini-grid**: always 6×6, showing a fixed diagonal-like path:
  - Vertical chains (top↔bottom, left↔right via `_chainPathCells`):
    indices `{1, 7, 8, 14, 15, 21, 22, 28, 34}` (row-col: `(0,1)→(1,1)→(1,2)→(2,2)→...`)
  - Horizontal chains (left↔right, right↔left via `_chainPathCellsHorizontal`):
    indices `{10, 11, 15, 16, 20, 21, 24, 25, 26}` — the 90° CW rotation of the vertical set.
- **Path color**: defaults to the constraint color (black for 1, white for 2) via the
  `_textColors` map, but can be overridden by the optional `fgcolor` parameter passed by
  `to_flutter._chainWidget`.
- **Background**: neutral grey for unfilled cells.
- **State colors**: grey (neutral), green (valid), red (invalid), highlightColor (highlighted).

The specific sides involved (`fromSide`, `toSide`) are **not** encoded in the mini-grid icon.
They are conveyed through the constraint label and detail view.

When CH is highlighted, the top-bar indicator switches to `highlightColor` (both border and
path). The grid's source/target border cells are **not** tinted — players locate the relevant
sides via the constraint label only.

## Gameplay

### Passive obstacle

CH is a **passive obstacle** constraint: it never requires the player to actively construct a
specific path. It only demands that *at least one* continuous path of the target color exists
between the two sides. The player's job is to **avoid inadvertently blocking every possible
path** — a failure detectable only once a complete opposite-color barrier separates the sides.

This makes CH a constraint of avoidance rather than construction, closer in spirit to FM
(forbids specific patterns) than to GS or LT (require active group building). The deduction
patterns in `apply` fire only when the state forces a specific cell to prevent permanent
blockage — not to build the "intended" path.

### Topological reasoning

CH introduces **topological reasoning** — the player thinks about connectivity, cuts, and
bottlenecks rather than counts or shapes.

### Key deduction patterns

#### Forced bridge (weight 2)

Two segments of the target-color path are separated by a single free cell. That free cell
must take the target color to connect them, otherwise no path can exist.

```
1 1 0 2 2
1 1 ? 2 2    →  ? must be 1 (the only bridge between left and right segments)
1 1 0 2 2
```

#### Border saturation (weight 1)

If all cells on the source side except one are the opposite color, that remaining cell must
be the target color (it's the only possible path start). Symmetrically for the target side.

#### Opposite-color barrier (weight 2)

If a continuous wall of the opposite color already separates the source side from the target
side (detected by flood-fill), the constraint is impossible.

## Integration

### Registry

**File**: `lib/getsomepuzzle/constraints/registry.dart`

Registered under slug `CH` in `constraintRegistry` (alphabetical order), with
`fromParams: ChainConstraint.new` and `generateAllParameters` pointing to the static method.

### to_flutter.dart

**File**: `lib/getsomepuzzle/constraints/to_flutter.dart`

Routes `ChainConstraint` instances to `ChainWidget` via a private `_chainWidget` builder,
sized proportionally to the constraint count in the top bar.

### Generator

**File**: `lib/getsomepuzzle/generator/prefill/path.dart`
**File**: `lib/getsomepuzzle/generator/prefill/sy.dart`

CH is listed in the `_guardRailSlugs` list for both the path-based and symmetry-based
guard-rail prefill scenarios, alongside GC, CC, RC, QA, etc.

No manual integration needed for the main generator — it uses `generateAllParameters` from
the registry dynamically. CH constraints are satisfiable roughly ~50% of the time on 3×3
grids with random 50/50 fill; the generator's solution-validity filter handles failures
naturally.

### Localization

**Files**: `lib/l10n/app_en.arb`, `app_fr.arb`, `app_es.arb`

Keys:
- `constraintChain` — EN: `"chain"`, FR: `"chaîne"`, ES: `"cadena"`
- `constraintExplainCH` — explanation shown in the new-constraint dialog

### Onboarding

CH is included in the discovery-order slug lists in `test/onboarding_test.dart`,
`test/onboarding_filters_test.dart`, `bin/cluster_puzzles.dart`,
`bin/extract_onboarding.dart`, `bin/vectorize_puzzles.dart`, and
`integration_test/helpers/harness.dart`.

## Known limitations

- **`apply()` handles only simple deductions.** Forced-bridge detection requires simulating
  `f = opposite` for each free cell and checking `_isBlocked` — `O(freeCells × floodFill)`
  per call. Acceptable for typical grid sizes (up to ~12×12).
- **Cut-set reasoning not implemented.** Multi-cell minimal cuts (where a set of cells forms
  a bottleneck) are not detected. The forced-bridge check covers single-cell cuts; multi-cell
  cuts are deferred.
- **No complicity implemented.** Cross-constraint deductions between CH and GS, FM, SY, etc.
  are natural candidates for future work.
- **Multi-path ambiguity.** CH only requires *existence* of a path, not uniqueness. The
  player may need to deduce which path is the "real" one when multiple are possible. This is
  intentional — the constraint is about existence, not specificity.
