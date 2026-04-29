import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
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
    rearmIdleTimer();
  }

  /// Called once a mutation settles into a stable state. Clears hints,
  /// schedules help/ranking recomputation, notifies listeners, and re-arms
  /// the idle watchdog. Not called during drag steps — the drag commits
  /// via [handleDragEnd].
  void _afterMutation() {
    _clearHint();
    _scheduleHelpMe();
    _scheduleHintRanking();
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

  void openPuzzle(PuzzleData puz, int playlistLength) {
    _beforeMutation();
    _cancelIdleTimer();
    dbSize = playlistLength;
    currentMeta = puz;
    currentPuzzle = currentMeta!.begin();
    paused = false;
    betweenPuzzles = false;
    _stoppedForCompletion = false;
    _autoPauseReason = null;
    _afterMutation();
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
    }
    if (currentPuzzle!.cellValues[idx] != firstDragValue &&
        currentPuzzle!.cellValues[idx] == 0) {
      currentPuzzle!.setValue(idx, firstDragValue!);
      currentMeta?.stats?.recordCellEdit();
      if (history.isEmpty || history.last != idx) history.add(idx);
    }
    notifyListeners();
  }

  void handleDragEnd() {
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
    _beforeMutation();
    lastRightDragIdx = idx;
    if (firstRightDragValue == null) {
      firstRightDragValue = currentValue == 0 ? 2 : 0;
      print("$idx $currentValue $firstRightDragValue");
      final changed = currentPuzzle!.setValue(idx, firstRightDragValue!);
      if (changed) {
        currentMeta?.stats?.recordCellEdit();
        if (history.isEmpty || history.last != idx) history.add(idx);
      }
    }
    final oppositeValue = firstRightDragValue == 0 ? 2 : 0;
    if (currentPuzzle!.cellValues[idx] == oppositeValue) {
      final changed = currentPuzzle!.setValue(idx, firstRightDragValue!);
      if (changed) {
        currentMeta?.stats?.recordCellEdit();
        if (history.isEmpty || history.last != idx) history.add(idx);
      }
    }
    notifyListeners();
  }

  void handleRightDragEnd() {
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

  /// Drive the multi-tap hint flow. Both modes share tap 1 (errors) — the
  /// modes only differ on what subsequent taps do. The caller pre-resolves
  /// every l10n string into [texts]; this method picks the right one for the
  /// stage being entered.
  void onHintTap(Settings settings, HintTexts texts) {
    if (currentPuzzle == null) return;
    final mode = settings.hintType;

    // Stage 0 → 1: errors, regardless of mode.
    if (hintStage == 0) {
      _revealErrors(texts);
      hintStage = 1;
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
      helpMove!.isImpossible!.isValid = false;
      hintText = texts.hintImpossible;
      hintIsError = true;
    } else {
      if (helpMove!.isForce) {
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
        hintText = texts.hintForce;
      } else {
        helpMove!.givenBy.isHighlighted = true;
        currentPuzzle!.cells[helpMove!.idx].isHighlighted = true;
        hintText = texts.hintDeducedFrom(helpMove!.givenBy);
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
    if (addHintConstraint()) {
      hintText = texts.hintConstraintAdded;
      hintIsError = false;
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

    final worker = HintWorker();
    _hintWorker = worker;
    worker
        .compute(
          width: puzzle.width,
          height: puzzle.height,
          domain: puzzle.domain,
          solution: puzzle.cachedSolution!,
          existingConstraints: existingConstraints,
          readonlyIndices: readonlyIndices,
        )
        .then((result) {
          // Drop stale results: the worker we awaited is no longer the
          // active one (cancelled or replaced by a newer call).
          if (!identical(worker, _hintWorker)) return;
          result.shuffle();
          availableHintConstraints = result;
          hintConstraintsReady = true;
          _hintWorker = null;
          _computeHintRanking();
        })
        .catchError((Object _) {
          // Cancellation closes the receive port → first throws StateError.
          // Nothing to do: a newer worker is in flight (or none is needed).
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

    final worker = HintRankWorker();
    _hintRankWorker = worker;
    worker
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
          // Drop stale results: this worker may have been cancelled and
          // replaced by a newer one mid-flight (rapid cell changes).
          if (!identical(worker, _hintRankWorker)) return;
          availableHintConstraints = result.ranked;
          _usefulHintCount = result.usefulCount;
          _hintRankWorker = null;
          notifyListeners();
        })
        .catchError((Object _) {
          // Cancellation closes the receive port → first throws StateError.
          // A newer ranker has already taken over (or none is needed).
        });
  }

  void _cancelHintRanking() {
    _hintRankDebounce?.cancel();
    _hintRankWorker?.dispose();
    _hintRankWorker = null;
  }

  /// Pick the front candidate and add it to the puzzle. Useful candidates
  /// (those that unlock new propagation) come first; once they're exhausted
  /// the player can still request a constraint and gets one from the
  /// non-useful tail — adding redundant constraints is harmless and lets a
  /// player who asks for help past the propagation horizon receive
  /// something rather than a blank "none available" message.
  /// Returns true if a constraint was added.
  bool addHintConstraint() {
    if (currentPuzzle == null || availableHintConstraints.isEmpty) {
      return false;
    }

    // Clear previous highlights before adding a new one
    currentPuzzle!.clearHighlights();

    // Front of the list: useful first, then non-useful tail.
    final serialized = availableHintConstraints.removeAt(0);
    if (_usefulHintCount > 0) _usefulHintCount--;

    // Parse "SLUG:params" and create the constraint
    final colonIdx = serialized.indexOf(':');
    final slug = serialized.substring(0, colonIdx);
    final params = serialized.substring(colonIdx + 1);
    final constraint = createConstraint(slug, params);
    if (constraint == null) return false;

    constraint.isHighlighted = true;
    currentPuzzle!.constraints.add(constraint);
    if (currentMeta != null) {
      currentMeta!.hints += 1;
      currentMeta!.stats?.hints += 1;
    }
    _scheduleHintRanking();
    notifyListeners();
    return true;
  }

  /// Whether the "add constraint" hint button should be enabled.
  /// True as long as any candidate remains, regardless of whether it's
  /// "useful" — the player can opt to add a redundant constraint anyway.
  bool get canAddHintConstraint =>
      hintConstraintsReady && availableHintConstraints.isNotEmpty;

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
    _cancelHintRanking();
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
  final String Function(Constraint givenBy) hintDeducedFrom;
  final String hintConstraintAdded;
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
    required this.hintConstraintNone,
  });
}
