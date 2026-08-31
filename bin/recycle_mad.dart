// Recycling step: convert a mad-overflow feed into puzzles for the deficient
// collections via target-level readonly-easing.
//
// Background (docs/dev/collection_management.md, "Collection orchestrator and
// puzzle recycling"): free generation over-produces 6-mad. Instead of
// discarding the excess, this step eases each mad line down with
// `EaseObjective.targetLevel` (lib/getsomepuzzle/recycle.dart) and routes the
// landed result into its `classifyTrace` collection. The landing experiment
// (bin/experiment_landing.dart) measured that targeting `player` lands ~58 %
// exactly (feeds 2-player, with beginner/expert fallouts) and targeting
// `expert` lands ~54 % exactly (feeds 5-expert); `strong`/`advanced` stay
// structurally hard.
//
// Per line the step aims at the first `--targets` entry whose collection is
// still below `--cap` (live-balanced: routed lines increment the count, so
// once 2-player reaches the cap, later lines aim at 5-expert). Routing is by
// the puzzle's *actual* final level, so fallouts land where they belong.
//
// Default is a dry-run report. `--apply` writes the new lines into
// `assets/<level>.txt` via a `<file>.recycle` staging file that is renamed
// over the original (existing lines preserved verbatim; canonical-key
// duplicates skipped), so `git diff` shows exactly what moved. It also
// *consumes* the feed: lines that were successfully routed are removed from
// the feed file, and lines that stayed mad are parked in
// `assets/6-mad-stuck.txt` (or `--emit-mad PATH`) and also removed, so the
// feed converges to just the unparsable lines instead of being re-read in full
// every run. `--sample` skips consumption (it only processes a subset).
//
// Under `--apply`, progress is flushed to disk every `--checkpoint` lines
// (default 200): routed lines are appended to their destination files and
// stayed-mad lines to the stuck file, then both are consumed from the feed —
// all idempotently. An interrupted run therefore resumes on the next launch
// (the feed is exactly the remaining work) and the destination dedup skips
// lines already written.
//
// Usage:
//   dart run bin/recycle_mad.dart --feed assets/6-mad-recycled.txt
//                                 [--targets player,expert,strong]
//                                 [--cap 20000]
//                                 [--max-additions 20] [--candidate-cap 8]
//                                 [--timeout-ms 15000]
//                                 [--sample N] [--seed 42]
//                                 [--apply] [--emit-mad PATH]
//                                 [--verbose] [--help]

import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/recycle.dart';

/// Destination file per in-cascade level (the six playable collections).
const Map<PuzzleLevel, String> _levelToFile = {
  PuzzleLevel.beginner: 'assets/1-easy.txt',
  PuzzleLevel.player: 'assets/2-player.txt',
  PuzzleLevel.advanced: 'assets/3-advanced.txt',
  PuzzleLevel.strong: 'assets/4-strong.txt',
  PuzzleLevel.expert: 'assets/5-expert.txt',
  PuzzleLevel.mad: 'assets/6-mad.txt',
};

const _targetNames = {
  'player': PuzzleLevel.player,
  'advanced': PuzzleLevel.advanced,
  'strong': PuzzleLevel.strong,
  'expert': PuzzleLevel.expert,
};

/// Default sink for lines that stay mad under --apply (unless --emit-mad
/// overrides it). Keeps the feed shrinking instead of re-reading them.
const String _defaultStuckPath = 'assets/6-mad-stuck.txt';

String _stuckPath(_Args a) => a.emitMad ?? _defaultStuckPath;

class _Args {
  String feed = 'assets/6-mad-recycled.txt';
  List<PuzzleLevel> targets = const [
    PuzzleLevel.player,
    PuzzleLevel.expert,
    PuzzleLevel.strong,
  ];
  int cap = 20000;
  int maxAdditions = 20;
  int candidateCap = 8;
  int timeoutMs = 15000;
  int checkpoint = 200;
  int? sample;
  int seed = 42;
  bool apply = false;
  String? emitMad;
  bool verbose = false;
}

void main(List<String> args) {
  final a = _Args();

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--feed':
        a.feed = args[++i];
      case '--targets':
        final names = args[++i].split(',');
        final levels = <PuzzleLevel>[];
        for (final n in names) {
          final lvl = _targetNames[n.trim()];
          if (lvl == null) {
            stderr.writeln(
              '--targets accepts a comma list over {player,advanced,strong,expert} '
              '(got "$n")',
            );
            exit(1);
          }
          levels.add(lvl);
        }
        if (levels.isEmpty) {
          stderr.writeln('--targets must list at least one level');
          exit(1);
        }
        a.targets = levels;
      case '--cap':
        a.cap = int.parse(args[++i]);
      case '--max-additions':
        a.maxAdditions = int.parse(args[++i]);
      case '--candidate-cap':
        a.candidateCap = int.parse(args[++i]);
      case '--timeout-ms':
        a.timeoutMs = int.parse(args[++i]);
      case '--checkpoint':
        a.checkpoint = int.parse(args[++i]);
      case '--sample':
        a.sample = int.parse(args[++i]);
      case '--seed':
        a.seed = int.parse(args[++i]);
      case '--apply':
        a.apply = true;
      case '--emit-mad':
        a.emitMad = args[++i];
      case '-v':
      case '--verbose':
        a.verbose = true;
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

  final feedFile = File(a.feed);
  if (!feedFile.existsSync()) {
    stderr.writeln('Feed not found: ${a.feed}');
    exit(1);
  }
  var feedLines = feedFile
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();
  if (a.sample != null && a.sample! < feedLines.length) {
    final rng = Random(a.seed);
    feedLines = List<String>.from(feedLines)..shuffle(rng);
    feedLines = feedLines.take(a.sample!).toList();
  }
  stderr.writeln(
    'Feed: ${feedLines.length} lines from ${a.feed} '
    '(targets=${a.targets.map((t) => t.name).join(',')}, cap=${a.cap})',
  );

  // Current collection sizes — drives the open-target decision. Updated live
  // as lines are routed so balancing converges.
  final counts = <PuzzleLevel, int>{};
  for (final lvl in _levelToFile.keys) {
    counts[lvl] = _countLines(_levelToFile[lvl]!);
  }
  stderr.writeln('Current counts:');
  for (final lvl in _levelToFile.keys) {
    stderr.writeln('  ${_levelToFile[lvl]!.padRight(24)} ${counts[lvl] ?? 0}');
  }

  // Process.
  final landed = <PuzzleLevel, List<String>>{};
  final aimCounts = <PuzzleLevel, int>{};
  final madLines = <String>[];
  // Canonical keys of the *original feed lines* that were successfully routed
  // or stayed mad — both consumed from the feed under --apply. Only unparsable
  // lines are re-read next run.
  final routedKeys = <String>{};
  final madKeys = <String>{};
  int unparsable = 0;
  final sw = Stopwatch()..start();

  for (int k = 0; k < feedLines.length; k++) {
    final line = feedLines[k];
    final target = _pickTarget(a, counts);
    aimCounts[target] = (aimCounts[target] ?? 0) + 1;

    final e = _ease(line, a, target);
    if (e == null) {
      unparsable++;
      continue;
    }
    if (e.line != null && _levelToFile.containsKey(e.finalLevel)) {
      landed.putIfAbsent(e.finalLevel, () => []).add(e.line!);
      counts[e.finalLevel] = (counts[e.finalLevel] ?? 0) + 1; // live balance
      try {
        routedKeys.add(canonicalPuzzleKey(line));
      } catch (_) {}
    } else {
      madLines.add(line);
      try {
        madKeys.add(canonicalPuzzleKey(line));
      } catch (_) {}
    }
    if (a.verbose) {
      stderr.writeln(
        '[${k + 1}/${feedLines.length}] -> ${e.finalLevel.name} '
        '(+${e.readonlyAdded} cells, ${e.ms}ms)',
      );
    } else if ((k + 1) % 25 == 0) {
      stderr.write('\r  ${k + 1}/${feedLines.length} done...   ');
    }
    if (a.apply && a.checkpoint > 0 && (k + 1) % a.checkpoint == 0) {
      final addedNow = _apply(landed, quiet: true);
      final stuckNow = _writeStayedMad(_stuckPath(a), madLines);
      _consumeFeed(a, routedKeys, madKeys);
      if (addedNow == 0 && stuckNow == 0) {
        stderr.writeln(
          '  [checkpoint @ ${k + 1}/${feedLines.length}] nothing new to flush',
        );
      } else {
        stderr.writeln(
          '  [checkpoint @ ${k + 1}/${feedLines.length}] +$addedNow routed, +$stuckNow stayed-mad (resumable)',
        );
      }
    }
  }
  stderr.writeln(
    '\r  ${feedLines.length} lines processed in ${sw.elapsed.inSeconds}s',
  );

  _report(a, aimCounts, landed, madLines.length, unparsable);

  if (!a.apply && a.emitMad != null && madLines.isNotEmpty) {
    File(a.emitMad!).writeAsStringSync('${madLines.join('\n')}\n');
    stderr.writeln('Wrote ${madLines.length} stayed-mad lines to ${a.emitMad}');
  }

  if (a.apply) {
    _apply(landed, quiet: true);
    _writeStayedMad(_stuckPath(a), madLines);
    // Consume the feed: drop routed and stayed-mad lines so it converges to
    // just the unparsable lines (re-tried next run). Skipped under --sample.
    _consumeFeed(a, routedKeys, madKeys);
  } else {
    stderr.writeln('(dry-run — pass --apply to write the routed lines)');
  }
}

/// Rewrite the feed to remove the [routedKeys] and [madKeys] (lines that
/// landed in a collection or stayed mad this run), preserving comments/blanks
/// and every other line. Staged + renamed so an interrupted run never corrupts
/// the feed.
void _consumeFeed(_Args a, Set<String> routedKeys, Set<String> madKeys) {
  if (a.sample != null) return; // partial processing — do not rewrite
  if (routedKeys.isEmpty && madKeys.isEmpty) return;
  final file = File(a.feed);
  if (!file.existsSync()) return;
  final remaining = <String>[];
  int removed = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) {
      remaining.add(line);
      continue;
    }
    try {
      final key = canonicalPuzzleKey(line);
      if (routedKeys.contains(key) || madKeys.contains(key)) {
        removed++;
        continue;
      }
    } catch (_) {}
    remaining.add(line);
  }
  if (removed == 0) return;
  final tmpPath = '${a.feed}.consume';
  File(tmpPath).writeAsStringSync('${remaining.join('\n')}\n');
  File(tmpPath).renameSync(a.feed);
  stderr.writeln(
    '  ${a.feed}: consumed $removed lines '
    '(${remaining.where((l) => l.trim().isNotEmpty && !l.startsWith('#')).length} remain)',
  );
}

PuzzleLevel _pickTarget(_Args a, Map<PuzzleLevel, int> counts) {
  for (final t in a.targets) {
    if ((counts[t] ?? 0) < a.cap) return t;
  }
  return a.targets.first;
}

({String? line, PuzzleLevel finalLevel, int readonlyAdded, int ms})? _ease(
  String line,
  _Args a,
  PuzzleLevel target,
) {
  final Puzzle pu;
  try {
    pu = Puzzle(line);
  } catch (_) {
    return null;
  }
  final solved = pu.clone();
  if (!solved.solve()) return null;
  final r = easePuzzle(
    pu,
    solved.cellValues,
    EaseOptions(
      target: target,
      objective: EaseObjective.targetLevel,
      maxAdditions: a.maxAdditions,
      candidateCap: a.candidateCap,
      timeoutMs: a.timeoutMs,
    ),
  );
  return (
    line: r.line,
    finalLevel: r.finalLevel,
    readonlyAdded: r.readonlyAdded,
    ms: r.ms,
  );
}

void _report(
  _Args a,
  Map<PuzzleLevel, int> aimCounts,
  Map<PuzzleLevel, List<String>> landed,
  int stayedMad,
  int unparsable,
) {
  stdout.writeln('');
  stdout.writeln('=== RECYCLE REPORT ===');
  stdout.writeln(
    'Targets (priority): ${a.targets.map((t) => t.name).join(', ')}',
  );
  stdout.writeln('Aimed at:');
  for (final t in a.targets) {
    stdout.writeln('  ${t.name.padRight(10)} ${aimCounts[t] ?? 0}');
  }
  stdout.writeln('Unparsable/unsolvable: $unparsable');
  stdout.writeln('Stayed mad (not routed): $stayedMad');

  final routed = landed.values.fold<int>(0, (s, l) => s + l.length);
  stdout.writeln('');
  stdout.writeln(
    'Routed $routed lines by final level${a.apply ? ' (applied)' : ' (dry-run)'}:',
  );
  final allLevels = _levelToFile.keys.toList();
  for (final lvl in allLevels) {
    final n = landed[lvl]?.length ?? 0;
    if (n == 0 && !a.verbose) continue;
    stdout.writeln('  ${_levelToFile[lvl]!.padRight(24)} +$n');
  }
}

/// Append the routed lines to their destination files, deduped against the
/// existing content by canonical key, via a `<file>.recycle` staging file
/// renamed over the original.
int _apply(Map<PuzzleLevel, List<String>> landed, {bool quiet = false}) {
  if (!quiet) {
    stderr.writeln('');
    stderr.writeln('Writing routed lines...');
  }
  var totalAdded = 0;
  for (final entry in landed.entries) {
    final path = _levelToFile[entry.key]!;
    final existing = File(path).existsSync()
        ? File(path).readAsLinesSync()
        : <String>[];
    final existingKeys = <String>{};
    for (final l in existing) {
      if (l.trim().isEmpty || l.startsWith('#')) continue;
      try {
        existingKeys.add(canonicalPuzzleKey(l));
      } catch (_) {}
    }
    final added = <String>[];
    for (final l in entry.value) {
      try {
        if (existingKeys.add(canonicalPuzzleKey(l))) added.add(l);
      } catch (_) {}
    }
    if (added.isEmpty) {
      if (!quiet) stderr.writeln('  $path: nothing new (all duplicates)');
      continue;
    }
    final tmpPath = '$path.recycle';
    File(tmpPath).writeAsStringSync('${[...existing, ...added].join('\n')}\n');
    File(tmpPath).renameSync(path);
    totalAdded += added.length;
    stderr.writeln(
      '  $path: +${added.length} (${existing.length} -> ${existing.length + added.length})',
    );
  }
  return totalAdded;
}

/// Append the stayed-mad lines to [path], deduped by canonical key, via a
/// `<path>.stuck` staging file renamed over the original. Returns the number
/// of new lines actually written (0 when all were already parked).
int _writeStayedMad(String path, List<String> lines) {
  final existing = File(path).existsSync()
      ? File(path).readAsLinesSync()
      : <String>[];
  final existingKeys = <String>{};
  for (final l in existing) {
    if (l.trim().isEmpty || l.startsWith('#')) continue;
    try {
      existingKeys.add(canonicalPuzzleKey(l));
    } catch (_) {}
  }
  final added = <String>[];
  for (final l in lines) {
    try {
      if (existingKeys.add(canonicalPuzzleKey(l))) added.add(l);
    } catch (_) {}
  }
  if (added.isEmpty) return 0;
  final tmpPath = '$path.stuck';
  File(tmpPath).writeAsStringSync('${[...existing, ...added].join('\n')}\n');
  File(tmpPath).renameSync(path);
  stderr.writeln(
    '  $path: +${added.length} stayed-mad '
    '(${existing.length} -> ${existing.length + added.length})',
  );
  return added.length;
}

int _countLines(String path) {
  final f = File(path);
  if (!f.existsSync()) return 0;
  var n = 0;
  for (final l in f.readAsLinesSync()) {
    if (l.trim().isEmpty || l.startsWith('#')) continue;
    n++;
  }
  return n;
}

void _printUsage() {
  stderr.writeln('''
Usage: dart run bin/recycle_mad.dart [options]

Recycling step: ease a mad-overflow feed down into the deficient collections
via target-level readonly-easing (lib/getsomepuzzle/recycle.dart), routing
each landed line into its classifyTrace collection.

Options:
  --feed PATH          Mad overflow feed (default: assets/6-mad-recycled.txt)
  --targets LIST       Target priority, comma list over
                       {player,advanced,strong,expert}
                       (default: player,expert,strong). Per line, aims at the
                       first target whose collection is below --cap.
  --cap N              Collection cap for the open-target decision
                       (default: 20000)
  --max-additions N    Readonly-cell cap per puzzle (default: 20)
  --candidate-cap N    Free cells to try per step (default: 8)
  --timeout-ms MS      Per-solve budget (default: 15000)
  --checkpoint N       Flush routed lines to disk every N lines under
                       --apply (default: 200); 0 disables mid-run flush
  --sample N           Process at most N feed lines (seeded shuffle)
  --seed N             Sampling seed (default: 42)
  --apply              Write routed lines into assets/<level>.txt, park
                       stayed-mad lines in the stuck file, and consume both
                       from the feed, flushing every --checkpoint lines so an
                       interrupted run resumes on relaunch (default: dry-run)
  --emit-mad PATH      Park stayed-mad lines in PATH instead of the default
                       assets/6-mad-stuck.txt (dry-run: dump only)
  -v, --verbose        Per-line progress
  -h, --help           Show this help
''');
}
