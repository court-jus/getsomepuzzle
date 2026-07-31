# Autopilot mode

Autopilot mode drives the puzzle UI from an external scenario file, moving a
fake mouse cursor and mutating the puzzle state. It is activated by the
`--scenario=<path>` CLI flag and is intended for automated demonstrations,
screenshots, and visual regression testing.

## Activation

Pass a scenario file path at launch:

```
getsomething --scenario=/path/to/scenario.txt
```

The flag is parsed in `main()` alongside the existing `--no-onboarding` and
`--lang=` flags. The path is threaded through `MyApp` → `MyHomePage` and
consumed by `_MyHomePageState.initialize()`. When a scenario path is present,
the app suppresses all onboarding modals, new-constraint dialogs, the locale
chooser and the idle auto-pause; it also skips loading stats and the puzzle
database entirely.

## Scenario file format

One action per line. Lines starting with `#` are comments. Empty lines are
ignored. Unquoted tokens are split on whitespace; double-quoted strings
(`"..."`) are treated as a single token and `\n` inside quotes becomes an
actual newline.

### Actions

| Action | Syntax | Behaviour |
|--------|--------|-----------|
| `loadState` | `loadState <v2_line>` | Replace the current puzzle with the given v2 line. Malformed lines are logged and skipped. |
| `wait` | `wait <ms>` | Pause execution for N milliseconds. |
| `mouse` | `mouse <col>,<row>` | Move the fake cursor to the centre of the grid cell at column `col`, row `row` (0-indexed, origin top-left). Cursor becomes visible on the first `mouse` or `mouseTo` action. The movement is animated at 1 px/ms, clamped to a minimum of 200 ms and a maximum of 500 ms. The next action does not start until the animation completes. |
| `mouseTo` | `mouseTo <target>` | Move the fake cursor to a named UI widget (see targets below). Same animation rules as `mouse`. |
| `setValue` | `setValue <col>,<row>,<color>` | Set the cell at `(col, row)` to the named colour value. Waits for one frame after the mutation so the UI redraws before the next action. |
| `hint` | `hint` | One tap on the hint button. Follows the multi-tap flow: in `deducibleCell` mode each call advances the stage (errors → cell → cell+constraint → apply → restart); in `addConstraint` mode (errors → attach constraint). Waits for the hint's visual changes to paint before continuing. |
| `dialog` | `dialog "title" "body"` | Show a subtitle overlay at the centre of the screen (light-green text with a thin black outline, transparent background, movie-subtitle style). The body can contain `\n` for line breaks. |
| `dialog` | `dialog` | Dismiss any currently open subtitle overlay. |
| `textcolor` | `textcolor <textColor> <fillColor> <borderColor>` | Change the colours used by subsequent `dialog` actions. Each colour is a [PuzzleColors] semantic name (`dialogAccent`, `highlight`, `forbidden`, `mandatory`, `constraintValid`, `pauseOverlayBg`, `transparent`, …) or a hex code (`#RRGGBB` or `#AARRGGBB`). Use `default` to reset a slot to its original value. All three arguments are required. |
| `background` | `background <color>` | Set a full-screen background colour for subsequent `dialog` actions. A rectangle covering the entire screen is drawn **behind** the dialog text, so the title/body stay legible on top of it. Accepts the same colour tokens as `textcolor` (semantic names, `#RRGGBB`/`#AARRGGBB`, or `default` to reset to transparent). The background is part of the dialog overlay: it appears with the next `dialog "title" "text"` and is removed when `dialog` (no args) dismisses it. |

### `mouseTo` targets

**Special targets:**

- `hint` — the lightbulb hint button in the AppBar.

**Constraint targets:**

A constraint reference in the form `SLUG:PARAMS` where `SLUG` is a two-letter
constraint code and `PARAMS` is the serialized parameters. The cursor moves to
the centre of that constraint's widget in the top, left, or right constraint
bar. For constraint types that have no bar widget (e.g. `GS`, `LT`, `PA`), the
position is computed geometrically from the anchor cell's grid position.

Examples: `FM:1.2`, `RC:0.1.3`, `GS:5.1`, `PA:10.top`.

### Colour names

The `setValue` action accepts the following names (case-insensitive, matching
the `CellValue` enum):

| Name | Meaning |
|------|---------|
| `free` | No colour (reset cell) |
| `black` | First domain colour |
| `white` | Second domain colour |
| `purple` | Third domain colour |

### Example

```
# Demo: explain and solve a puzzle step by step
loadState v2_12_3x3_000102000_GS:5.1;FM:111_1:121212212
dialog "Group Size" "This puzzle uses GS:5.1 —\nthe group of cell 5 is exactly 1"
wait 2000
mouseTo GS:5.1
wait 500
dialog
wait 300
mouse 0,0
wait 200
setValue 0,0,black
wait 100
mouse 1,1
wait 200
setValue 1,1,black
wait 100
mouse 2,2
wait 200
setValue 2,2,black
wait 400
mouseTo FM:111
wait 200
hint
wait 500
hint
wait 300
mouseTo hint
```

## Scenario generation via the `create-scenario` skill

The `create-scenario` skill (`.opencode/skills/create-scenario/SKILL.md`)
automatically generates scenario files from a puzzle URL or v2 line. It runs
the solver, parses every deduction step, groups them by constraint source,
and writes a scenario file with explanatory dialogs.

### Workflow

1. **Invoke** the skill by asking the agent to "create a demo", "generate a
   scenario", or "show how to solve" a puzzle.
2. The agent runs `dart run bin/solve.dart "<puzzle_url_or_v2_line>"`.
3. It parses the solver output — v2 line, domain, grid dimensions, each
   deduction step.
4. Steps are grouped by constraint source; steps from the same constraint
   share an explanatory dialog sequence (rule → already-known → deduction).
5. The agent generates the scenario file in `docs/scenario/`.

### Naming

The filename is derived from the constraint types in the puzzle:

| Constraints | Example name |
|-------------|--------------|
| Single type | `FM_only`, `GS_only` |
| Two types | `FM_GS`, `LT_PA` (alphabetical) |
| Three+ types | `mixed_constraints` |
| Trial-and-error involved | Prefix `intricate_` (e.g. `intricate_FM_GS`) |

If the chosen name already exists, a numeric suffix is appended (`_1`, `_2`,
etc.).

### Step transformation

| Solver step | Scenario translation |
|-------------|----------------------|
| `(r,c) = colour` | `mouse col,row` + `wait 100` + `setValue col,row,colour` |
| `(r,c) != colour` (2-colour puzzle) | `mouse col,row` + `wait 100` + `setValue col,row,<other colour>` |
| `(r,c) != colour` (3-colour puzzle) | **Skipped** — the elimination leaves 2 possibilities, so a single `setValue` is ambiguous |
| `constraint - SLUG:PARAMS` | `mouseTo SLUG:PARAMS` to point at the constraint, then a dialog explaining the rule |
| `complicity - NAME` | Dialog explaining the cross-constraint interaction (no `mouseTo` — complicity classes have no widget) |
| `findAMove - SLUG:PARAMS` | All `findAMove` steps grouped under one "Trial Deduction" dialog explaining trial-and-error reasoning |

### Dialog style

Each constraint group is explained with **three short dialogs** — the rule,
what is already known (with the mouse moved over the relevant already-set
cells in between), and the deduction. All dialog read times are a fixed
**3000 ms**.

### Intro and ending

Every generated scenario starts with a welcome dialog on a filled background
(`background bottomBarBg`) before `loadState`, and ends with a "Puzzle
solved!" dialog on a filled background.

See `.opencode/skills/create-scenario/SKILL.md` for the full specification,
including explanation templates for every constraint type and complicity.

## Architecture

### Data model

`AutopilotAction` is a sealed class hierarchy in
`lib/getsomepuzzle/model/autopilot_state.dart`. Each action variant carries the
parsed arguments. The top-level type is the sealed class `AutopilotAction` with
these subtypes:

- `LoadStateAction(v2Line)` — puzzle line to load
- `WaitAction(milliseconds)` — delay duration
- `MouseAction(col, row)` — grid cell target
- `MouseToAction(target)` — named widget target (string)
- `SetValueAction(col, row, value)` — cell colour assignment (`CellValue`)
- `HintAction()` — trigger hint
- `DialogAction(title?, text?)` — show or close subtitle overlay (both
  null = close)
- `TextColorAction(textColor, fillColor, borderColor)` — change colours for
  subsequent subtitle overlays (raw string tokens, resolved at runtime)
- `BackgroundAction(color)` — full-screen background colour for subsequent
  subtitle overlays (raw string token, resolved at runtime)

### Parsing

`lib/getsomepuzzle/autopilot/autopilot_core.dart` exports a pure function
`parseScenario(String content) → List<AutopilotAction>`. It has no Flutter
dependencies and is shared between the native isolate and the web fallback.
Colour names are resolved to `CellValue` during parsing; invalid names produce
a warning and the action is dropped from the list.

The tokeniser (`_tokenise`) handles both unquoted tokens (split on whitespace)
and double-quoted strings (`"..."`) as single tokens. Within quoted strings
the `\n` escape sequence is converted to an actual newline.

### Isolate layer

The `AutopilotDriver` class (in platform-specific shells) spawns an isolate
that reads the scenario file from disk, calls `parseScenario()`, and returns
the complete action list via `SendPort`. The main thread receives the list and
executes actions sequentially.

- **Native** (`autopilot_io.dart`): uses `Isolate.spawn`, following the
  existing `HintWorker` pattern. The isolate entry point receives a
  `_ScenarioParams(filePath, sendPort)`, reads the file, parses it, and sends
  the result.
- **Web** (`autopilot_web.dart`): returns an empty list — the autopilot is a
  desktop-only feature.
- **Stub** (`autopilot_stub.dart`): returns an empty list (unsupported
  platform).

`autopilot.dart` uses conditional exports (matching the `hint_worker.dart`
pattern) to select the right backend at compile time.

### Execution engine

Processing lives in `_MyHomePageState` in `lib/main.dart`. When a scenario
path is set, `initialize()` immediately returns after minimal setup (locale,
log line, schedule on next frame). The normal database and stats initialisation
are skipped. On the next frame `_startAutopilot()` spawns the driver, awaits
the action list, then enters a sequential loop. Every action is `await`ed:

1. **LoadState**: calls `GameModel.loadPuzzleFromLine()` — a method that
   bypasses the Database, playlist, and onboarding. Waits one frame for the
   widget tree to rebuild before the next action.
2. **Wait**: `await Future.delayed(duration)`. The only source of timing.
3. **Mouse / MouseTo**: waits one frame for layout consistency, queries the
   target widget's render position, then starts a time-based linear animation
   loop that samples the cursor position at roughly 60 fps. The duration is
   `distance / 1px/ms` clamped to [200 ms, 500 ms]. `await`s the full
   animation before returning.
4. **SetValue**: calls `Puzzle.setValue(idx, value, ignoreOptions: true)`,
   updates constraint status, calls `game.refresh()` (triggers `notifyListeners`),
   then waits one frame so the new cell colour is painted.
5. **Hint**: calls `showHelpMove()` on the next frame (the same multi-tap flow
   used by the lightbulb button). Waits an additional frame for visual changes
   (highlights, applied move, stage text) to paint.
6. **Dialog**: if title+text are both null, removes the subtitle overlay via
   `_removeDialogOverlay()`. Otherwise inserts a new `OverlayEntry` containing
   an `AutopilotDialog` (stroked-text subtitle style) into the Navigator's
   overlay using the current text/fill/border colours. Waits one frame so
   the overlay renders.
7. **TextColor**: resolves each of the three colour tokens via
   `_resolveColorToken()` (tries [PuzzleColors.resolveByName], then hex
   parsing, then falls back to the default) and updates the corresponding
   `_dialogTextColor`, `_dialogFillColor`, `_dialogBorderColor` fields for
   subsequent `dialog` actions.
8. **Background**: resolves the colour token via `_resolveColorToken()` and
   stores it in `_dialogBackgroundColor` (`default` / unresolved tokens reset
   to `Colors.transparent`). On the next `dialog` action the overlay's
   `Positioned.fill` stack draws a full-screen `ColoredBox` with that colour
   first, then the centered `AutopilotDialog` on top, so the text always sits
   above the background.

After the final action the app stays on the last puzzle state — it does not
exit, transition, or loop.

Each action is logged at `INFO` level with `autopilot: START <action>` and
`autopilot: END <action>` markers. Cursor animation details (distance,
duration) are logged at `FINE` level.

### Fake cursor

The `FakeCursor` widget in `lib/widgets/fake_cursor.dart` renders a small
arrow pointer with a red shadow for visibility. It is wrapped in
`IgnorePointer` so it never intercepts real input. The cursor is managed via
an `OverlayEntry` inserted into the Navigator's overlay, which covers the
entire screen including the AppBar. The overlay entry is created on the first
`mouse` or `mouseTo` action and removed on dispose.

Global coordinates are used for positioning: each target's `RenderBox` is
queried via a `GlobalKey`, and the cursor is positioned at the target's global
centre.

Cursor movement uses a time-based linear interpolation loop (`DateTime.now()`
for elapsed time, `Offset.lerp` for interpolation) rather than Flutter's
`AnimationController`, so the duration is always exact regardless of frame
timing. A generation counter (`_cursorAnimationGeneration`) ensures that a new
move immediately cancels any in-flight animation.

### Widget position resolution

Three lookup mechanisms in `_MyHomePageState` enable position queries:

- `_hintButtonKey` — a `GlobalKey` on the lightbulb `IconButton` in the
  AppBar. Resolves `mouseTo hint`.
- `PuzzleWidgetState.getCellGlobalCenter(int idx)` — returns the global centre
  of a grid cell using the grid render box and the adjusted cell size.
  Resolves `mouse col,row`.
- `PuzzleWidgetState.getConstraintGlobalPosition(String serialized)` — first
  tries the `_arrowKeys` map (widget-based bar widgets). If the constraint has
  no bar widget (e.g. `GroupSize`, `LetterGroup`), falls back to computing the
  position geometrically from the anchor cell's coordinates via the grid
  render box. Resolves `mouseTo FM:111`, `mouseTo GS:5.1`, etc.

The `_arrowKeys` map in `PuzzleWidgetState` (`lib/widgets/puzzle.dart`) maps
`Constraint` instances to `GlobalKey`s. In autopilot mode every constraint
widget in the three bars receives a key (not just highlighted ones), via the
`_keyForConstraint` helper.

### Dialog / Subtitle overlay

The `AutopilotDialog` in `lib/widgets/autopilot_dialog.dart` is a subtitle
overlay rendered on top of the whole UI (via an `OverlayEntry` in the
Navigator overlay). It displays the title and body text centred on screen
with a stroked-text technique — each glyph gets a thin black outline
(1.5 px) so it remains legible against any background, just like movie
subtitles. The background defaults to `Colors.transparent`. The colours
can be changed at runtime via the `textcolor` action, which resolves
[PuzzleColors] semantic names and hex codes.

The overlay is wrapped in `IgnorePointer` so it never intercepts input.
The only way to dismiss it is a subsequent `dialog` action with no
arguments.

When a `background` action has been issued, the dialog overlay first draws a
full-screen coloured rectangle (the `_dialogBackgroundColor`, transparent by
default) and then the centered text on top of it — the background is removed
together with the dialog.

### Error handling

All errors are non-fatal. A `Logger.warning` is emitted and the action is
skipped for:

- Malformed `loadState` line
- `setValue` targeting an out-of-bounds cell, a readonly cell, or an invalid
  colour name
- `mouse` targeting an out-of-bounds cell
- `mouseTo` targeting an unknown name or a constraint not present on the
  current puzzle
- `mouseTo` targeting a widget whose `RenderBox` is not yet laid out

## Future improvements

- **3-colour elimination support**: `!=` steps in 3-colour puzzles cannot
  currently be shown (an elimination leaves two possible colours, so
  `setValue` is ambiguous). The scenario generator skips them.
- **Trial-and-error sub-step demonstration**: `findAMove` steps currently
  show a single dialog summarising the deduction. A future version could
  run the solver's intermediate propagation steps as a `loadState` +
  replay sequence to show the contradiction that proves the move.
- **Non-linear scenarios**: branching, loops, and conditional actions
  (e.g. "if stuck, try a hint").

## Key files

| File | Role |
|------|------|
| `lib/getsomepuzzle/model/autopilot_state.dart` | Sealed action class hierarchy |
| `lib/getsomepuzzle/autopilot/autopilot_core.dart` | Text → action list parser (quoted-string tokeniser) |
| `lib/getsomepuzzle/autopilot/autopilot_io.dart` | Native isolate driver |
| `lib/getsomepuzzle/autopilot/autopilot_web.dart` | Web fallback driver |
| `lib/getsomepuzzle/autopilot/autopilot_stub.dart` | Stub for unsupported platforms |
| `lib/getsomepuzzle/autopilot/autopilot.dart` | Conditional exports |
| `lib/widgets/fake_cursor.dart` | Cursor overlay widget (arrow + red shadow) |
| `lib/widgets/autopilot_dialog.dart` | Subtitle overlay widget (stroked-text, movie-subtitle style) |
| `lib/getsomepuzzle/model/app_theme.dart` | `PuzzleColors.resolveByName()` — semantic colour resolution for `textcolor` |
| `lib/main.dart` | CLI parsing, execution engine, overlay management |
| `lib/getsomepuzzle/model/game_model.dart` | `loadPuzzleFromLine()` method |
| `lib/widgets/puzzle.dart` | Autopilot-mode key assignment, position lookup |
