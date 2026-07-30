import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  String input = 'assets/2-player.txt';
  String output = 'single_path_puzzles.txt';
  bool verbose = false;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-i' || a == '--input') {
      if (i + 1 >= args.length) _die('missing value for $a');
      input = args[++i];
    } else if (a == '-o' || a == '--output') {
      if (i + 1 >= args.length) _die('missing value for $a');
      output = args[++i];
    } else if (a == '--verbose' || a == '-v') {
      verbose = true;
    } else if (a == '-h' || a == '--help') {
      stderr.writeln(
        'Usage: dart run bin/find_single_path_puzzles.dart '
        '[-i input.txt] [-o output.txt] [--verbose]',
      );
      exit(0);
    } else {
      _die('unknown argument: $a');
    }
  }

  final inputFile = File(input);
  if (!inputFile.existsSync()) _die('input file not found: $input');

  final lines = inputFile
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final outSink = File(output).openWrite();
  final stopwatch = Stopwatch()..start();

  int processed = 0;
  int kept = 0;
  final reasons = <String, int>{};

  for (final line in lines) {
    processed++;
    final result = _scanLine(line);
    if (result.kept) {
      outSink.writeln(line);
      kept++;
      if (verbose) stderr.writeln('[$processed] KEPT');
    } else {
      reasons[result.reason] = (reasons[result.reason] ?? 0) + 1;
      if (verbose) {
        stderr.writeln('[$processed] REJECTED — ${result.reason}');
      }
    }
    if (!verbose && processed % 100 == 0) {
      stderr.write('\r$processed/${lines.length} — $kept kept');
    }
  }

  outSink.close();
  stopwatch.stop();
  if (!verbose) stderr.writeln();
  stderr.writeln('Done in ${stopwatch.elapsed.inSeconds}s');
  stderr.writeln('Processed: $processed');
  stderr.writeln(
    'Kept (single-path): $kept '
    '(${(100.0 * kept / processed).toStringAsFixed(2)}%)',
  );
  stderr.writeln('Rejection reasons:');
  final sortedReasons = reasons.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedReasons) {
    stderr.writeln('  ${e.value}\t${e.key}');
  }
}

class _ScanResult {
  final bool kept;
  final String reason;
  _ScanResult.kept() : kept = true, reason = 'kept';
  _ScanResult.rejected(this.reason) : kept = false;
}

_ScanResult _scanLine(String line) {
  final Puzzle p;
  try {
    p = Puzzle(line);
  } catch (e) {
    return _ScanResult.rejected('parse error');
  }

  // Solve using the model (includes drain optimization). Works on a clone;
  // we replay the steps on `p` to advance the puzzle state.
  final steps = p.solveExplained();
  if (steps.isEmpty) return _ScanResult.rejected('no move (stuck)');

  for (final step in steps) {
    // At each state, check that exactly one possible move exists.
    final moves = p.findAllMoves();
    if (moves.isEmpty) return _ScanResult.rejected('no move (stuck)');
    if (moves.length > 1) return _ScanResult.rejected('branching (>1 moves)');
    final m = moves.first;
    if (m.isImpossible != null) return _ScanResult.rejected('impossible move');

    // Advance the puzzle state by replaying this step.
    switch (step) {
      case SetValueStep(:final cellIdx, :final value):
        p.cells[cellIdx].setForSolver(value);
      case RemoveOptionStep(:final cellIdx, :final option):
        p.cells[cellIdx].removeOptionForSolver(option);
    }
  }

  if (!p.complete) return _ScanResult.rejected('stuck at end');

  // Sanity-check that the resolved grid actually satisfies every constraint.
  final violations = p.constraints.where((c) => !c.verify(p)).toList();
  if (violations.isNotEmpty) {
    return _ScanResult.rejected('violations at completion');
  }
  return _ScanResult.kept();
}

Never _die(String msg) {
  stderr.writeln('Error: $msg');
  exit(1);
}
