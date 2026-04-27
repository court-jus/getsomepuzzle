// Computes a "trace score" for puzzles: a measure of deduction elegance based
// on how the solver's step-by-step trace looks (interleaved constraints vs.
// single-constraint cascade, force ratio, diversity, starting points).
//
// Usage:
//   dart run bin/trace_score.dart [--file PATH] [--sample N] [--seed S]
//                                 [--top K] [--bottom K] [--timeout-ms MS]

import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class TraceMetrics {
  final String line;
  final int totalSteps;
  final int propSteps;
  final int forceSteps;
  final int switches;
  final int maxCascade;
  final int distinctConstraints;
  final int totalConstraints;
  final int startPropSteps; // propagation steps before first force
  final int forceDepthSum; // total propagation depth across all force steps
  final int forceDepthMax; // worst single force-round depth
  final bool needsBacktrack;
  final bool solved;
  final double score;
  final Map<String, int> constraintUsage;

  TraceMetrics({
    required this.line,
    required this.totalSteps,
    required this.propSteps,
    required this.forceSteps,
    required this.switches,
    required this.maxCascade,
    required this.distinctConstraints,
    required this.totalConstraints,
    required this.startPropSteps,
    required this.forceDepthSum,
    required this.forceDepthMax,
    required this.needsBacktrack,
    required this.solved,
    required this.score,
    required this.constraintUsage,
  });

  double get switchRatio => propSteps > 1 ? switches / (propSteps - 1) : 0.0;
  double get cascadeRatio => propSteps > 0 ? maxCascade / propSteps : 0.0;
  double get forceRatio => totalSteps > 0 ? forceSteps / totalSteps : 0.0;
  // Average propagation depth per force step. 0 when no force steps.
  double get forceDepthAvg => forceSteps > 0 ? forceDepthSum / forceSteps : 0.0;
  double get diversity =>
      totalConstraints > 0 ? distinctConstraints / totalConstraints : 0.0;
  bool get startOk => startPropSteps >= 1;
}

TraceMetrics scorePuzzle(String line, {int timeoutMs = 15000}) {
  final puzzle = Puzzle(line);
  final totalConstraints = puzzle.constraints.length;

  // First, determine whether the puzzle is solvable by propagation+force
  // alone. If not, it needs backtracking → disqualified.
  final probe = puzzle.clone();
  final solvedWithoutBT = probe.solve();

  if (!solvedWithoutBT) {
    return TraceMetrics(
      line: line,
      totalSteps: 0,
      propSteps: 0,
      forceSteps: 0,
      switches: 0,
      maxCascade: 0,
      distinctConstraints: 0,
      totalConstraints: totalConstraints,
      startPropSteps: 0,
      forceDepthSum: 0,
      forceDepthMax: 0,
      needsBacktrack: true,
      solved: false,
      score: -100.0,
      constraintUsage: const {},
    );
  }

  final steps = puzzle.solveExplained(timeoutMs: timeoutMs);

  int propSteps = 0;
  int forceSteps = 0;
  int switches = 0;
  int cascade = 0;
  int maxCascade = 0;
  int startPropSteps = 0;
  int forceDepthSum = 0;
  int forceDepthMax = 0;
  bool seenForce = false;
  String? prevConstraint;
  final distinct = <String>{};
  final usage = <String, int>{};

  for (final step in steps) {
    if (step.method == SolveMethod.force) {
      forceSteps++;
      forceDepthSum += step.forceDepth;
      if (step.forceDepth > forceDepthMax) forceDepthMax = step.forceDepth;
      seenForce = true;
      prevConstraint = null;
      cascade = 0;
      continue;
    }
    propSteps++;
    if (!seenForce) startPropSteps++;
    distinct.add(step.constraint);
    usage[step.constraint] = (usage[step.constraint] ?? 0) + 1;

    if (step.constraint == prevConstraint) {
      cascade++;
    } else {
      if (prevConstraint != null) switches++;
      cascade = 1;
    }
    if (cascade > maxCascade) maxCascade = cascade;
    prevConstraint = step.constraint;
  }

  final totalSteps = propSteps + forceSteps;

  final switchRatio = propSteps > 1 ? switches / (propSteps - 1) : 0.0;
  final cascadeRatio = propSteps > 0 ? maxCascade / propSteps : 0.0;
  final diversity = totalConstraints > 0
      ? distinct.length / totalConstraints
      : 0.0;
  final startOk = startPropSteps >= 1 ? 1.0 : 0.0;
  // Force penalty replaces the previous binary force_ratio. The pain of a
  // force round is the *depth* of its propagation chain to refutation, not
  // just the round happening — see lib/getsomepuzzle/model/puzzle.dart
  // computeComplexity for the same intuition.
  final avgForceDepth = forceSteps > 0 ? forceDepthSum / forceSteps : 0.0;
  final forcePenalty = forceSteps == 0
      ? 0.0
      : (3.0 + 2.0 * avgForceDepth + 1.5 * forceDepthMax);

  final score =
      40.0 * switchRatio -
      40.0 * cascadeRatio -
      forcePenalty +
      20.0 * diversity +
      20.0 * startOk;

  return TraceMetrics(
    line: line,
    totalSteps: totalSteps,
    propSteps: propSteps,
    forceSteps: forceSteps,
    switches: switches,
    maxCascade: maxCascade,
    distinctConstraints: distinct.length,
    totalConstraints: totalConstraints,
    startPropSteps: startPropSteps,
    forceDepthSum: forceDepthSum,
    forceDepthMax: forceDepthMax,
    needsBacktrack: false,
    solved: true,
    score: score,
    constraintUsage: usage,
  );
}

void main(List<String> args) {
  String filePath = 'assets/default.txt';
  int sample = 200;
  int seed = 42;
  int topK = 5;
  int bottomK = 5;
  int timeoutMs = 15000;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--file':
        filePath = args[++i];
      case '--sample':
        sample = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--top':
        topK = int.parse(args[++i]);
      case '--bottom':
        bottomK = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/trace_score.dart '
          '[--file PATH] [--sample N] [--seed S] '
          '[--top K] [--bottom K] [--timeout-ms MS]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $filePath');
    exit(1);
  }

  final allLines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();
  stderr.writeln('Loaded ${allLines.length} puzzles from $filePath');

  final rng = Random(seed);
  final shuffled = List<String>.from(allLines)..shuffle(rng);
  final sampleLines = shuffled.take(sample).toList();
  stderr.writeln('Scoring $sample puzzles (seed=$seed)...');

  final results = <TraceMetrics>[];
  final sw = Stopwatch()..start();
  for (int i = 0; i < sampleLines.length; i++) {
    try {
      results.add(scorePuzzle(sampleLines[i], timeoutMs: timeoutMs));
    } catch (e) {
      stderr.writeln('  ERROR on puzzle ${i + 1}: $e');
    }
    if ((i + 1) % 20 == 0) {
      stderr.write('\r  ${i + 1}/${sampleLines.length} scored...  ');
    }
  }
  stderr.writeln('\nDone in ${sw.elapsed.inSeconds}s');

  _report(results, topK: topK, bottomK: bottomK);
}

void _report(
  List<TraceMetrics> results, {
  required int topK,
  required int bottomK,
}) {
  final scored = results.where((r) => !r.needsBacktrack).toList();
  final bt = results.where((r) => r.needsBacktrack).length;

  stdout.writeln('');
  stdout.writeln('=== SUMMARY ===');
  stdout.writeln('Total scored:       ${results.length}');
  stdout.writeln(
    'Backtrack-needed:   $bt '
    '(${(bt / results.length * 100).toStringAsFixed(1)}%) — disqualified',
  );
  stdout.writeln('Scorable:           ${scored.length}');

  if (scored.isEmpty) return;

  final scores = scored.map((r) => r.score).toList()..sort();
  final mean = scores.reduce((a, b) => a + b) / scores.length;
  stdout.writeln('');
  stdout.writeln('Score distribution:');
  stdout.writeln('  min      ${scores.first.toStringAsFixed(1)}');
  stdout.writeln('  p10      ${_percentile(scores, 10).toStringAsFixed(1)}');
  stdout.writeln('  p25      ${_percentile(scores, 25).toStringAsFixed(1)}');
  stdout.writeln('  median   ${_percentile(scores, 50).toStringAsFixed(1)}');
  stdout.writeln('  p75      ${_percentile(scores, 75).toStringAsFixed(1)}');
  stdout.writeln('  p90      ${_percentile(scores, 90).toStringAsFixed(1)}');
  stdout.writeln('  max      ${scores.last.toStringAsFixed(1)}');
  stdout.writeln('  mean     ${mean.toStringAsFixed(1)}');

  stdout.writeln('');
  stdout.writeln('Histogram (score buckets of 10):');
  _histogram(scores);

  stdout.writeln('');
  stdout.writeln('Average component breakdown:');
  stdout.writeln(
    '  switch_ratio     ${_avg(scored.map((r) => r.switchRatio)).toStringAsFixed(3)} (high = good)',
  );
  stdout.writeln(
    '  cascade_ratio    ${_avg(scored.map((r) => r.cascadeRatio)).toStringAsFixed(3)} (low  = good)',
  );
  stdout.writeln(
    '  force_ratio      ${_avg(scored.map((r) => r.forceRatio)).toStringAsFixed(3)} (low  = good)',
  );
  stdout.writeln(
    '  force_depth_avg  ${_avg(scored.map((r) => r.forceDepthAvg)).toStringAsFixed(2)} (low  = good)',
  );
  stdout.writeln(
    '  force_depth_max  ${_avg(scored.map((r) => r.forceDepthMax.toDouble())).toStringAsFixed(2)} (low  = good)',
  );
  stdout.writeln(
    '  diversity        ${_avg(scored.map((r) => r.diversity)).toStringAsFixed(3)} (high = good)',
  );
  stdout.writeln(
    '  start_ok (frac)  ${_avg(scored.map((r) => r.startOk ? 1.0 : 0.0)).toStringAsFixed(3)}',
  );

  final sortedDesc = List<TraceMetrics>.from(scored)
    ..sort((a, b) => b.score.compareTo(a.score));

  stdout.writeln('');
  stdout.writeln('=== TOP $topK (most elegant traces) ===');
  for (final r in sortedDesc.take(topK)) {
    _printPuzzleCard(r);
  }

  stdout.writeln('');
  stdout.writeln('=== BOTTOM $bottomK (trivial / cascade-dominated) ===');
  for (final r in sortedDesc.reversed.take(bottomK)) {
    _printPuzzleCard(r);
  }
}

void _printPuzzleCard(TraceMetrics r) {
  final preview = r.line.length > 100
      ? '${r.line.substring(0, 97)}...'
      : r.line;
  stdout.writeln(
    '  score=${r.score.toStringAsFixed(1)}  '
    'steps=${r.totalSteps} (prop=${r.propSteps}, force=${r.forceSteps})  '
    'switches=${r.switches}  max_cascade=${r.maxCascade}  '
    'distinct=${r.distinctConstraints}/${r.totalConstraints}',
  );
  stdout.writeln('    $preview');
  final usageStr =
      (r.constraintUsage.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(5)
          .map((e) => '${e.key}×${e.value}')
          .join(', ');
  if (usageStr.isNotEmpty) {
    stdout.writeln('    uses: $usageStr');
  }
}

double _percentile(List<double> sortedAsc, int p) {
  if (sortedAsc.isEmpty) return 0.0;
  final idx = ((p / 100.0) * (sortedAsc.length - 1)).round();
  return sortedAsc[idx.clamp(0, sortedAsc.length - 1)];
}

double _avg(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0.0;
  return list.reduce((a, b) => a + b) / list.length;
}

void _histogram(List<double> sortedScores) {
  if (sortedScores.isEmpty) return;
  final minS = sortedScores.first;
  final maxS = sortedScores.last;
  const bucketSize = 10.0;
  final firstBucket = (minS / bucketSize).floor() * bucketSize;
  final lastBucket = (maxS / bucketSize).ceil() * bucketSize;
  final buckets = <double, int>{};
  for (double b = firstBucket; b < lastBucket; b += bucketSize) {
    buckets[b] = 0;
  }
  for (final s in sortedScores) {
    final bucket = (s / bucketSize).floor() * bucketSize;
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
  }
  final maxCount = buckets.values.fold<int>(0, max);
  final sortedKeys = buckets.keys.toList()..sort();
  for (final k in sortedKeys) {
    final count = buckets[k]!;
    final barLen = maxCount > 0 ? (count / maxCount * 40).round() : 0;
    final label =
        '[${k.toStringAsFixed(0).padLeft(5)}, ${(k + bucketSize).toStringAsFixed(0).padLeft(5)})';
    stdout.writeln('  $label  ${'█' * barLen} $count');
  }
}
