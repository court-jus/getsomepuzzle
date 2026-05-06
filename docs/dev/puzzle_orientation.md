# Puzzle Auto-Rotation (Screen Orientation Match)

When a landscape puzzle (width > height) is rendered on a portrait screen — or
a portrait puzzle on a landscape screen — `cellSize` collapses on the
constrained dimension and the grid renders tiny cells with a wide empty band
along the other axis. The auto-rotation feature transforms the puzzle 90°
clockwise on the fly so its aspect ratio matches the available screen.

The rotation is **logically transparent**: same domain, same solutions, every
constraint preserved (re-expressed for the rotated layout). Stats, progress and
deductive complexity are unaffected.

## Trigger

`lib/main.dart::_MyHomePageState.build`, right after the `MediaQuery` reads.

```dart
final puzzleLandscape = p.width > p.height;
final screenLandscape = screenW > screenH;
if (p.width != p.height && puzzleLandscape != screenLandscape) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (!identical(game.currentPuzzle, p)) return;
    game.rotateCurrentPuzzle();
  });
}
```

- Square puzzles are skipped — rotation has no display benefit.
- The mutation is deferred via `addPostFrameCallback` so we never mutate state
  during a `build` pass.
- The post-frame guard checks `identical(game.currentPuzzle, p)` to avoid
  re-rotating a puzzle that has already been replaced (e.g. by a concurrent
  `openPuzzle`).
- The loop terminates after one rotation: once dimensions are swapped, the
  predicate is satisfied and no further rotation is scheduled. If the user
  flips the device, the next build sees a fresh mismatch and rotates back.

## Rotation primitives

`lib/getsomepuzzle/utils/rotation.dart` exposes two helpers used everywhere a
positional value must be re-mapped:

- `rotateIdx90CW(idx, width, height)` — converts a 1D cell index of a
  `(width, height)` grid into the 1D index it occupies after a 90° CW
  rotation (in the new `(height, width)` grid). Mapping:
  `(c, r) → (newCol = H-1-r, newRow = c)`.
- `rotate2D90CW(grid)` — rotates a 2D `List<List<T>>` 90° CW. Used by the
  `ForbiddenMotif` rotation path.

## `Constraint.rotated(int origWidth, int origHeight)`

Defined as abstract on `Constraint` (`lib/getsomepuzzle/constraints/constraint.dart`).
Every concrete subclass overrides it. The arguments are the dimensions of the
puzzle **before** rotation; the returned constraint is valid against the
post-rotation `(origHeight, origWidth)` grid.

| Slug   | File                  | Behaviour                                                                                          |
| ------ | --------------------- | -------------------------------------------------------------------------------------------------- |
| `QA`   | `quantity.dart`       | Identity (no positional data).                                                                     |
| `GC`   | `group_count.dart`    | Identity (no positional data).                                                                     |
| `SH`   | `shape.dart`          | Identity. `variants` already covers all 8 rotations/mirrors of the shape.                          |
| `GS`   | `groups.dart`         | Re-index the anchor cell via `rotateIdx90CW`.                                                      |
| `LT`   | `groups.dart`         | Re-index every entry of `indices`.                                                                 |
| `NC`   | `neighbor_count.dart` | Re-index the anchor cell.                                                                          |
| `EY`   | `eyes_constraint.dart`| Re-index the anchor cell. The 4-direction scan in `whatDoIsee` is symmetric — no further changes.  |
| `CC`   | `column_count.dart`   | Swap class to `RowCountConstraint`. Column `c` becomes row `c` after 90° CW.                       |
| `RC`   | `row_count.dart`      | Swap class to `ColumnCountConstraint`. Row `r` becomes column `H-1-r`.                             |
| `PA`   | `parity.dart`         | Re-index. Remap `side`: `left→top`, `right→bottom`, `top→right`, `bottom→left`, `horizontal↔vertical`. |
| `DF`   | `different_from.dart` | `right@idx → down@rotateIdx(idx)`; `down@idx → right@rotateIdx(idx + W)` (anchor shifts to the original `down` neighbour, which is the new `left` neighbour). |
| `SY`   | `symmetry.dart`       | Re-index. Remap `axis`: `1↔3` (⟍↔⟋), `2↔4` (\|↔―), `5` (point) invariant.                            |
| `FM`   | `motif.dart`          | Rotate the 2D `motif` pattern via `rotate2D90CW`.                                                  |

### Why some constraints aren't trivial

- **CC ↔ RC swap.** They are different classes; you can't keep `CC` after a
  90° rotation because what used to be a column is now a row.
- **PA sides.** A cell originally to the **left** of the anchor lands
  **above** it after 90° CW. The full mapping is a 4-cycle on the cardinal
  sides plus a 2-cycle on horizontal/vertical.
- **DF anchor shift.** `right@(c, r)` pairs `(c, r)` with `(c+1, r)`. After
  rotation those map to two cells in the same column → the relation is now
  vertical, anchored at the rotation of `(c, r)` → emit `down@rotateIdx(idx)`.
  But `down@(c, r)` pairs `(c, r)` with `(c, r+1)`, which after rotation are
  in the same row, with the original "bottom" cell now on the **left**. The
  `right` direction must be anchored on the left cell, so we re-anchor on the
  rotation of `idx + W`.
- **SY axes.** Derived from the rotation transform of `(dx, dy)`: 90° CW
  sends `(dx, dy) → (-dy, dx)`. Diagonals and orthogonals each form a 2-cycle;
  point symmetry is invariant.

### Adding a new constraint

`Constraint.rotated()` is abstract in the base — the analyzer will not flag a
missing override (Dart allows it on a non-abstract base) but tests in
`test/rotation_test.dart` will fail. Every new `Constraint` subclass must
provide its own `rotated()` implementation. If unsure, fall back to a clone of
the constraint produced through its own `serialize()`.

## `Puzzle.rotated()`

Defined in `lib/getsomepuzzle/model/puzzle.dart`. Reconstructs a v2 line
representation of the rotated puzzle and feeds it back through the regular
`Puzzle(line)` constructor.

What is preserved across rotation:

- **Cell values.** Each cell's value is moved to its rotated index.
- **Readonly flag.** The prefill (`cells with value > 0` at construction) is
  rebuilt over the rotated grid.
- **Cached solution.** If `cachedSolution` is set, every value is moved to the
  rotated index and a `1:<digits>` solution segment is emitted.
- **Cached complexity.** Reused as-is.
- **Player progress.** Non-readonly cells with values are written back as a
  trailing `_p:<digits>` field, so the parser restores them on construction.

The constructor parses the new line, instantiates fresh `Cell` objects and
fresh `Constraint` instances — UI flags (`isHighlighted`, `isValid`,
`isComplete`) are reset to defaults.

## Canonical key invariance

`canonicalPuzzleKey` (`lib/getsomepuzzle/model/canonical.dart`) is
**rotation-invariant**: a puzzle and any of its rotations canonicalize to the
same key. This is what keeps stats merged across orientations — the player's
plays of the original orientation and of the rotated orientation share one
stats entry.

The implementation enumerates all 4 rotations of the input and returns the
lexicographically smallest identity key. Two rotations are not enough: if the
180° rotation of `L` happens to be lex-smaller than both `L` and `rot(L)`, the
two-rotation `min` picks different values when called on `L` versus `rot(L)`.
Cost: one `Puzzle(...)` parse plus 3 rotations per call. Only invoked at stats
write/read time and at puzzle open — never inside the solver hot path.

## `GameModel.rotateCurrentPuzzle`

`lib/getsomepuzzle/model/game_model.dart` exposes the user-facing entry point.

```dart
void rotateCurrentPuzzle()
```

The method **toggles** between two states:

- **Native** (`_isPuzzleRotated == false`): the puzzle is in the orientation
  delivered by `PuzzleData.begin()` — i.e. the database line.
- **Rotated** (`_isPuzzleRotated == true`): the puzzle has been rotated 90°
  clockwise from native.

Each call swaps states. From native we apply one 90° CW transform; from the
rotated state we apply **three** 90° CW transforms (= 90° CCW), so the puzzle
lands back on its native layout instead of on a 180°-flipped layout. Without
this, two successive screen-orientation changes (portrait → landscape →
portrait) would leave the player on `rot²(orig)` rather than `orig` — visually
disorienting.

Steps:

1. Skip if there is no puzzle, or it is square.
2. Determine `quarters = _isPuzzleRotated ? 3 : 1`.
3. Translate every entry of the undo `history` through `quarters` successive
   `rotateIdx90CW` calls (with the dimension swap at each step) so undo keeps
   popping the right cells in the new grid.
4. Drop transient interaction state (`firstDragValue`, `lastDragIdx`,
   `firstRightDragValue`, `lastRightDragIdx`, `_pendingRightClickIdx`,
   `helpMove`) — those indices live in the **old** grid.
5. Apply `Puzzle.rotated()` `quarters` times.
6. Flip `_isPuzzleRotated`.
7. Run `_afterMutation` to clear hints, reschedule help and ranking workers,
   notify listeners, re-arm the idle watchdog.

`_isPuzzleRotated` is reset to `false` in `openPuzzle` and `clearPuzzle` so a
new puzzle always starts from the native state.

## Tests

`test/rotation_test.dart` covers:

- `rotateIdx90CW` corner mapping and the 4-cycle invariant on a non-square
  grid.
- `rotate2D90CW` on a 2x3 reference pattern.
- Per-constraint 4-fold identity: every concrete `Constraint` subclass must
  return to its starting `serialize()` after four 90° rotations.
- `Puzzle.rotated()` 4-fold identity (compared via `canonicalPuzzleKey`) and
  dimension swap on a non-square puzzle.
- End-to-end "rotation preserves solubility" on three real puzzles
  (`assets/4-strong.txt`, `assets/3-advanced.txt`) — a square 4x4, a
  landscape 6x5 and a portrait 4x6 — picked so their union of slugs spans
  every player-facing constraint type (FM, PA, GS, LT, QA, SY, DF, CC, RC,
  GC, NC, EY, SH).
- `canonicalPuzzleKey` rotation invariance on the same three puzzles.

## Caveats / known limitations

- **Mid-drag rotation** would corrupt the gesture state. In practice the user
  cannot rotate the device fast enough between two drag events to reproduce
  this; defensive code in `rotateCurrentPuzzle` clears all drag state on
  rotation.
- **`PuzzleData` line stays original.** `currentMeta` (and the database file)
  is unaffected by runtime rotation. When stats are written, the source line
  for the stats entry is `PuzzleData.lineRepresentation` — the canonical key
  takes care of merging stats across orientations.
- **Generator unchanged.** New puzzles are created in their natural
  orientation. Auto-rotation only kicks in at render time on the player's
  device.
