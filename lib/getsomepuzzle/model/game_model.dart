import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';
import 'package:logging/logging.dart';

/// Why the game was automatically paused. Null means either the user paused
/// manually (no subtitle needed) or the game is running.
enum AutoPauseReason { idle, focusLost }

/// Differentiate between "no hint ready" and "hint is being computed"
enum HintConstraintStatus { ready, inprogress, nohint, canceled }

class GameModel extends ChangeNotifier {
  // --- Puzzle state ---
  PuzzleData? currentMeta;
  Puzzle? currentPuzzle;
  List<int> history = [];
  int dbSize = 0;

  /// True when `currentPuzzle` has been rotated 90° clockwise from its
  /// native (database) orientation by the auto-rotation feature. Toggled
  /// by `rotateCurrentPuzzle`: the next call from the rotated state
  /// rotates back (CCW) instead of forward, so two consecutive screen-
  /// orientation flips return the puzzle to its starting layout.
  bool _isPuzzleRotated = false;

  // --- Hint state ---
  /// Next deducible move, refreshed (debounced) by [_scheduleHelpMe] after
  /// every mutation. Computed with `checkErrors: false` — error reporting is
  /// done separately by [_revealErrors] on tap 1 of the hint flow.
  Move? helpMove;
  String hintText = "";
  bool hintIsError = false;

  /// Position in the multi-tap hint sequence. The transitions are mode-
  /// dependent (see [HintType]). Both modes start at 0 → 1 (errors), then
  /// diverge:
  ///   - `deducibleCell`: 1 → 2 (cell only) → 3 (cell + constraint) → 4
  ///     (apply move). The apply path mutates and `_afterMutation` resets
  ///     this back to 0.
  ///   - `addConstraint`: 1 → 2 (attach a new constraint) → 0 (manual reset
  ///     since attaching a constraint does not call `_afterMutation`).
  /// Reset to 0 by [_clearHint], so any mutation, undo, restart, puzzle open
  /// or hint-mode switch starts the cycle fresh.
  int hintStage = 0;

  // --- Session state ---
  bool paused = false;
  bool betweenPuzzles = false;

  /// True when the stopwatch was silently paused because the puzzle is
  /// complete in manual-validation mode. Cleared as soon as the player
  /// breaks completeness (clears a cell) or the puzzle transitions away.
  bool _stoppedForCompletion = false;

  /// Non-null when `paused` was set automatically (idle timeout, app focus
  /// lost). Used by the pause overlay to tell the user *why* they were
  /// paused. Cleared by manual pause and resume.
  AutoPauseReason? _autoPauseReason;
  AutoPauseReason? get autoPauseReason => _autoPauseReason;

  /// Pending automatic check. Every cell mutation re-arms this timer from 0;
  /// when it fires we run `checkPuzzle` (which displays errors, increments
  /// failures and/or switches to the next puzzle). Cancelled on any mutation
  /// that invalidates the pending check (tap, drag, restart, undo, pause, …).
  Timer? _checkDebounce;

  /// Fires an `autoPause(AutoPauseReason.idle)` after the configured idle
  /// window elapses without any interaction.
  Timer? _idleTimer;
  Duration? idleTimeoutDuration;

  // --- Visual feedback ---
  String topMessage = "";
  Color topMessageColor = Colors.black;

  // --- Hint constraint state ---
  HintWorker? _hintWorker;
  List<String> availableHintConstraints = [];
  HintConstraintStatus hintConstraintsReady = HintConstraintStatus.inprogress;

  /// Set when the player taps to reveal an `addConstraint` hint while the
  /// search is still [HintConstraintStatus.inprogress]: we then show the
  /// "computing…" message and stash the l10n strings here so the worker's
  /// completion callback can reveal the result on its own, without making the
  /// player tap again. Cleared once consumed (or on cancel / cycle reset).
  HintTexts? _pendingRevealTexts;

  /// Mirrors `settings.hintType` so [startHintConstraintComputation] can
  /// short-circuit when the player is not in `addConstraint` mode. The
  /// computation is expensive (clone+solve loop over every candidate
  /// constraint) and on web it runs on the main isolate, so re-firing it on
  /// every cell mutation makes the UI feel frozen. Owners must keep this in
  /// sync with the settings; defaults to `deducibleCell` (cheap mode).
  HintType hintType = HintType.deducibleCell;

  // --- Drag state ---
  int? firstDragValue;
  int? lastDragIdx;
  int? firstRightDragValue;
  int? lastRightDragIdx;

  /// Cell index of an in-flight right-click whose toggle is **deferred**
  /// until either the user releases the button (single click) or moves
  /// to another cell (drag start). Without this, the right button's
  /// `Listener.onPointerDown` would commit the toggle the instant the
  /// button is pressed — visually inconsistent with the left button,
  /// where `GestureDetector.onTap` only fires at release.
  int? _pendingRightClickIdx;

  Timer? _helpDebounce;
  final _log = Logger("GameModel");

  // ---------------------------------------------------------------------------
  // Internal helpers – factorise the repeated reset patterns
  // ---------------------------------------------------------------------------

  /// Clear all hint state: highlight, displayed text, the pre-computed move
  /// that the hint button would apply, and the multi-tap stage. Called on
  /// every mutation so a stale hint can't be applied to a puzzle that has
  /// since changed.
  void _clearHint() {
    currentPuzzle?.clearHighlights();
    hintText = "";
    hintIsError = false;
    helpMove = null;
    hintStage = 0;
  }

  /// Full reset of interaction state for undo / restart: unfreezes the
  /// manual-completion stopwatch, clears error highlights and top message,
  /// then commits via [_afterMutation].
  void _resetPuzzleState() {
    if (_stoppedForCompletion) {
      currentMeta?.stats?.resume();
      _stoppedForCompletion = false;
    }

    betweenPuzzles = false;
    currentPuzzle?.clearConstraintsValidity();
    currentPuzzle?.updateConstraintStatus();
    setTopMessage();
    _afterMutation();
  }

  /// Called at the start of any puzzle mutation (tap, drag step, undo,
  /// restart, puzzle open). Cancels any pending debounced check so errors
  /// don't surface mid-interaction, and re-arms the idle watchdog so a
  /// long drag or multi-step interaction is not mistaken for inactivity.
  void _beforeMutation() {
    _cancelCheckDebounce();
    cancelHintConstraintComputation();
    rearmIdleTimer();
  }

  /// Called once a mutation settles into a stable state. Clears hints,
  /// schedules the help recomputation, notifies listeners, and re-arms the
  /// idle watchdog. The `addConstraint` hint search is *not* fired here — it
  /// runs on demand from [onHintTap] (tap 1). Not called during drag steps —
  /// the drag commits via [handleDragEnd].
  void _afterMutation() {
    _clearHint();
    _scheduleHelpMe();
    notifyListeners();
    rearmIdleTimer();
  }

  /// Force a UI refresh (e.g. after external settings change).
  void refresh() {
    notifyListeners();
  }

  void setTopMessage({String text = "", Color color = Colors.black}) {
    topMessage = text;
    topMessageColor = color;
  }

  // ---------------------------------------------------------------------------
  // Puzzle lifecycle
  // ---------------------------------------------------------------------------

  void openPuzzle(
    PuzzleData puz,
    int playlistLength, {
    String? progressRestoredText,
    bool? screenIsLandscape,
  }) {
    _beforeMutation();
    history = [];
    _cancelIdleTimer();
    dbSize = playlistLength;
    currentMeta = puz;
    currentPuzzle = currentMeta!.begin();
    _isPuzzleRotated = false;
    // Apply auto-rotation synchronously here — before `_afterMutation`
    // notifies listeners — so the very first build sees the puzzle in the
    // correct orientation. Without this, the build-time post-frame
    // callback in `main.dart` would rotate one frame later, producing a
    // visible flicker on puzzle open. `Puzzle.rotated()` preserves cell
    // values, readonly flags, the cached solution, and restored
    // progress, so this is logically transparent.
    if (screenIsLandscape != null && currentPuzzle != null) {
      final p = currentPuzzle!;
      if (p.width != p.height) {
        final puzzleLandscape = p.width > p.height;
        if (puzzleLandscape != screenIsLandscape) {
          currentPuzzle = p.rotated();
          _isPuzzleRotated = true;
        }
      }
    }
    paused = false;
    betweenPuzzles = false;
    _stoppedForCompletion = false;
    _autoPauseReason = null;
    if (progressRestoredText != null &&
        currentPuzzle?.hasRestoredProgress == true) {
      setTopMessage(text: progressRestoredText, color: Colors.blue.shade700);
    }
    _afterMutation();
  }

  /// Toggle the rotation state of `currentPuzzle` between native and 90°
  /// clockwise, used by the screen-orientation auto-rotation feature.
  /// No-op for square puzzles, or when no puzzle is loaded.
  ///
  /// From native, applies a single 90° CW rotation. From the rotated state,
  /// applies three 90° CW rotations (= 90° CCW) so the puzzle returns to
  /// its **original** layout — without this, two successive orientation
  /// changes would land on a 180°-flipped puzzle instead of the starting
  /// position.
  ///
  /// The rotation is logically transparent (`Puzzle.rotated()` preserves
  /// cell values, readonly flags, the cached solution, and the player's
  /// progress) but every positional piece of UI state — the undo history,
  /// any in-flight drag, the pre-computed help move — points to indices in
  /// the *old* grid. Drag/click state is dropped; history indices are
  /// translated through `rotateIdx90CW` so undo still pops the right cells.
  void rotateCurrentPuzzle() {
    final p = currentPuzzle;
    if (p == null) return;
    if (p.width == p.height) return;
    // From native (rotated=false) we apply one CW; from rotated (true) we
    // apply three CW, which sums to 360° relative to the native form and
    // brings the player back to the original layout.
    final quarters = _isPuzzleRotated ? 3 : 1;
    history = history
        .map((idx) => _rotateIdxCW(idx, p.width, p.height, quarters))
        .toList();
    firstDragValue = null;
    lastDragIdx = null;
    firstRightDragValue = null;
    lastRightDragIdx = null;
    _pendingRightClickIdx = null;
    helpMove = null;
    Puzzle next = p;
    for (int i = 0; i < quarters; i++) {
      next = next.rotated();
    }
    currentPuzzle = next;
    _isPuzzleRotated = !_isPuzzleRotated;
    _afterMutation();
  }

  /// Apply `quarters` (1..3) successive 90° CW transforms to a 1D cell
  /// index, walking the dimension swap at each step.
  static int _rotateIdxCW(int idx, int width, int height, int quarters) {
    var i = idx;
    var w = width;
    var h = height;
    for (int k = 0; k < quarters; k++) {
      i = rotateIdx90CW(i, w, h);
      final t = w;
      w = h;
      h = t;
    }
    return i;
  }

  void clearPuzzle() {
    _cancelCheckDebounce();
    _cancelIdleTimer();
    cancelHintConstraintComputation();
    currentPuzzle = null;
    history = [];
    _isPuzzleRotated = false;
    betweenPuzzles = false;
    notifyListeners();
  }

  void restart() {
    if (currentPuzzle == null) return;
    _beforeMutation();
    history = [];
    currentPuzzle!.restart();
    _resetPuzzleState();
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    _beforeMutation();
    currentPuzzle!.resetCell(history.removeLast());
    currentPuzzle!.updateConstraintStatus();
    _resetPuzzleState();
  }

  // ---------------------------------------------------------------------------
  // Pause / resume
  // ---------------------------------------------------------------------------

  void pause() {
    paused = true;
    _autoPauseReason = null;
    _cancelCheckDebounce();
    _cancelIdleTimer();
    currentMeta?.stats?.pause();
    notifyListeners();
  }

  void resume() {
    paused = false;
    _autoPauseReason = null;
    // If the puzzle is still complete in manual mode, keep the stopwatch
    // frozen — the user must break completeness or validate.
    if (currentPuzzle != null && !_stoppedForCompletion) {
      currentMeta?.stats?.resume();
    }
    notifyListeners();
    rearmIdleTimer();
  }

  /// Pause the game from an automatic source (idle timeout, app focus lost).
  /// Behaves like [pause] but records the reason so the pause overlay can
  /// explain to the user why the game stopped. No-op if already paused —
  /// the earliest reason wins, which avoids the focus-loss event that
  /// follows an idle pause from overwriting the original cause.
  void autoPause(AutoPauseReason reason) {
    if (paused) return;
    paused = true;
    _autoPauseReason = reason;
    _cancelCheckDebounce();
    _cancelIdleTimer();
    currentMeta?.stats?.pause();
    notifyListeners();
  }

  /// Record a user interaction and re-arm the idle watchdog from 0. Pass
  /// `settings.idleTimeoutDuration` as [duration]; null disables the feature.
  /// After an idle auto-pause, interactions are ignored until [resume] runs —
  /// this avoids a stray event from silently re-arming the clock while the
  /// pause overlay is still showing.
  void rearmIdleTimer() {
    if (_autoPauseReason == AutoPauseReason.idle) return;
    _cancelIdleTimer();
    if (idleTimeoutDuration == null) return;
    if (currentPuzzle == null || paused || betweenPuzzles) return;
    _idleTimer = Timer(idleTimeoutDuration!, () {
      _idleTimer = null;
      autoPause(AutoPauseReason.idle);
    });
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Freeze/unfreeze the stopwatch based on whether the puzzle is complete
  /// while in manual-validation mode. No-op outside of manual mode.
  void _syncManualCompletionPause(Settings settings) {
    if (currentPuzzle == null) return;
    if (settings.validateType != ValidateType.manual) {
      // Leaving manual mode while frozen: unfreeze the stopwatch.
      if (_stoppedForCompletion) {
        currentMeta?.stats?.resume();
        _stoppedForCompletion = false;
      }
      return;
    }
    if (currentPuzzle!.complete && !_stoppedForCompletion) {
      currentMeta?.stats?.pause();
      _stoppedForCompletion = true;
    } else if (!currentPuzzle!.complete && _stoppedForCompletion) {
      currentMeta?.stats?.resume();
      _stoppedForCompletion = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Cell interaction
  // ---------------------------------------------------------------------------

  /// Returns true if the tap was handled (cell was toggled).
  bool handleTap(int idx) {
    if (currentPuzzle == null) return false;
    if (currentPuzzle!.cells[idx].readonly) return false;
    _beforeMutation();
    currentPuzzle!.incrValue(idx);
    currentMeta?.stats?.recordCellEdit();
    currentPuzzle!.clearConstraintsValidity();
    if (history.isEmpty || history.last != idx) history.add(idx);
    _log.fine('tap cell $idx → ${currentPuzzle!.cellValues[idx]}');
    _afterMutation();
    return true;
  }

  void handleDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (lastDragIdx != null && idx == lastDragIdx) return;
    _beforeMutation();
    lastDragIdx = idx;
    if (firstDragValue == null) {
      final myOpposite = currentPuzzle!.domain
          .whereNot((e) => e == currentPuzzle!.cellValues[idx])
          .first;
      firstDragValue = myOpposite;
      currentPuzzle!.setValue(idx, firstDragValue!);
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
      _log.fine('drag cell $idx → ${currentPuzzle!.cellValues[idx]}');
    }
    if (currentPuzzle!.cellValues[idx] != firstDragValue &&
        currentPuzzle!.cellValues[idx] == 0) {
      currentPuzzle!.setValue(idx, firstDragValue!);
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
      _log.fine('drag cell $idx → ${currentPuzzle!.cellValues[idx]}');
    }
    notifyListeners();
  }

  void handleDragEnd() {
    // Skip when no drag was actually started: the cell-widget's
    // gesture detector emits drag-end on every gesture release,
    // including taps that never crossed the pan threshold.
    if (firstDragValue == null && lastDragIdx == null) return;
    _log.fine('drag end');
    firstDragValue = null;
    lastDragIdx = null;
    _afterMutation();
  }

  void handleRightDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (lastRightDragIdx != null && idx == lastRightDragIdx) return;
    final currentValue = currentPuzzle!.cellValues[idx];
    if (firstRightDragValue == null && currentValue == 1) return;

    if (firstRightDragValue == null) {
      // First event of a right-button gesture (pointer-down on a cell
      // whose value is not black). Defer the toggle: we don't know
      // yet whether this is a single click (commit on release) or a
      // drag (commit at the moment the user moves to another cell).
      firstRightDragValue = currentValue == 0 ? 2 : 0;
      _pendingRightClickIdx = idx;
      lastRightDragIdx = idx;
      return;
    }

    // Subsequent event on a *different* cell: a drag is happening.
    // Flush the deferred initial click first (logged as a click,
    // since at the time it was committed the user hadn't moved yet),
    // then paint the new cell if it sits at the opposite value.
    _beforeMutation();
    lastRightDragIdx = idx;
    if (_pendingRightClickIdx != null) {
      _commitRightToggle(_pendingRightClickIdx!, isDrag: false);
      _pendingRightClickIdx = null;
    }
    final oppositeValue = firstRightDragValue == 0 ? 2 : 0;
    if (currentValue == oppositeValue) {
      _commitRightToggle(idx, isDrag: true);
    }
    notifyListeners();
  }

  void _commitRightToggle(int idx, {required bool isDrag}) {
    final changed = currentPuzzle!.setValue(idx, firstRightDragValue!);
    if (changed) {
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
      _log.fine(
        '${isDrag ? "right-drag" : "right-click"} cell $idx '
        '→ ${currentPuzzle!.cellValues[idx]}',
      );
    }
  }

  void handleRightDragEnd() {
    // Skip when no right-drag was actually started: the cell widget's
    // `Listener.onPointerUp` fires for every pointer release on
    // desktop/web, including a regular left-click — without this
    // guard each tap would log a spurious "right-drag end" and
    // re-run `_afterMutation`.
    if (firstRightDragValue == null && lastRightDragIdx == null) return;
    // Commit a deferred right-click that was never converted to a
    // drag — the user pressed and released without moving. This is
    // where the symmetric "commit on release" semantics with the
    // left button live.
    if (_pendingRightClickIdx != null) {
      _beforeMutation();
      _commitRightToggle(_pendingRightClickIdx!, isDrag: false);
      _pendingRightClickIdx = null;
    }
    _log.fine('right-drag end');
    firstRightDragValue = null;
    lastRightDragIdx = null;
    _afterMutation();
  }

  // ---------------------------------------------------------------------------
  // Check / validation
  // ---------------------------------------------------------------------------

  void handleCheck(
    Settings settings, {
    required String invalidConstraintsText,
    required String Function(int count) errorsCountText,
    required void Function() onPuzzleCompleted,
  }) {
    _syncManualCompletionPause(settings);
    // Every mutation re-arms the debounce from 0: the player must let the
    // puzzle sit for 1s before errors surface or the switch happens. This is
    // why the existing errors are cleared synchronously on tap (via
    // `clearConstraintsValidity`) — they only reappear if the next check,
    // after the debounce, still finds them.
    _checkDebounce?.cancel();
    _checkDebounce = Timer(const Duration(seconds: 1), () {
      _checkDebounce = null;
      if (currentPuzzle == null) return;
      checkPuzzle(
        settings,
        invalidConstraintsText: invalidConstraintsText,
        errorsCountText: errorsCountText,
        onPuzzleCompleted: onPuzzleCompleted,
      );
    });
  }

  void checkPuzzle(
    Settings settings, {
    bool manualCheck = false,
    required String invalidConstraintsText,
    required String Function(int count) errorsCountText,
    required void Function() onPuzzleCompleted,
  }) {
    // Manual-validation mode holds back *all* automatic feedback
    // (errors, count, completion transition) until the player presses
    // « Valider » — which calls us back with manualCheck=true. Without
    // this gate, the debounce would surface errors as soon as the grid
    // is full, even though the player explicitly opted out of automatic
    // validation.
    if (!manualCheck && settings.validateType == ValidateType.manual) {
      return;
    }
    // In `complete` (« Attendre ») mode the player asked us to hold
    // off any validation feedback until the grid is fully filled. The
    // only useful check before that is "is the puzzle complete?"
    // (a O(N) "no zero cells" scan) — we skip the full constraint
    // check entirely in that case. Manual validate-button clicks
    // bypass the gate so the player can still force a check.
    if (!manualCheck &&
        settings.liveCheckType == LiveCheckType.complete &&
        !currentPuzzle!.complete) {
      return;
    }
    final shouldShowErrors =
        settings.liveCheckType == LiveCheckType.all || currentPuzzle!.complete;
    final failedConstraints = currentPuzzle!.check(
      saveResult: shouldShowErrors,
    );
    if (failedConstraints.isNotEmpty &&
        settings.liveCheckType == LiveCheckType.complete) {
      currentMeta!.failures += 1;
      currentMeta!.stats?.failures += 1;
    }
    if (failedConstraints.isNotEmpty && shouldShowErrors) {
      setTopMessage(text: invalidConstraintsText, color: Colors.red);
    } else if (failedConstraints.isNotEmpty &&
        settings.liveCheckType == LiveCheckType.count) {
      setTopMessage(
        text: errorsCountText(failedConstraints.length),
        color: Colors.red,
      );
    } else {
      setTopMessage();
    }
    _log.fine(
      'check: ${failedConstraints.length} failed, '
      'complete=${currentPuzzle!.complete}',
    );
    notifyListeners();

    final shouldComplete =
        failedConstraints.isEmpty &&
        currentPuzzle!.complete &&
        (manualCheck || settings.validateType != ValidateType.manual);
    if (shouldComplete) {
      _log.info('Puzzle completed');
      _finalizeCompletion(settings, onPuzzleCompleted);
    }
  }

  void _finalizeCompletion(
    Settings settings,
    void Function() onPuzzleCompleted,
  ) {
    currentMeta!.stop();
    _stoppedForCompletion = false;
    onPuzzleCompleted();
    if (settings.showRating == ShowRating.yes) {
      betweenPuzzles = true;
    }
    notifyListeners();
  }

  void _cancelCheckDebounce() {
    _checkDebounce?.cancel();
    _checkDebounce = null;
  }

  // ---------------------------------------------------------------------------
  // Hint
  // ---------------------------------------------------------------------------

  /// Drive the multi-tap hint flow. Both modes share tap 1 (errors) — the
  /// modes only differ on what subsequent taps do. The caller pre-resolves
  /// every l10n string into [texts]; this method picks the right one for the
  /// stage being entered.
  void onHintTap(Settings settings, HintTexts texts) {
    if (currentPuzzle == null) return;
    final mode = settings.hintType;
    _log.fine('hint tap: stage=$hintStage mode=$mode');

    // Stage 0 → 1: errors, regardless of mode.
    if (hintStage == 0) {
      _revealErrors(texts);
      hintStage = 1;
      // On-demand: in `addConstraint` mode, kick off the (expensive) search
      // for a simplifying constraint now — while the player reads the "all
      // correct" pass — so tap 2 can consume it. Skip when:
      //  - the error pass surfaced a mistake (`hintIsError`): the player must
      //    fix it first, and a contradictory state has no useful candidate;
      //  - a pass is already ready or in flight (e.g. fields pre-populated, or
      //    a slow web pass still running) → don't wipe a usable result.
      if (mode == HintType.addConstraint &&
          !hintIsError &&
          hintConstraintsReady != HintConstraintStatus.ready &&
          hintConstraintsReady != HintConstraintStatus.inprogress) {
        startHintConstraintComputation();
      }
      notifyListeners();
      return;
    }

    if (mode == HintType.deducibleCell) {
      switch (hintStage) {
        case 1:
          _revealCellOnly(texts);
          hintStage = 2;
        case 2:
          _revealCellAndConstraint(texts);
          hintStage = 3;
        case 3:
          _applyHelpMove();
          // _afterMutation has already reset hintStage to 0.
          return;
      }
    } else {
      // addConstraint mode: tap 2 attaches a new constraint, then we cycle
      // back to stage 0 so the next tap re-runs the error pass.
      if (hintStage == 1) {
        _revealAddedConstraint(texts);
        hintStage = 0;
      }
    }
    notifyListeners();
  }

  /// Reset the multi-tap cycle without touching the puzzle state. Used when
  /// the hint mode is switched mid-puzzle so the next tap starts at stage 1.
  void resetHintCycle() {
    currentPuzzle?.clearHighlights();
    hintText = "";
    hintIsError = false;
    hintStage = 0;
    _pendingRevealTexts = null;
    notifyListeners();
  }

  /// Tap 1 — surface error info (or "all correct" when the grid is fine).
  /// Shared between both hint modes. Three sub-cases, in priority order:
  ///   (a) a constraint is currently violated → highlight it
  ///   (b) a filled cell diverges from the cached solution → highlight it
  ///   (c) nothing wrong → "all correct so far" message, no highlight
  void _revealErrors(HintTexts texts) {
    final puzzle = currentPuzzle!;
    puzzle.clearHighlights();

    final failed = puzzle.check(saveResult: false);
    if (failed.isNotEmpty) {
      failed.first.isHighlighted = true;
      hintText = texts.someConstraintsInvalid;
      hintIsError = true;
      return;
    }

    final wrongIdx = puzzle.findFirstWrongCell();
    if (wrongIdx != null) {
      puzzle.cells[wrongIdx].isHighlighted = true;
      hintText = texts.hintCellWrong;
      hintIsError = true;
      return;
    }

    hintText = texts.hintAllCorrectSoFar;
    hintIsError = false;
  }

  /// Tap 2 of `deducibleCell` — highlight the deducible cell, no source yet.
  /// No-op if [helpMove] hasn't been computed (debounce race or puzzle
  /// already solved); the next tap will retry from the current stage.
  void _revealCellOnly(HintTexts texts) {
    if (helpMove == null) return;
    currentPuzzle!.clearHighlights();
    currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
    hintText = texts.hintCellDeducible;
    hintIsError = false;
  }

  /// Tap 3 of `deducibleCell` — also highlight the giving constraint, which
  /// triggers the arrow widget (see `widgets/puzzle.dart`). Increment the
  /// hint counter here: this is the "real" reveal — tap 1 is diagnostic only.
  void _revealCellAndConstraint(HintTexts texts) {
    if (helpMove == null) return;
    currentPuzzle!.clearHighlights();
    if (helpMove!.isImpossible != null) {
      final impossibleSource = helpMove!.isImpossible;
      // Only Constraints carry the `isValid` UI flag; complicities
      // currently have no on-screen representation, so we just skip the
      // highlight in that branch.
      if (impossibleSource is Constraint) impossibleSource.isValid = false;
      hintText = texts.hintImpossible;
      hintIsError = true;
    } else {
      if (helpMove!.isForce) {
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
        hintText = texts.hintForce;
      } else {
        final givenBy = helpMove!.givenBy;
        if (givenBy is Constraint) givenBy.isHighlighted = true;
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
        hintText = texts.hintDeducedFrom(givenBy);
      }
      hintIsError = false;
    }
    if (currentMeta != null) {
      currentMeta!.hints += 1;
      currentMeta!.stats?.hints += 1;
    }
  }

  /// Tap 4 of `deducibleCell` — apply the move. Triggers `_afterMutation`,
  /// which resets [hintStage] and recomputes the next [helpMove].
  void _applyHelpMove() {
    if (helpMove == null) return;
    currentPuzzle!.setValue(helpMove!.idx, helpMove!.value);
    history.add(helpMove!.idx);
    _afterMutation();
  }

  /// Tap 2 of `addConstraint` — attach the next useful constraint, or
  /// surface a "no more available" message when the candidate list is
  /// empty (still leaves the button useful: tap 1 worked, this is just the
  /// terminal feedback). Stage advancement is handled by the caller.
  void _revealAddedConstraint(HintTexts texts) {
    if (hintConstraintsReady == HintConstraintStatus.inprogress) {
      hintText = texts.hintConstraintInprogress;
      hintIsError = false;
      // Remember we're waiting on this pass: its completion callback will
      // reveal the constraint for us (no extra tap needed).
      _pendingRevealTexts = texts;
    } else if (addHintConstraint()) {
      hintText = texts.hintConstraintAdded;
      hintIsError = false;
      startHintConstraintComputation();
    } else {
      currentPuzzle?.clearHighlights();
      hintText = texts.hintConstraintNone;
      hintIsError = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Rating
  // ---------------------------------------------------------------------------

  void like(int liked) {
    if (currentMeta == null) return;
    currentMeta!.pleasure = liked;
    if (liked > 0) {
      currentMeta!.liked = DateTime.now();
    } else if (liked < 0) {
      currentMeta!.disliked = DateTime.now();
    }
  }

  // ---------------------------------------------------------------------------
  // Hint constraint computation
  // ---------------------------------------------------------------------------

  /// Start computing valid hint constraints in a background Isolate.
  /// Only works if the current puzzle has a cached solution.
  void startHintConstraintComputation() {
    cancelHintConstraintComputation();
    // Skip the expensive clone+solve loop entirely when the player is in
    // `deducibleCell` mode — the resulting list is never shown to them, and
    // on web the work runs on the main isolate (no true background thread),
    // which froze the UI when `_afterMutation` re-fired this on every tap.
    if (hintType != HintType.addConstraint) return;
    final puzzle = currentPuzzle;
    if (puzzle == null || puzzle.cachedSolution == null) return;

    hintConstraintsReady = HintConstraintStatus.inprogress;
    availableHintConstraints = [];

    final worker = HintWorker();
    _hintWorker = worker;
    worker
        .compute(puzzle: puzzle)
        .then((result) {
          // Drop stale results: the worker we awaited is no longer the
          // active one (cancelled or replaced by a newer call).
          if (!identical(worker, _hintWorker)) return;
          onHintConstraintComputed(result);
        })
        .catchError((Object _) {
          // Cancellation closes the receive port → first throws StateError.
          // Nothing to do: a newer worker is in flight (or none is needed).
        });
  }

  /// Settle the state once a constraint search returns [result] (the
  /// serialized constraint, or null when none was found). Visible for testing
  /// — production code reaches it only through the worker's completion
  /// callback in [startHintConstraintComputation].
  void onHintConstraintComputed(String? result) {
    availableHintConstraints = result == null ? [] : [result];
    hintConstraintsReady = result == null
        ? HintConstraintStatus.nohint
        : HintConstraintStatus.ready;
    _hintWorker = null;
    // If the player is parked on the "computing…" message, reveal the
    // freshly-computed constraint immediately instead of waiting for another
    // tap. `_revealAddedConstraint` now sees a settled status (ready/nohint),
    // so it adds the constraint or shows "none".
    final pending = _pendingRevealTexts;
    if (pending != null) {
      _pendingRevealTexts = null;
      _revealAddedConstraint(pending);
    }
    notifyListeners();
  }

  void cancelHintConstraintComputation() {
    _hintWorker?.dispose();
    _hintWorker = null;
    hintConstraintsReady = HintConstraintStatus.canceled;
    availableHintConstraints = [];
    // Drop any pending auto-reveal: the pass it was waiting on is gone.
    _pendingRevealTexts = null;
  }

  /// Add the offered hint constraint to the puzzle, then reset the hint state
  /// so the next tap-1 recomputes a fresh suggestion against the new state.
  /// Returns true if a constraint was added.
  bool addHintConstraint() {
    if (currentPuzzle == null || availableHintConstraints.isEmpty) {
      return false;
    }

    // Clear previous highlights before adding a new one
    currentPuzzle!.clearHighlights();

    final serialized = availableHintConstraints.removeAt(0);

    // Parse "SLUG:params" and create the constraint
    final colonIdx = serialized.indexOf(':');
    final slug = serialized.substring(0, colonIdx);
    final params = serialized.substring(colonIdx + 1);
    final constraint = createConstraint(slug, params);
    if (constraint == null) return false;

    constraint.isHighlighted = true;
    final before = currentPuzzle!.constraints
        .map((c) => c.serialize())
        .join('|');
    currentPuzzle!.addConstraint(constraint);
    final after = currentPuzzle!.constraints
        .map((c) => c.serialize())
        .join('|');
    if (before == after) {
      // The add changed nothing (e.g. an LT merge with no new cell). Don't
      // claim a constraint was added and don't bill the hint; reset so the
      // next tap-1 recomputes a fresh suggestion against the current state.
      hintConstraintsReady = HintConstraintStatus.canceled;
      notifyListeners();
      return false;
    }
    if (currentMeta != null) {
      currentMeta!.hints += 1;
      currentMeta!.stats?.hints += 1;
    }
    // The suggestion is consumed and the puzzle changed; force the next
    // tap-1 to recompute from scratch rather than reuse a stale state.
    hintConstraintsReady = HintConstraintStatus.canceled;
    notifyListeners();
    return true;
  }

  /// Whether the "add constraint" hint button should be enabled.
  /// True as long as a computed candidate is available.
  bool get canAddHintConstraint =>
      hintConstraintsReady == HintConstraintStatus.ready &&
      availableHintConstraints.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Help computation (debounced)
  // ---------------------------------------------------------------------------

  void _scheduleHelpMe() {
    _helpDebounce?.cancel();
    _helpDebounce = Timer(const Duration(milliseconds: 300), _computeHelp);
  }

  void _computeHelp() {
    if (currentPuzzle == null) return;
    // Errors are surfaced by tap 1 of the hint flow ([_revealErrors]); the
    // pre-computed move is purely the next *deducible* move.
    helpMove = currentPuzzle!.findAMove(checkErrors: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _helpDebounce?.cancel();
    _cancelCheckDebounce();
    _cancelIdleTimer();
    _hintWorker?.dispose();
    super.dispose();
  }
}

/// L10n strings for the hint flow, pre-resolved by the caller. Bundled in a
/// struct rather than passed individually because [GameModel.onHintTap] picks
/// the right one based on the (mode, stage, sub-case) combo at call time.
class HintTexts {
  final String someConstraintsInvalid;
  final String hintCellWrong;
  final String hintAllCorrectSoFar;
  final String hintCellDeducible;
  final String hintImpossible;
  final String hintForce;
  final String Function(CanApply givenBy) hintDeducedFrom;
  final String hintConstraintAdded;
  final String hintConstraintInprogress;
  final String hintConstraintNone;

  const HintTexts({
    required this.someConstraintsInvalid,
    required this.hintCellWrong,
    required this.hintAllCorrectSoFar,
    required this.hintCellDeducible,
    required this.hintImpossible,
    required this.hintForce,
    required this.hintDeducedFrom,
    required this.hintConstraintAdded,
    required this.hintConstraintInprogress,
    required this.hintConstraintNone,
  });
}
