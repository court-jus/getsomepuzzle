// Run solveExplained on a single puzzle and pretty-print the trace, then
// brute-force enumerate all completions to detect non-uniqueness.
//
// Usage:
//   dart run bin/inspect_puzzle.dart "<v2_...>"
//                                    [--enum-limit N]
//                                    [--branch IDX=VAL ...]
//                                    [--no-enum]
//
// `--branch IDX=VAL` replays the solveExplained trace up to (but not
// including) the step that would set cell IDX, then sets IDX=VAL instead
// and continues propagation step-by-step, logging each deduction and the
// responsible constraint. Useful to identify which constraint disagrees
// with `verify()` when a puzzle has multiple solutions.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

String _gridString(List<int> values, int width) {
  final sb = StringBuffer();
  for (int i = 0; i < values.length; i++) {
    final v = values[i];
    String ch;
    if (v == 0) {
      ch = '.';
    } else if (v == 1) {
      ch = '#';
    } else if (v == 2) {
      ch = 'o';
    } else {
      ch = v.toString();
    }
    sb.write(ch);
    sb.write(' ');
    if ((i + 1) % width == 0) sb.write('\n');
  }
  return sb.toString();
}

String _coord(int idx, int width) {
  final r = idx ~/ width;
  final c = idx % width;
  return '(r$r,c$c)';
}

void _enumerateSolutions(
  Puzzle puzzle,
  List<List<int>> out, {
  required int limit,
}) {
  // Indices of free cells (those whose initial value is 0).
  final freeIdx = <int>[];
  for (int i = 0; i < puzzle.cells.length; i++) {
    if (puzzle.cells[i].value == 0) freeIdx.add(i);
  }

  void rec(int k) {
    if (out.length >= limit) return;
    if (k == freeIdx.length) {
      // All free cells are assigned. Check all constraints.
      final errors = puzzle.check(saveResult: false);
      if (errors.isEmpty) {
        out.add(List<int>.from(puzzle.cellValues));
      }
      return;
    }
    final idx = freeIdx[k];
    for (final v in puzzle.domain) {
      puzzle.setValue(idx, v);
      // Light pruning: if any constraint already fails (state itself broken
      // or unreachable), abort this branch.
      if (puzzle.check(saveResult: false).isEmpty) {
        rec(k + 1);
      }
      if (out.length >= limit) return;
    }
    puzzle.setValue(idx, 0);
  }

  rec(0);
}

void main(List<String> args) {
  String? line;
  int enumLimit = 5;
  bool runEnum = true;
  final branches = <int, int>{};

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--enum-limit') {
      enumLimit = int.parse(args[++i]);
    } else if (a == '--no-enum') {
      runEnum = false;
    } else if (a == '--branch') {
      final parts = args[++i].split('=');
      if (parts.length != 2) {
        stderr.writeln('--branch expects IDX=VAL');
        exit(1);
      }
      branches[int.parse(parts[0])] = int.parse(parts[1]);
    } else if (a == '-h' || a == '--help') {
      stderr.writeln(
        'Usage: dart run bin/inspect_puzzle.dart "<v2_...>" '
        '[--enum-limit N] [--branch IDX=VAL ...] [--no-enum]',
      );
      exit(0);
    } else if (line == null) {
      line = a;
    } else {
      stderr.writeln('Unknown argument: $a');
      exit(1);
    }
  }

  if (line == null) {
    stderr.writeln(
      'Usage: dart run bin/inspect_puzzle.dart "<v2_...>" '
      '[--enum-limit N] [--branch IDX=VAL ...] [--no-enum]',
    );
    exit(1);
  }
  final puzzle = Puzzle(line);

  stdout.writeln('=== Puzzle ===');
  stdout.writeln(
    '${puzzle.width}x${puzzle.height}, '
    'domain=${puzzle.domain}, '
    '${puzzle.constraints.length} constraints',
  );
  stdout.writeln('');
  stdout.writeln('Initial grid:');
  stdout.write(_gridString(puzzle.cellValues, puzzle.width));
  stdout.writeln('');

  stdout.writeln('Constraints:');
  for (final c in puzzle.constraints) {
    stdout.writeln('  ${c.serialize()}  -- ${c.toHuman(puzzle)}');
  }
  stdout.writeln('');

  // --- solveExplained trace ---
  final traceClone = puzzle.clone();
  final steps = traceClone.solveExplained(timeoutMs: 30000);
  stdout.writeln('=== solveExplained trace (${steps.length} steps) ===');

  // Apply steps to a fresh clone, printing each move and the resulting grid.
  final replay = puzzle.clone();
  for (int i = 0; i < steps.length; i++) {
    final s = steps[i];
    final method = s.method == SolveMethod.force
        ? 'FORCE(d=${s.forceDepth})'
        : 'PROP';
    final reason = s.constraint.isNotEmpty ? ' by ${s.constraint}' : '';
    stdout.writeln(
      'step ${(i + 1).toString().padLeft(3)}: '
      '${_coord(s.cellIdx, replay.width)} = ${s.value}  [$method]$reason',
    );
    replay.setValue(s.cellIdx, s.value);
  }
  stdout.writeln('');
  stdout.writeln('Grid after trace:');
  stdout.write(_gridString(replay.cellValues, replay.width));
  stdout.writeln('Complete? ${replay.complete}');
  stdout.writeln(
    'Errors after trace: ${replay.check(saveResult: false).length}',
  );
  stdout.writeln('');

  // --- Branched continuation (--branch IDX=VAL) ---
  if (branches.isNotEmpty) {
    stdout.writeln('=== Branch continuation ===');
    final branched = puzzle.clone();
    final branchedIdxs = branches.keys.toSet();
    int stopAt = steps.length;
    for (int i = 0; i < steps.length; i++) {
      if (branchedIdxs.contains(steps[i].cellIdx)) {
        stopAt = i;
        break;
      }
    }
    stdout.writeln(
      'Replaying $stopAt trace steps before first branched cell, '
      'then forcing: '
      '${branches.entries.map((e) => '${_coord(e.key, branched.width)}=${e.value}').join(', ')}',
    );
    for (int i = 0; i < stopAt; i++) {
      branched.setValue(steps[i].cellIdx, steps[i].value);
    }
    for (final entry in branches.entries) {
      branched.setValue(entry.key, entry.value);
      stdout.writeln(
        'BRANCH set ${_coord(entry.key, branched.width)} = ${entry.value}',
      );
    }
    stdout.writeln('Grid after branch:');
    stdout.write(_gridString(branched.cellValues, branched.width));
    stdout.writeln('');

    // Step-by-step propagation. Use findAMove with checkErrors=true so any
    // inter-constraint violation surfaces as a corrective Move (with the
    // responsible constraint in `givenBy`).
    int s = 0;
    while (true) {
      // Check whether any constraint already reports a violation on the
      // current state. This catches the bug where verify() and apply()
      // disagree: if verify says ok but apply forces something invalid,
      // we'll see verify start failing after the apply step.
      final errors = branched.check(saveResult: false);
      if (errors.isNotEmpty) {
        stdout.writeln(
          '!! verify() FAILS on ${errors.length} constraint(s) at this state:',
        );
        for (final e in errors) {
          stdout.writeln('     ${e.serialize()}  -- ${e.toHuman(branched)}');
        }
      }

      final m = branched.findAMove(checkErrors: false);
      if (m == null) {
        stdout.writeln('Stuck after $s extra step(s). No move available.');
        break;
      }
      if (m.isImpossible != null) {
        stdout.writeln(
          'CONTRADICTION reported by ${m.isImpossible!.serialize()} '
          '(${m.isImpossible!.toHuman(branched)})',
        );
        break;
      }
      s++;
      final method = m.isForce ? 'FORCE(d=${m.forceDepth})' : 'PROP';
      stdout.writeln(
        'extra step ${s.toString().padLeft(2)}: '
        '${_coord(m.idx, branched.width)} = ${m.value}  [$method] '
        'by ${m.givenBy.serialize()}',
      );
      branched.setValue(m.idx, m.value);
      if (branched.complete) {
        final post = branched.check(saveResult: false);
        if (post.isEmpty) {
          stdout.writeln('Reached COMPLETE state, all constraints satisfied.');
        } else {
          stdout.writeln(
            'Reached complete state but ${post.length} constraint(s) FAIL:',
          );
          for (final e in post) {
            stdout.writeln('     ${e.serialize()}  -- ${e.toHuman(branched)}');
          }
        }
        break;
      }
      if (s > 200) {
        stdout.writeln('Stopped after 200 extra steps (safety cap).');
        break;
      }
    }
    stdout.writeln('');
  }

  if (!runEnum) return;

  // --- Enumerate up to enumLimit solutions ---
  stdout.writeln('=== Solution enumeration (brute force, max $enumLimit) ===');
  final enumClone = puzzle.clone();
  final solutions = <List<int>>[];
  _enumerateSolutions(enumClone, solutions, limit: enumLimit);
  stdout.writeln(
    'Found ${solutions.length} solution(s) (search capped at $enumLimit).',
  );
  for (int i = 0; i < solutions.length; i++) {
    stdout.writeln('--- Solution ${i + 1} ---');
    stdout.write(_gridString(solutions[i], puzzle.width));
  }
  if (solutions.length >= 2) {
    stdout.writeln('');
    stdout.writeln('Diff between solution 1 and 2 (cells that differ):');
    final s1 = solutions[0];
    final s2 = solutions[1];
    for (int i = 0; i < s1.length; i++) {
      if (s1[i] != s2[i]) {
        stdout.writeln(
          '  ${_coord(i, puzzle.width)}: sol1=${s1[i]} vs sol2=${s2[i]}',
        );
      }
    }
  }

  // --- Compare against cached solution ---
  if (puzzle.cachedSolution != null) {
    stdout.writeln('');
    stdout.writeln('Cached solution from puzzle line:');
    stdout.write(_gridString(puzzle.cachedSolution!, puzzle.width));
  }
}
