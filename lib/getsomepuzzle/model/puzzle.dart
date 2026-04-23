import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/helptext.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/other_solution.dart';

/// Result of a single apply-and-set step in the shared loop.
enum ApplyLoopResult { applied, complete, impossible, stuck }

/// Exception thrown by the solver when a contradiction is detected.
class SolverContradiction implements Exception {
  final String message;
  SolverContradiction([this.message = '']);
}

/// Method used to determine a cell value during solving.
enum SolveMethod { propagation, force }

/// One step in the step-by-step solving trace.
class SolveStep {
  final int cellIdx;
  final int value;
  final String constraint;
  final SolveMethod method;

  const SolveStep({
    required this.cellIdx,
    required this.value,
    required this.constraint,
    required this.method,
  });

  @override
  String toString() {
    return '${method.name}: cell $cellIdx = $value${constraint.isNotEmpty ? ' by $constraint' : ''}';
  }
}

class Stats {
  int failures = 0;
  int hints = 0;
  int duration = 0;
  Stopwatch timer = Stopwatch();

  @override
  String toString() {
    // 2025-08-23T22:59:42 8s - 0f 3x3_000001020_GS:5.1;PA:6.top;PA:0.right;PA:2.left;FM:222_1:212121122
    return "${(timer.elapsedMilliseconds / 1000).round()}s - ${failures}f - ${hints}h";
  }

  void begin() {
    timer.start();
    failures = 0;
    hints = 0;
  }

  void pause() {
    timer.stop();
  }

  void resume() {
    timer.start();
  }

  void stop(String puzzleRepresentation) {
    timer.stop();
    duration = (timer.elapsedMilliseconds / 1000).round();
    timer.reset();
  }
}

class Puzzle {
  String lineRepresentation;
  List<int> domain = [];
  int width = 0;
  int height = 0;
  List<Cell> _cells = [];
  List<Constraint> constraints = [];
  int? cachedComplexity;
  List<int>? cachedSolution;

  /// Cached result of `getGroups(this)`. Invalidated whenever any cell's
  /// value or options change via `Cell.onMutate`.
  List<List<int>>? cachedGroups;

  List<Cell> get cells => _cells;
  set cells(List<Cell> value) {
    _cells = value;
    for (final c in _cells) {
      c.onMutate = _invalidateCaches;
    }
    _invalidateCaches();
  }

  void _invalidateCaches() {
    cachedGroups = null;
  }

  Puzzle(this.lineRepresentation) {
    var attributesStr = lineRepresentation.split("_");
    final dimensions = attributesStr[2].split("x");
    domain = attributesStr[1].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    cells = attributesStr[3]
        .split("")
        .map((e) => int.parse(e))
        .indexed
        .map((e) => Cell(e.$2, e.$1, domain, e.$2 > 0))
        .toList();
    final strConstraints = attributesStr[4].split(";");
    for (var strConstraint in strConstraints) {
      final constraintAttr = strConstraint.split(":");
      final slug = constraintAttr[0];
      final params = constraintAttr.length > 1 ? constraintAttr[1] : '';
      if (slug == 'TX') {
        constraints.add(HelpText(params));
      } else {
        final c = createConstraint(slug, params);
        if (c != null) constraints.add(c);
      }
    }
    if (attributesStr.length > 5) {
      final solParts = attributesStr[5].split(':');
      if (solParts[0] == '1' && solParts.length > 1) {
        cachedSolution = solParts[1]
            .split('')
            .map((e) => int.parse(e))
            .toList();
      }
    }
  }

  void restart() {
    for (var cell in cells) {
      if (!cell.readonly) {
        cell.value = 0;
        cell.options = cell.domain;
      }
    }
    _invalidateCaches();
  }

  List<int> get cellValues => cells.map((cell) => cell.value).toList();
  Map<int, List<Constraint>> get cellConstraints {
    final Map<int, List<Constraint>> result = {};
    for (var constraint in constraints.whereType<CellsCentricConstraint>()) {
      for (var idx in constraint.indices) {
        if (!result.keys.contains(idx)) {
          result[idx] = [];
        }
        result[idx]!.add(constraint);
      }
    }
    return result;
  }

  int getValue(int idx) {
    return cells[idx].value;
  }

  List<List<Cell>> getRows() {
    // 12_4x5_00020210200022001201_FM:1.2;PA:10.top;PA:19.top_1:22222212221122111211
    return cells.slices(width).toList();
  }

  List<List<Cell>> getColumns() {
    final rows = getRows();
    final List<List<Cell>> result = [];
    for (var i = 0; i < rows[0].length; i++) {
      result.add([]);
      for (var row in rows) {
        result[i].add(row[i]);
      }
    }
    return result;
  }

  List<int> getNeighbors(int idx) {
    final maxidx = width * height - 1;
    final minidx = 0;
    final ridx = idx ~/ width;
    final abv = idx - width;
    final bel = idx + width;
    final lft = idx - 1;
    final rgt = idx + 1;
    final List<int> result = [];
    if (abv >= minidx) result.add(abv);
    if (bel <= maxidx) result.add(bel);
    if (lft >= minidx && lft ~/ width == ridx) result.add(lft);
    if (rgt <= maxidx && rgt ~/ width == ridx) result.add(rgt);
    return result;
  }

  bool setValue(int idx, int value) {
    final cell = cells[idx];
    final result = cell.setValue(value);
    updateConstraintStatus();
    return result;
  }

  void updateConstraintStatus() {
    for (final constraint in constraints) {
      constraint.isComplete = constraint.isCompleteFor(this);
    }
  }

  void resetCell(int idx) {
    final cell = cells[idx];
    cell.reset();
  }

  void incrValue(int idx) {
    final currentValue = cellValues[idx];
    setValue(idx, (currentValue + 1) % (domain.length + 1));
  }

  bool get complete {
    return !cellValues.any((val) => val == 0);
  }

  List<Constraint> check({bool saveResult = true}) {
    final List<Constraint> result = [];
    for (var constraint in constraints) {
      if (!constraint.check(this, saveResult: saveResult)) {
        result.add(constraint);
      }
    }
    return result;
  }

  Move? apply() {
    for (var c in constraints) {
      final move = c.apply(this);
      if (move != null) return move;
    }
    return null;
  }

  /// Shared loop: calls apply() repeatedly, sets values, tracks last move.
  /// Returns (result, lastMove, changeCount).
  (ApplyLoopResult, Move?, int) _applyLoop() {
    int changes = 0;
    Move? lastMove;
    while (true) {
      final move = apply();
      if (move == null) return (ApplyLoopResult.stuck, lastMove, changes);
      lastMove = move;
      if (move.isImpossible != null) {
        return (ApplyLoopResult.impossible, move, changes);
      }
      setValue(move.idx, move.value);
      changes++;
      if (complete) {
        final hasErrors = check(saveResult: false).isNotEmpty;
        if (hasErrors) {
          return (ApplyLoopResult.impossible, move, changes);
        }
        return (ApplyLoopResult.complete, move, changes);
      }
    }
  }

  Move? applyAll() {
    final (result, lastMove, _) = _applyLoop();
    switch (result) {
      case ApplyLoopResult.stuck:
        return null;
      case ApplyLoopResult.impossible:
        return Move(
          0,
          0,
          lastMove!.givenBy,
          isImpossible: lastMove.isImpossible ?? lastMove.givenBy,
        );
      case ApplyLoopResult.complete:
        return Move(0, 0, lastMove!.givenBy);
      case ApplyLoopResult.applied:
        return null; // should not happen, loop always reaches stuck/impossible/complete
    }
  }

  /// Next deducible move, or null if stuck. Does not mutate `this`.
  /// [checkErrors] returns a corrective move for invalid constraints (UI-only).
  /// [tryForce] enables the force fallback when propagation is stuck.
  Move? findAMove({bool checkErrors = true, bool tryForce = true}) {
    if (checkErrors) {
      final hasErrors = check(saveResult: false);
      if (hasErrors.isNotEmpty) {
        final firstError = hasErrors.first;
        final errorMove = firstError.apply(this);
        if (errorMove != null) {
          return errorMove;
        }
      }
    }
    final easyMove = apply();
    if (easyMove != null) return easyMove;
    if (!tryForce) return null;
    return _forceOneCell();
  }

  /// Try setting each free cell to each domain value on a clone; if a value
  /// leads to contradiction, return the opposite as a forced move.
  Move? _forceOneCell() {
    final clone = this.clone();
    for (var freeCell in clone.cells.indexed.where(
      (entry) => entry.$2.value == 0,
    )) {
      for (var value in clone.domain) {
        clone.setValue(freeCell.$1, value);
        Move? result = clone.applyAll();
        final unsolvableErrors = clone.check(saveResult: false);
        if (unsolvableErrors.isNotEmpty) {
          final opposite = clone.domain.whereNot((v) => v == value).first;
          clone.setValue(freeCell.$1, opposite);
          return Move(
            freeCell.$1,
            opposite,
            unsolvableErrors.first,
            isForce: true,
          );
        }
        if (result != null && result.isImpossible != null) {
          final opposite = clone.domain.whereNot((v) => v == value).first;
          return Move(freeCell.$1, opposite, result.givenBy, isForce: true);
        } else if (result != null && result.isImpossible == null) {
          return Move(freeCell.$1, value, result.givenBy, isForce: true);
        } else {
          for (var cell in cellValues.indexed) {
            clone.setValue(cell.$1, cell.$2);
          }
        }
      }
    }
    return null;
  }

  void clearConstraintsValidity() {
    for (var constraint in constraints) {
      constraint.isValid = true;
    }
  }

  void clearHighlights() {
    for (var constraint in constraints) {
      constraint.isHighlighted = false;
    }
    for (var cell in cells) {
      cell.isHighlighted = false;
    }
  }

  // --- Constructor for empty puzzles (no lineRepresentation parsing) ---
  Puzzle.empty(this.width, this.height, this.domain) : lineRepresentation = '' {
    cells = List.generate(width * height, (idx) => Cell(0, idx, domain, false));
  }

  Puzzle clone() {
    final p = Puzzle.empty(width, height, domain);
    p.lineRepresentation = lineRepresentation;
    p.cells = cells.map((c) => c.clone()).toList();
    // Deep-clone constraints: the mutable UI-state fields (`isValid`,
    // `isHighlighted`, `isComplete`) must not be shared between the clone
    // and the original, else exploratory solver work on the clone (force,
    // backtracking, findAMove) leaks state into the original puzzle.
    p.constraints = constraints.map(_cloneConstraint).toList();
    return p;
  }

  static Constraint _cloneConstraint(Constraint c) {
    if (c is HelpText) return HelpText(c.text);
    if (c is OtherSolutionConstraint) {
      return OtherSolutionConstraint(List<int>.from(c.solution));
    }
    final serialized = c.serialize();
    final colonIdx = serialized.indexOf(':');
    if (colonIdx < 0) return c;
    final slug = serialized.substring(0, colonIdx);
    final params = serialized.substring(colonIdx + 1);
    return createConstraint(slug, params) ?? c;
  }

  List<(Cell, int)> freeCells() {
    return cells.indexed
        .where((entry) => entry.$2.isFree)
        .map((entry) => (entry.$2, entry.$1))
        .toList();
  }

  double computeRatio() {
    final values = cellValues;
    return values.where((v) => v == 0).length / values.length;
  }

  bool isPossible() {
    return cells.every((c) => c.isPossible);
  }

  /// Apply propagation-only deductions until stuck, complete, or contradiction.
  /// Returns the number of setValue calls made, or `null` if a contradiction
  /// was hit (meaning the current state is inconsistent — callers use this as
  /// a rejection signal).
  /// [verifyAfterEachMove] re-runs all constraints' `verify()` after each set,
  /// to catch inter-constraint violations that per-constraint `apply()` misses.
  int? propagateToFixpoint({bool verifyAfterEachMove = false}) {
    int moves = 0;
    while (true) {
      final m = findAMove(checkErrors: false, tryForce: false);
      if (m == null) return moves;
      if (m.isImpossible != null) return null;
      setValue(m.idx, m.value);
      moves++;
      if (verifyAfterEachMove && check(saveResult: false).isNotEmpty) {
        return null;
      }
      if (complete) return moves;
    }
  }

  /// Iterative constraint propagation (solver).
  /// Calls apply() repeatedly and sets values.
  /// When [autoCheck] is true, verify all constraints after each step
  /// and throw on violation (like Python's auto_check=True).
  /// Throws [SolverContradiction] on contradiction.
  /// Returns the number of changes made.
  int applyConstraintsPropagation({bool autoCheck = false}) {
    int changes = 0;
    while (true) {
      final move = apply();
      if (move == null) return changes;
      if (move.isImpossible != null) {
        throw SolverContradiction('Constraint returned impossible');
      }
      setValue(move.idx, move.value);
      changes++;
      if (autoCheck) {
        final failed = check(saveResult: false);
        if (failed.isNotEmpty) {
          throw SolverContradiction(
            'Constraint verification failed after apply',
          );
        }
      }
      if (complete) {
        final failed = check(saveResult: false);
        if (failed.isNotEmpty) {
          throw SolverContradiction('Completed but constraints violated');
        }
        return changes;
      }
    }
  }

  /// For each free cell, try each value on a clone. If a value leads to
  /// contradiction, eliminate it from the cell's options.
  /// When [stopAfterFirst] is true, returns as soon as one cell is determined.
  /// Returns true if any progress was made.
  /// Throws [SolverContradiction] if any cell runs out of options.
  bool applyWithForce({bool stopAfterFirst = false}) {
    bool changed = false;
    final free = freeCells();
    for (final (cell, idx) in free) {
      if (cell.options.length <= 1) continue;
      for (final value in List<int>.from(cell.options)) {
        final testPu = clone();
        testPu.cells[idx].setForSolver(value);
        if (testPu.propagateToFixpoint(verifyAfterEachMove: true) != null) {
          continue;
        }
        cell.options.remove(value);
        if (cell.options.length == 1) {
          cell.setForSolver(cell.options[0]);
          changed = true;
          if (stopAfterFirst) return true;
        } else if (cell.options.isEmpty) {
          throw SolverContradiction('Cell $idx has no options left');
        }
      }
    }
    return changed;
  }

  /// Compute puzzle complexity on a 0-100 scale.
  ///
  /// Three components:
  /// - **Force rounds** (0-90): each round of forced deduction = 10 points,
  ///   capped at 9 rounds. 100 if backtracking is needed.
  /// - **Rule diversity** (0-4): number of distinct constraint types.
  ///   1 type=0, 2=1, 3=2, 4-5=3, 6+=4.
  /// - **Emptiness** (0-6): proportion of free cells.
  ///   Fully empty=6, 50% filled=3, fully filled=0.
  int computeComplexity() {
    if (cachedComplexity != null) return cachedComplexity!;

    final size = width * height;
    final totalFree = freeCells().length;
    if (totalFree == 0) {
      cachedSolution = cellValues;
      cachedComplexity = 0;
      return 0;
    }

    // Count distinct rule types (exclude HelpText)
    final ruleTypes = constraints
        .map((c) => c.serialize().split(':').first)
        .where((s) => s.isNotEmpty && s != 'TX')
        .toSet()
        .length;

    // Rule diversity: 1→0, 2→1, 3→2, 4-5→3, 6+→4
    final int ruleDiversity;
    if (ruleTypes <= 1) {
      ruleDiversity = 0;
    } else if (ruleTypes <= 3) {
      ruleDiversity = ruleTypes - 1;
    } else if (ruleTypes <= 5) {
      ruleDiversity = 3;
    } else {
      ruleDiversity = 4;
    }

    // Emptiness: ratio of free cells, scaled to 0-6
    final emptiness = (totalFree / size * 6).round();

    // Force rounds
    final test = clone();
    try {
      test.applyConstraintsPropagation();
    } on SolverContradiction {
      cachedComplexity = 100;
      return 100;
    }

    int forceRounds = 0;
    if (test.freeCells().isNotEmpty) {
      for (int step = 0; step < 200; step++) {
        try {
          final forced = test.applyWithForce(stopAfterFirst: true);
          if (!forced) break;
          forceRounds++;
          test.applyConstraintsPropagation();
        } on SolverContradiction {
          cachedComplexity = 100;
          return 100;
        }
        if (test.freeCells().isEmpty) break;
      }
      // Needs backtracking
      if (test.freeCells().isNotEmpty) {
        cachedComplexity = 100;
        return 100;
      }
    }

    cachedSolution = test.cellValues;
    final forceScore = (forceRounds * 10).clamp(0, 90);
    cachedComplexity = (forceScore + ruleDiversity + emptiness).clamp(0, 100);
    return cachedComplexity!;
  }

  /// Step-by-step solving trace, returning each deduction made.
  /// Does not modify the puzzle — works on a clone.
  /// If [timeoutMs] is provided, stops after that many milliseconds.
  List<SolveStep> solveExplained({int? timeoutMs}) {
    final steps = <SolveStep>[];
    final test = clone();
    final stopwatch = timeoutMs != null ? (Stopwatch()..start()) : null;
    bool timedOut() =>
        stopwatch != null && stopwatch.elapsedMilliseconds > timeoutMs!;

    // Propagation phase
    while (true) {
      if (timedOut()) return [];
      final move = test.apply();
      if (move == null) break;
      if (move.isImpossible != null) break;
      test.setValue(move.idx, move.value);
      steps.add(
        SolveStep(
          cellIdx: move.idx,
          value: move.value,
          constraint: move.givenBy.serialize(),
          method: SolveMethod.propagation,
        ),
      );
      if (test.complete) {
        return steps;
      }
    }

    // Force + propagation loop
    for (int round = 0; round < 200; round++) {
      if (timedOut()) return [];
      // Force one cell
      final beforeForce = test.freeCells().map((e) => e.$2).toSet();
      try {
        if (!test.applyWithForce(stopAfterFirst: true)) break;
      } on SolverContradiction {
        break;
      }
      // Find which cell was forced
      final afterForce = test.freeCells().map((e) => e.$2).toSet();
      final forced = beforeForce.difference(afterForce);
      for (final idx in forced) {
        steps.add(
          SolveStep(
            cellIdx: idx,
            value: test.cellValues[idx],
            constraint: '',
            method: SolveMethod.force,
          ),
        );
      }
      if (test.complete) {
        return steps;
      }

      // Propagate after force
      while (true) {
        if (timedOut()) return [];
        final move = test.apply();
        if (move == null) break;
        if (move.isImpossible != null) break;
        test.setValue(move.idx, move.value);
        steps.add(
          SolveStep(
            cellIdx: move.idx,
            value: move.value,
            constraint: move.givenBy.serialize(),
            method: SolveMethod.propagation,
          ),
        );
        if (test.complete) {
          return steps;
        }
      }
    }

    return steps;
  }

  /// Unified solving: propagation + force loop.
  /// Returns true if fully solved.
  bool solve({int maxSteps = 20}) {
    try {
      applyConstraintsPropagation();
    } on SolverContradiction {
      return false;
    }
    if (freeCells().isEmpty) {
      return complete && check(saveResult: false).isEmpty;
    }
    for (int step = 0; step < maxSteps; step++) {
      try {
        final forceChanged = applyWithForce();
        if (freeCells().isEmpty) {
          return complete && check(saveResult: false).isEmpty;
        }
        final propChanges = applyConstraintsPropagation();
        if (freeCells().isEmpty) {
          return complete && check(saveResult: false).isEmpty;
        }
        if (!forceChanged && propChanges == 0) break;
      } on SolverContradiction {
        return false;
      }
    }
    return freeCells().isEmpty && complete && check(saveResult: false).isEmpty;
  }

  /// Full solver: propagation + force + MRV backtracking.
  /// Returns (solved puzzle or null, steps).
  (Puzzle?, int) solveWithBacktracking({int maxSteps = 100000, int level = 0}) {
    final st = clone();
    try {
      final solved = st.solve();
      if (solved && st.complete) return (st, 0);
    } on SolverContradiction {
      return (null, 0);
    }
    if (!st.isPossible()) {
      // Force left state corrupted, retry with propagation only
      final st2 = clone();
      try {
        st2.applyConstraintsPropagation();
      } on SolverContradiction {
        return (null, 0);
      }
      if (st2.freeCells().isEmpty && st2.complete) return (st2, 0);
      return _backtrack(st2, maxSteps, level);
    }
    return _backtrack(st, maxSteps, level);
  }

  (Puzzle?, int) _backtrack(Puzzle st, int maxSteps, int level) {
    int steps = 0;
    while (steps <= maxSteps) {
      if (st.freeCells().isEmpty &&
          st.complete &&
          st.check(saveResult: false).isEmpty) {
        return (st, steps);
      }
      steps++;
      // MRV heuristic: pick cell with fewest options
      final free = st.freeCells();
      if (free.isEmpty) return (null, steps);
      free.sort((a, b) => a.$1.options.length.compareTo(b.$1.options.length));
      final (cell, idx) = free.first;
      if (cell.options.isEmpty) return (null, steps);
      for (final option in List<int>.from(cell.options)) {
        final clone = st.clone();
        clone.cells[idx].setForSolver(option);
        final (subSt, subSteps) = clone.solveWithBacktracking(
          maxSteps: maxSteps - steps,
          level: level + 1,
        );
        steps += subSteps;
        if (subSt != null) return (subSt, steps);
        st.cells[idx].options.remove(option);
        if (st.cells[idx].options.isEmpty) return (null, steps);
      }
    }
    return (null, steps);
  }

  /// Count distinct solutions (up to [maxSolutions]).
  int countSolutions({int maxSolutions = 2}) {
    final solutions = <List<int>>[];
    final test = clone();
    for (int i = 0; i < maxSolutions; i++) {
      final (sol, _) = test.solveWithBacktracking();
      if (sol == null) break;
      solutions.add(sol.cellValues);
      // Exclude this solution and try again
      test.constraints.add(OtherSolutionConstraint(sol.cellValues));
      // Reset cells to re-solve from scratch
      for (final cell in test.cells) {
        if (!cell.readonly) {
          cell.value = 0;
          cell.options = cell.domain.toList();
        }
      }
      test._invalidateCaches();
    }
    return solutions.length;
  }

  /// Remove constraints that don't affect the number of solutions.
  /// Iterates from last to first; if removing a constraint keeps
  /// the same solution count, the constraint is useless.
  void removeUselessRules() {
    final initialCount = countSolutions();
    int i = constraints.length;
    while (i > 0) {
      i--;
      if (constraints[i] is HelpText) continue;
      final removed = constraints.removeAt(i);
      final newCount = countSolutions();
      if (newCount != initialCount) {
        // Constraint was needed, put it back
        constraints.insert(i, removed);
      }
    }
  }

  /// Export puzzle to the v2 line format.
  /// When [compute] is false, skip complexity and solution computation.
  String lineExport({bool compute = true}) {
    final domainStr = domain.map((v) => v.toString()).join('');
    final valuesStr = cellValues.map((v) => v.toString()).join('');
    final constraintsStr = constraints
        .where((c) => c is! HelpText)
        .map((c) => c.serialize())
        .join(';');
    final complexity = compute ? computeComplexity() : 0;
    final sol = cachedSolution;
    final solutionStr = sol != null ? '1:${sol.join('')}' : '0:0';
    return 'v2_${domainStr}_${width}x${height}_${valuesStr}_${constraintsStr}_${solutionStr}_$complexity';
  }
}
