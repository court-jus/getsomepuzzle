import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_rank_worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
import 'package:logging/logging.dart';

/// Why the game was automatically paused. Null means either the user paused
/// manually (no subtitle needed) or the game is running.
enum AutoPauseReason { idle, focusLost }

class GameModel extends ChangeNotifier {
  // --- Puzzle state ---
  PuzzleData? currentMeta;
  Puzzle? currentPuzzle;
  List<int> history = [];
  int dbSize = 0;

  // --- Hint state ---
  Move? helpMove;
  String hintText = "";
  bool hintIsError = false;

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
  /// window elapses without any interaction. Callers pass the current
  /// duration via [markInteraction] so the model does not need to know the
  /// user's settings directly.
  Timer? _idleTimer;

  // --- Visual feedback ---
  String topMessage = "";
  Color topMessageColor = Colors.black;

  // --- Hint constraint state ---
  HintWorker? _hintWorker;
  HintRankWorker? _hintRankWorker;
  Timer? _hintRankDebounce;
  List<String> availableHintConstraints = [];
  bool hintConstraintsReady = false;
  int _usefulHintCount = 0;

  // --- Drag state ---
  int? firstDragValue;
  int? lastDragIdx;
  int? firstRightDragValue;
  int? lastRightDragIdx;

  Timer? _helpDebounce;
  final _log = Logger("GameModel");

  // ---------------------------------------------------------------------------
  // Internal helpers – factorise the repeated reset patterns
  // ---------------------------------------------------------------------------

  /// Clears hint highlight and text, used when user interacts with the puzzle.
  void _clearHint() {
    currentPuzzle?.clearHighlights();
    hintText = "";
  }

  /// Full reset of interaction state (hint, errors, between-puzzles).
  /// Used after undo / restart where both the view and the puzzle state change.
  void _resetPuzzleState() {
    _clearHint();
    betweenPuzzles = false;
    currentPuzzle?.clearConstraintsValidity();
    currentPuzzle?.updateConstraintStatus();
    setTopMessage();
  }

  /// Schedule hint computation and notify the UI.
  /// Called after every mutation that changes which moves are available.
  void _onPuzzleChanged() {
    _scheduleHelpMe();
    _scheduleHintRanking();
    notifyListeners();
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

  void openPuzzle(PuzzleData puz, int playlistLength) {
    _cancelCheckDebounce();
    _cancelIdleTimer();
    dbSize = playlistLength;
    currentMeta = puz;
    currentPuzzle = currentMeta!.begin();
    paused = false;
    betweenPuzzles = false;
    _stoppedForCompletion = false;
    _autoPauseReason = null;
    hintText = "";
    _onPuzzleChanged();
  }

  void clearPuzzle() {
    _cancelCheckDebounce();
    _cancelIdleTimer();
    cancelHintConstraintComputation();
    currentPuzzle = null;
    history = [];
    betweenPuzzles = false;
    notifyListeners();
  }

  void restart() {
    if (currentPuzzle == null) return;
    _cancelCheckDebounce();
    history = [];
    currentPuzzle!.restart();
    _clearCompletionFreeze();
    _resetPuzzleState();
    _onPuzzleChanged();
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    _cancelCheckDebounce();
    currentPuzzle!.resetCell(history.removeLast());
    currentPuzzle!.updateConstraintStatus();
    _clearCompletionFreeze();
    _resetPuzzleState();
    _onPuzzleChanged();
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
  void markInteraction(Duration? duration) {
    if (_autoPauseReason == AutoPauseReason.idle) return;
    _rearmIdleTimer(duration);
  }

  void _rearmIdleTimer(Duration? duration) {
    _cancelIdleTimer();
    if (duration == null) return;
    if (currentPuzzle == null || paused || betweenPuzzles) return;
    _idleTimer = Timer(duration, () {
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

  /// Unfreeze the manual-completion stopwatch when a puzzle mutation is
  /// guaranteed to leave the puzzle incomplete (restart / undo).
  void _clearCompletionFreeze() {
    if (!_stoppedForCompletion) return;
    currentMeta?.stats?.resume();
    _stoppedForCompletion = false;
  }

  // ---------------------------------------------------------------------------
  // Cell interaction
  // ---------------------------------------------------------------------------

  /// Returns true if the tap was handled (cell was toggled).
  bool handleTap(int idx) {
    if (currentPuzzle == null) return false;
    if (currentPuzzle!.cells[idx].readonly) return false;
    _cancelCheckDebounce();
    _clearHint();
    currentPuzzle!.incrValue(idx);
    currentPuzzle!.clearConstraintsValidity();
    helpMove = null;
    if (history.isEmpty || history.last != idx) history.add(idx);
    _onPuzzleChanged();
    return true;
  }

  void handleDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (lastDragIdx != null && idx == lastDragIdx) return;
    _cancelCheckDebounce();
    lastDragIdx = idx;
    if (firstDragValue == null) {
      final myOpposite = currentPuzzle!.domain
          .whereNot((e) => e == currentPuzzle!.cellValues[idx])
          .first;
      firstDragValue = myOpposite;
      currentPuzzle!.setValue(idx, firstDragValue!);
      if (history.isEmpty || history.last != idx) history.add(idx);
    }
    if (currentPuzzle!.cellValues[idx] != firstDragValue &&
        currentPuzzle!.cellValues[idx] == 0) {
      currentPuzzle!.setValue(idx, firstDragValue!);
      if (history.isEmpty || history.last != idx) history.add(idx);
    }
    notifyListeners();
  }

  void handleDragEnd() {
    firstDragValue = null;
    lastDragIdx = null;
    notifyListeners();
  }

  void handleRightDrag(int idx) {
    if (currentPuzzle == null) return;
    if (idx < 0 || idx >= currentPuzzle!.cells.length) return;
    if (lastRightDragIdx != null && idx == lastRightDragIdx) return;
    final currentValue = currentPuzzle!.cellValues[idx];
    if (firstRightDragValue == null && currentValue == 1) return;
    _cancelCheckDebounce();
    lastRightDragIdx = idx;
    if (firstRightDragValue == null) {
      firstRightDragValue = currentValue == 0 ? 2 : 0;
      print("$idx $currentValue $firstRightDragValue");
      final changed = currentPuzzle!.setValue(idx, firstRightDragValue!);
      if (changed && (history.isEmpty || history.last != idx)) history.add(idx);
    }
    final oppositeValue = firstRightDragValue == 0 ? 2 : 0;
    if (currentPuzzle!.cellValues[idx] == oppositeValue) {
      final changed = currentPuzzle!.setValue(idx, firstRightDragValue!);
      if (changed && (history.isEmpty || history.last != idx)) history.add(idx);
    }
    notifyListeners();
  }

  void handleRightDragEnd() {
    firstRightDragValue = null;
    lastRightDragIdx = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Check / validation
  // ---------------------------------------------------------------------------

  void handleCheck(
    Settings settings, {
    required void Function() onPuzzleCompleted,
  }) {
    _syncManualCompletionPause(settings);
    if (settings.validateType == ValidateType.manual) return;
    // Every mutation re-arms the debounce from 0: the player must let the
    // puzzle sit for 1s before errors surface or the switch happens. This is
    // why the existing errors are cleared synchronously on tap (via
    // `clearConstraintsValidity`) — they only reappear if the next check,
    // after the debounce, still finds them.
    _checkDebounce?.cancel();
    _checkDebounce = Timer(const Duration(seconds: 1), () {
      _checkDebounce = null;
      if (currentPuzzle == null) return;
      checkPuzzle(settings, onPuzzleCompleted: onPuzzleCompleted);
    });
  }

  void checkPuzzle(
    Settings settings, {
    bool manualCheck = false,
    required void Function() onPuzzleCompleted,
  }) {
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
    if (failedConstraints.isNotEmpty) {
      if (shouldShowErrors) {
        setTopMessage(
          text: "Some constraints are not valid.",
          color: Colors.red,
        );
      } else {
        setTopMessage(
          text: "${failedConstraints.length} errors.",
          color: Colors.red,
        );
      }
    } else {
      setTopMessage();
    }
    notifyListeners();

    final shouldComplete =
        failedConstraints.isEmpty &&
        currentPuzzle!.complete &&
        (manualCheck || settings.validateType != ValidateType.manual);
    if (shouldComplete) {
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

  /// Shows the hint or applies the help move.
  /// [resolvedHintText] must be pre-resolved from l10n by the caller.
  void showHelpMove(String resolvedHintText) {
    if (helpMove == null) return;
    if (hintText.isNotEmpty && !hintIsError) {
      _clearHint();
      currentPuzzle!.setValue(helpMove!.idx, helpMove!.value);
      history.add(helpMove!.idx);
      _onPuzzleChanged();
      return;
    }
    currentPuzzle!.clearHighlights();
    if (helpMove!.isImpossible != null) {
      helpMove!.isImpossible!.isValid = false;
      hintText = resolvedHintText;
      hintIsError = true;
    } else {
      if (helpMove!.isForce) {
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
      } else {
        helpMove!.givenBy.isHighlighted = true;
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
      }
      hintText = resolvedHintText;
      hintIsError = false;
    }
    notifyListeners();
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
    final puzzle = currentPuzzle;
    if (puzzle == null || puzzle.cachedSolution == null) return;

    hintConstraintsReady = false;
    availableHintConstraints = [];
    _usefulHintCount = 0;

    final existingConstraints = puzzle.constraints
        .map((c) => c.serialize())
        .toSet();
    final readonlyIndices = <int>{};
    for (int i = 0; i < puzzle.cells.length; i++) {
      if (puzzle.cells[i].readonly) readonlyIndices.add(i);
    }

    _hintWorker = HintWorker();
    _hintWorker!
        .compute(
          width: puzzle.width,
          height: puzzle.height,
          domain: puzzle.domain,
          solution: puzzle.cachedSolution!,
          existingConstraints: existingConstraints,
          readonlyIndices: readonlyIndices,
        )
        .then((result) {
          result.shuffle();
          availableHintConstraints = result;
          hintConstraintsReady = true;
          _hintWorker = null;
          _computeHintRanking();
        });
  }

  void cancelHintConstraintComputation() {
    _cancelHintRanking();
    _hintWorker?.dispose();
    _hintWorker = null;
    hintConstraintsReady = false;
    availableHintConstraints = [];
    _usefulHintCount = 0;
  }

  // ---------------------------------------------------------------------------
  // Hint constraint ranking
  // ---------------------------------------------------------------------------

  void _scheduleHintRanking() {
    if (!hintConstraintsReady || availableHintConstraints.isEmpty) return;
    _hintRankDebounce?.cancel();
    _hintRankDebounce = Timer(
      const Duration(milliseconds: 300),
      _computeHintRanking,
    );
  }

  void _computeHintRanking() {
    _hintRankWorker?.dispose();
    _hintRankWorker = null;
    final puzzle = currentPuzzle;
    if (puzzle == null || availableHintConstraints.isEmpty) return;

    _hintRankWorker = HintRankWorker();
    _hintRankWorker!
        .rank(
          width: puzzle.width,
          height: puzzle.height,
          domain: puzzle.domain,
          cellValues: puzzle.cellValues,
          existingConstraints: puzzle.constraints
              .map((c) => c.serialize())
              .toList(),
          candidateConstraints: availableHintConstraints,
        )
        .then((result) {
          availableHintConstraints = result.ranked;
          _usefulHintCount = result.usefulCount;
          _hintRankWorker = null;
          notifyListeners();
        });
  }

  void _cancelHintRanking() {
    _hintRankDebounce?.cancel();
    _hintRankWorker?.dispose();
    _hintRankWorker = null;
  }

  /// Pick the first useful constraint and add it to the puzzle.
  /// Returns true if a constraint was added.
  bool addHintConstraint() {
    if (currentPuzzle == null || _usefulHintCount <= 0) return false;

    // Clear previous highlights before adding a new one
    currentPuzzle!.clearHighlights();

    // Take the first useful constraint (ranking puts them at the front)
    final serialized = availableHintConstraints.removeAt(0);
    _usefulHintCount--;

    // Parse "SLUG:params" and create the constraint
    final colonIdx = serialized.indexOf(':');
    final slug = serialized.substring(0, colonIdx);
    final params = serialized.substring(colonIdx + 1);
    final constraint = createConstraint(slug, params);
    if (constraint == null) return false;

    constraint.isHighlighted = true;
    currentPuzzle!.constraints.add(constraint);
    _scheduleHintRanking();
    notifyListeners();
    return true;
  }

  /// Whether the "add constraint" hint button should be enabled.
  bool get canAddHintConstraint => hintConstraintsReady && _usefulHintCount > 0;

  // ---------------------------------------------------------------------------
  // Help computation (debounced)
  // ---------------------------------------------------------------------------

  void _scheduleHelpMe() {
    _helpDebounce?.cancel();
    _helpDebounce = Timer(const Duration(milliseconds: 300), _computeHelp);
  }

  void _computeHelp() {
    if (currentPuzzle == null) return;
    _log.fine(currentPuzzle!.lineRepresentation);
    helpMove = currentPuzzle!.findAMove();
    notifyListeners();
  }

  @override
  void dispose() {
    _helpDebounce?.cancel();
    _cancelCheckDebounce();
    _cancelIdleTimer();
    _hintWorker?.dispose();
    _cancelHintRanking();
    super.dispose();
  }
}
