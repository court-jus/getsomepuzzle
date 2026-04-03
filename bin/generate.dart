import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main(List<String> args) {
  final parsed = _parseArgs(args);

  final mode = parsed['mode'] as String;
  switch (mode) {
    case 'generate':
      _runGenerate(parsed);
    case 'check':
      _runCheck(parsed['checkFile'] as String);
  }
}

// --- Generate mode ---

void _runGenerate(Map<String, dynamic> parsed) {
  final count = parsed['count'] as int;
  final minWidth = parsed['minWidth'] as int;
  final maxWidth = parsed['maxWidth'] as int;
  final minHeight = parsed['minHeight'] as int;
  final maxHeight = parsed['maxHeight'] as int;
  final output = parsed['output'] as String?;
  final bannedRules = (parsed['banned'] as String?)?.split(',').toSet() ?? {};
  final requiredRules = (parsed['required'] as String?)?.split(',').toSet() ?? {};

  final rng = Random();
  IOSink? sink;
  if (output != null) {
    sink = File(output).openWrite(mode: FileMode.append);
  }

  int generated = 0;
  int attempts = 0;
  final totalSw = Stopwatch()..start();
  final puzzleSw = Stopwatch();
  final durations = <int>[];

  void finish() {
    stderr.writeln('');
    stderr.writeln('Done: $generated puzzles in ${_fmt(totalSw.elapsed)} ($attempts attempts)');
    if (durations.isNotEmpty) {
      stderr.writeln('  avg: ${_avgMs(durations)}ms, median: ${_medianMs(durations)}ms, '
          'min: ${durations.reduce(min)}ms, max: ${durations.reduce(max)}ms');
    }
    sink?.close();
  }

  ProcessSignal.sigint.watch().listen((_) {
    finish();
    exit(0);
  });

  while (generated < count) {
    attempts++;
    final width = minWidth + rng.nextInt(maxWidth - minWidth + 1);
    final height = minHeight + rng.nextInt(maxHeight - minHeight + 1);

    if (!puzzleSw.isRunning) puzzleSw..reset()..start();

    final config = GeneratorConfig(
      width: width,
      height: height,
      requiredRules: requiredRules,
      bannedRules: bannedRules,
      count: 1,
    );

    final line = PuzzleGenerator.generateOne(
      config,
      onProgress: (p) {
        stderr.write(
          '\r[${_fmt(totalSw.elapsed)}] $generated/$count '
          '| attempt $attempts, ${width}x$height, '
          '${p.constraintsTried}/${p.constraintsTotal} constraints'
          '          ',
        );
      },
    );

    if (line != null) {
      generated++;
      puzzleSw.stop();
      durations.add(puzzleSw.elapsedMilliseconds);
      puzzleSw.reset();

      if (sink != null) {
        sink.writeln(line);
        sink.flush();
      } else {
        stdout.writeln(line);
      }

      stderr.write(
        '\r[${_fmt(totalSw.elapsed)}] $generated/$count '
        '| avg ${_avgMs(durations)}ms, med ${_medianMs(durations)}ms'
        '                                        \n',
      );
    }
  }

  finish();
}

// --- Check mode ---

void _runCheck(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $filePath');
    exit(1);
  }
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty && !l.startsWith('#')).toList();
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
        stderr.writeln('  INVALID (${solutions} solutions): $line');
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
  stderr.writeln('Done in ${_fmt(sw.elapsed)}: $valid valid, $invalid invalid out of ${lines.length}');
  if (invalid > 0) exit(1);
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
    'output': null,
    'banned': null,
    'required': null,
    'checkFile': null,
  };

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        result['mode'] = 'check';
        result['checkFile'] = args[++i];
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
  stderr.writeln('''
Usage: dart run bin/generate.dart [options]

Modes:
  (default)               Generate puzzles
  --check FILE            Validate puzzles from file (1 solution each)

Generation options:
  -n, --count N           Number of puzzles to generate (default: 10)
  -W, --min-width N       Minimum grid width (default: 4)
      --max-width N       Maximum grid width (default: 7)
  -H, --min-height N      Minimum grid height (default: 4)
      --max-height N      Maximum grid height (default: 8)
  -o, --output FILE       Output file (default: stdout)
      --ban RULES         Comma-separated rule slugs to exclude (e.g. FM,LT)
      --require RULES     Comma-separated rule slugs to require (e.g. PA,GS)

General:
  -h, --help              Show this help

Rule slugs: FM (forbidden motif), PA (parity), GS (group size),
            LT (letter group), QA (quantity), SY (symmetry)

Examples:
  dart run bin/generate.dart -n 100 -o puzzles.txt
  dart run bin/generate.dart --check assets/try_me.txt
''');
}
