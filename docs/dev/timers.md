# Timers

Four behaviours together decide *when* the `Stats` stopwatch runs and when the
puzzle is paused. They share a small piece of state in `GameModel` so each
trigger can compose without stepping on the others.

## Shared state in `GameModel`

- `bool _stoppedForCompletion` — the stopwatch was frozen because the puzzle
  is complete in manual validation mode. Silent freeze, no overlay.
- `Timer? _completionDebounce` — pending "switch to next puzzle" action when
  a play has just completed under live validation; cancellable.
- `AutoPauseReason? _autoPauseReason` — non-null when the puzzle was paused
  by an automatic trigger (`idle` or `focusLost`). Drives the overlay
  subtitle and forces an explicit user resume.

`GameModel.pause()` / `resume()` keep their pre-existing behaviour and clear
`_autoPauseReason` on resume.

## 1. Timer freeze in manual validation

In `ValidateType.manual`, `checkPuzzle` deliberately does not call
`currentMeta!.stop()` on completion — completion only fires when the user
clicks the explicit Validate button. To avoid the stopwatch ticking between
"puzzle complete" and "user validates", `handleCheck` freezes the stopwatch
when the puzzle becomes complete and resumes it if the player edits a cell
back into an incomplete state:

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

`_stoppedForCompletion` is reset by `openPuzzle`, `restart`, `undo`, and the
manual `Validate` path (which calls `currentMeta!.stop()`, resetting the
stopwatch anyway). The user pause button is guarded so that resuming after a
manual pause does not call `stats.resume()` while the completion freeze is
still active.

**Tests**: `test/manual_completion_timer_test.dart`.

## 2. Completion debounce on live validation

In `LiveCheckType.all` / `count`, fixing an error that *also* completes the
puzzle used to switch to the next puzzle instantaneously, which felt abrupt.
The completion transition now goes through a unified debounce:

1. `_completionDebounce` (a `Timer`) is started by `checkPuzzle` when the
   puzzle is complete and has no failed constraints (and we are not in the
   manual-validate branch).
2. After 1 s the timer calls `currentMeta!.stop()` and `onPuzzleCompleted()`.
3. Any user-initiated mutation cancels the timer: `handleTap`, `handleDrag`,
   `handleRightDrag`, `restart`, `undo`, `openPuzzle`, `clearPuzzle`, `pause`.
   If the puzzle is still complete and valid after the cancelling mutation,
   `handleCheck` reschedules; otherwise nothing fires.
4. The explicit manual Validate button bypasses the debounce — it calls
   `checkPuzzle(manualCheck: true)` and acts immediately.

The previous 1 s branch in `handleCheck` for `LiveCheckType.complete` is now
redundant: the debounce lives in `checkPuzzle`, so `handleCheck` calls
`_autoCheck` synchronously for every live mode.

**Tests**: `test/completion_debounce_test.dart`,
`integration_test/completion_debounce_integration_test.dart`.

## 3. Idle detection

A `IdleTimeout` enum in `lib/getsomepuzzle/model/settings.dart`:

```dart
enum IdleTimeout { disabled, s5, s10, s30, m1, m2 }
```

Default: `IdleTimeout.disabled` (no behaviour change for existing users).
Persisted under storage key `"settingsIdleTimeout"` using the enum name; a
helper `Settings.idleTimeoutDuration` exposes the matching `Duration?`. The
settings page renders a `DropdownButton<IdleTimeout>` using ARB keys
`settingIdleTimeout`, `settingIdleTimeoutDisabled`,
`settingIdleTimeoutS5..M2`.

### Tracking interactions

`GameModel.markInteraction()` is called at the top of every cell input
(`handleTap`, `handleDrag`, `handleRightDrag`) and the relevant button
handlers. It:

1. Resets `_lastInteractionAt = DateTime.now()`.
2. Returns immediately if `_autoPauseReason == AutoPauseReason.idle` —
   once the player has been idle-paused, only an explicit resume should
   restart the clock; this avoids accidental moves on returning.

### Scheduling the pause

A `Timer? _idleTimer` lives in `_MyHomePageState`. It is rebuilt when:

- a puzzle is opened (`openPuzzle`),
- the user resumes,
- settings change (the settings page calls `onSettingsChange`),
- `markInteraction` fires (reset).

The timer is single-shot. On fire it calls
`game.autoPause(AutoPauseReason.idle)`, which sets `paused = true`,
`_autoPauseReason = idle`, and pauses the stopwatch. It is **disabled** when
`settings.idleTimeout == IdleTimeout.disabled`, `game.currentPuzzle == null`,
`game.paused`, or `game.betweenPuzzles`.

**Tests**: `test/idle_timeout_test.dart`,
`test/auto_pause_reason_test.dart`,
`integration_test/idle_auto_pause_test.dart`.

## 4. Pause when focus is lost

Implemented via Flutter's `WidgetsBindingObserver`, which fires
`didChangeAppLifecycleState` on every supported platform — including web (tab
change → `hidden`, tab close → `detached`) and desktop (window unfocused →
`inactive` / `hidden`). No platform-specific code is needed.

`_MyHomePageState`:

1. Mixes in `WidgetsBindingObserver`.
2. Registers in `initState` (`WidgetsBinding.instance.addObserver(this)`)
   and unregisters in `dispose`.
3. Implements:

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
         // Deliberately do nothing: the user must click to resume so they
         // get visual confirmation and cannot lose time to a still-running
         // clock.
       case AppLifecycleState.detached:
         break;
     }
   }
   ```

`game.autoPause(AutoPauseReason.focusLost)` sets `paused = true`,
`_autoPauseReason = focusLost`, pauses the stopwatch, and cancels both the
completion debounce (feature 2) and the idle timer (feature 3).

### Composition with the other features

- If `_stoppedForCompletion` is already true, calling `stats.pause()` again
  is a no-op; the resume guard in `GameModel.resume` checks the completion
  flag.
- If the idle timer already fired before focus loss, `_autoPauseReason` gets
  overwritten from `idle` to `focusLost`. The distinction only matters for
  the overlay subtitle.

**Tests**: `integration_test/focus_auto_pause_test.dart`. Lifecycle behaviour
cannot be fully asserted by `flutter test` alone — the integration test runs
under `xvfb-run -a flutter test integration_test/... -d linux`.

## Pause overlay

`PauseOverlay` accepts the `AutoPauseReason` so the subtitle reflects the
trigger ("Paused due to inactivity", "Paused because the app lost focus") and
falls back to the default text when the user paused manually.
