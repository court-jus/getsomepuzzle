// Correlates puzzle ratings (liked / disliked / neutral) from stats/stats.txt
// with the trace score computed by bin/trace_score.dart.
//
// Usage: dart run bin/rating_correlation.dart [--stats PATH] [--timeout-ms MS]

import 'dart:io';

import 'trace_score.dart' show TraceMetrics, scorePuzzle;

void main(List<String> args) {
  String statsPath = 'stats/stats.txt';
  int timeoutMs = 15000;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--stats':
        statsPath = args[++i];
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/rating_correlation.dart '
          '[--stats PATH] [--timeout-ms MS]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  final file = File(statsPath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $statsPath');
    exit(1);
  }

  final entries = <(String puzzle, String rating)>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(' - ');
    if (parts.length < 2) continue;
    // Header part: "<ts> <dur>s <fail>f <puzzle_line>"
    final headerTokens = parts[0].split(' ');
    if (headerTokens.length < 4) continue;
    final puzzle = headerTokens[3];
    if (!puzzle.startsWith('v2_')) continue;
    final rating = parts[1].trim();
    entries.add((puzzle, rating));
  }
  stderr.writeln('Loaded ${entries.length} rated entries from $statsPath');

  final byRating = <String, List<TraceMetrics>>{};
  final sw = Stopwatch()..start();
  int done = 0;
  for (final (puzzle, rating) in entries) {
    try {
      final m = scorePuzzle(puzzle, timeoutMs: timeoutMs);
      byRating.putIfAbsent(rating, () => []).add(m);
    } catch (e) {
      stderr.writeln('  ERROR on puzzle $done: $e');
    }
    done++;
    if (done % 50 == 0) {
      stderr.write('\r  $done/${entries.length} scored...  ');
    }
  }
  stderr.writeln('\nDone in ${sw.elapsed.inSeconds}s');

  _report(byRating);
}

const _labels = {'_L_': 'Liked   ', '__D': 'Disliked', '___': 'Neutral '};

void _report(Map<String, List<TraceMetrics>> byRating) {
  stdout.writeln('');
  stdout.writeln('=== SCORE DISTRIBUTION BY RATING ===');
  stdout.writeln('');

  final order = ['_L_', '___', '__D'];
  for (final key in order) {
    final list = byRating[key] ?? [];
    if (list.isEmpty) continue;
    final label = _labels[key] ?? key;
    final scored = list.where((m) => !m.needsBacktrack).toList();
    final bt = list.length - scored.length;

    stdout.writeln('--- $label (${list.length} puzzles) ---');
    stdout.writeln(
      '  backtrack-needed: $bt '
      '(${(bt / list.length * 100).toStringAsFixed(1)}%)',
    );

    if (scored.isEmpty) {
      stdout.writeln('  (no scorable puzzles)');
      stdout.writeln('');
      continue;
    }

    final scores = scored.map((m) => m.score).toList()..sort();
    stdout.writeln(
      '  score   min=${scores.first.toStringAsFixed(1)}'
      '  p25=${_pct(scores, 25).toStringAsFixed(1)}'
      '  median=${_pct(scores, 50).toStringAsFixed(1)}'
      '  p75=${_pct(scores, 75).toStringAsFixed(1)}'
      '  max=${scores.last.toStringAsFixed(1)}'
      '  mean=${_mean(scores).toStringAsFixed(1)}',
    );

    stdout.writeln('  component means:');
    stdout.writeln(
      '    switch_ratio   ${_avgD(scored.map((m) => m.switchRatio)).toStringAsFixed(3)}',
    );
    stdout.writeln(
      '    cascade_ratio  ${_avgD(scored.map((m) => m.cascadeRatio)).toStringAsFixed(3)}',
    );
    stdout.writeln(
      '    force_ratio    ${_avgD(scored.map((m) => m.forceRatio)).toStringAsFixed(3)}',
    );
    stdout.writeln(
      '    diversity      ${_avgD(scored.map((m) => m.diversity)).toStringAsFixed(3)}',
    );
    stdout.writeln(
      '    start_ok frac  ${_avgD(scored.map((m) => m.startOk ? 1.0 : 0.0)).toStringAsFixed(3)}',
    );
    stdout.writeln(
      '    prop_steps     ${_avgD(scored.map((m) => m.propSteps.toDouble())).toStringAsFixed(1)}',
    );
    stdout.writeln(
      '    force_steps    ${_avgD(scored.map((m) => m.forceSteps.toDouble())).toStringAsFixed(2)}',
    );
    stdout.writeln('');
  }

  // Side-by-side comparison
  stdout.writeln('=== HEAD-TO-HEAD: Liked vs Disliked ===');
  final liked = (byRating['_L_'] ?? [])
      .where((m) => !m.needsBacktrack)
      .toList();
  final disliked = (byRating['__D'] ?? [])
      .where((m) => !m.needsBacktrack)
      .toList();
  final neutral = (byRating['___'] ?? [])
      .where((m) => !m.needsBacktrack)
      .toList();

  if (liked.isNotEmpty && disliked.isNotEmpty) {
    final likedMean = _mean(liked.map((m) => m.score).toList());
    final dislikedMean = _mean(disliked.map((m) => m.score).toList());
    final neutralMean = _mean(neutral.map((m) => m.score).toList());
    stdout.writeln(
      '  mean score   liked=${likedMean.toStringAsFixed(1)}  '
      'neutral=${neutralMean.toStringAsFixed(1)}  '
      'disliked=${dislikedMean.toStringAsFixed(1)}',
    );
    stdout.writeln(
      '  delta        liked - disliked = '
      '${(likedMean - dislikedMean).toStringAsFixed(1)}',
    );
  }

  // How many liked above a threshold vs. disliked below?
  stdout.writeln('');
  stdout.writeln('Cumulative distribution (fraction with score >= X):');
  stdout.writeln('  threshold   liked    neutral  disliked');
  for (final t in [0, 10, 20, 30, 40, 50, 60]) {
    final likedFrac = _fractionAbove(liked, t.toDouble());
    final neutralFrac = _fractionAbove(neutral, t.toDouble());
    final dislikedFrac = _fractionAbove(disliked, t.toDouble());
    stdout.writeln(
      '  >= ${t.toString().padLeft(3)}      '
      '${likedFrac.toStringAsFixed(2).padLeft(6)}   '
      '${neutralFrac.toStringAsFixed(2).padLeft(6)}   '
      '${dislikedFrac.toStringAsFixed(2).padLeft(6)}',
    );
  }

  // Show disliked puzzles with their scores to eyeball
  stdout.writeln('');
  stdout.writeln('=== DISLIKED puzzles (all, sorted by score) ===');
  final dislikedSorted = List<TraceMetrics>.from(disliked)
    ..sort((a, b) => b.score.compareTo(a.score));
  for (final m in dislikedSorted) {
    _card(m);
  }
  final dislikedBT = (byRating['__D'] ?? []).where((m) => m.needsBacktrack);
  for (final m in dislikedBT) {
    stdout.writeln('  score=BT (backtrack-needed)');
    stdout.writeln(
      '    ${m.line.length > 100 ? '${m.line.substring(0, 97)}...' : m.line}',
    );
  }
}

void _card(TraceMetrics r) {
  final preview = r.line.length > 110
      ? '${r.line.substring(0, 107)}...'
      : r.line;
  stdout.writeln(
    '  score=${r.score.toStringAsFixed(1).padLeft(6)}  '
    'steps=${r.totalSteps} (p=${r.propSteps},f=${r.forceSteps})  '
    'sw=${r.switches}  casc=${r.maxCascade}  '
    'd=${r.distinctConstraints}/${r.totalConstraints}',
  );
  stdout.writeln('    $preview');
}

double _pct(List<double> sortedAsc, int p) {
  if (sortedAsc.isEmpty) return 0.0;
  final idx = ((p / 100.0) * (sortedAsc.length - 1)).round();
  return sortedAsc[idx.clamp(0, sortedAsc.length - 1)];
}

double _mean(List<double> xs) {
  if (xs.isEmpty) return 0.0;
  return xs.reduce((a, b) => a + b) / xs.length;
}

double _avgD(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0.0;
  return list.reduce((a, b) => a + b) / list.length;
}

double _fractionAbove(List<TraceMetrics> ms, double threshold) {
  if (ms.isEmpty) return 0.0;
  final n = ms.where((m) => m.score >= threshold).length;
  return n / ms.length;
}
