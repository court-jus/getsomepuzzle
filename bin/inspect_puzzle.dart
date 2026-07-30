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

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/puzzle_display.dart';

String _coord(int idx, int width) {
  final r = idx ~/ width;
  final c = idx % width;
  return '(r$r,c$c)';
}

void main(List<String> args) {
  String? line;
  int enumLimit = 5;
  bool runEnum = true;
  final branches = <int, CellValue>{};

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
      branches[int.parse(parts[0])] = cellRepresentationToValue(parts[1]);
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
  stdout.write(formatGrid(puzzle.cellValues, puzzle.width, puzzle.height));
  stdout.writeln('');

  stdout.writeln('Constraints:');
  stdout.write(formatConstraints(puzzle.constraints, puzzle));
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
    if (s.value != null) {
      replay.setValue(s.cellIdx, s.value!);
    } else if (s.removeOption != null) {
      replay.removeOption(s.cellIdx, s.removeOption!);
    }
  }
  stdout.writeln('');
  stdout.writeln('Grid after trace:');
  stdout.write(
    formatGrid(
      replay.cellValues,
      replay.width,
      replay.height,
      showHeaders: false,
    ),
  );
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
      if (steps[i].value != null) {
        branched.setValue(steps[i].cellIdx, steps[i].value!);
      } else if (steps[i].removeOption != null) {
        branched.removeOption(steps[i].cellIdx, steps[i].removeOption!);
      }
    }
    for (final entry in branches.entries) {
      branched.setValue(entry.key, entry.value);
      stdout.writeln(
        'BRANCH set ${_coord(entry.key, branched.width)} = ${entry.value}',
      );
    }
    stdout.writeln('Grid after branch:');
    stdout.write(
      formatGrid(
        branched.cellValues,
        branched.width,
        branched.height,
        showHeaders: false,
      ),
    );
    stdout.writeln('');

    // Propagation after the branch using solveExplained (includes drain).
    // Replay the returned steps, cross-checking verify() at each state.
    stdout.writeln('Propagating...');
    final branchSteps = branched.solveExplained();
    if (branchSteps.isEmpty) {
      stdout.writeln('Stuck. No move available from this branch.');
    } else {
      final maxBranchSteps = 200;
      for (int si = 0; si < branchSteps.length && si < maxBranchSteps; si++) {
        // Cross-check at the state before this step.
        final errors = branched.check(saveResult: false);
        if (errors.isNotEmpty) {
          stdout.writeln(
            '!! verify() FAILS on ${errors.length} constraint(s) at this state:',
          );
          for (final e in errors) {
            stdout.writeln('     ${e.serialize()}  -- ${e.toHuman(branched)}');
          }
        }

        final s = branchSteps[si];
        if (s.method == SolveMethod.force) {
          stdout.writeln(
            'extra step ${(si + 1).toString().padLeft(2)}: '
            '${_coord(s.cellIdx, branched.width)} = ${s.value}  '
            '[FORCE(d=${s.forceDepth})] by ${s.constraint}',
          );
        } else {
          stdout.writeln(
            'extra step ${(si + 1).toString().padLeft(2)}: '
            '${_coord(s.cellIdx, branched.width)} = ${s.value}  '
            '[PROP] by ${s.constraint}',
          );
        }

        if (s.value != null) {
          branched.setValue(s.cellIdx, s.value!);
        } else if (s.removeOption != null) {
          branched.removeOption(s.cellIdx, s.removeOption!);
        }

        if (branched.complete) {
          final post = branched.check(saveResult: false);
          if (post.isEmpty) {
            stdout.writeln(
              'Reached COMPLETE state, all constraints satisfied.',
            );
          } else {
            stdout.writeln(
              'Reached complete state but ${post.length} constraint(s) FAIL:',
            );
            for (final e in post) {
              stdout.writeln(
                '     ${e.serialize()}  -- ${e.toHuman(branched)}',
              );
            }
          }
          break;
        }
      }
      if (!branched.complete) {
        stdout.writeln(
          'Stopped after ${min(maxBranchSteps, branchSteps.length)} '
          'extra step(s) (safety cap).',
        );
      }
    }
    stdout.writeln('');
  }

  if (!runEnum) return;

  // --- Enumerate up to enumLimit solutions ---
  stdout.writeln('=== Solution enumeration (brute force, max $enumLimit) ===');
  final enumClone = puzzle.clone();
  final solutions = enumerateSolutions(enumClone, limit: enumLimit);
  stdout.writeln(
    'Found ${solutions.length} solution(s) (search capped at $enumLimit).',
  );
  for (int i = 0; i < solutions.length; i++) {
    stdout.writeln('--- Solution ${i + 1} ---');
    stdout.write(
      formatGrid(solutions[i], puzzle.width, puzzle.height, showHeaders: false),
    );
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
    stdout.write(
      formatGrid(
        puzzle.cachedSolution!,
        puzzle.width,
        puzzle.height,
        showHeaders: false,
      ),
    );
  }
}
