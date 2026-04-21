# Timers fixes

## Timer in manual validation

When the user is using the "manual" ValidateType, the timer should pause when
the puzzle is complete but it should restart if they clear a cell and the puzzle
is not complete anymore.

## Debounce before error checking

In automatic validation mode, when the player made a mistake, the error is shown
and when they fix the error, the UI switches to the next puzzle immediately, without
waiting for the usual error checking debounce.

## Idle detection

Add a setting "auto idle detection" with a dropdown that allows the player to choose
a timeout (values : 5s, 10s, 30s, 1mn, 2mn). If the timeout is reached without any
interaction, automatically pause the puzzle.

## Pause when focus is lost

On the web application, if another tab is opened or the current tab is not the game anymore,
automatically pause the game. Same if the browser is minified. On desktop, pause the game
when the app is not the currently active app (minified or another program is active). On
mobile, pause the game when the user switches to another app.

---

# Implementation plan

All four features share a common concern: decide *when* the `Stats` stopwatch should
run. Today the only drivers are `openPuzzle` / `restart` (start), the user pause
button (`GameModel.pause/resume`) and the completion path in `checkPuzzle` (stop).
We will add three new drivers (completion-in-manual, idle, focus). To keep the
logic coherent we introduce a single internal helper `_autoPause(reason)` /
`_autoResume(reason)` in `GameModel` that manipulates `stats.pause()` /
`stats.resume()` *without* flipping the user-facing `paused` flag when the
intent is just to freeze the stopwatch silently (feature 1), and *with* flipping
it (so the pause overlay shows) when the intent is to block interaction
(features 3 and 4).

Concretely we add two new fields on `GameModel`:

- `bool _stoppedForCompletion` — tracks whether the stopwatch was frozen because
  the puzzle is complete in manual mode (feature 1). No overlay.
- `AutoPauseReason? _autoPauseReason` — non-null when pause was triggered by
  idle or focus loss (features 3 and 4). Drives the overlay and requires an
  explicit user action to resume.

`GameModel.pause()` / `resume()` keep their current behaviour and clear
`_autoPauseReason`.

## 1. Timer in manual validation

**Where:** `lib/getsomepuzzle/model/game_model.dart`.

In `ValidateType.manual`, `checkPuzzle` deliberately does NOT call
`currentMeta!.stop()` on completion (see line 262-263: completion only fires if
`manualCheck || validateType != manual`). The stopwatch therefore keeps running
between "puzzle complete" and "user clicks the Validate button". We want to
freeze it during that window.

**Hook point:** `handleCheck` is called after every cell mutation (tap, drag
end, right-drag end — see `main.dart:215-235`). It already knows `settings` and
has access to `currentPuzzle!.complete`. Add at the top of `handleCheck`:

```dart
if (settings.validateType == ValidateType.manual) {
  if (currentPuzzle!.complete && !_stoppedForCompletion) {
    currentMeta?.stats?.pause();
    _stoppedForCompletion = true;
  } else if (!currentPuzzle!.complete && _stoppedForCompletion) {
    currentMeta?.stats?.resume();
    _stoppedForCompletion = false;
  }
}
```

Also reset `_stoppedForCompletion = false` in `openPuzzle`, `restart` and
`undo` (where the puzzle state changes outside the tap path). In
`checkPuzzle`, when the manual validate button fires `currentMeta!.stop()`,
clear the flag too (stop resets the stopwatch anyway).

**Interaction with user pause:** if the user clicks the manual pause button
while `_stoppedForCompletion` is true, `game.pause()` calls `stats.pause()`
on an already-paused stopwatch — Stopwatch ignores that. When they resume we
must NOT call `stats.resume()` if `_stoppedForCompletion` is still true. Guard
`resume()` accordingly.

**Tests:** add a widget/unit test in `test/` that drives a manual-mode puzzle
to completion, asserts `stats.timer.isRunning` is false, toggles a cell off,
asserts it's running again.

## 2. Debounce before error checking on completion transition

**Where:** `lib/getsomepuzzle/model/game_model.dart`, `handleCheck` and
`checkPuzzle`.

**Current behaviour.** In `LiveCheckType.all` / `count`, `handleCheck` calls
`_autoCheck` synchronously, which calls `checkPuzzle`, which — if the puzzle is
complete and valid — calls `onPuzzleCompleted` immediately → `loadPuzzle()` →
switch. In `LiveCheckType.complete` the same path is already delayed by 1s
(line 234-237). The inconsistency is the bug: after a player fixes an error
and that fix happens to complete the puzzle, the switch feels abrupt.

**Fix.** Unify the debounce for the *completion transition* only, keeping
live error display instantaneous.

1. Introduce `Timer? _completionDebounce` on `GameModel`.
2. Split `checkPuzzle` into two phases:
   - **Error evaluation** (synchronous, unchanged): run `currentPuzzle!.check`,
     update `topMessage`, increment failure counter.
   - **Completion action** (new): when the puzzle is complete and has no
     failed constraints and (`manualCheck || validateType != manual`), instead
     of calling `currentMeta!.stop()` + `onPuzzleCompleted()` inline, schedule
     them via `_completionDebounce = Timer(Duration(seconds: 1), ...)`.
3. Cancel `_completionDebounce` whenever the puzzle state changes in a way
   that invalidates the pending completion: `handleTap`, `handleDrag`,
   `handleRightDrag`, `restart`, `undo`, `openPuzzle`, `clearPuzzle`,
   `pause`. If after the cancel-triggering mutation the puzzle is still
   complete and valid, `handleCheck` will reschedule; otherwise nothing fires.
4. Manual validation (the explicit button click) must remain instantaneous —
   pass `manualCheck: true` and skip the debounce in that branch.
5. The existing 1s branch in `handleCheck` for `LiveCheckType.complete` is now
   redundant (the debounce lives in `checkPuzzle`), so simplify `handleCheck`
   to always call `_autoCheck` synchronously for every mode.

**Edge cases to cover in tests:**
- `all` mode: fill the last correct cell → no switch for 1s → puzzle loads.
- `all` mode: during the 1s window, clear a cell → completion debounce
  cancelled, no switch.
- `complete` mode: same scenarios still work (regression guard).
- Manual button click after completion → switches with no debounce.

## 3. Idle detection

**New setting.** Add `IdleTimeout` enum in `lib/getsomepuzzle/model/settings.dart`:

```dart
enum IdleTimeout { disabled, s5, s10, s30, m1, m2 }
```

Default: `IdleTimeout.disabled` (preserves current behaviour for existing
users). Follow the same pattern as `ValidateType`:

- Add `IdleTimeout? idleTimeout` to `ChangeableSettings` and update
  `toString`.
- Add `IdleTimeout idleTimeout` to `Settings` with default
  `IdleTimeout.disabled`.
- Add load/save switches using `idleTimeout.name` as storage key
  `"settingsIdleTimeout"`.
- Add `if (newValue.idleTimeout != null)` branch in `Settings.change`.
- Expose a helper `Duration? idleTimeoutDuration` that maps the enum to a
  Duration (or `null` when disabled).

**UI.** In `lib/widgets/settings_page.dart`, add a new `Map<IdleTimeout,
String>` using l10n strings and render a `DropdownButton<IdleTimeout>` using
`IdleTimeout.values.map(...)` (the compact pattern used for `LiveCheckType`
and `HintType`). Add six l10n keys in each ARB file under `lib/l10n/`:
`settingIdleTimeout`, `settingIdleTimeoutDisabled`, `settingIdleTimeoutS5`, …,
`settingIdleTimeoutM2`. Run `flutter gen-l10n`.

**Tracking interactions.** The idle clock must reset on any game interaction.
We route all cell input through `GameModel.handleTap` / `handleDrag` /
`handleRightDrag` plus the button handlers in `_MyHomePageState`. Centralise
by adding a `GameModel.markInteraction()` method called at the top of every
one of those methods. `markInteraction()`:

1. Resets `_lastInteractionAt = DateTime.now()`.
2. If `_autoPauseReason == AutoPauseReason.idle`, do nothing here — the user
   must explicitly resume (via the overlay). Rationale: if they've already
   been idle-paused, a tap probably means they're coming back; but requiring
   an explicit resume avoids accidental moves.

**Scheduling the pause.** In `_MyHomePageState`, add a `Timer? _idleTimer`.
Rebuild the timer whenever:

- a puzzle is opened (`openPuzzle`),
- the user resumes,
- settings change (the settings page already calls back via
  `onSettingsChange`),
- `markInteraction` fires (reset).

Implementation: use `Timer` (single-shot), not `Timer.periodic`. On fire, call
`game.autoPause(AutoPauseReason.idle)` which sets `paused = true`,
`_autoPauseReason = idle`, and calls `stats.pause()`. Do not rearm; it gets
rearmed on resume/interaction.

Disable when `settings.idleTimeout == IdleTimeout.disabled`,
`game.currentPuzzle == null`, `game.paused`, or `game.betweenPuzzles`.

**Overlay.** Reuse `PauseOverlay`. Add a `reason` parameter (or a bit of text
from `GameModel`) so the overlay can display "Paused due to inactivity" vs
the default text. Minor — can ship without.

**Tests:** unit-test the helper `Settings.idleTimeoutDuration`; integration-test
the `GameModel.markInteraction` + auto-pause path using `fakeAsync`.

## 4. Pause when focus is lost

**Hook:** Flutter's `WidgetsBindingObserver` fires `didChangeAppLifecycleState`
on all supported platforms — including web (tab change → `hidden`, tab close
→ `detached`) and desktop (window unfocused → `inactive` / `hidden`). No
platform-specific code is needed.

**Changes to `_MyHomePageState`:**

1. `with WidgetsBindingObserver` on the mixin list.
2. In `initState`: `WidgetsBinding.instance.addObserver(this);`.
3. In `dispose`: `WidgetsBinding.instance.removeObserver(this);`.
4. Implement:

   ```dart
   @override
   void didChangeAppLifecycleState(AppLifecycleState state) {
     if (game.currentPuzzle == null || game.betweenPuzzles) return;
     switch (state) {
       case AppLifecycleState.inactive:
       case AppLifecycleState.hidden:
       case AppLifecycleState.paused:
         if (!game.paused) game.autoPause(AutoPauseReason.focusLost);
       case AppLifecycleState.resumed:
         // Deliberately do nothing: user must click to resume so they get
         // visual confirmation and cannot lose time to a still-running clock.
       case AppLifecycleState.detached:
         break;
     }
   }
   ```

5. `game.autoPause(AutoPauseReason.focusLost)` sets `paused = true`,
   `_autoPauseReason = focusLost`, `stats.pause()`, cancels the completion
   debounce (feature 2) and the idle timer (feature 3).

**Interaction with features 1–3:**
- If `_stoppedForCompletion` is already true (puzzle complete in manual
  mode), calling `stats.pause()` again is a no-op; resume logic must still
  check the completion flag.
- If the idle timer already fired, `_autoPauseReason` gets overwritten from
  `idle` to `focusLost`. That's fine; the distinction only matters for the
  overlay subtitle.

**Testing caveat per CLAUDE.md.** UI/focus behaviour can't be asserted by
`flutter test` alone. For features 3 and 4, after implementation, manually
verify in browser (switch tab) and on desktop (alt-tab). Report explicitly
whether manual verification was done.

## Sequencing / commits

Suggested order so each commit is independently shippable and testable:

1. **Commit 1 — manual-mode timer freeze (feature 1).** Smallest surface, no
   new setting, no lifecycle plumbing. Unit tests included.
2. **Commit 2 — completion debounce unification (feature 2).** Refactors
   `handleCheck` / `checkPuzzle` to route completion through a single
   cancellable debounce. Regression tests for `complete` mode, new tests for
   `all` / `count`.
3. **Commit 3 — `AutoPauseReason` scaffolding.** Introduce
   `AutoPauseReason` enum, `GameModel.autoPause()`, overlay subtitle. No
   triggers wired yet; kept separate to keep diffs reviewable.
4. **Commit 4 — idle detection (feature 3).** Add setting, l10n, timer
   plumbing in `_MyHomePageState`, hook `markInteraction`.
5. **Commit 5 — focus-loss pause (feature 4).** Add
   `WidgetsBindingObserver`, wire lifecycle to `autoPause`.

## Open questions for the user

- **Idle default:** ship as `disabled` so no behaviour change for existing
  users, or default to `m1` / `m2`?
  - Answer: disabled by default
- **Focus-regain auto-resume:** plan above keeps the overlay so the user
  clicks to resume. Would you prefer auto-resume on `AppLifecycleState.resumed`?
  (Risk: player away from keyboard, timer starts ticking without them
  noticing.)
  - Answer: click to resume only
- **Overlay subtitle:** worth shipping "Paused due to inactivity" / "Paused
  because the app lost focus" now, or keep the existing single "Paused"
  message for v1?
  - Answer: yes, add subtitle so the user knows why the pause was triggered
