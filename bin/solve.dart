import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/puzzle_display.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/solve.dart <puzzle_file | puzzle_line | share_url>',
    );
    exit(1);
  }

  String input = args[0];
  // If the argument doesn't point at an existing file, try to normalize
  // it as a puzzle representation (share URL, bare canonical key, or
  // full v2 line). Falls through to the file-loading branch below when
  // the input looks like a filesystem path.
  if (!File(input).existsSync()) {
    final normalized = normalizeToV2Line(input);
    if (normalized != null) input = normalized;
  }

  final List<String> lines;
  final file = File(input);
  if (file.existsSync()) {
    lines = file
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  } else {
    // Not a file — try to interpret the argument as a single puzzle line.
    // Puzzle(...) throws on a malformed representation.
    try {
      Puzzle(input);
    } catch (e) {
      stderr.writeln(
        'Argument is neither an existing file nor a valid puzzle line: $input',
      );
      stderr.writeln('Parse error: $e');
      exit(1);
    }
    lines = [input];
  }

  for (int i = 0; i < lines.length; i++) {
    if (lines.length > 1) {
      print('========== Puzzle ${i + 1}/${lines.length} ==========');
    }
    _solvePuzzle(lines[i]);
    if (i < lines.length - 1) print('');
  }
}

void _solvePuzzle(String line) {
  final p = Puzzle(line);

  // Prefill ratio captured before the replay mutates the grid — needed by
  // the difficulty cascade at the end.
  final prefillRatio = 1 - p.freeCells().length / (p.width * p.height);

  print('Puzzle: $line');
  print('');
  print(describePuzzle(p));
  print('--- Solving steps ---');
  final trace = p.solveTrace();

  // Must run while the puzzle is still in its initial state: the method
  // short-circuits to 0 on a complete grid.
  p.computeComplexityFromSteps(trace.steps);

  int step = 0;
  for (final s in trace.steps) {
    step++;
    final r = s.cellIdx ~/ p.width;
    final c = s.cellIdx % p.width;
    switch (s) {
      case SetValueStep(:final value, :final method, :final isComplicity):
        p.setValue(s.cellIdx, value);
        final foundBy = switch (method) {
          SolveMethod.force => 'findAMove',
          SolveMethod.propagation when isComplicity => 'complicity',
          SolveMethod.propagation => 'constraint',
        };
        print(
          'Step $step: ($r,$c) = ${value.name}  [$foundBy - ${s.constraint}]'
          ' <cplx ${s.method == SolveMethod.force ? 5 + 5 * s.forceDepth : s.complexity}>',
        );
      case RemoveOptionStep(:final option, :final method, :final isComplicity):
        p.removeOption(s.cellIdx, option);
        final foundBy = switch (method) {
          SolveMethod.force => 'findAMove',
          SolveMethod.propagation when isComplicity => 'complicity',
          SolveMethod.propagation => 'constraint',
        };
        print(
          'Step $step: ($r,$c) != ${option.name}  [$foundBy - ${s.constraint}]'
          ' <cplx ${s.method == SolveMethod.force ? 5 + 5 * s.forceDepth : s.complexity}>',
        );
    }
  }

  print('');
  if (trace.impossibleBy != null) {
    print('IMPOSSIBLE detected by ${trace.impossibleBy}');
  } else if (p.complete) {
    final violations = p.constraints
        .where((c) => !c.verify(p))
        .toList(growable: false);
    print('Solution:');
    print(formatGrid(p.cellValues, p.width, p.height));
    if (violations.isEmpty) {
      print('VALID');
    } else {
      print('INVALID — violated constraints:');
      for (final c in violations) {
        print('  ${c.serialize()} — ${c.toHuman(p)}');
      }
    }
  } else {
    print('Stuck — no deduction possible');
    print('Final state (incomplete):');
    print(formatGrid(p.cellValues, p.width, p.height));
  }

  // Complexity + difficulty collection from the trace we already hold —
  // no re-solve, no routing/redistribution, just classification output.
  final level = classifyTrace(
    steps: trace.steps,
    prefillRatio: prefillRatio,
    solved: trace.impossibleBy == null && p.complete,
  );
  final collectionKey = levelToPlayableCollectionKey[level];
  print('');
  print('--- Complexity ---');
  print('Complexity: ${p.cachedComplexity}');
  print(
    'Collection: ${levelLabels[level]}'
    '${collectionKey != null ? ' ($collectionKey.txt)' : ''}',
  );
}
