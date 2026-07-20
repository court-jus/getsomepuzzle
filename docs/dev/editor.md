# In-app puzzle editor

The editor (`CreatePage`, `lib/widgets/create_page/create_page.dart`) lets a
player author a puzzle by hand: choose a grid size, fix cells black/white, attach
constraints, validate it with the solver on demand, then **test** the puzzle
(play it immediately) or **save** it into a writable playlist.

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
- **Solver feedback** — `_propagationCells`, `_forceCells` (cell-border
  colouring) and `_solvedValues` (corner hints), populated by the last
  validation run and cleared on the next edit.
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

It is cheap and side-effect-free, so it is called freely — once per validation
run, once per grid build (for the background painter), and on test/save. The
domain is always `defaultDomain` (two colours).

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
- **corner indicator** — `cornerIndicatorValue` shows the deduced colour
  (`_solvedValues`) on non-fixed cells, previewing the solution.
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

All removals go through `_removeConstraint`, which also clears the solver
feedback.

## Solver validation

A **Validate** button (`createValidate` l10n key) in the `BottomAppBar`
runs the solver on demand and opens a modal report dialog. Every edit
(`_addConstraint`, `_removeConstraint`, `_setFixedCell`, puzzle load)
calls `_clearSolveFeedback()` inside its `setState`, which empties the
feedback sets and resets every constraint's `isValid` to `true` — the
grid only ever displays the outcome of the latest validation run on the
current puzzle.

### Dialog

`showSolverReportDialog` (`dialogs/solver_report_dialog.dart`) is a
stateful `AlertDialog` with two phases:

1. **Progress** — a `CircularProgressIndicator` plus the
   `createSolverChecking` label, while the solver runs in a `compute()`
   isolate (`_solvePuzzle`). The dialog cannot be dismissed
   (`barrierDismissible: false`, no close button); a solver failure pops
   it with `null`.
2. **Report** — once the solver finishes, the dialog swaps its content
   for the deduction counts and the verdict, with a single *OK* button
   that pops the dialog and returns the `SolverReport`.

### Report content

**Deduction counts** — over the free (non-fixed) cells, via
`createSolverDeducible` (deduced X / total Y), plus a
`createSolverBruteForce` sub-line giving the brute-force share when at
least one cell required it.

**Verdicts** (mutually exclusive, priority order):

1. **Contradiction** — `impossibleBy != null`. Error icon and the
   `createSolverContradiction` message naming the culprit.
2. **Incomplete** — no contradiction, but the solver stalled. Warning
   icon and the `createSolverIncomplete` message suggesting more
   constraints.
3. **Solved** — the solver completed the grid. Success icon and the
   `createSolverValid` message, which embeds the **localised
   playable-collection name** matching the solver trace (via
   `classifyTrace` → `levelToPlayableCollectionKey` →
   `CollectionLabels.labelFor`). `maxPrefill: 1.0` disables the
   prefill-ratio rerouting, since fixed cells are author-chosen clues
   rather than generator prefill.

### Grid feedback

When the dialog closes with a report, `_validatePuzzle` applies it to
the editor state:

- **green border** on `propagationCells` (cells deduced by pure
  propagation);
- **orange border** on `forceCells` (cells whose first deduction occurs
  at or after the first `SolveMethod.force` step);
- **corner triangle** on every deduced cell, showing the value the cell
  first took in the trace (a `RemoveOption` on the 2-colour domain
  resolves to the surviving colour).

The per-cell sets are populated even when the solve is incomplete or
contradictory, so the author still sees what the solver managed to
deduce. When the contradiction was raised by a regular `Constraint`
present in `_constraints`, that instance's `isValid` is set to `false`
so its widget shows the orange border (same convention as
`_revealErrors` in `game_model.dart`); complicities have no widget, so
the dialog message is their only highlight. The feedback persists until
the next edit clears it, and amber LT/MJ/IM selection borders keep
precedence over solver borders.

### Definitions

- **Deduced cell** — a non-fixed cell whose value becomes known while
  replaying the trace: target of a `SetValueStep`, or of a
  `RemoveOptionStep` whose surviving option (2-colour domain) becomes
  the value.
- **Brute-force cell** — a deduced cell whose *first* deduction step
  occurs at or after the first `SolveMethod.force` step in the trace.
- **Corner value** — the value a deduced cell first takes during the
  replay.

### SolverReport & `_solvePuzzle`

`_solvePuzzle` (`create_page.dart`, run in the isolate) builds the
`SolverReport` (`dialogs/solver_report.dart`) on top of the shared
`Puzzle.solveTrace` loop (the same deduction loop backing
`Puzzle.solveExplained`, capped at 1000 steps; the editor passes a 10 s
timeout). `solveTrace` returns the recorded `steps`, the `serialize()`
of the constraint/complicity that raised the contradiction
(`impossibleBy`) and an `aborted` flag for the timeout; the per-cell
sets (`propagationCells`, `forceCells`, `cornerValues`) and the
`solved` flag are derived by replaying the trace on a clone inside the
isolate. The report also carries `deducedCount`, `bruteForceCount` and
`totalFreeCells` for the dialog.

Steps record `isComplicity: givenBy is Complicity` so `classifyTrace`
can distinguish complicities from single-constraint deductions.

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
  `confirm_delete_dialog.dart`, `playlist_name_dialog.dart`) plus
  the solver report dialog (`solver_report_dialog.dart`) and its
  `SolverReport` data class (`solver_report.dart`).
- `shared/color_count_dialog.dart` — reusable colour-count input used by several
  constraint dialogs.
