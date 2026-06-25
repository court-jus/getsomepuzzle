# In-app puzzle editor

The editor (`CreatePage`, `lib/widgets/create_page/create_page.dart`) lets a
player author a puzzle by hand: choose a grid size, fix cells black/white, attach
constraints, watch the solver react live, then **test** the puzzle (play it
immediately) or **save** it into a writable playlist.

It is the manual counterpart to the generator (`docs/dev/generator.md`): same
`Puzzle` model and solver, driven by taps instead of search.

## Two phases

`build` switches on `_editing`:

1. **Dimensions form** (`_buildDimensionsForm`) — two sliders (width / height,
   each `3..10`) and a *Start* button, plus a text field that loads a puzzle
   from a pasted `v2_…` line (`_loadFromRepresentation`, via `Puzzle(line)`).
2. **Editor** (`_buildEditor`) — the grid plus top/side constraint bars, the
   playlist dropdown and the *Test* / *Save* buttons.

`_newPuzzle` (AppBar `+`) resets back to a blank 4×4 form.

## State

All editing state lives in `_CreatePageState`:

- **Geometry / content** — `_width`, `_height`, `_fixedCells`
  (`Map<int, CellValue>`, only black/white entries; absent ⇒ free) and
  `_constraints` (`List<Constraint>`).
- **Two-tap authoring modes** — `_letterGroupMode` (+ `_letterGroupLetter`,
  `_letterGroupIndices`) and `_majorityZoneMode` (+ `_majorityZoneColor`,
  `_majorityZoneFirstIdx`). See *Adding constraints*.
- **Live-solve output** — `_propagationCells`, `_forceCells` (cell-border
  colouring), `_solvedValues` (corner hints), `_autoComplexity`,
  `_autoImpossibleBy`, `_autoSolving`, debounced by `_solveDebounce`.
- **Save target** — `_targetPlaylist`.

### Surviving navigation

Pressing *Test* navigates away from the editor, which would normally dispose its
state. `_saveState` snapshots `(_width, _height, _constraints, _fixedCells)` into
the static `CreatePage.savedState` (an `EditorState`,
`lib/widgets/create_page/editor_state.dart`); `initState` restores and clears it.
So returning from a test session re-opens the same in-progress puzzle.

## Building the `Puzzle`

`_buildPuzzle()` is the single bridge from editor state to the engine:

```dart
final p = Puzzle.empty(_width, _height, defaultDomain);
for (final entry in _fixedCells.entries) {
  p.cells[entry.key].setForSolver(entry.value);
  p.cells[entry.key].readonly = true;   // fixed = readonly clue
}
p.replaceConstraints(_constraints);
```

It is cheap and side-effect-free, so it is called freely — once per live solve,
once per grid build (for the background painter), and on test/save. The domain is
always `defaultDomain` (two colours).

## Rendering

`_buildEditor` stacks four pieces above the grid body:

- **`_buildTopBar`** — global constraints with no anchor cell that show above the
  grid: `Motif`, `QuantityConstraint`, `GroupCountConstraint`,
  `BoundingBoxConstraint`, `ChainConstraint`. Each is wrapped in a
  `GestureDetector` whose tap calls `_confirmDeleteTopBar`. This list must stay in
  sync with the game's top-bar `Wrap` in `lib/widgets/puzzle.dart`.
- **`_buildColumnCountRow`** — per-column `CC` / `CT` indicators aligned to the
  grid columns, also tap-to-delete.
- **`_buildGrid`** — the grid itself, plus the left-side `RC` / `RT` indicators
  when present.
- Below: the *no constraints* hint, the playlist dropdown and the action buttons.

The grid is the shared **`PuzzleGridStack`**
(`lib/widgets/puzzle_grid_stack.dart`, see `docs/dev/constraints/implication.md`),
the exact widget the game uses. The editor passes `puzzle: _buildPuzzle()`,
`dfDefaultColor: Colors.blueGrey` / `dfHighlightColor: Colors.green` (the game
uses black87 / highlight) and a `cellBuilder` delegating to `_buildEditorCell`.
Sharing this widget guarantees the cell-colour background and the IM/DF/MJ
painters render identically to the game.

`_buildEditorCell` builds a `CellWidget` per cell:

- **fill** — `_fixedCells[idx]` or `CellValue.free` (painted by the stack's
  background painter; `readonly: isFixed`).
- **border** — amber for the active LT/MJ selection, else green for a
  `_propagationCells` cell, else orange for a `_forceCells` cell.
- **corner indicator** — `cornerIndicatorValue` shows the solved colour
  (`_solvedValues`) on non-fixed cells, previewing the unique solution.
- **tap** — `_onCellTap`. The drag/secondary callbacks are no-ops (the editor
  never colours by dragging).

## Cell interaction

`_onCellTap(cellIdx)` dispatches in order:

1. **MJ zone mode** → `_finishMajorityZone` (second corner).
2. **Letter-group mode** → toggle `cellIdx` in `_letterGroupIndices`.
3. **Tap inside an existing MJ zone** → `_showMjDeletePicker` lists the
   overlapping zones (by `serialize()`); picking one removes it.
4. Otherwise: an empty, unconstrained cell → `_pickAndAddConstraint`; a cell that
   already holds a constraint or a fixed value → `_openCellActions`.

`_openCellActions` (`showCellActionsDialog`, enum `CellAction`) offers
*add new* / *delete a constraint* (via `showDeleteConstraintPicker`) /
*remove fixed* / *fix black* / *fix white*.

## Adding constraints

`_pickAndAddConstraint` opens `showConstraintTypePicker`
(`dialogs/constraint_type_picker.dart`), which renders one tile per entry of
`constraintRegistry` using `previewForSlug` — so a newly registered slug appears
automatically, no edit here. The picker also returns the pseudo-slugs `fixBlack`
/ `fixWhite` for the pinned fix-colour row.

The returned slug drives a `switch` to the matching per-constraint dialog under
`dialogs/` (e.g. `showParityDialog`, `showBoundingBoxDialog`, …); each returns a
fully-built `Constraint` (or `null` on cancel) handed to `_addConstraint`. Anchor
cells / dimensions are passed so dialogs can default sensibly.

Two slugs are **two-tap modes** instead of a single dialog, because they need
multiple cells:

- **`LT` (letter group)** — `_startLetterGroup` asks for a free letter, enters
  selection mode; subsequent taps toggle cells; the AppBar *Done* button calls
  `_finishLetterGroup`, which emits `LetterGroup('<letter>.i.j.…')` when ≥ 2 cells
  are selected.
- **`MJ` (majority zone)** — `_startMajorityZone` asks for a colour and records
  the first corner; the next tap (`_finishMajorityZone`) defines the rectangle.
  Zones smaller than 3 cells are rejected with a `createZoneTooSmall` SnackBar.

## Deleting constraints

- **Top-bar / CC / CT / RC / RT widgets** — tap → `_confirmDeleteTopBar`
  (`showConfirmDeleteDialog`).
- **Cell-anchored constraints** — *delete a constraint* in the cell-actions
  dialog → `showDeleteConstraintPicker`.
- **MJ zones** — tapping a cell inside them → `_showMjDeletePicker`.

All removals go through `_removeConstraint`, which re-triggers a live solve.

## Live solve

Every mutation (`_addConstraint`, `_removeConstraint`, `_setFixedCell`,
load) calls `_scheduleAutoSolve`:

1. Mark `_autoSolving`, reset every constraint's `isValid` to `true` (clears the
   previous orange culprit highlight), and `debugPrint` the current line export.
2. After a **500 ms debounce**, `_autoSolve` builds the puzzle and runs
   `_solvePuzzle` in a `compute()` isolate.

`_solvePuzzle` mirrors `Puzzle.solveExplained`'s loop (capped at 1000 steps /
10 s) but also returns the `serialize()` of whatever raised an `Impossible`
(`impossibleBy`). Each step is classified:

- `SetValue` and non-force `RemoveOption` → **propagation** (green border).
- force `RemoveOption` (`isForce`) → **force** (orange border).

Back on the UI thread `_autoSolve` stores the per-cell sets, the solved values,
`computeComplexity()` and `impossibleBy`. When a contradiction is raised by a
real constraint present in `_constraints`, that instance's `isValid` is set
`false` so its widget shows the orange border (the same convention as
`_revealErrors` in `game_model.dart`); complicities have no widget, so the bottom
bar instead shows the `serialize()` label next to the complexity.

The bottom bar (`BottomAppBar`) shows size, constraint count and a brain icon
with the complexity (`...` while solving, red `<cplx> (<culprit>)` when
impossible-by-complicity).

## Test & save

- **`_testPuzzle`** — `_saveState()`, then export the line with
  `lineExport(compute: false)` (no precomputed difficulty) and hand a
  `PuzzleData` to `onPuzzleSelected`; `onTestStarted` lets the host start a test
  session.
- **`_savePuzzle`** — `lineExport()` (with difficulty), `addToPlaylist` into
  `_targetPlaylist`, reload that file, confirm with a SnackBar.
- The playlist dropdown lists writable playlists; the `__new__` entry calls
  `_createNewPlaylistForSave` (`showPlaylistNameDialog` → `createUserPlaylist`).

## Files

- `create_page.dart` — the page, all state and handlers above.
- `editor_state.dart` — `EditorState` snapshot for navigation survival
  (re-exported from `create_page.dart`).
- `dialogs/` — one dialog per constraint slug plus the shared pickers
  (`constraint_type_picker.dart`, `cell_actions_dialog.dart`,
  `confirm_delete_dialog.dart`, `playlist_name_dialog.dart`).
- `shared/color_count_dialog.dart` — reusable colour-count input used by several
  constraint dialogs.
