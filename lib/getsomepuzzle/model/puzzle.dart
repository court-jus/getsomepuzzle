import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/helptext.dart';

/// Method used to determine a cell value during solving.
enum SolveMethod { propagation, force }

/// One step in the step-by-step solving trace.
class SolveStep {
  final int cellIdx;
  final int value;
  final String constraint;
  final SolveMethod method;
  // For a force step, length of the propagation chain that exposed the
  // contradiction. Same semantic as `Move.forceDepth`. 0 for propagation.
  final int forceDepth;

  const SolveStep({
    required this.cellIdx,
    required this.value,
    required this.constraint,
    required this.method,
    this.forceDepth = 0,
  });

  @override
  String toString() {
    return '${method.name}: cell $cellIdx = $value${constraint.isNotEmpty ? ' by $constraint' : ''}${method == SolveMethod.force ? ' (depth=$forceDepth)' : ''}';
  }
}

class Stats {
  int failures = 0;
  int hints = 0;
  int duration = 0;
  Stopwatch timer = Stopwatch();

  // Cell-modification analytics. Recorded per user-driven cell edit (taps
  // and drags), not on hint-driven reveals. Useful for richer level-of-skill
  // regression: the in-play hesitation pattern is a feature that the bare
  // `duration` does not capture.
  /// Total user-driven cell edits during the play. ≥ cells in a clean run,
  /// higher when the player changes their mind.
  int cellEdits = 0;

  /// Time (ms) from puzzle start to the very first cell edit. Captures the
  /// "reading the constraints" phase, which scales with constraint count
  /// rather than grid size.
  int firstClickMs = 0;

  /// Longest gap (ms) between two consecutive cell edits. Captures
  /// "stuck moments" within the play that the total duration averages out.
  int longestGapMs = 0;
  int _lastEditMs = 0;

  @override
  String toString() {
    // 2025-08-23T22:59:42 8s - 0f 3x3_000001020_GS:5.1;PA:6.top;PA:0.right;PA:2.left;FM:222_1:212121122
    return "${(timer.elapsedMilliseconds / 1000).round()}s - ${failures}f - ${hints}h";
  }

  void begin() {
    timer.start();
    failures = 0;
    hints = 0;
    cellEdits = 0;
    firstClickMs = 0;
    longestGapMs = 0;
    _lastEditMs = 0;
  }

  /// Record a single user-driven cell edit. Only call from real interactions
  /// (tap, drag) — not from hint-revealed cell fills, which are counted under
  /// `hints` instead.
  void recordCellEdit() {
    final now = timer.elapsedMilliseconds;
    cellEdits++;
    if (firstClickMs == 0) {
      firstClickMs = now;
    } else {
      final gap = now - _lastEditMs;
      if (gap > longestGapMs) longestGapMs = gap;
    }
    _lastEditMs = now;
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

  /// True when the line representation carried a saved play-state field
  /// (trailing `_p:<values>`) and that state has been applied to the
  /// non-readonly cells. Consumers (the game model) read it once on open
  /// to surface a "progress restored" message.
  bool hasRestoredProgress = false;

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
    // Optional trailing play-state field "p:<cellvalues>" (length must
    // match the grid). Values for readonly cells are ignored — those
    // already carry the puzzle's initial state. Non-zero values for the
    // remaining cells are applied so the player resumes where they left
    // off. Backward compatible: missing field = no saved progress.
    for (var i = 6; i < attributesStr.length; i++) {
      final field = attributesStr[i];
      if (!field.startsWith('p:')) continue;
      final values = field.substring(2);
      if (values.length != cells.length) break;
      for (int j = 0; j < cells.length; j++) {
        if (cells[j].readonly) continue;
        final v = int.tryParse(values[j]);
        if (v != null && v != 0) cells[j].setValue(v);
      }
      hasRestoredProgress = true;
      break;
    }
    _aggregateLetterGroups();
  }

  /// Build a line representation that carries the player's current cell
  /// values as a trailing `_p:<values>` field. The leading fields
  /// (initial readonly cells, constraints, solution, complexity) are
  /// preserved verbatim from the original [lineRepresentation]; any
  /// existing play-state suffix is replaced.
  String lineWithPlayState() {
    final parts = lineRepresentation.split('_');
    parts.removeWhere((p) => p.startsWith('p:'));
    final playStr = cellValues.map((v) => v.toString()).join('');
    parts.add('p:$playStr');
    return parts.join('_');
  }

  /// Merge `LT:<letter>....` constraints sharing the same letter into a
  /// single `LetterGroup` whose `indices` list every cell of that letter.
  /// Generation produces pairs (one `LT` per pair of cells sharing a
  /// letter), but display and deduction logic are simpler — and stronger —
  /// when each letter is represented by a single constraint with N cells.
  void _aggregateLetterGroups() {
    final byLetter = <String, LetterGroup>{};
    final newConstraints = <Constraint>[];
    for (final c in constraints) {
      if (c is! LetterGroup) {
        newConstraints.add(c);
        continue;
      }
      final existing = byLetter[c.letter];
      if (existing == null) {
        byLetter[c.letter] = c;
        newConstraints.add(c);
      } else {
        for (final idx in c.indices) {
          if (!existing.indices.contains(idx)) existing.indices.add(idx);
        }
      }
    }
    constraints = newConstraints;
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

  /// Try setting each free cell to each domain value on a fresh clone; if a
  /// value leads to contradiction, return the opposite as a forced move.
  ///
  /// Scans every (cell, value) pair and returns the move whose refutation
  /// requires the **shortest propagation chain** (`forceDepth`). The
  /// shallowest contradiction is what a human player can verify in their
  /// head — picking the first one found would often hand the player a
  /// 10-step cascade when a 1-step refutation existed elsewhere on the
  /// grid. Short-circuits as soon as a depth-0 refutation is found (can't
  /// do better).
  Move? _forceOneCell() {
    Move? best;
    int bestDepth = -1;
    for (final (idx, cell) in cells.indexed) {
      if (cell.value != 0) continue;
      for (final value in domain) {
        final clone = this.clone();
        clone.setValue(idx, value);
        final r = clone._propagateCount();
        final opposite = domain.whereNot((v) => v == value).first;

        Move? candidate;
        int depth;

        if (r.failed) {
          // Propagation hit an explicit impossibility. Re-run apply once
          // to recover the responsible constraint for the hint display.
          final diag = clone.apply();
          candidate = Move(
            idx,
            opposite,
            diag?.givenBy ?? clone.constraints.first,
            isForce: true,
            forceDepth: r.moves,
          );
          depth = r.moves;
        } else {
          final errors = clone.check(saveResult: false);
          if (errors.isNotEmpty) {
            candidate = Move(
              idx,
              opposite,
              errors.first,
              isForce: true,
              forceDepth: r.moves,
            );
            depth = r.moves;
          } else {
            // Cascade reached a stuck or complete-and-consistent state.
            // We cannot conclude anything: a complete-and-consistent
            // cascade only proves the value is *possible*, not forced —
            // claiming "the opposite would have failed" is circular,
            // since this routine is itself how we test for refutation.
            continue;
          }
        }

        if (best == null || depth < bestDepth) {
          best = candidate;
          bestDepth = depth;
          if (bestDepth == 0) return best;
        }
      }
    }
    return best;
  }

  /// Like `propagateToFixpoint` but always returns the move count, even
  /// when propagation hits an impossibility. `failed=true` signals the
  /// impossibility branch.
  ({int moves, bool failed}) _propagateCount() {
    int moves = 0;
    while (true) {
      final m = findAMove(checkErrors: false, tryForce: false);
      if (m == null) return (moves: moves, failed: false);
      if (m.isImpossible != null) return (moves: moves, failed: true);
      setValue(m.idx, m.value);
      moves++;
      if (complete) return (moves: moves, failed: false);
    }
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

  /// First filled cell whose value diverges from [cachedSolution], or null
  /// when nothing is wrong (or no solution is stored). Used by the hint
  /// system's "tap 1" to surface a wrong cell without revealing its source.
  int? findFirstWrongCell() {
    final sol = cachedSolution;
    if (sol == null) return null;
    for (int i = 0; i < cells.length; i++) {
      final v = cells[i].value;
      if (v != 0 && v != sol[i]) return i;
    }
    return null;
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
    // findAMove) leaks state into the original puzzle.
    p.constraints = constraints.map(_cloneConstraint).toList();
    return p;
  }

  static Constraint _cloneConstraint(Constraint c) {
    if (c is HelpText) return HelpText(c.text);
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

  /// Compute puzzle complexity on a 0-100 scale.
  ///
  /// Three components:
  /// - **Force effort** (0-90): each forced deduction costs `1 + depth`
  ///   where `depth` is the propagation chain length to refutation. The
  ///   sum is multiplied by 5 and capped at 90. A round with an immediate
  ///   contradiction (depth 0) costs 5; one that requires the player to
  ///   trace 8 cascading steps in their head costs 45. 100 if the puzzle
  ///   isn't deductively solvable at all.
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

    // Force effort: run findAMove to fixpoint, summing (1 + forceDepth)
    // for each forced deduction so deep cascades cost more than shallow
    // refutations. Any contradiction → puzzle isn't deductively solvable
    // → complexity 100.
    final test = clone();
    int forceEffort = 0;
    for (int step = 0; step < 1000; step++) {
      final m = test.findAMove(checkErrors: false);
      if (m == null) break;
      if (m.isImpossible != null) {
        cachedComplexity = 100;
        return 100;
      }
      test.setValue(m.idx, m.value);
      if (m.isForce) forceEffort += 1 + m.forceDepth;
      if (test.complete) break;
    }
    if (test.freeCells().isNotEmpty) {
      cachedComplexity = 100;
      return 100;
    }

    cachedSolution = test.cellValues;
    final forceScore = (forceEffort * 5).clamp(0, 90);
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

    for (int step = 0; step < 1000; step++) {
      if (timedOut()) return [];
      final m = test.findAMove(checkErrors: false);
      if (m == null || m.isImpossible != null) break;
      test.setValue(m.idx, m.value);
      steps.add(
        SolveStep(
          cellIdx: m.idx,
          value: m.value,
          constraint: m.isForce ? '' : m.givenBy.serialize(),
          method: m.isForce ? SolveMethod.force : SolveMethod.propagation,
          forceDepth: m.isForce ? m.forceDepth : 0,
        ),
      );
      if (test.complete) return steps;
    }

    return steps;
  }

  /// Unified solving: loop `findAMove` until stuck, contradiction, or complete.
  /// Returns true if fully solved.
  bool solve({int maxSteps = 200}) {
    for (int i = 0; i < maxSteps; i++) {
      final m = findAMove(checkErrors: false);
      if (m == null || m.isImpossible != null) break;
      setValue(m.idx, m.value);
    }
    return complete && check(saveResult: false).isEmpty;
  }

  /// Validity check used everywhere a puzzle's uniqueness must be confirmed
  /// (generator, polisher, `--check`, `removeUselessRules`).
  ///
  /// Returns `true` iff `solve()` (propagation + force, no backtracking)
  /// reaches the unique completion from the readonly cells. This is the
  /// project-wide convention: any puzzle that can't be deduced this way is
  /// invalid by definition — it would also be unsolvable with the in-game
  /// hint system, which uses the same `solve()` machinery.
  bool isDeductivelyUnique() {
    final test = clone();
    return test.solve();
  }

  /// Remove constraints that aren't required for the puzzle to remain
  /// deductively solvable. Iterates from last to first; if removing a
  /// constraint still leaves `isDeductivelyUnique()` true, that constraint
  /// was redundant for the in-game solver and stays removed.
  void removeUselessRules() {
    if (!isDeductivelyUnique()) return;
    int i = constraints.length;
    while (i > 0) {
      i--;
      if (constraints[i] is HelpText) continue;
      final removed = constraints.removeAt(i);
      if (!isDeductivelyUnique()) {
        // Constraint was needed, put it back.
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
