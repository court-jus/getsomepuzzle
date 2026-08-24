// Shared readonly-easing core for "puzzle recycling" (see
// docs/dev/collection_management.md, "Collection orchestrator and puzzle
// recycling"). Converts a mad puzzle into a lower collection by fixing free
// cells to their solution values and marking them readonly, until the trace
// lands at/below a target level (or progress stalls / the prefill cap is hit).
//
// This is the logic extracted from bin/pilot_readonly.dart so the pilot, the
// landing experiment (bin/experiment_landing.dart) and the future recycling
// step share one source of truth for the subtle parts: candidate selection,
// the exact-integer prefill-cap headroom check, the score-based objective and
// the sort + autoShrinkDomain + lineExport export tail.
//
// The caller owns the [Puzzle] and its unique [solution]: parse the line,
// solve a clone for the cell values, then call [easePuzzle]. The puzzle is
// mutated in place (readonly cells are added); the returned [EaseResult]
// carries the exported v2 line (when the final level is a playable in-cascade
// level strictly below mad), the final level, prefill figures and wall time.
library;

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Hard ceiling on prefill ratio (matches `classifyTrace`'s default). A puzzle
/// with prefillRatio > this routes to an overfilled bucket, so easing never
/// pushes past it.
const double kMaxEasePrefill = 0.30;

const List<PuzzleLevel> _playable = [
  PuzzleLevel.beginner,
  PuzzleLevel.player,
  PuzzleLevel.advanced,
  PuzzleLevel.strong,
  PuzzleLevel.expert,
  PuzzleLevel.mad,
];

/// Cell-selection objective when committing a readonly fix.
enum EaseObjective {
  /// Commit the fix that lowers the level most (original behaviour; biases
  /// toward overshoot into player).
  minLevel,

  /// Commit the fix that kills force while keeping a complicity in the
  /// target's band, landing advanced/strong instead of overshooting. Only
  /// meaningful for `strong` / `advanced` targets.
  hitBand,

  /// Commit the fix that lands closest to the exact target level, preferring
  /// not to undershoot below it. Generalised form used to fill a specific
  /// collection (e.g. `player` for 2-player, `expert` for 5-expert).
  targetLevel,
}

class EaseOptions {
  final PuzzleLevel target;
  final EaseObjective objective;
  final int maxAdditions;
  final int candidateCap;
  final int timeoutMs;

  const EaseOptions({
    required this.target,
    this.objective = EaseObjective.hitBand,
    this.maxAdditions = 20,
    this.candidateCap = 8,
    this.timeoutMs = 15000,
  });
}

class EaseResult {
  /// Exported v2 line when [finalLevel] is a playable in-cascade level
  /// strictly below mad; `null` otherwise (stayed mad, undetermined, or an
  /// out-of-cascade bucket).
  final String? line;

  /// Final classified level after easing.
  final PuzzleLevel finalLevel;

  final int readonlyAdded;
  final double initialPrefill;
  final double finalPrefill;
  final int ms;

  const EaseResult({
    required this.line,
    required this.finalLevel,
    required this.readonlyAdded,
    required this.initialPrefill,
    required this.finalPrefill,
    required this.ms,
  });
}

/// Ease [pu] in place by fixing free cells to their [solution] values and
/// marking them readonly, until it lands at/below [opts.target] or progress
/// stalls / the 30 % prefill cap is reached.
EaseResult easePuzzle(Puzzle pu, List<CellValue> solution, EaseOptions opts) {
  final total = pu.cells.length;
  final initialReadonly = pu.cells.where((c) => c.readonly).length;
  final initialPrefill = initialReadonly / total;

  int added = 0;
  var trace = pu.solveExplained(timeoutMs: opts.timeoutMs);
  var level = classifyTrace(
    steps: trace,
    prefillRatio: initialPrefill,
    solved: _traceCompletes(pu, trace),
  );
  final sw = Stopwatch()..start();

  while (added < opts.maxAdditions) {
    if (level.index <= opts.target.index) break;
    if (!_playable.contains(level) || level == PuzzleLevel.undetermined) break;

    // Headroom check (exact integer arithmetic): never let the readonly count
    // push the prefill ratio past kMaxEasePrefill, so a finished puzzle can't
    // be mis-routed to an overfilled bucket by a sub-percent floating-point
    // overshoot.
    if ((initialReadonly + added + 1) * 10 > total * 3) break;

    // Candidate free cells to fix: force-move targets first (the direct cause
    // of "mad"), then any other free cell. Bounded by candidateCap.
    final candidates = _candidateCells(pu, trace, opts.candidateCap);
    if (candidates.isEmpty) break;

    // Commit the candidate that best satisfies the objective, only if it
    // improves on the current state.
    int? bestIdx;
    var bestScore = _score(_health(pu, trace), level, opts);
    for (final c in candidates) {
      final probe = pu.clone();
      probe.cells[c].setForSolver(solution[c]);
      probe.cells[c].readonly = true;
      final pTrace = probe.solveExplained(timeoutMs: opts.timeoutMs);
      final pLevel = classifyTrace(
        steps: pTrace,
        prefillRatio: (initialReadonly + added + 1) / total,
        solved: _traceCompletes(probe, pTrace),
      );
      final s = _score(_health(probe, pTrace), pLevel, opts);
      if (s < bestScore) {
        bestScore = s;
        bestIdx = c;
      }
    }
    if (bestIdx == null) break; // plateau: no candidate improved the objective.

    pu.cells[bestIdx].setForSolver(solution[bestIdx]);
    pu.cells[bestIdx].readonly = true;
    added++;
    final finalPrefill = (initialReadonly + added) / total;
    trace = pu.solveExplained(timeoutMs: opts.timeoutMs);
    level = classifyTrace(
      steps: trace,
      prefillRatio: finalPrefill,
      solved: _traceCompletes(pu, trace),
    );
  }

  final ms = sw.elapsedMilliseconds;
  final finalPrefill = (initialReadonly + added) / total;

  // Export tail, mirroring the generator's `_finalize`: replay the final trace
  // on a clone to get the solved grid, sort constraints easier-first,
  // auto-shrink the domain, then serialize. Utilises the last computed trace.
  String? outLine;
  if (_playable.contains(level) &&
      level != PuzzleLevel.undetermined &&
      level.index < PuzzleLevel.mad.index) {
    try {
      final replay = pu.clone();
      for (final s in trace) {
        if (s.value != null) {
          replay.setValue(s.cellIdx, s.value!);
        } else if (s.removeOption != null) {
          replay.removeOption(s.cellIdx, s.removeOption!);
        }
      }
      pu.sortConstraintsByDifficulty(trace);
      PuzzleGenerator.autoShrinkDomain(pu, replay);
      outLine = pu.lineExport();
    } catch (_) {
      outLine = null;
    }
  }

  return EaseResult(
    line: outLine,
    finalLevel: level,
    readonlyAdded: added,
    initialPrefill: initialPrefill,
    finalPrefill: finalPrefill,
    ms: ms,
  );
}

// --- Internals ---------------------------------------------------------------

/// Minimal trace health relevant to the `classifyTrace` cascade: whether the
/// trace completed, how many force rounds it used, and the highest complicity
/// tier.
typedef _Health = ({bool solved, int forceMoves, int maxComplCx});

_Health _health(Puzzle probe, List<SolveStep> trace) {
  final solved = _traceCompletes(probe, trace);
  int forceMoves = 0;
  int maxComplCx = 0;
  if (solved) {
    for (final s in trace) {
      if (s.method == SolveMethod.force) {
        forceMoves++;
      } else if (s.isComplicity && s.complexity > maxComplCx) {
        maxComplCx = s.complexity;
      }
    }
  }
  return (solved: solved, forceMoves: forceMoves, maxComplCx: maxComplCx);
}

/// Rank a candidate's resulting trace for commit-selection. Lower is better.
double _score(_Health h, PuzzleLevel level, EaseOptions o) {
  if (!h.solved) return double.infinity;
  switch (o.objective) {
    case EaseObjective.minLevel:
      return level.index.toDouble();
    case EaseObjective.hitBand:
      return _hitBand(h, o.target);
    case EaseObjective.targetLevel:
      return _targetLevel(h, level, o.target);
  }
}

/// Hit-band scoring: kill force while preserving a complicity in the target's
/// band (strong wants tier ≥ 4, advanced wants tier 1-3), then the adjacent
/// band, then any no-force (player/beginner), then still-mad.
double _hitBand(_Health h, PuzzleLevel target) {
  if (h.forceMoves > 0) return 10000.0 + h.forceMoves * 1000;
  final c = h.maxComplCx.toDouble();
  if (target == PuzzleLevel.strong) {
    if (c >= 4) return 0; // lands strong
    if (c >= 1) {
      return 10 + (4 - c); // lands advanced; closer to strong = better
    }
    return 200; // no complicity → player/beginner
  } else {
    if (c >= 1 && c <= 3) return c; // lands advanced; closer to tier 1 = better
    if (c >= 4) return 10; // lands strong (adjacent band, acceptable)
    return 200; // no complicity → player/beginner
  }
}

/// Generalised level-targeting objective. Two parts:
///
///  * **Force-reduction reward** — while forceMoves > 0, the dominant term is
///    `forceMoves * 1000` (mirroring `_hitBand`). This makes the eager search
///    commit a fix that merely lowers force (mad 2-round → mad 1-round) even
///    when the level index stays mad, so it climbs out of the plateau that a
///    pure level-distance score caused (see "Pilot results").
///  * **Level steering** — once force is dead, the off-set distance term
///    steers to the exact target level, treating undershoot below the target
///    (flooding a lower collection) as costlier than leaving it above.
double _targetLevel(_Health h, PuzzleLevel level, PuzzleLevel target) {
  final d = level.index - target.index;
  if (d == 0) return 0;
  final forceTerm = h.forceMoves * 1000.0;
  if (d > 0) return forceTerm + (100 + d); // still harder than target
  return forceTerm + (200 - d); // undershot below target → worse
}

/// Candidate free cells to fix, in priority order: force-move target cells
/// (what makes the puzzle "mad"), then any remaining free cell. Truncated to
/// [cap].
List<int> _candidateCells(Puzzle pu, List<SolveStep> trace, int cap) {
  final forceCells = <int>[];
  final seen = <int>{};
  for (final s in trace) {
    if (s.method == SolveMethod.force &&
        s.cellIdx >= 0 &&
        seen.add(s.cellIdx)) {
      forceCells.add(s.cellIdx);
    }
  }
  final freeCells = <int>[];
  for (int i = 0; i < pu.cells.length; i++) {
    if (pu.cells[i].readonly) continue;
    if (pu.cells[i].value != CellValue.free) continue;
    if (!seen.contains(i)) freeCells.add(i);
  }
  return [...forceCells, ...freeCells].take(cap).toList();
}

bool _traceCompletes(Puzzle pu, List<SolveStep> trace) {
  if (trace.isEmpty) return false;
  final replay = pu.clone();
  for (final s in trace) {
    if (s.value != null) {
      replay.setValue(s.cellIdx, s.value!);
    } else if (s.removeOption != null) {
      replay.removeOption(s.cellIdx, s.removeOption!);
    }
  }
  return replay.complete && replay.check(saveResult: false).isEmpty;
}
