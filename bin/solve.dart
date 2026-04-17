import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/solve.dart <puzzle_file>');
    exit(1);
  }

  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exit(1);
  }

  final lines = file
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

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

  print('Puzzle: $line');
  print('Grid ${p.width}x${p.height}, constraints:');
  for (final constraint in p.constraints) {
    print('  ${constraint.serialize()} — ${constraint.toHuman()}');
  }
  print('');

  print('Initial state:');
  _printGrid(p);

  int step = 0;
  while (!p.complete) {
    Move? move;
    Constraint? source;
    String? foundBy;
    for (final constraint in p.constraints) {
      move = constraint.apply(p);
      if (move != null) {
        source = constraint;
        foundBy = "constraint";
        break;
      }
    }

    if (move == null) {
      move = p.findAMove();
      if (move == null) {
        print('Stuck — no deduction possible');
        break;
      } else {
        foundBy = "findAMove";
        source = move.givenBy;
      }
    }
    if (move.isImpossible != null) {
      print('IMPOSSIBLE detected by ${source!.serialize()}');
      break;
    }

    step++;
    final r = move.idx ~/ p.width;
    final c = move.idx % p.width;
    final colorName = move.value == 1 ? 'BLACK' : 'WHITE';
    p.cells[move.idx].setForSolver(move.value);
    print(
      'Step $step: ($r,$c) = $colorName  [$foundBy - ${source!.serialize()}]',
    );
  }

  print('');
  if (p.complete) {
    final allValid = p.constraints.every((constraint) => constraint.verify(p));
    print('Solution:');
    _printGrid(p);
    print(allValid ? 'VALID' : 'INVALID');
  } else {
    print('Final state (incomplete):');
    _printGrid(p);
  }
}

void _printGrid(Puzzle p) {
  for (int r = 0; r < p.height; r++) {
    final row = <String>[];
    for (int c = 0; c < p.width; c++) {
      final v = p.cellValues[r * p.width + c];
      row.add(
        v == 0
            ? '.'
            : v == 1
            ? 'B'
            : 'W',
      );
    }
    print('  ${row.join(" ")}');
  }
}
