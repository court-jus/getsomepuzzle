import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);

  final mode = parsed['mode'] as String;
  switch (mode) {
    case 'generate':
      await _runGenerate(parsed);
    case 'check':
      _runCheck(parsed['checkFile'] as String);
    case 'read-stats':
      _runReadStats(parsed['statsDir'] as String);
  }
}

// --- Generate mode ---

Future<void> _runGenerate(Map<String, dynamic> parsed) async {
  final count = parsed['count'] as int;
  final minWidth = parsed['minWidth'] as int;
  final maxWidth = parsed['maxWidth'] as int;
  final minHeight = parsed['minHeight'] as int;
  final maxHeight = parsed['maxHeight'] as int;
  final maxTime = parsed['maxTime'] as int;
  final output = parsed['output'] as String?;
  final bannedRules = (parsed['banned'] as String?)?.split(',').toSet() ?? {};
  final requiredRules =
      (parsed['required'] as String?)?.split(',').toSet() ?? {};

  IOSink? sink;
  if (output != null) {
    sink = File(output).openWrite(mode: FileMode.append);
  }

  // Load existing collection stats if output file exists
  final usageStats = <String, int>{};
  if (output != null && File(output).existsSync()) {
    final existing = File(output).readAsLinesSync();
    usageStats.addAll(PuzzleGenerator.computeUsageStats(existing));
    stderr.writeln(
      'Loaded ${existing.where((l) => l.trim().isNotEmpty).length} existing puzzles',
    );
    _printHistogram(usageStats);
  }

  int generated = 0;
  final totalSw = Stopwatch()..start();
  final durations = <int>[];
  int histLines = 0; // number of histogram lines currently displayed
  int lastPuzzleMs = 0;

  bool finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    stderr.writeln('');
    stderr.writeln('Done: $generated puzzles in ${_fmt(totalSw.elapsed)}');
    if (durations.isNotEmpty) {
      stderr.writeln(
        '  avg: ${_avgMs(durations)}ms, median: ${_medianMs(durations)}ms, '
        'min: ${durations.reduce(min)}ms, max: ${durations.reduce(max)}ms',
      );
    }
    sink?.close();
    exit(0);
  }

  final config = GeneratorConfig(
    width: minWidth,
    height: minHeight,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
    maxTime: Duration(seconds: maxTime),
    requiredRules: requiredRules,
    bannedRules: bannedRules,
    count: count,
  );

  final worker = GeneratorWorker();
  final stream = worker.start(config, usageStats: usageStats);

  ProcessSignal.sigint.watch().listen((_) {
    worker.cancel();
    finish();
    exit(0);
  });

  await for (final message in stream) {
    switch (message) {
      case GeneratorProgressMessage(:final progress):
        stderr.write(
          '\r[${_fmt(totalSw.elapsed)}] $generated/$count '
          '| ${progress.constraintsTried}/${progress.constraintsTotal} constraints'
          '          ',
        );
      case GeneratorPuzzleMessage(:final puzzleLine):
        generated++;
        final now = totalSw.elapsedMilliseconds;
        durations.add(now - lastPuzzleMs);
        lastPuzzleMs = now;

        if (sink != null) {
          sink.writeln(puzzleLine);
        } else {
          stdout.writeln(puzzleLine);
        }

        // Update local usage stats for histogram display
        final parts = puzzleLine.split('_');
        if (parts.length >= 5) {
          final newSlugs = parts[4]
              .split(';')
              .map((c) => c.split(':').first)
              .where((s) => s.isNotEmpty)
              .toSet();
          for (final slug in newSlugs) {
            usageStats[slug] = (usageStats[slug] ?? 0) + 1;
          }
        }

        // Clear previous histogram + progress line
        if (histLines > 0) {
          stderr.write('\x1B[${histLines + 1}A\x1B[J');
        } else {
          stderr.write('\r\x1B[K');
        }

        // Progress line
        stderr.writeln(
          '[${_fmt(totalSw.elapsed)}] $generated/$count '
          '| avg ${_avgMs(durations)}ms, med ${_medianMs(durations)}ms',
        );

        // Histogram
        histLines = _printHistogram(usageStats);
      case GeneratorDoneMessage():
        break;
    }
  }

  finish();
}

int _printHistogram(Map<String, int> stats) {
  if (stats.isEmpty) return 0;
  final sorted = stats.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final maxVal = sorted.first.value;
  const barWidth = 30;
  int lines = 0;
  for (final entry in sorted) {
    final bar = maxVal > 0
        ? '█' * ((entry.value / maxVal * barWidth).round())
        : '';
    stderr.writeln('  ${entry.key.padRight(3)} $bar ${entry.value}');
    lines++;
  }
  return lines;
}

// --- Check mode ---

void _runCheck(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $filePath');
    exit(1);
  }
  final lines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();
  stderr.writeln('Checking ${lines.length} puzzles from $filePath...');

  int valid = 0;
  int invalid = 0;
  final sw = Stopwatch()..start();

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    try {
      final p = Puzzle(line);
      final solutions = p.countSolutions();
      if (solutions == 1) {
        valid++;
      } else {
        invalid++;
        stderr.writeln('  INVALID ($solutions solutions): $line');
      }
    } catch (e) {
      invalid++;
      stderr.writeln('  ERROR: $line ($e)');
    }
    if ((i + 1) % 10 == 0) {
      stderr.write('\r  ${i + 1}/${lines.length} checked...          ');
    }
  }

  stderr.writeln('');
  stderr.writeln(
    'Done in ${_fmt(sw.elapsed)}: $valid valid, $invalid invalid out of ${lines.length}',
  );
  if (invalid > 0) exit(1);
}

// --- Read-stats mode ---

void _runReadStats(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    stderr.writeln('Directory not found: $dirPath');
    exit(1);
  }

  final allLines = <String>[];
  int filesRead = 0;
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    if (entity.path.endsWith('sorted_puzzles.txt')) continue;
    filesRead++;
    allLines.addAll(entity.readAsLinesSync());
  }

  stderr.writeln('Read $filesRead files');

  final stats = aggregateStats(allLines);
  final sorted = sortPuzzlesByDifficulty(stats);

  for (final puzzle in sorted) {
    stdout.writeln(puzzle);
  }

  stderr.writeln('Sorted ${sorted.length} puzzles by difficulty');
  if (sorted.isNotEmpty) {
    final easiest = stats[sorted.first]!;
    final hardest = stats[sorted.last]!;
    stderr.writeln(
      '  easiest: level ${easiest.level} (${easiest.total} plays)',
    );
    stderr.writeln(
      '  hardest: level ${hardest.level} (${hardest.total} plays)',
    );
  }
}

// --- Utilities ---

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}m${s.toString().padLeft(2, '0')}s' : '${d.inSeconds}s';
}

int _avgMs(List<int> durations) {
  if (durations.isEmpty) return 0;
  return durations.reduce((a, b) => a + b) ~/ durations.length;
}

int _medianMs(List<int> durations) {
  if (durations.isEmpty) return 0;
  final sorted = List<int>.from(durations)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) ~/ 2;
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final result = <String, dynamic>{
    'mode': 'generate',
    'count': 10,
    'minWidth': 4,
    'maxWidth': 7,
    'minHeight': 4,
    'maxHeight': 8,
    'maxTime': 60,
    'output': null,
    'banned': null,
    'required': null,
    'checkFile': null,
    'statsDir': null,
  };

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        result['mode'] = 'check';
        result['checkFile'] = args[++i];
      case '--read-stats':
        result['mode'] = 'read-stats';
        result['statsDir'] = args[++i];
      case '-n':
      case '--count':
        result['count'] = int.parse(args[++i]);
      case '-W':
      case '--min-width':
        result['minWidth'] = int.parse(args[++i]);
      case '--max-width':
        result['maxWidth'] = int.parse(args[++i]);
      case '-H':
      case '--min-height':
        result['minHeight'] = int.parse(args[++i]);
      case '--max-height':
        result['maxHeight'] = int.parse(args[++i]);
      case '-T':
      case '--max-time':
        result['maxTime'] = int.parse(args[++i]);
      case '-o':
      case '--output':
        result['output'] = args[++i];
      case '--ban':
        result['banned'] = args[++i];
      case '--require':
        result['required'] = args[++i];
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

  if (result['maxWidth'] < result['minWidth']) {
    result['maxWidth'] = result['minWidth'];
  }
  if (result['maxHeight'] < result['minHeight']) {
    result['maxHeight'] = result['minHeight'];
  }

  return result;
}

void _printUsage() {
  final String rules = constraintRegistry
      .map((regEntry) => "${regEntry.slug} (${regEntry.label})")
      .join(", ");
  stderr.writeln('''
Usage: dart run bin/generate.dart [options]

Modes:
  (default)               Generate puzzles
  --check FILE            Validate puzzles from file (1 solution each)
  --read-stats DIR        Aggregate play stats, output puzzles sorted by difficulty

Generation options:
  -n, --count N           Number of puzzles to generate (default: 10)
  -W, --min-width N       Minimum grid width (default: 4)
      --max-width N       Maximum grid width (default: 7)
  -H, --min-height N      Minimum grid height (default: 4)
      --max-height N      Maximum grid height (default: 8)
  -T, --max-time S        Maximum generation time (in seconds, default: 60)
  -o, --output FILE       Output file (default: stdout)
      --ban RULES         Comma-separated rule slugs to exclude (e.g. FM,LT)
      --require RULES     Comma-separated rule slugs to require (e.g. PA,GS)

General:
  -h, --help              Show this help

Rule slugs: $rules

Examples:
  dart run bin/generate.dart -n 100 -o puzzles.txt
  dart run bin/generate.dart --check assets/try_me.txt
  dart run bin/generate.dart --read-stats ~/Documents/getsomepuzzle/
''');
}
