import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint_registry.dart';
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
  int duration = 0;
  Stopwatch timer = Stopwatch();

  @override
  String toString() {
    // 2025-08-23T22:59:42 8s - 0f 3x3_000001020_GS:5.1;PA:6.top;PA:0.right;PA:2.left;FM:222_1:212121122
    return "${(timer.elapsedMilliseconds / 1000).round()}s - ${failures}f";
  }

  void begin() {
    timer.start();
    failures = 0;
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
  List<Cell> cells = [];
  List<Constraint> constraints = [];
  int? cachedComplexity;
  List<int>? cachedSolution;

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
  }

  void restart() {
    for (var cell in cells) {
      if (!cell.readonly) {
        cell.value = 0;
        cell.options = cell.domain;
      }
    }
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

  List<List<int>> getGroups() {
    final List<Set<int>> sameValues = [
      for (var idx in Iterable.generate(cellValues.length))
        getNeighborsSameValue(idx).toSet(),
    ];
    final Map<int, Set<int>> groups = {};
    var groupCount = 0;
    for (var others in sameValues) {
      if (others.isEmpty) continue;
      final existing = {
        for (var item in groups.entries)
          if (others.intersection(item.value).isNotEmpty) item.key: item.value,
      };
      if (existing.isEmpty) {
        groupCount += 1;
        groups[groupCount] = others;
        continue;
      }
      // Merge the groups
      final newIdx = existing.keys.toList()[0];
      var newGrp = existing[newIdx]!.union(others);
      final indicesRemove = existing.keys.where((i) => i != newIdx);
      for (var indexRemove in indicesRemove) {
        final removeGrp = existing[indexRemove];
        if (removeGrp != null) {
          groups.remove(indexRemove);
          newGrp = newGrp.union(removeGrp);
        }
      }
      groups[newIdx] = groups[newIdx]!.union(newGrp);
    }
    final List<List<int>> result = groups.values.map((grp) {
      final indices = grp.toList();
      indices.sort();
      return indices;
    }).toList();
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

  List<int> getNeighborsSameValue(int idx) {
    final myValue = cellValues[idx];
    if (myValue == 0) return [];
    final List<int> result = [idx];
    result.addAll(getNeighbors(idx).where((e) => cellValues[e] == myValue));
    return result;
  }

  List<int> getNeighborsSameValueOrEmpty(int idx, int myValue) {
    final List<int> result = [idx];
    result.addAll(
      getNeighbors(
        idx,
      ).where((e) => cellValues[e] == myValue || cellValues[e] == 0),
    );
    return result;
  }

  bool setValue(int idx, int value) {
    final cell = cells[idx];
    return cell.setValue(value);
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

  Move? findAMove() {
    // First find broken constraints
    final hasErrors = check(saveResult: false);
    if (hasErrors.isNotEmpty) {
      final firstError = hasErrors.first;
      final errorMove = firstError.apply(this);
      if (errorMove != null) {
        return errorMove;
      }
    }
    // Then try by directly applying the constraint
    final easyMove = apply();
    if (easyMove != null) return easyMove;
    // Nothing was found, we will now try on a cloned puzzle
    // to randomly set a cell's value and see if that leads to
    // an impossible to solve puzzle. It would mean that this
    // value is forbidden.
    final clone = this.clone();
    for (var freeCell in clone.cells.indexed.where(
      (entry) => entry.$2.value == 0,
    )) {
      for (var value in clone.domain) {
        clone.setValue(freeCell.$1, value);
        Move? result = clone.applyAll();
        // Check if the puzzle became unsolvable (constraint violation)
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
    p.constraints = constraints.toList();
    return p;
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

  /// For each free cell, try each value, clone + propagate with autoCheck.
  /// If a value leads to contradiction, eliminate it.
  /// Returns true if any progress was made.
  bool applyWithForce() {
    bool changed = false;
    final free = freeCells();
    for (final (cell, idx) in free) {
      if (cell.options.length <= 1) continue;
      for (final value in List<int>.from(cell.options)) {
        final testPu = clone();
        testPu.cells[idx].setForSolver(value);
        try {
          testPu.applyConstraintsPropagation(autoCheck: true);
        } on SolverContradiction {
          // This value leads to contradiction, remove it
          cell.options.remove(value);
          if (cell.options.length == 1) {
            cell.setForSolver(cell.options[0]);
            changed = true;
          } else if (cell.options.isEmpty) {
            throw SolverContradiction('Cell $idx has no options left');
          }
        }
      }
    }
    return changed;
  }

  /// Like [applyWithForce] but stops after determining a single cell.
  /// Returns true if one cell was determined by force.
  bool applyWithForceSingle() {
    final free = freeCells();
    for (final (cell, idx) in free) {
      if (cell.options.length <= 1) continue;
      for (final value in List<int>.from(cell.options)) {
        final testPu = clone();
        testPu.cells[idx].setForSolver(value);
        try {
          testPu.applyConstraintsPropagation(autoCheck: true);
        } on SolverContradiction {
          cell.options.remove(value);
          if (cell.options.length == 1) {
            cell.setForSolver(cell.options[0]);
            return true;
          } else if (cell.options.isEmpty) {
            throw SolverContradiction('Cell $idx has no options left');
          }
        }
      }
    }
    return false;
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
          final forced = test.applyWithForceSingle();
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
    Stopwatch? stopwatch;
    final timeout = timeoutMs;
    if (timeout != null) {
      stopwatch = Stopwatch()..start();
    }

    // Propagation phase
    while (true) {
      if (timeout != null &&
          stopwatch != null &&
          stopwatch.elapsedMilliseconds > timeout) {
        return [];
      }
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
      if (timeout != null &&
          stopwatch != null &&
          stopwatch.elapsedMilliseconds > timeout) {
        return [];
      }
      // Force one cell
      final beforeForce = test.freeCells().map((e) => e.$2).toSet();
      try {
        if (!test.applyWithForceSingle()) break;
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
        if (timeout != null &&
            stopwatch != null &&
            stopwatch.elapsedMilliseconds > timeout) {
          return [];
        }
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

  List<List<int>> toVirtualGroups() {
    final idxToExplore = cellValues.indexed.toList();
    final Map<int, List<int>> explored = {};
    final Map<int, Map<int, List<int>>> groupsPerValuePerCell = {};
    while (idxToExplore.isNotEmpty) {
      final exploring = idxToExplore.removeAt(0);
      final exploreIdx = exploring.$1;
      final value = exploring.$2;
      final others = explored[value] ?? [];
      if (others.contains(exploreIdx)) {
        continue;
      }
      others.add(exploreIdx);
      explored[value] = others;
      final sameOrEmpty = getNeighborsSameValueOrEmpty(exploreIdx, value);
      if (groupsPerValuePerCell[value] == null) {
        groupsPerValuePerCell[value] = {};
      }
      if (groupsPerValuePerCell[value]![exploreIdx] == null) {
        groupsPerValuePerCell[value]![exploreIdx] = [];
      }
      groupsPerValuePerCell[value]![exploreIdx]!.addAll(sameOrEmpty);
      for (var neighbor in sameOrEmpty) {
        if (neighbor != exploreIdx) {
          idxToExplore.add((neighbor, value));
        }
      }
    } // while
    final Map<int, List<Set<int>>> setsPerValue = {};
    for (var valueEntry in groupsPerValuePerCell.entries) {
      final value = valueEntry.key;
      final valueData = valueEntry.value;
      for (var dataEntry in valueData.entries) {
        final idx = dataEntry.key;
        final newGroup = dataEntry.value.toSet();
        if (setsPerValue[value] == null) {
          setsPerValue[value] = [];
        }
        for (var existing in findAndPop(setsPerValue[value]!, idx)) {
          newGroup.addAll(existing);
        }
        setsPerValue[value]!.add(newGroup);
      }
    }
    return setsPerValue.values.flattenedToList
        .map((grp) => grp.toList())
        .toList();
  }
}

List<Set<int>> findAndPop(List<Set<int>> setlist, int value) {
  /*
    Pops the sets in setlist that contains value.
    */
  final Set<int> indices = {};
  for (var setEntry in setlist.indexed) {
    final idx = setEntry.$1;
    final candidate = setEntry.$2;
    if (candidate.contains(value)) {
      indices.add(idx);
    }
  }
  final List<Set<int>> result = [];
  for (var idx in indices.sorted((a, b) => a - b).reversed) {
    result.add(setlist.removeAt(idx));
  }
  return result;
}
