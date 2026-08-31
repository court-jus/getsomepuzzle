// Dry-run "up-easing": take easy puzzles that already carry a complicity
// base-slug pair (produced by bin/find_complicity_candidates.dart) and try
// removing each constraint one at a time. If the surviving constraints now
// combine into a Complicity move, the puzzle re-classifies as advanced/strong.
//
// This is the inverse of the down-easing lever (lib/getsomepuzzle/recycle.dart):
// down-easing adds constraints/readonly cells to kill force; up-easing removes
// the single constraint that currently pins a cell, so the remaining pair must
// combine instead.
//
// Cost is bounded by only running the expensive backtracking uniqueness check
// (`enumerateSolutions`) on removals that actually land at advanced/strong —
// every other outcome only needs one `classifyPuzzle` (a cheap solve). Hits are
// flushed to stderr as they are found, so an interrupted run still reports
// what it achieved.
//
// Reports only; writes nothing.
//
// Usage:
//   dart run bin/up_ease.dart
//       [--input assets/complicity-recycling-candidates.txt]
//       [--sample N] [--seed 42] [--timeout-ms 30000] [--max-removals 30]
//       [--progress N] [--verbose]

import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  var input = 'assets/complicity-recycling-candidates.txt';
  int? sample;
  var seed = 42;
  var timeoutMs = 30000;
  var maxRemovals = 30;
  var progressEvery = 10;
  var verbose = false;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        input = args[++i];
      case '--sample':
        sample = int.parse(args[++i]);
      case '--seed':
        seed = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '--max-removals':
        maxRemovals = int.parse(args[++i]);
      case '--progress':
        progressEvery = int.parse(args[++i]);
      case '-v':
      case '--verbose':
        verbose = true;
      case '-h':
      case '--help':
        stderr.writeln(_usage);
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        stderr.writeln(_usage);
        exit(1);
    }
  }

  final file = File(input);
  if (!file.existsSync()) {
    stderr.writeln('not found: $input');
    exit(1);
  }
  var lines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();
  if (sample != null && sample < lines.length) {
    lines = List<String>.from(lines)..shuffle(Random(seed));
    lines = lines.take(sample).toList();
  }
  stderr.writeln('Candidates: ${lines.length}');

  final baselineCounts = <String, int>{};
  // Histogram of every removal outcome (uniqueness NOT yet checked).
  final reachableByLevel = <String, int>{};
  // Of the removals that landed advanced/strong, split by uniqueness.
  int okAdvanced = 0;
  int okStrong = 0;
  int ambiguousAdvanced = 0;
  int ambiguousStrong = 0;
  int probes = 0;
  // Per-puzzle salvage: at least one unique removal lands here.
  int canAdvanced = 0;
  int canStrong = 0;
  int parsed = 0;

  final sw = Stopwatch()..start();

  for (int li = 0; li < lines.length; li++) {
    final line = lines[li];
    final p = _parse(line);
    if (p == null) continue;
    parsed++;

    final baseline = classifyPuzzle(p, timeoutMs: timeoutMs);
    baselineCounts[baseline.name] = (baselineCounts[baseline.name] ?? 0) + 1;

    var thisAdvanced = false;
    var thisStrong = false;
    final n = min(p.constraints.length, maxRemovals);

    for (int ci = 0; ci < n; ci++) {
      final clone = p.clone();
      clone.removeConstraintAt(ci);
      probes++;

      final lvl = classifyPuzzle(clone, timeoutMs: timeoutMs);
      reachableByLevel[lvl.name] = (reachableByLevel[lvl.name] ?? 0) + 1;

      if (lvl == PuzzleLevel.advanced || lvl == PuzzleLevel.strong) {
        // Expensive backtracking uniqueness only for the outcomes that matter.
        final unique = enumerateSolutions(clone, limit: 2).length == 1;
        if (unique) {
          if (lvl == PuzzleLevel.advanced) {
            okAdvanced++;
            thisAdvanced = true;
          } else {
            okStrong++;
            thisStrong = true;
          }
          stderr.writeln(
            'HIT: #${li + 1} rm#$ci -> ${lvl.name} (unique)  [$line]',
          );
        } else {
          if (lvl == PuzzleLevel.advanced) {
            ambiguousAdvanced++;
          } else {
            ambiguousStrong++;
          }
          stderr.writeln(
            'HIT(ambiguous): #${li + 1} rm#$ci -> ${lvl.name} (>=2 sols)',
          );
        }
      }

      if (verbose) {
        stderr.writeln('  #${li + 1} rm#$ci -> ${lvl.name}');
      }
    }

    if (thisAdvanced) canAdvanced++;
    if (thisStrong) canStrong++;
    if ((li + 1) % progressEvery == 0) {
      stderr.writeln(
        '  progress: ${li + 1}/${lines.length} puzzles, '
        '$okAdvanced advanced + $okStrong strong unique hits so far',
      );
    }
  }

  sw.stop();
  stderr.writeln('Processed $parsed puzzles in ${sw.elapsed.inSeconds}s\n');

  stdout.writeln('=== UP-EASE REPORT (dry-run) ===');
  stdout.writeln('Candidates processed: $parsed');
  stdout.writeln('Baseline levels:');
  _printSorted(baselineCounts);
  stdout.writeln('');
  stdout.writeln('Per-puzzle salvage (>=1 unique removal reaches it):');
  stdout.writeln('  -> advanced: $canAdvanced');
  stdout.writeln('  -> strong:   $canStrong');
  stdout.writeln('');
  stdout.writeln('Removal probes: $probes');
  stdout.writeln('Landing level of every removal (uniqueness unchecked):');
  _printSorted(reachableByLevel);
  stdout.writeln('');
  stdout.writeln('Of the removals that landed advanced/strong:');
  stdout.writeln(
    '  -> advanced, unique: $okAdvanced   (ambiguous: $ambiguousAdvanced)',
  );
  stdout.writeln(
    '  -> strong,   unique: $okStrong   (ambiguous: $ambiguousStrong)',
  );
}

void _printSorted(Map<String, int> m) {
  final entries = m.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  for (final e in entries) {
    stdout.writeln('  ${e.key.padRight(14)} ${e.value}');
  }
}

Puzzle? _parse(String line) {
  try {
    return Puzzle(line);
  } catch (_) {
    return null;
  }
}

const _usage = '''
Usage: dart run bin/up_ease.dart [options]

Dry-run "up-easing": remove one constraint at a time from easy candidates and
report whether any removal re-classifies the puzzle as advanced/strong while
staying uniquely solvable. Writes nothing.

Options:
  --input PATH      Candidate file (default: assets/complicity-recycling-candidates.txt)
  --sample N        Process at most N candidates (seeded shuffle)
  --seed N          Sampling seed (default: 42)
  --timeout-ms MS   Per-solve budget (default: 30000)
  --max-removals N  Constraints to try removing per puzzle (default: 30)
  --progress N      Report progress every N puzzles (default: 10)
  -v, --verbose     Per-removal line
  -h, --help        Show this help
''';
