import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint_registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/settings.dart';
import 'package:logging/logging.dart';

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
  bool shouldCheck = false;

  // --- Visual feedback ---
  String topMessage = "";
  Color topMessageColor = Colors.black;

  // --- Hint constraint state ---
  HintWorker? _hintWorker;
  List<String> availableHintConstraints = [];
  bool hintConstraintsReady = false;

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
    setTopMessage();
  }

  /// Schedule hint computation and notify the UI.
  /// Called after every mutation that changes which moves are available.
  void _onPuzzleChanged() {
    _scheduleHelpMe();
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
    dbSize = playlistLength;
    currentMeta = puz;
    currentPuzzle = currentMeta!.begin();
    paused = false;
    betweenPuzzles = false;
    hintText = "";
    _onPuzzleChanged();
  }

  void clearPuzzle() {
    cancelHintConstraintComputation();
    currentPuzzle = null;
    history = [];
    betweenPuzzles = false;
    notifyListeners();
  }

  void restart() {
    if (currentPuzzle == null) return;
    history = [];
    currentPuzzle!.restart();
    _resetPuzzleState();
    _onPuzzleChanged();
  }

  void undo() {
    if (currentPuzzle == null || history.isEmpty) return;
    currentPuzzle!.resetCell(history.removeLast());
    _resetPuzzleState();
    _onPuzzleChanged();
  }

  // ---------------------------------------------------------------------------
  // Pause / resume
  // ---------------------------------------------------------------------------

  void pause() {
    paused = true;
    currentMeta?.stats?.pause();
    notifyListeners();
  }

  void resume() {
    paused = false;
    if (currentPuzzle != null) {
      currentMeta?.stats?.resume();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cell interaction
  // ---------------------------------------------------------------------------

  /// Returns true if the tap was handled (cell was toggled).
  bool handleTap(int idx) {
    if (currentPuzzle == null) return false;
    if (currentPuzzle!.cells[idx].readonly) return false;
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
    if (settings.liveCheckType == LiveCheckType.all ||
        settings.liveCheckType == LiveCheckType.count) {
      shouldCheck = true;
      _autoCheck(settings, onPuzzleCompleted: onPuzzleCompleted);
      return;
    }
    if (settings.validateType == ValidateType.manual) return;
    shouldCheck = currentPuzzle!.complete;
    if (shouldCheck) {
      Future.delayed(
        const Duration(seconds: 1),
        () => _autoCheck(settings, onPuzzleCompleted: onPuzzleCompleted),
      );
    }
  }

  void _autoCheck(
    Settings settings, {
    required void Function() onPuzzleCompleted,
  }) {
    if (!shouldCheck) return;
    shouldCheck = false;
    if (currentPuzzle == null) return;
    checkPuzzle(settings, onPuzzleCompleted: onPuzzleCompleted);
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
    if (failedConstraints.isEmpty) {
      if (currentPuzzle!.complete &&
          (manualCheck || settings.validateType != ValidateType.manual)) {
        currentMeta!.stop();
        onPuzzleCompleted();
        if (settings.showRating == ShowRating.yes) {
          betweenPuzzles = true;
        }
      }
    } else if (settings.liveCheckType == LiveCheckType.complete) {
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
          availableHintConstraints = result;
          hintConstraintsReady = true;
          _hintWorker = null;
          notifyListeners();
        });
  }

  void cancelHintConstraintComputation() {
    _hintWorker?.dispose();
    _hintWorker = null;
    hintConstraintsReady = false;
    availableHintConstraints = [];
  }

  /// Pick a random constraint from available ones and add it to the puzzle.
  /// Returns true if a constraint was added.
  bool addHintConstraint() {
    if (currentPuzzle == null || availableHintConstraints.isEmpty) return false;

    availableHintConstraints.shuffle();
    final serialized = availableHintConstraints.removeLast();

    // Parse "SLUG:params" and create the constraint
    final colonIdx = serialized.indexOf(':');
    final slug = serialized.substring(0, colonIdx);
    final params = serialized.substring(colonIdx + 1);
    final constraint = createConstraint(slug, params);
    if (constraint == null) return false;

    constraint.isHighlighted = true;
    currentPuzzle!.constraints.add(constraint);
    notifyListeners();
    return true;
  }

  /// Whether the "add constraint" hint button should be enabled.
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
    helpMove = currentPuzzle!.findAMove();
    notifyListeners();
  }

  @override
  void dispose() {
    _helpDebounce?.cancel();
    _hintWorker?.dispose();
    super.dispose();
  }
}
