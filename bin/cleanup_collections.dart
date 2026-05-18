// Identify and (optionally) remove low-value puzzles from the playable
// collections. Three independent passes, each gated by its own flag:
//
//   --disliked   Drop puzzles that appear with a `disliked` timestamp
//                in stats_aggregated/*.txt. Cross-reference is done
//                via `canonicalPuzzleKey` so format drift and rotation
//                don't break the match.
//
//   --boring     Drop puzzles whose deduction trace is dominated by
//                trivial Forbidden-Motif constraints (the 1×2 / 2×1
//                FM variants — FM:11, FM:1.1, FM:12, FM:1.2, FM:22,
//                FM:2.2, FM:21, FM:2.1). Threshold tunable via
//                --boring-threshold (default 0.9). Easiest collections
//                are exempt by default — beginners need those puzzles
//                — toggle with --no-exempt-easiest.
//
// Without --apply the script just prints what *would* be removed. With
// --apply each modified collection is rewritten to `<path>.cleanup`;
// the user mv's it into place after reviewing the diff.
//
// Usage:
//   dart run bin/cleanup_collections.dart [--disliked] [--boring]
//                                          [--apply]
//                                          [--min-dislikes N]
//                                          [--boring-threshold X]
//                                          [--boring-min-moves N]
//                                          [--no-exempt-easiest]
//                                          [--sample N]
//                                          [--timeout-ms MS]
//                                          [--stats-dir DIR]
//                                          [--verbose]
//
// If neither --disliked nor --boring is passed, both run.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

const _collections = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/overfilled-easy.txt',
  'assets/overfilled.txt',
];

// Collections exempt from the "boring" pass by default: beginners are
// the audience these trivial-FM puzzles are written for, removing them
// here would gut the onboarding catalog.
const _exemptedFromBoring = {'assets/1-easy.txt', 'assets/overfilled-easy.txt'};

// Trivial-FM serializations: every 1×2 and 2×1 forbidden motif (two
// cells side-by-side or stacked). Weight 0 in the complexity scale —
// the player reads the deduction off without reasoning. Stored as the
// exact `Constraint.serialize()` output so they match what
// `SolveStep.constraint` reports.
const _trivialFMs = {
  'FM:11', 'FM:22', 'FM:12', 'FM:21', // 1×2 horizontal
  'FM:1.1', 'FM:2.2', 'FM:1.2', 'FM:2.1', // 2×1 vertical
};

class _PuzzleLoc {
  final String file;
  final String line;
  _PuzzleLoc(this.file, this.line);
}

class _Args {
  bool runDisliked = false;
  bool runBoring = false;
  bool apply = false;
  bool verbose = false;
  bool exemptEasiest = true;
  int minDislikes = 1;
  double boringThreshold = 0.9;
  int boringMinMoves = 5;
  int? sample;
  int timeoutMs = 15000;
  String statsDir = 'stats_aggregated';
}

void main(List<String> args) {
  final a = _Args();

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--disliked':
        a.runDisliked = true;
      case '--boring':
        a.runBoring = true;
      case '--apply':
        a.apply = true;
      case '-v':
      case '--verbose':
        a.verbose = true;
      case '--no-exempt-easiest':
        a.exemptEasiest = false;
      case '--min-dislikes':
        a.minDislikes = int.parse(args[++i]);
      case '--boring-threshold':
        a.boringThreshold = double.parse(args[++i]);
      case '--boring-min-moves':
        a.boringMinMoves = int.parse(args[++i]);
      case '--sample':
        a.sample = int.parse(args[++i]);
      case '--timeout-ms':
        a.timeoutMs = int.parse(args[++i]);
      case '--stats-dir':
        a.statsDir = args[++i];
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        _printUsage();
        exit(1);
    }
  }

  // Default: run all passes.
  if (!a.runDisliked && !a.runBoring) {
    a.runDisliked = true;
    a.runBoring = true;
  }

  stderr.writeln('Loading collections...');
  final byKey = _loadCollections();
  final byFile = _groupByFile(byKey);
  stderr.writeln(
    '  ${byKey.length} unique puzzles across ${byFile.length} collections',
  );

  // Each pass populates this set with canonical keys to drop. Applied
  // together at the end so a puzzle flagged by either pass is removed
  // exactly once.
  final toRemove = <String>{};
  final reasons = <String, String>{};

  if (a.runDisliked) {
    stderr.writeln('');
    stderr.writeln('=== PASS 1: disliked puzzles ===');
    final dislikes = _loadDislikes(a.statsDir);
    stderr.writeln(
      '  ${dislikes.length} unique disliked puzzles across stats files',
    );
    _reportAndCollectDisliked(byKey, dislikes, a, toRemove, reasons);
  }

  if (a.runBoring) {
    stderr.writeln('');
    stderr.writeln('=== PASS 2: trivial-FM-dominated puzzles ===');
    _reportAndCollectBoring(byKey, a, toRemove, reasons);
  }

  stderr.writeln('');
  stderr.writeln('=== TOTAL ===');
  stderr.writeln(
    '  ${toRemove.length} puzzles flagged for removal '
    '(${(toRemove.length / byKey.length * 100).toStringAsFixed(1)}% of corpus)',
  );

  if (toRemove.isEmpty) return;

  // Per-file breakdown of the removal set.
  final perFile = <String, int>{};
  for (final key in toRemove) {
    final loc = byKey[key];
    if (loc != null) perFile.update(loc.file, (v) => v + 1, ifAbsent: () => 1);
  }
  for (final path in _collections) {
    final n = perFile[path] ?? 0;
    if (n > 0) {
      final total = byFile[path]?.length ?? 0;
      stderr.writeln(
        '  $path: $n / $total (${(n / total * 100).toStringAsFixed(1)}%)',
      );
    }
  }

  if (!a.apply) {
    stderr.writeln('');
    stderr.writeln(
      '(dry-run, no files written — pass --apply to write .cleanup files)',
    );
    return;
  }

  stderr.writeln('');
  stderr.writeln('Writing .cleanup files...');
  _writeCleanupFiles(byFile, toRemove, reasons, verbose: a.verbose);
}

Map<String, _PuzzleLoc> _loadCollections() {
  final out = <String, _PuzzleLoc>{};
  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  warn: $path not found, skipping');
      continue;
    }
    final lines = file.readAsLinesSync();
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        continue;
      }
      // Collections may carry a same puzzle in two files (e.g. before a
      // recompute --route): keep the first occurrence, the writer pass
      // visits each file independently anyway.
      out.putIfAbsent(key, () => _PuzzleLoc(path, line));
    }
  }
  return out;
}

Map<String, List<String>> _groupByFile(Map<String, _PuzzleLoc> byKey) {
  final out = <String, List<String>>{};
  for (final entry in byKey.entries) {
    out.putIfAbsent(entry.value.file, () => []).add(entry.key);
  }
  return out;
}

/// Scan stats_aggregated/*.txt for entries with a disliked timestamp
/// (the SLD code is `__D`). Returns canonical-key → dislike count.
/// Multiple plays of the same puzzle by the same player count once
/// each — that's the raw signal; the threshold is `--min-dislikes`.
Map<String, int> _loadDislikes(String statsDir) {
  final counts = <String, int>{};
  final dir = Directory(statsDir);
  if (!dir.existsSync()) {
    stderr.writeln('  warn: $statsDir not found, no dislikes loaded');
    return counts;
  }
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.txt')) continue;
    for (final raw in entity.readAsLinesSync()) {
      final entry = StatEntry.parse(raw);
      if (entry == null || entry.disliked == null) continue;
      String key;
      try {
        key = canonicalPuzzleKey(entry.puzzleLine);
      } catch (_) {
        continue;
      }
      counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

void _reportAndCollectDisliked(
  Map<String, _PuzzleLoc> byKey,
  Map<String, int> dislikes,
  _Args args,
  Set<String> toRemove,
  Map<String, String> reasons,
) {
  // Intersection: disliked puzzles that are still in a collection.
  final hits = <String, int>{};
  for (final entry in dislikes.entries) {
    if (!byKey.containsKey(entry.key)) continue;
    if (entry.value < args.minDislikes) continue;
    hits[entry.key] = entry.value;
  }
  stderr.writeln(
    '  ${hits.length} disliked puzzles found in collections '
    '(min-dislikes=${args.minDislikes})',
  );

  // Per-file breakdown so the user sees where dislikes concentrate.
  final perFile = <String, int>{};
  for (final key in hits.keys) {
    perFile.update(byKey[key]!.file, (v) => v + 1, ifAbsent: () => 1);
  }
  for (final path in _collections) {
    final n = perFile[path] ?? 0;
    if (n > 0) stderr.writeln('    $path: $n');
  }

  for (final entry in hits.entries) {
    toRemove.add(entry.key);
    reasons[entry.key] = 'disliked x${entry.value}';
    if (args.verbose) {
      final loc = byKey[entry.key]!;
      stderr.writeln(
        '    ${loc.file}: disliked x${entry.value}  ${_preview(loc.line)}',
      );
    }
  }
}

void _reportAndCollectBoring(
  Map<String, _PuzzleLoc> byKey,
  _Args args,
  Set<String> toRemove,
  Map<String, String> reasons,
) {
  // Pre-filter by constraint slug: a puzzle with no trivial-FM
  // constraint can't be trivial-FM dominated, no need to solve it.
  final candidates = <String>[];
  for (final entry in byKey.entries) {
    if (args.exemptEasiest && _exemptedFromBoring.contains(entry.value.file)) {
      continue;
    }
    if (_hasTrivialFM(entry.value.line)) candidates.add(entry.key);
  }
  stderr.writeln(
    '  ${candidates.length} puzzles carry at least one trivial-FM constraint '
    '(${args.exemptEasiest ? "easiest exempted" : "all collections included"})',
  );

  if (args.sample != null && args.sample! < candidates.length) {
    candidates.length = args.sample!;
    stderr.writeln('  sampling first ${args.sample} for the trace pass');
  }

  int processed = 0;
  int flagged = 0;
  final perFile = <String, int>{};
  final sw = Stopwatch()..start();

  for (final key in candidates) {
    final loc = byKey[key]!;
    final ratio = _trivialFMRatio(loc.line, args);
    processed++;
    if (ratio == null) {
      // Skipped: too few moves or solve failed. Not flagged.
    } else if (ratio >= args.boringThreshold) {
      toRemove.add(key);
      reasons[key] = 'trivial-FM ${(ratio * 100).toStringAsFixed(0)}%';
      perFile.update(loc.file, (v) => v + 1, ifAbsent: () => 1);
      flagged++;
      if (args.verbose) {
        stderr.writeln(
          '    ${loc.file}: trivial-FM ${(ratio * 100).toStringAsFixed(0)}%  '
          '${_preview(loc.line)}',
        );
      }
    }
    if (processed % 200 == 0) {
      stderr.write(
        '\r  $processed/${candidates.length} traced, $flagged flagged...   ',
      );
    }
  }
  stderr.writeln(
    '\r  $processed traced in ${sw.elapsed.inSeconds}s, $flagged flagged       ',
  );
  for (final path in _collections) {
    final n = perFile[path] ?? 0;
    if (n > 0) stderr.writeln('    $path: $n');
  }
}

/// Cheap check: does the constraints field carry any trivial-FM slug?
/// Avoids a full Puzzle parse + solve on the bulk of the corpus.
bool _hasTrivialFM(String line) {
  // Field 4 (0-indexed) is the constraints list.
  final parts = line.split('_');
  if (parts.length < 5) return false;
  final field = parts[4];
  for (final c in field.split(';')) {
    if (_trivialFMs.contains(c)) return true;
  }
  return false;
}

/// Solve the puzzle and return the fraction of propagation moves
/// attributed to a trivial-FM slug. Returns `null` when the puzzle
/// has too few propagation moves to be meaningful, or when the
/// solver couldn't finish — in both cases we don't flag the puzzle.
double? _trivialFMRatio(String line, _Args args) {
  try {
    final puzzle = Puzzle(line);
    final steps = puzzle.solveExplained(timeoutMs: args.timeoutMs);
    int propMoves = 0;
    int trivialMoves = 0;
    for (final s in steps) {
      if (s.method != SolveMethod.propagation) continue;
      propMoves++;
      if (_trivialFMs.contains(s.constraint)) trivialMoves++;
    }
    if (propMoves < args.boringMinMoves) return null;
    return trivialMoves / propMoves;
  } catch (_) {
    return null;
  }
}

void _writeCleanupFiles(
  Map<String, List<String>> byFile,
  Set<String> toRemove,
  Map<String, String> reasons, {
  required bool verbose,
}) {
  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final originalLines = file.readAsLinesSync();
    final kept = <String>[];
    int dropped = 0;
    for (final line in originalLines) {
      if (line.trim().isEmpty || line.startsWith('#')) {
        kept.add(line);
        continue;
      }
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        kept.add(line);
        continue;
      }
      if (toRemove.contains(key)) {
        dropped++;
        if (verbose) {
          stderr.writeln('  drop $path: ${reasons[key]}  ${_preview(line)}');
        }
        continue;
      }
      kept.add(line);
    }
    if (dropped == 0) continue;
    final outPath = '$path.cleanup';
    File(outPath).writeAsStringSync('${kept.join('\n')}\n');
    stderr.writeln('  $outPath: $dropped removed, ${kept.length} kept');
  }
}

String _preview(String line) {
  return line.length > 90 ? '${line.substring(0, 87)}...' : line;
}

void _printUsage() {
  stderr.writeln('''
Usage: dart run bin/cleanup_collections.dart [options]

Passes (run both by default):
  --disliked              Flag puzzles disliked in stats_aggregated/*.txt
  --boring                Flag puzzles where >threshold of propagation
                          moves come from trivial-FM constraints

Options:
  --apply                 Write <path>.cleanup files. Without it, only
                          report what would be removed.
  --min-dislikes N        Drop puzzles disliked >= N times (default 1)
  --boring-threshold X    Trivial-FM share above which a puzzle is
                          "boring" (default 0.9)
  --boring-min-moves N    Skip puzzles with fewer propagation moves
                          (default 5) — too short to be meaningful
  --no-exempt-easiest     Include 1-easy.txt and overfilled-easy.txt
                          in the boring pass (off by default — those
                          puzzles are *meant* to teach trivial-FM)
  --sample N              Cap the boring pass to N candidates (dev aid)
  --timeout-ms MS         Per-puzzle solver timeout (default 15000)
  --stats-dir DIR         Stats directory (default stats_aggregated)
  -v, --verbose           Per-puzzle removal lines
  -h, --help              Show this help
''');
}
