import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';
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
    super.dispose();
  }
}
