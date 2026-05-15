import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/registry.dart'
    as complicities_registry;
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// Outcome of [Puzzle.simplify]. Mirrors the `(success, level, count)`
/// trio the easing loop needs to decide whether to emit or drop, plus
/// the puzzle's solve trace **at the final state** so the caller can
/// reuse it (e.g. for `sortConstraintsByDifficulty`) instead of paying
/// for an extra `solveExplained` round.
class SimplifyResult {
  /// Number of constraints accepted by the surgical loop.
  final int additionsCount;

  /// Level the puzzle classifies at after all accepted additions
  /// (== input level if nothing was accepted).
  final PuzzleLevel finalLevel;

  /// True iff [finalLevel] is at or below the requested target.
  final bool reachedTarget;

  /// Solve trace for the puzzle in its final state — populated even
  /// when [additionsCount] is 0, so callers don't need to branch on
  /// "did simplify actually run something?".
  final List<SolveStep> finalSteps;

  const SimplifyResult({
    required this.additionsCount,
    required this.finalLevel,
    required this.reachedTarget,
    required this.finalSteps,
  });
}

/// A solve step is "too hard" for [target] iff its presence forces the
/// classifier cascade above [target]. Used by [Puzzle.simplify] to pick
/// the cell the next surgical addition should focus on.
bool _isStepTooHardFor(SolveStep step, PuzzleLevel target) {
  switch (target) {
    case PuzzleLevel.beginner:
      // beginner: forceMoves == 0, maxComplCx == 0, maxPropCx < 3.
      if (step.method == SolveMethod.force) return true;
      if (step.isComplicity) return true;
      return step.complexity >= 3;
    case PuzzleLevel.player:
      // player: forceMoves == 0, maxComplCx == 0; propCx unbounded.
      if (step.method == SolveMethod.force) return true;
      return step.isComplicity;
    case PuzzleLevel.advanced:
      // advanced: forceMoves == 0, 0 < maxComplCx < 4.
      if (step.method == SolveMethod.force) return true;
      return step.isComplicity && step.complexity >= 4;
    case PuzzleLevel.strong:
      // strong: forceMoves == 0. Complicities allowed regardless of cplx.
      return step.method == SolveMethod.force;
    case PuzzleLevel.expert:
      // expert: 1 force step allowed with depth <= 5. Per-step we only
      // flag depth > 5; the count side of the rule isn't per-step.
      return step.method == SolveMethod.force && step.forceDepth > 5;
    case PuzzleLevel.mad:
    case PuzzleLevel.overfilledEasy:
    case PuzzleLevel.overfilled:
    case PuzzleLevel.undetermined:
      return false;
  }
}

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
  // Player-effort tier of this propagation deduction (0..5). Mirrors
  // `Move.complexity`. Always 0 for force steps.
  final int complexity;
  // True when the propagation step was issued by a `Complicity` rather
  // than an individual `Constraint`. Always false for force steps.
  final bool isComplicity;

  const SolveStep({
    required this.cellIdx,
    required this.value,
    required this.constraint,
    required this.method,
    this.forceDepth = 0,
    this.complexity = 0,
    this.isComplicity = false,
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
  // Mutable backing list. Touched only via the helpers below; external
  // code reads through the unmodifiable view exposed as `constraints`.
  // Centralising mutations lets us maintain invariants (LetterGroup
  // aggregation, complicity cache) automatically on every add/remove.
  final List<Constraint> _constraints = [];
  late final List<Constraint> constraints = UnmodifiableListView(_constraints);
  // Lazy cross-constraint deductions cache. Recomputed on demand the
  // first time after any constraint mutation; tried only after all
  // constraints are stuck in the propagation loop.
  List<Complicity>? _complicitiesCache;
  List<Complicity> get complicities {
    return _complicitiesCache ??= [
      for (final c in complicities_registry.allComplicities())
        if (c.isPresent(this)) c,
    ];
  }

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
      // Legacy `TX:*` (HelpText) entries from the deprecated tutorial
      // collection are silently dropped — they were pedagogical
      // markdown references with no effect on solving. Old custom
      // playlists or imported lines may still carry them.
      if (slug == 'TX') continue;
      final params = constraintAttr.length > 1 ? constraintAttr[1] : '';
      final c = createConstraint(slug, params);
      if (c != null) addConstraint(c);
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
  }

  /// Add a constraint to the puzzle. Goes through the central helper so
  /// every code path benefits from LetterGroup aggregation (`LT:<letter>`
  /// pairs sharing the same letter merge into a single N-cell group)
  /// and from the complicity-cache invalidation. The aggregation must
  /// happen on every add — not just at parse time — otherwise the
  /// generator can validate two `LT:D` pairs against their local
  /// connectivity and miss the combined "all four cells in one group"
  /// invariant that the constructor enforces after deserialisation.
  void addConstraint(Constraint c) {
    if (c is LetterGroup) {
      final existing = _constraints.firstWhereOrNull(
        (other) => other is LetterGroup && other.letter == c.letter,
      );
      if (existing != null) {
        final group = existing as LetterGroup;
        for (final idx in c.indices) {
          if (!group.indices.contains(idx)) group.indices.add(idx);
        }
        _complicitiesCache = null;
        return;
      }
    }
    _constraints.add(c);
    _complicitiesCache = null;
  }

  void addAllConstraints(Iterable<Constraint> cs) {
    for (final c in cs) {
      addConstraint(c);
    }
  }

  /// Add a constraint at the **front** of the list so `apply` consults
  /// it before any pre-existing constraint. Used by `simplify` to let
  /// a low-cplx candidate override the cell moves of a dominant
  /// high-cplx constraint already in the puzzle (e.g. a required SH).
  ///
  /// Honours the same LetterGroup aggregation contract as
  /// [addConstraint]: prepending a `LetterGroup` whose letter already
  /// has a constraint in the list merges their indices and moves the
  /// (now combined) entry to the front. This keeps the
  /// "one LT per letter" invariant the constraint construction logic
  /// expects, even under the front-insertion path.
  void prependConstraint(Constraint c) {
    if (c is LetterGroup) {
      final existingIdx = _constraints.indexWhere(
        (other) => other is LetterGroup && other.letter == c.letter,
      );
      if (existingIdx >= 0) {
        final existing = _constraints[existingIdx] as LetterGroup;
        for (final idx in c.indices) {
          if (!existing.indices.contains(idx)) existing.indices.add(idx);
        }
        // Move the merged entry to position 0. `removeAt` shifts the
        // remaining entries left so the subsequent `insert(0, …)`
        // lands in the same slot regardless of `existingIdx`.
        _constraints.removeAt(existingIdx);
        _constraints.insert(0, existing);
        _complicitiesCache = null;
        return;
      }
    }
    _constraints.insert(0, c);
    _complicitiesCache = null;
  }

  void removeConstraint(Constraint c) {
    if (_constraints.remove(c)) {
      _complicitiesCache = null;
    }
  }

  Constraint removeConstraintAt(int index) {
    final removed = _constraints.removeAt(index);
    _complicitiesCache = null;
    return removed;
  }

  /// Insert without aggregation. Used by `removeUselessRules` to put
  /// back a constraint that was tentatively removed; aggregation is
  /// already settled at that point.
  void insertConstraintAt(int index, Constraint c) {
    _constraints.insert(index, c);
    _complicitiesCache = null;
  }

  /// Reorder the in-memory constraint list by the **minimum** move
  /// complexity each constraint contributed in [steps] (ascending —
  /// easiest first). Ties broken lexicographically on `serialize()`
  /// for stability.
  ///
  /// Rationale for **min** rather than max: a constraint useful as
  /// a starting hint (one cplx=0 move on the initial state) belongs
  /// at the front even if its other moves later in the trace are
  /// expensive. The player gauges difficulty from the most accessible
  /// deduction, not the average.
  ///
  /// Steps with `constraint == ''` (force) and steps from
  /// `Complicity` instances credit no specific constraint, so they
  /// don't influence ranking. Constraints with **zero** contributing
  /// prop steps in [steps] (claimed elsewhere or just inert here) are
  /// pushed to the end via an `intMaxValue` sentinel rank.
  ///
  /// **Does not solve** — [steps] must be supplied by the caller,
  /// typically the `solveExplained` trace it already computed for
  /// classification. Side effects:
  ///   - `Puzzle.apply()` iterates `constraints` in order, so simpler
  ///     deductions surface first in the hint system and in the
  ///     `solveExplained` trace of subsequent calls.
  ///   - `lineExport` serialises constraints in list order, so the
  ///     persisted line carries the easier-first order on disk too.
  ///
  /// Used by the generator post-loop and by maintenance tools. Never
  /// call from the player runtime — the line on disk is already
  /// sorted from the production-side rewrite.
  void sortConstraintsByDifficulty(List<SolveStep> steps) {
    // Accumulate the smallest contributed cplx per serialized
    // constraint. Force steps carry an empty `constraint` field, so
    // they are naturally skipped. Complicity steps carry the
    // complicity's own serialize(); since no entry in
    // `_constraints` matches that, those are also harmless to scan
    // through.
    final minCplx = <String, int>{};
    for (final s in steps) {
      if (s.constraint.isEmpty) continue;
      final prev = minCplx[s.constraint];
      if (prev == null || s.complexity < prev) {
        minCplx[s.constraint] = s.complexity;
      }
    }

    _constraints.sort((a, b) {
      final ra = minCplx[a.serialize()] ?? _noContribRank;
      final rb = minCplx[b.serialize()] ?? _noContribRank;
      if (ra != rb) return ra.compareTo(rb);
      return a.serialize().compareTo(b.serialize());
    });
    _complicitiesCache = null;
  }

  /// Sentinel used by [sortConstraintsByDifficulty] for constraints
  /// that contributed no step to the input trace. Picked above any
  /// realistic per-move `complexity` (0..5 in practice) so contributors
  /// always sort before non-contributors.
  static const int _noContribRank = 1 << 30;

  void replaceConstraints(Iterable<Constraint> cs) {
    _constraints.clear();
    _complicitiesCache = null;
    addAllConstraints(cs);
  }

  /// Pin the complicity list to empty. Used by hypothetical solver
  /// passes (SY×FM complicity, measure_complicities) that must not
  /// recurse through complicities while exploring branches; without
  /// this they would loop on the very complicity that called them.
  void disableComplicities() {
    _complicitiesCache = const [];
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
    // Second level: try complicities once individual constraints are
    // exhausted. The next iteration of the outer propagation loop will
    // call apply() again and constraints get another chance with the
    // freshly placed cell.
    for (var c in complicities) {
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
    // findAMove) leaks state into the original puzzle. The cloned
    // LetterGroup instances are pre-aggregated, so going through
    // `addConstraint` is a no-op for the merge step but still invalidates
    // the complicity cache so it gets recomputed against the clone's
    // own constraint list on first access.
    p.replaceConstraints(constraints.map(_cloneConstraint));
    return p;
  }

  static Constraint _cloneConstraint(Constraint c) {
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
  /// - **Effort** (0-90): sum of per-move weights along the deduction chain.
  ///   A propagation move contributes `Move.complexity` (0-5 tier; see
  ///   docs/dev/complexity.md for the per-deduction inventory). A force
  ///   move contributes `5 + 5 * forceDepth`, matching the pre-existing
  ///   `(1 + depth) * 5` scaling so old scores stay in the same band. 100
  ///   if the puzzle isn't deductively solvable at all.
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

    // Count distinct rule types.
    final ruleTypes = constraints
        .map((c) => c.serialize().split(':').first)
        .where((s) => s.isNotEmpty)
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

    // Effort: run findAMove to fixpoint, accumulating each move's player-
    // effort weight. Propagation moves carry a 0-5 weight set by the
    // constraint's apply(); force moves carry `5 + 5 * forceDepth`. Any
    // contradiction → puzzle isn't deductively solvable → complexity 100.
    final test = clone();
    int effort = 0;
    for (int step = 0; step < 1000; step++) {
      final m = test.findAMove(checkErrors: false);
      if (m == null) break;
      if (m.isImpossible != null) {
        cachedComplexity = 100;
        return 100;
      }
      test.setValue(m.idx, m.value);
      if (m.isForce) {
        effort += 5 + 5 * m.forceDepth;
      } else {
        effort += m.complexity;
      }
      if (test.complete) break;
    }
    if (test.freeCells().isNotEmpty) {
      cachedComplexity = 100;
      return 100;
    }

    cachedSolution = test.cellValues;
    final forceScore = effort.clamp(0, 90);
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
          complexity: m.isForce ? 0 : m.complexity,
          isComplicity: !m.isForce && m.givenBy is Complicity,
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
      final removed = removeConstraintAt(i);
      if (!isDeductivelyUnique()) {
        // Constraint was needed, put it back. We bypass aggregation
        // here because the constraint set is already in the post-
        // aggregation shape — re-aggregating would be a no-op but
        // would lose the original index.
        insertConstraintAt(i, removed);
      }
    }
  }

  /// Attempt to lower this puzzle's classified difficulty toward
  /// [targetLevel] by adding constraints. The strategy is
  /// "indispensable-by-exploration":
  ///
  ///   1. Trace this puzzle via `solveExplained` and classify. If the
  ///      level is already at or below [targetLevel], stop.
  ///   2. On a **clone**, naively expand: add candidates one by one
  ///      until the clone's classified level drops by at least one
  ///      tier. The candidate that triggered the drop is marked
  ///      **indispensable** — every candidate added before it served
  ///      as context (a "potential unblocker") but is discarded.
  ///   3. Graft only the indispensable onto the original (`this`).
  ///   4. Reclassify the original. Whether or not its level actually
  ///      dropped (the indispensable may have needed clone-context to
  ///      fire alone), loop back to step 1. The next pass starts from
  ///      the slightly-improved original — additional indispensables
  ///      accumulate until the target is reached or progress stalls.
  ///
  /// Rationale: the previous full-naive algorithm reached the target
  /// but kept every transitional candidate, padding the constraint
  /// list. By extracting one transition-trigger per pass, the final
  /// set is closer to minimal — the puzzle gains only the constraints
  /// that actually moved the cascade needle, not the context
  /// scaffolding that happened to come along.
  ///
  /// Candidates are drawn from `generateAllParameters` over
  /// [allowedSlugs] (default: every registered slug), filtered to
  /// those compatible with this puzzle's unique solution and not
  /// already present. Stable serialize-order so the same puzzle yields
  /// the same simplification trace.
  ///
  /// Mutates `this` by appending each accepted indispensable. Cell
  /// values (including readonly) are never modified.
  /// `removeUselessRules` is **not** invoked — calling it would strip
  /// the very constraints we just added.
  ///
  /// [onStep] is called after each grafted indispensable with the
  /// constraint, the new classified level on the original, and the
  /// cell of the first too-hard step that motivated this pass.
  SimplifyResult simplify({
    required PuzzleLevel targetLevel,
    int maxSteps = 50,
    Duration? maxTime,
    Set<String>? allowedSlugs,
    bool Function()? shouldStop,
    void Function(Constraint added, PuzzleLevel newLevel, int targetCell)?
    onStep,
  }) {
    // Watchdogs: per-call wall-clock budget plus the worker-level
    // cancellation signal. Checked between candidate tests and between
    // outer passes so the call can be aborted mid-exploration without
    // burning the rest of the budget on a doomed pass.
    final sw = maxTime != null ? (Stopwatch()..start()) : null;
    bool timedOut() {
      if (shouldStop?.call() == true) return true;
      if (sw != null && maxTime != null && sw.elapsed > maxTime) return true;
      return false;
    }

    // Compute the unique solution. Candidates that don't verify against
    // it would make the puzzle unsolvable, so we filter them out.
    final solved = clone();
    if (!solved.solve()) {
      return SimplifyResult(
        additionsCount: 0,
        finalLevel: PuzzleLevel.undetermined,
        reachedTarget: false,
        finalSteps: const [],
      );
    }

    final slugs = allowedSlugs ?? constraintSlugs.toSet();
    final existing = constraints.map((c) => c.serialize()).toSet();
    final readonlyIndices = <int>{
      for (final (i, c) in cells.indexed)
        if (c.readonly) i,
    };
    final candidates = <Constraint>[];
    for (final slug in slugs) {
      final params = generateAllParameters(
        slug,
        width,
        height,
        domain,
        slug == 'DF' ? readonlyIndices : null,
      );
      if (params == null) continue;
      for (final p in params) {
        final c = createConstraint(slug, p);
        if (c == null) continue;
        if (existing.contains(c.serialize())) continue;
        if (!c.verify(solved)) continue;
        candidates.add(c);
      }
    }
    candidates.sort((a, b) => a.serialize().compareTo(b.serialize()));

    final prefillRatio = cells.where((c) => c.readonly).length / cells.length;
    var currentSteps = solveExplained();
    var currentLevel = _classifyFromSteps(currentSteps, prefillRatio);
    var additions = 0;

    while (additions < maxSteps && candidates.isNotEmpty) {
      if (currentLevel.index <= targetLevel.index) break;
      if (timedOut()) break;

      // Diagnostic anchor for the [onStep] callback: the cell of the
      // first too-hard step in the current trace. Not used for
      // filtering — exploration adds candidates unconditionally and
      // detects the trigger via the level cascade. `-1` means the
      // current level is above target but no individual step is
      // flagged (e.g. target=expert aggregate force count).
      int focusCell = -1;
      for (final s in currentSteps) {
        if (_isStepTooHardFor(s, targetLevel)) {
          focusCell = s.cellIdx;
          break;
        }
      }

      // Exploration phase. Naively expand a clone — add candidates in
      // order without any acceptance criterion — until the clone's
      // classified level strictly drops. The trigger is the
      // indispensable; the preceding additions ride along but are
      // **not** grafted onto the original.
      final exploreClone = clone();
      final explorePool = List<Constraint>.from(candidates);
      Constraint? indispensable;
      int indispensableIdx = -1;
      var exploreLevel = currentLevel;
      for (int i = 0; i < explorePool.length; i++) {
        if (timedOut()) break;
        final c = explorePool[i];
        // Prepend (not append) so `Puzzle.apply()` consults `c` before
        // any pre-existing constraint. Required when the puzzle is
        // dominated by a high-cplx constraint that fires first on
        // every cell it touches (e.g. `--require SH`): appended
        // candidates would be tried last and never override the
        // dominant constraint's moves. `prependConstraint` also
        // preserves the LetterGroup aggregation contract.
        exploreClone.prependConstraint(c);
        final exploreSteps = exploreClone.solveExplained();
        final newLevel = _classifyFromSteps(exploreSteps, prefillRatio);
        if (newLevel.index < exploreLevel.index) {
          // Cascade transition triggered. Even if `newLevel` is still
          // above `targetLevel`, the next outer-loop pass will pick
          // up where this one leaves off.
          indispensable = c;
          indispensableIdx = i;
          break;
        }
      }
      if (indispensable == null) {
        // Even adding every remaining candidate fails to move the
        // cascade — true plateau, no point trying further iterations.
        break;
      }

      // Graft only the indispensable onto the original, same
      // front-insertion semantic as the exploration: the indispensable
      // must be consulted by `apply` before the pre-existing
      // constraints, otherwise its cheaper deduction won't surface
      // when the original constraint can also fire on the same cell.
      prependConstraint(indispensable);
      candidates.removeAt(indispensableIdx);
      currentSteps = solveExplained();
      currentLevel = _classifyFromSteps(currentSteps, prefillRatio);
      additions++;
      onStep?.call(indispensable, currentLevel, focusCell);
    }

    return SimplifyResult(
      additionsCount: additions,
      finalLevel: currentLevel,
      reachedTarget: currentLevel.index <= targetLevel.index,
      finalSteps: currentSteps,
    );
  }

  /// Re-classify a trace against a known prefill ratio. Replays the
  /// trace on a clone to confirm completeness — incomplete traces are
  /// `undetermined`, matching the contract of `classifyTrace`.
  PuzzleLevel _classifyFromSteps(List<SolveStep> steps, double prefillRatio) {
    final replay = clone();
    for (final s in steps) {
      replay.setValue(s.cellIdx, s.value);
    }
    final completed =
        replay.complete && replay.check(saveResult: false).isEmpty;
    return classifyTrace(
      steps: steps,
      prefillRatio: prefillRatio,
      solved: completed,
    );
  }

  /// Return a fresh puzzle equivalent to a 90° clockwise rotation of this
  /// one. Dimensions are swapped, every cell is transposed, and every
  /// constraint is rotated through `Constraint.rotated`. Cell values,
  /// readonly flags and any cached solution are preserved (rotated
  /// alongside the cells), so the returned puzzle is logically equivalent
  /// — same domain, same solutions, same player progress.
  Puzzle rotated() {
    final n = width * height;
    final newWidth = height;
    final newHeight = width;

    final newValues = List<int>.filled(n, 0);
    final newReadonly = List<bool>.filled(n, false);
    for (int origIdx = 0; origIdx < n; origIdx++) {
      final newIdx = rotateIdx90CW(origIdx, width, height);
      newValues[newIdx] = cells[origIdx].value;
      newReadonly[newIdx] = cells[origIdx].readonly;
    }

    // Field 3 of the v2 line is the *initial* prefill: only readonly cells
    // carry their value, the rest is 0. Player progress is restored from
    // the trailing `_p:` field.
    final prefillStr = List.generate(
      n,
      (i) => newReadonly[i] ? newValues[i] : 0,
    ).map((v) => v.toString()).join('');

    final domainStr = domain.map((v) => v.toString()).join('');
    final rotatedConstraintsStr = constraints
        .map((c) => c.rotated(width, height).serialize())
        .join(';');

    String solutionStr = '0:0';
    final sol = cachedSolution;
    if (sol != null && sol.length == n) {
      final rotatedSolution = List<int>.filled(n, 0);
      for (int origIdx = 0; origIdx < n; origIdx++) {
        rotatedSolution[rotateIdx90CW(origIdx, width, height)] = sol[origIdx];
      }
      solutionStr = '1:${rotatedSolution.map((v) => v.toString()).join('')}';
    }

    final complexityStr = (cachedComplexity ?? 0).toString();
    var line =
        'v2_${domainStr}_${newWidth}x$newHeight'
        '_${prefillStr}_${rotatedConstraintsStr}_${solutionStr}_$complexityStr';

    final hasProgress = List.generate(
      n,
      (i) => !newReadonly[i] && newValues[i] != 0,
    ).any((x) => x);
    if (hasProgress) {
      final playStr = newValues.map((v) => v.toString()).join('');
      line = '${line}_p:$playStr';
    }

    return Puzzle(line);
  }

  /// Export puzzle to the v2 line format.
  /// When [compute] is false, skip complexity and solution computation.
  String lineExport({bool compute = true}) {
    final domainStr = domain.map((v) => v.toString()).join('');
    final valuesStr = cellValues.map((v) => v.toString()).join('');
    final constraintsStr = constraints.map((c) => c.serialize()).join(';');
    final complexity = compute ? computeComplexity() : 0;
    final sol = cachedSolution;
    final solutionStr = sol != null ? '1:${sol.join('')}' : '0:0';
    return 'v2_${domainStr}_${width}x${height}_${valuesStr}_${constraintsStr}_${solutionStr}_$complexity';
  }
}
