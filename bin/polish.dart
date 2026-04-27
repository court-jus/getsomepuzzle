// Polish phase for generated puzzles (S2).
//
// Reads puzzles, and for each one tries local mutations
// (add / remove a constraint) that:
//   1. preserve unique-solvability,
//   2. improve the trace score from `bin/trace_score.dart`.
// Greedy best-improvement loop until no mutation helps or budget is
// exhausted. Output: improved puzzles + summary of mutations applied.
//
// Usage:
//   dart run bin/polish.dart [--in FILE] [--out FILE]
//                            [--max-iter N] [--max-candidates N]
//                            [--timeout-ms MS]

import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

import 'trace_score.dart' show scorePuzzle;

void main(List<String> args) async {
  String? inPath;
  String? outPath;
  int maxIter = 4;
  int? maxCandidates = 30; // sample N random candidates per iter
  bool verbose = false;
  int timeoutMs = 15000;
  int seed = 42;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        inPath = args[++i];
      case '--out':
        outPath = args[++i];
      case '--max-iter':
        maxIter = int.parse(args[++i]);
      case '--max-candidates':
        maxCandidates = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '-v':
      case '--verbose':
        verbose = true;
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/polish.dart [--in FILE] [--out FILE] '
          '[--max-iter N] [--max-candidates N] [--timeout-ms MS] [--seed S]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  // Source.
  List<String> lines;
  if (inPath != null) {
    final f = File(inPath);
    if (!f.existsSync()) {
      stderr.writeln('File not found: $inPath');
      exit(1);
    }
    lines = f.readAsLinesSync();
  } else {
    lines = <String>[];
    String? raw;
    while ((raw = stdin.readLineSync()) != null) {
      lines.add(raw!);
    }
  }

  // Sink.
  IOSink sink;
  bool closeSink = false;
  if (outPath != null) {
    sink = File(outPath).openWrite();
    closeSink = true;
  } else {
    sink = stdout;
  }

  final rng = Random(seed);
  int read = 0;
  int polished = 0; // changed at least once
  int unchanged = 0;
  int skipped = 0; // not uniquely solvable to begin with
  double sumScoreIn = 0.0;
  double sumScoreOut = 0.0;
  int sumConstraintsIn = 0;
  int sumConstraintsOut = 0;
  int totalAdds = 0;
  int totalRemoves = 0;

  final sw = Stopwatch()..start();

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    read++;

    final result = _polishOne(
      line,
      maxIter: maxIter,
      maxCandidates: maxCandidates,
      timeoutMs: timeoutMs,
      rng: rng,
    );

    if (result == null) {
      skipped++;
      continue;
    }

    sumScoreIn += result.scoreIn;
    sumScoreOut += result.scoreOut;
    sumConstraintsIn += result.constraintsIn;
    sumConstraintsOut += result.constraintsOut;
    totalAdds += result.adds;
    totalRemoves += result.removes;

    sink.writeln(result.outLine);
    await sink.flush();
    if (result.adds + result.removes > 0) {
      polished++;
    } else {
      unchanged++;
    }

    if (verbose) {
      stderr.writeln(
        '  [$read] score ${result.scoreIn.toStringAsFixed(1)} '
        '→ ${result.scoreOut.toStringAsFixed(1)} '
        '(+${result.adds}/-${result.removes}, '
        '#c ${result.constraintsIn}→${result.constraintsOut}, '
        '${sw.elapsed.inSeconds}s)',
      );
    } else if (read % 1 == 0) {
      stderr.write(
        '\r  read=$read polished=$polished unchanged=$unchanged '
        'skipped=$skipped (${sw.elapsed.inSeconds}s)        ',
      );
    }
  }

  if (closeSink) await sink.flush().then((_) => sink.close());

  stderr.writeln('');
  stderr.writeln('=== POLISH SUMMARY ===');
  stderr.writeln('  read              $read');
  stderr.writeln(
    '  polished          $polished '
    '(${_pct(polished, read)})',
  );
  stderr.writeln(
    '  unchanged         $unchanged '
    '(${_pct(unchanged, read)})',
  );
  stderr.writeln(
    '  skipped (nonUniq) $skipped '
    '(${_pct(skipped, read)})',
  );
  final scored = polished + unchanged;
  if (scored > 0) {
    stderr.writeln(
      '  mean score in    ${(sumScoreIn / scored).toStringAsFixed(1)}',
    );
    stderr.writeln(
      '  mean score out   ${(sumScoreOut / scored).toStringAsFixed(1)}'
      ' (Δ ${((sumScoreOut - sumScoreIn) / scored).toStringAsFixed(1)})',
    );
    stderr.writeln(
      '  mean #constr in  ${(sumConstraintsIn / scored).toStringAsFixed(1)}',
    );
    stderr.writeln(
      '  mean #constr out ${(sumConstraintsOut / scored).toStringAsFixed(1)}',
    );
  }
  stderr.writeln('  total adds        $totalAdds');
  stderr.writeln('  total removes     $totalRemoves');
  stderr.writeln('  elapsed           ${sw.elapsed.inSeconds}s');
}

class _PolishResult {
  final String outLine;
  final double scoreIn;
  final double scoreOut;
  final int constraintsIn;
  final int constraintsOut;
  final int adds;
  final int removes;
  _PolishResult({
    required this.outLine,
    required this.scoreIn,
    required this.scoreOut,
    required this.constraintsIn,
    required this.constraintsOut,
    required this.adds,
    required this.removes,
  });
}

_PolishResult? _polishOne(
  String line, {
  required int maxIter,
  required int? maxCandidates,
  required int timeoutMs,
  required Random rng,
}) {
  final puzzle = Puzzle(line);
  final initialMetrics = scorePuzzle(line, timeoutMs: timeoutMs);
  // We require an already-uniquely-solvable puzzle as input.
  if (initialMetrics.needsBacktrack) return null;

  final scoreIn = initialMetrics.score;
  final constraintsIn = puzzle.constraints.length;

  // Build a fully-solved puzzle (so we can verify candidate constraints
  // against the canonical solution). Prefer cachedSolution; fall back to
  // solving if needed.
  final solved = _materializeSolution(puzzle);
  if (solved == null) {
    // Cannot construct a solved state — give up on this puzzle.
    return _PolishResult(
      outLine: line,
      scoreIn: scoreIn,
      scoreOut: scoreIn,
      constraintsIn: constraintsIn,
      constraintsOut: constraintsIn,
      adds: 0,
      removes: 0,
    );
  }

  // Enumerate candidate constraints (valid against the solution).
  final existingSerial = puzzle.constraints.map((c) => c.serialize()).toSet();
  final candidates = <Constraint>[];
  for (final entry in constraintRegistry) {
    final params = entry.generateAllParameters(
      puzzle.width,
      puzzle.height,
      puzzle.domain,
      null,
    );
    for (final p in params) {
      final c = createConstraint(entry.slug, p);
      if (c == null) continue;
      if (existingSerial.contains(c.serialize())) continue;
      if (!c.verify(solved)) continue;
      candidates.add(c);
    }
  }
  candidates.shuffle(rng);
  final pool = (maxCandidates != null && candidates.length > maxCandidates)
      ? candidates.take(maxCandidates).toList()
      : candidates;

  double currentScore = scoreIn;
  int adds = 0;
  int removes = 0;

  for (int iter = 0; iter < maxIter; iter++) {
    double bestDelta = 0.0;
    _Mutation? bestMutation;

    // Try removing each existing constraint.
    for (int i = 0; i < puzzle.constraints.length; i++) {
      final score = _scoreWithMutation(
        puzzle,
        removeIndex: i,
        timeoutMs: timeoutMs,
      );
      if (score == null) continue;
      final delta = score - currentScore;
      if (delta > bestDelta) {
        bestDelta = delta;
        bestMutation = _Mutation.remove(i);
      }
    }

    // Try adding each candidate constraint.
    for (int i = 0; i < pool.length; i++) {
      final cand = pool[i];
      final score = _scoreWithMutation(
        puzzle,
        addConstraint: cand,
        timeoutMs: timeoutMs,
      );
      if (score == null) continue;
      final delta = score - currentScore;
      if (delta > bestDelta) {
        bestDelta = delta;
        bestMutation = _Mutation.add(i);
      }
    }

    if (bestMutation == null) break;

    if (bestMutation.kind == _MutationKind.remove) {
      puzzle.constraints.removeAt(bestMutation.index);
      removes++;
    } else {
      final cand = pool.removeAt(bestMutation.index);
      puzzle.constraints.add(cand);
      adds++;
    }
    currentScore += bestDelta;
  }

  final outLine = puzzle.lineExport();
  return _PolishResult(
    outLine: outLine,
    scoreIn: scoreIn,
    scoreOut: currentScore,
    constraintsIn: constraintsIn,
    constraintsOut: puzzle.constraints.length,
    adds: adds,
    removes: removes,
  );
}

/// Return a clone of `puzzle` with every cell set to its solution value, so
/// that constraint.verify(solved) is meaningful. Returns null on failure.
Puzzle? _materializeSolution(Puzzle puzzle) {
  final sol = puzzle.cachedSolution;
  if (sol != null && sol.length == puzzle.cellValues.length) {
    final p = puzzle.clone();
    for (int i = 0; i < sol.length; i++) {
      p.setValue(i, sol[i]);
    }
    return p;
  }
  // Fallback: solve from scratch on a fresh clone.
  final p = puzzle.clone();
  p.restart();
  if (p.solve() && !p.cellValues.contains(0)) return p;
  return null;
}

/// Score the puzzle as if a single mutation were applied. Returns null if
/// the mutated puzzle is not uniquely solvable.
double? _scoreWithMutation(
  Puzzle puzzle, {
  int? removeIndex,
  Constraint? addConstraint,
  required int timeoutMs,
}) {
  final clone = puzzle.clone();
  if (removeIndex != null) {
    clone.constraints.removeAt(removeIndex);
  }
  if (addConstraint != null) {
    clone.constraints.add(addConstraint);
  }
  // Reset to the puzzle's starting state (only readonly cells set) so that
  // validity / scorePuzzle measure the puzzle fresh, not mid-play.
  clone.restart();
  if (!clone.isDeductivelyUnique()) return null;

  final line = clone.lineExport(compute: false);
  final m = scorePuzzle(line, timeoutMs: timeoutMs);
  if (m.needsBacktrack) return null;
  return m.score;
}

enum _MutationKind { add, remove }

class _Mutation {
  final _MutationKind kind;
  final int index;
  _Mutation.add(this.index) : kind = _MutationKind.add;
  _Mutation.remove(this.index) : kind = _MutationKind.remove;
}

String _pct(int n, int total) {
  if (total == 0) return '0%';
  return '${(n / total * 100).toStringAsFixed(1)}%';
}
