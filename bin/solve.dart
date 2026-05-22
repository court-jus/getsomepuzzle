import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/solve.dart <puzzle_file | puzzle_line | share_url>',
    );
    exit(1);
  }

  String input = args[0];
  // Accept a share URL like https://.../?puzzle=v2_... — extract the line.
  if (!input.startsWith('v2_') && !File(input).existsSync()) {
    try {
      final fromUrl = Uri.parse(input).queryParameters['puzzle'];
      if (fromUrl != null && fromUrl.startsWith('v2_')) {
        input = fromUrl;
      }
    } catch (_) {}
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

  print('Puzzle: $line');
  print('Grid ${p.width}x${p.height}, constraints:');
  for (final constraint in p.constraints) {
    print('  ${constraint.serialize()} — ${constraint.toHuman(p)}');
  }
  print('');

  print('Initial state:');
  _printGrid(p);

  int step = 0;
  while (!p.complete) {
    // p.apply() tries constraints first, then complicities — same order
    // as the production solver. findAMove falls back to force when both
    // levels are stuck.
    Move? move = p.apply();
    String foundBy = move == null
        ? 'findAMove'
        : (move.givenBy is Complicity ? 'complicity' : 'constraint');
    move ??= p.findAMove();
    if (move == null) {
      print('Stuck — no deduction possible');
      break;
    }
    final source = move.givenBy;
    if (move.isImpossible != null) {
      print('IMPOSSIBLE detected by ${source.serialize()}');
      break;
    }

    step++;
    final r = move.idx ~/ p.width;
    final c = move.idx % p.width;
    final colorName = move.value == 1 ? 'BLACK' : 'WHITE';
    p.cells[move.idx].setForSolver(move.value);
    print(
      'Step $step: ($r,$c) = $colorName  [$foundBy - ${source.serialize()}]',
    );
  }

  print('');
  if (p.complete) {
    final violations = p.constraints
        .where((c) => !c.verify(p))
        .toList(growable: false);
    print('Solution:');
    _printGrid(p);
    if (violations.isEmpty) {
      print('VALID');
    } else {
      print('INVALID — violated constraints:');
      for (final c in violations) {
        print('  ${c.serialize()} — ${c.toHuman(p)}');
      }
    }
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
