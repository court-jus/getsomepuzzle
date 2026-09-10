import 'dart:async';

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

  /// True when the stopwatch was silently paused because the puzzle is
  /// solved (complete + valid) in manual-next mode
  /// (`Settings.nextPuzzleDelay == NextPuzzleDelay.manual`). Same semantics
  /// as [_stoppedForCompletion] but keyed on *valid completion* rather than
  /// a full grid, so it is a distinct flag: the manual-validation freeze
  /// (which keyed on completeness alone) and this one can both be active
  /// at once and must not clear each other. Cleared when the player mutates
  /// the puzzle again (see [_beforeMutation]) or the play transitions away.
  bool _stoppedForManualNext = false;

  /// True when a solved puzzle waits for the player to tap the manual-next
  /// floating button (only in manual-next mode). Shown by the game screen's
  /// [Scaffold.floatingActionButton]; cleared on any mutation, on advance,
  /// and on puzzle transition.
  bool showNextFab = false;

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
  Color? topMessageColor;

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

  /// Constraint slugs the player has already learned (the owner's
  /// `ConstraintProgress.firstSeen` keys). Passed to the hint worker so an
  /// `addConstraint` hint never offers a type the player has not yet seen
  /// explained. Owners must keep this in sync; empty means "only reinforce
  /// types already on the puzzle".
  Set<String> learnedHintSlugs = const <String>{};

  // --- Drag state ---
  CellValue? firstDragValue;
  int? lastDragIdx;
  CellValue? firstRightDragValue;
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
  ///
  /// Also rolls back the `isValid` flags the error pass may have cleared
  /// ([_revealErrors] marks violated constraints invalid to show their red
  /// border) — without this, a red border set by a hint would stay stuck
  /// after the player interacts (e.g. after a drag, which has no explicit
  /// `clearConstraintsValidity` call of its own).
  void _clearHint() {
    currentPuzzle?.clearHighlights();
    currentPuzzle?.clearConstraintsValidity();
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
  ///
  /// Also drops the manual-next state: once the player edits the grid again,
  /// the puzzle is no longer "solved waiting for next" — the floating button
  /// disappears and the frozen stopwatch resumes counting.
  void _beforeMutation() {
    _cancelCheckDebounce();
    cancelHintConstraintComputation();
    rearmIdleTimer();
    showNextFab = false;
    if (_stoppedForManualNext) {
      currentMeta?.stats?.resume();
      _stoppedForManualNext = false;
    }
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

  void setTopMessage({String text = "", Color? color}) {
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
    _stoppedForManualNext = false;
    showNextFab = false;
    notifyListeners();
  }

  /// Load a puzzle directly from a v2 line string, bypassing the Database,
  /// playlist, onboarding, and locale machinery.
  ///
  /// Used by autopilot mode. Resets all interaction state, history and hint
  /// state, then opens the puzzle as if it were the only one in a playlist.
  /// No stats, no auto-rotation, and no modal dialogs fire.
  void loadPuzzleFromLine(String v2Line) {
    _beforeMutation();
    history = [];
    _cancelIdleTimer();
    dbSize = 1;
    currentMeta = PuzzleData(v2Line);
    currentPuzzle = Puzzle(v2Line);
    _isPuzzleRotated = false;
    paused = false;
    betweenPuzzles = false;
    _stoppedForCompletion = false;
    _autoPauseReason = null;
    setTopMessage();
    _afterMutation();
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
    // If the puzzle is still complete in manual mode, or solved in manual-
    // next mode, keep the stopwatch frozen — the user must break the state
    // or advance before it counts again.
    if (currentPuzzle != null &&
        !_stoppedForCompletion &&
        !_stoppedForManualNext) {
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
  ///
  /// [removeOptionMode] switches a free cell's tap from the regular
  /// `incrValue` cycle to the option-pruning cycle (only meaningful on
  /// 3+ colour puzzles — collapses to `incrValue` everywhere else).
  /// When the cell already has a value, both modes share the same
  /// behaviour so the player never gets "stuck" on a coloured cell.
  /// Apply the tap action selected by [removeOptionMode] to cell [idx], with
  /// the bookkeeping shared by every cell-paint gesture (tap, long-press,
  /// right-click): stats edit counter, constraint-validity reset, undo history
  /// and a log line under [label].
  void _applyTap(
    int idx, {
    required bool removeOptionMode,
    required String label,
  }) {
    if (removeOptionMode && currentPuzzle!.domain.length > 2) {
      currentPuzzle!.cycleRemoveOption(idx);
    } else {
      currentPuzzle!.incrValue(idx);
    }
    currentMeta?.stats?.recordCellEdit();
    currentPuzzle!.clearConstraintsValidity();
    if (history.isEmpty || history.last != idx) history.add(idx);
    _log.fine('$label cell $idx → ${currentPuzzle!.cellValues[idx]}');
  }

  bool handleTap(int idx, {bool removeOptionMode = false}) {
    if (currentPuzzle == null) return false;
    if (currentPuzzle!.cells[idx].readonly) return false;
    _beforeMutation();
    _applyTap(idx, removeOptionMode: removeOptionMode, label: 'tap');
    _afterMutation();
    return true;
  }

  void handleDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (currentPuzzle!.cells[idx].readonly) return;
    if (lastDragIdx != null && idx == lastDragIdx) return;
    _beforeMutation();
    lastDragIdx = idx;
    if (firstDragValue == null) {
      // First cell of the drag: pick the *next* colour in the cycle
      // (so the drag mirrors what a tap would do). Paint the initial
      // cell unconditionally, then lock that value for the rest of
      // the drag.
      firstDragValue = _nextCycle(currentPuzzle!.cellValues[idx]);
      _applyLeftDragPaint(idx);
    } else if (firstDragValue != CellValue.free &&
        currentPuzzle!.cellValues[idx] == CellValue.free) {
      // Subsequent cells: only repaint *free* cells, never overwrite
      // an already-coloured cell. When the cycle's "next" value is
      // free (drag starting on the domain's last colour), there's no
      // useful repaint to do — the initial cell was reset, the rest
      // is left alone.
      _applyLeftDragPaint(idx);
    }
    notifyListeners();
  }

  /// Apply [firstDragValue] to cell [idx]. Free target uses [resetCell]
  /// so the cell's options are restored to the full domain (otherwise it
  /// would land in the degenerate `value = free, options = []` state).
  void _applyLeftDragPaint(int idx) {
    if (firstDragValue == CellValue.free) {
      if (currentPuzzle!.cells[idx].value == CellValue.free) return;
      currentPuzzle!.resetCell(idx);
      currentPuzzle!.updateConstraintStatus();
    } else {
      // `ignoreOptions` because painting overrides any option-pruning the
      // player did on that cell — and an already-coloured start cell has
      // empty options, so the unguarded setValue would throw RangeError.
      // Mirrors the right-drag path (`_commitRightPaint` / `decrValue`).
      if (!currentPuzzle!.setValue(idx, firstDragValue!, ignoreOptions: true)) {
        return;
      }
    }
    currentMeta?.stats?.recordCellEdit();
    if (history.isEmpty || history.last != idx) history.add(idx);
    _log.fine('drag cell $idx → ${currentPuzzle!.cellValues[idx]}');
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
    if (currentPuzzle!.cells[idx].readonly) return;
    if (lastRightDragIdx != null && idx == lastRightDragIdx) return;
    final currentValue = currentPuzzle!.cellValues[idx];

    if (firstRightDragValue == null) {
      // First event of a right-button gesture. The deferred-commit
      // dance with [_pendingRightClickIdx] is kept: a lone press-and-
      // release acts as a right-click (committed at pointer-up), while
      // a move to another cell flushes the initial cell and starts
      // painting. The cached value is the *paint target* used on the
      // subsequent cells of a right-drag — derived from the initial
      // cell's colour through the cycle's previous step so the right
      // gesture mirrors the right-click cycle (free → domain.last,
      // domain[i] → domain[i-1], domain[0] → free).
      firstRightDragValue = _prevCycle(currentValue);
      _pendingRightClickIdx = idx;
      lastRightDragIdx = idx;
      return;
    }

    // Subsequent event on a *different* cell: a drag is happening.
    // Flush the deferred initial cell (which applies a [decrValue],
    // i.e. one step backward in the cycle), then paint the new cell
    // if it is free. We never overwrite an already-coloured cell on
    // a right-drag — symmetric with the left-drag.
    _beforeMutation();
    lastRightDragIdx = idx;
    if (_pendingRightClickIdx != null) {
      _commitRightDecr(_pendingRightClickIdx!, isDrag: false);
      _pendingRightClickIdx = null;
    }
    if (firstRightDragValue != CellValue.free &&
        currentValue == CellValue.free) {
      _commitRightPaint(idx);
    }
    notifyListeners();
  }

  /// Apply [Puzzle.decrValue] to the initial cell of a right gesture.
  /// Used both for a pure right-click (release without move) and as
  /// the deferred commit when a right-drag starts moving away from
  /// the initial cell.
  void _commitRightDecr(int idx, {required bool isDrag}) {
    final before = currentPuzzle!.cellValues[idx];
    currentPuzzle!.decrValue(idx);
    final after = currentPuzzle!.cellValues[idx];
    if (before != after) {
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
      _log.fine('${isDrag ? "right-drag" : "right-click"} cell $idx → $after');
    }
  }

  /// Paint the [firstRightDragValue] colour on a free cell traversed
  /// during a right-drag. Caller must have already checked the target
  /// is not free and the cell currently holds [CellValue.free].
  void _commitRightPaint(int idx) {
    final changed = currentPuzzle!.setValue(
      idx,
      firstRightDragValue!,
      ignoreOptions: true,
    );
    if (changed) {
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
      _log.fine('right-drag cell $idx → ${currentPuzzle!.cellValues[idx]}');
    }
  }

  /// [removeOptionMode] selects the swapped tap action committed by a pure
  /// right-click on a 3+ colour puzzle (see [handleLongPress]); it is ignored
  /// on 2-colour puzzles and by a right-drag.
  void handleRightDragEnd({bool removeOptionMode = false}) {
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
      if (currentPuzzle!.domain.length > 2) {
        _applyTap(
          _pendingRightClickIdx!,
          removeOptionMode: !removeOptionMode,
          label: 'right-click',
        );
      } else {
        _commitRightDecr(_pendingRightClickIdx!, isDrag: false);
      }
      _pendingRightClickIdx = null;
    }
    _log.fine('right-drag end');
    firstRightDragValue = null;
    lastRightDragIdx = null;
    _afterMutation();
  }

  /// Long-press on a cell — mobile fallback for the right-click.
  ///
  /// On a 3+ colour puzzle the long-press applies the *other* tap mode's
  /// action (see [_applyTap]): in normal mode it prunes one option dot
  /// (`cycleRemoveOption`), in remove-option mode it cycles the colour
  /// forward (`incrValue`). A coloured cell therefore falls back to
  /// `incrValue` in normal mode, exactly like a tap in remove-option mode.
  ///
  /// On a 2-colour puzzle (no option dots) the long-press keeps the
  /// historical backward colour cycle (`decrValue`).
  bool handleLongPress(int idx, {bool removeOptionMode = false}) {
    if (currentPuzzle == null) return false;
    if (currentPuzzle!.cells[idx].readonly) return false;
    if (currentPuzzle!.domain.length > 2) {
      _beforeMutation();
      _applyTap(idx, removeOptionMode: !removeOptionMode, label: 'long-press');
      _afterMutation();
      return true;
    }
    _beforeMutation();
    final before = currentPuzzle!.cellValues[idx];
    currentPuzzle!.decrValue(idx);
    final after = currentPuzzle!.cellValues[idx];
    if (before == after) {
      // No change (degenerate domain or already-blocked cell) — skip
      // the recordCellEdit / history bookkeeping but still flush state.
      _afterMutation();
      return false;
    }
    currentMeta?.stats?.recordCellEdit();
    currentPuzzle!.clearConstraintsValidity();
    if (history.isEmpty || history.last != idx) history.add(idx);
    _log.fine('long-press cell $idx → $after');
    _afterMutation();
    return true;
  }

  /// One step forward in the puzzle's colour cycle. Used to derive a
  /// left-drag's paint target from the first touched cell's colour, so
  /// the drag stays in sync with a regular tap.
  CellValue _nextCycle(CellValue v) {
    final domain = currentPuzzle!.domain;
    if (domain.isEmpty) return CellValue.free;
    if (v == CellValue.free) return domain.first;
    final i = domain.indexOf(v);
    if (i < 0 || i == domain.length - 1) return CellValue.free;
    return domain[i + 1];
  }

  /// Mirror of [_nextCycle] used by the right-drag handler.
  CellValue _prevCycle(CellValue v) {
    final domain = currentPuzzle!.domain;
    if (domain.isEmpty) return CellValue.free;
    if (v == CellValue.free) return domain.last;
    final i = domain.indexOf(v);
    if (i <= 0) return CellValue.free;
    return domain[i - 1];
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
    // puzzle sit before errors surface or the switch happens. The settle
    // window is the configured next-puzzle delay (1s / 3s / 10s); in manual
    // mode there is no auto-switch delay, so errors still surface on the
    // default 1s settle.
    _checkDebounce?.cancel();
    final delay = settings.nextPuzzleDelay == NextPuzzleDelay.manual
        ? const Duration(seconds: 1)
        : settings.nextPuzzleDelayDuration!;
    _checkDebounce = Timer(delay, () {
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
      if (settings.nextPuzzleDelay == NextPuzzleDelay.manual) {
        // Manual-next mode: no auto-switch. Freeze the solve time now (the
        // play is over) and surface the floating "next" button instead of
        // transitioning. The player advances via `advanceToNextPuzzle`.
        _log.info('Puzzle completed — waiting for manual next');
        if (!_stoppedForManualNext) {
          currentMeta?.stats?.pause();
          _stoppedForManualNext = true;
        }
        showNextFab = true;
        notifyListeners();
        return;
      }
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
    _stoppedForManualNext = false;
    showNextFab = false;
    onPuzzleCompleted();
    if (settings.showRating == ShowRating.yes) {
      betweenPuzzles = true;
    }
    notifyListeners();
  }

  /// Advance to the next puzzle from the manual-next floating button:
  /// finalizes the play exactly like the automatic path does
  /// ([_finalizeCompletion]). The solve was already recorded (stopwatch
  /// frozen) when the button appeared, so this only runs the completion /
  /// rating transition.
  void advanceToNextPuzzle(
    Settings settings,
    void Function() onPuzzleCompleted,
  ) {
    _finalizeCompletion(settings, onPuzzleCompleted);
  }

  /// If the current puzzle is solved and waiting on the manual-next button,
  /// finalize the play under [settings]. Used when the player switches the
  /// next-puzzle-delay setting away from `manual` mid-solve: the pending
  /// state must not survive, and auto mode would have advanced the solved
  /// puzzle anyway. No-op when no manual-next state is active.
  void advanceIfManualNextPending(
    Settings settings,
    void Function() onPuzzleCompleted,
  ) {
    if (!showNextFab && !_stoppedForManualNext) return;
    _finalizeCompletion(settings, onPuzzleCompleted);
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
  ///
  /// [onPuzzleCompleted] is invoked when the player taps the hint button on
  /// a fully-and-validly-completed puzzle past stage 1. Tap 1 still shows
  /// the "everything filled so far is correct" message (since no error /
  /// no wrong cell can be surfaced); the next tap repurposes the hint
  /// button as a "next puzzle" trigger so the player keeps moving without
  /// having to find a separate UI control.
  void onHintTap(
    Settings settings,
    HintTexts texts, {
    void Function()? onPuzzleCompleted,
  }) {
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

    // Past stage 1, on a complete-and-valid puzzle there is nothing left
    // to deduce — repurpose the next tap as "advance to the next puzzle"
    // so the player doesn't get stuck pressing a no-op button.
    if (currentPuzzle!.complete &&
        currentPuzzle!.check(saveResult: false).isEmpty) {
      if (onPuzzleCompleted != null) {
        onPuzzleCompleted();
        resetHintCycle();
      }
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
  ///   (a) constraints are currently violated → mark every violated
  ///       constraint invalid (red border, no arrows — no cell is
  ///       highlighted) and report how many are violated
  ///   (b) a filled cell diverges from the cached solution → highlight it
  ///   (c) nothing wrong → "all correct so far" message, no highlight
  void _revealErrors(HintTexts texts) {
    final puzzle = currentPuzzle!;
    puzzle.clearHighlights();

    final failed = puzzle.check(saveResult: false);
    if (failed.isNotEmpty) {
      for (final constraint in failed) {
        constraint.isValid = false;
      }
      hintText = texts.hintConstraintsInvalid(failed.length);
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
    final move = helpMove;
    if (move == null) return;
    currentPuzzle!.clearHighlights();
    switch (move) {
      case SetValue(:final idx):
        currentPuzzle!.cells[idx].isHighlighted = true;
        hintText = texts.hintCellDeducible;
      case RemoveOption(:final idx):
        currentPuzzle!.cells[idx].isHighlighted = true;
        // In a 2-colour domain, removing one option ≡ choosing the other, so
        // present the move as a cell deduction rather than an option removal.
        hintText = currentPuzzle!.domain.length == 2
            ? texts.hintCellDeducible
            : texts.hintCellOptionRemovable;
      case Impossible():
        // A contradiction has no single deducible cell to highlight at this
        // stage; tap 3 (_revealCellAndConstraint) surfaces it as
        // `hintImpossible`.
        break;
    }
    hintIsError = false;
  }

  /// Tap 3 of `deducibleCell` — also highlight the giving constraint, which
  /// triggers the arrow widget (see `widgets/puzzle.dart`). Increment the
  /// hint counter here: this is the "real" reveal — tap 1 is diagnostic only.
  void _revealCellAndConstraint(HintTexts texts) {
    final move = helpMove;
    if (move == null) return;
    currentPuzzle!.clearHighlights();
    switch (move) {
      case Impossible(:final givenBy):
        if (givenBy is Constraint) givenBy.isValid = false;
        hintText = texts.hintImpossible;
        hintIsError = true;
      case RemoveOption(
        :final idx,
        :final isForce,
        :final givenBy,
        :final contributors,
      ):
        currentPuzzle!.cells[idx].isHighlighted = true;
        final domain2 = currentPuzzle!.domain.length == 2;
        if (isForce) {
          hintText = domain2 ? texts.hintForce : texts.hintForceRemoveOption;
        } else {
          _highlightContributors(contributors, givenBy);
          hintText = domain2
              ? texts.hintDeducedFrom(givenBy)
              : texts.hintRemoveOptionDeducedFrom(givenBy);
        }
        hintIsError = false;
      case SetValue(:final idx, :final givenBy, :final contributors):
        _highlightContributors(contributors, givenBy);
        currentPuzzle!.cells[idx].isHighlighted = true;
        hintText = texts.hintDeducedFrom(givenBy);
        hintIsError = false;
    }
    if (currentMeta != null) {
      currentMeta!.hints += 1;
      currentMeta!.stats?.hints += 1;
    }
  }

  void _highlightContributors(List<CanApply> contributors, CanApply givenBy) {
    final targets = contributors.isEmpty ? <CanApply>[givenBy] : contributors;
    for (final c in targets) {
      if (c is Constraint) c.isHighlighted = true;
    }
  }

  /// Tap 4 of `deducibleCell` — apply the move. Triggers `_afterMutation`,
  /// which resets [hintStage] and recomputes the next [helpMove].
  ///
  /// Two move shapes are supported: `setValue` (the cell takes a concrete
  /// colour) and `removeOption` (the cell loses one possible colour but
  /// stays free, unless it was the last option in which case
  /// `Cell.removeOption` auto-collapses to a setValue).
  void _applyHelpMove() {
    final move = helpMove;
    if (move == null) return;
    switch (move) {
      case SetValue(:final idx, :final value):
        currentPuzzle!.setValue(idx, value, ignoreOptions: true);
        history.add(idx);
        _afterMutation();
      case RemoveOption(:final idx, :final option):
        currentPuzzle!.removeOption(idx, option);
        history.add(idx);
        _afterMutation();
      case Impossible():
        // Nothing to apply for a contradiction (matches the prior no-op).
        break;
    }
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
        .compute(puzzle: puzzle, learnedSlugs: learnedHintSlugs)
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
  /// Message shown when one or more constraints are violated on the first
  /// hint tap; takes the number of violated constraints.
  final String Function(int count) hintConstraintsInvalid;
  final String hintCellWrong;
  final String hintAllCorrectSoFar;
  final String hintCellDeducible;
  final String hintImpossible;
  final String hintForce;
  final String Function(CanApply givenBy) hintDeducedFrom;
  final String hintConstraintAdded;
  final String hintConstraintInprogress;
  final String hintConstraintNone;

  /// Variants used when the help move is a `removeOption` rather than a
  /// `setValue`. Same shape as their siblings above, but phrased in terms
  /// of "an option can be removed" rather than "the cell can be deduced".
  final String hintCellOptionRemovable;
  final String hintForceRemoveOption;
  final String Function(CanApply givenBy) hintRemoveOptionDeducedFrom;

  const HintTexts({
    required this.hintConstraintsInvalid,
    required this.hintCellWrong,
    required this.hintAllCorrectSoFar,
    required this.hintCellDeducible,
    required this.hintImpossible,
    required this.hintForce,
    required this.hintDeducedFrom,
    required this.hintConstraintAdded,
    required this.hintConstraintInprogress,
    required this.hintConstraintNone,
    required this.hintCellOptionRemovable,
    required this.hintForceRemoveOption,
    required this.hintRemoveOptionDeducedFrom,
  });
}
