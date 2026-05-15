// Diagnostic front-end for `Puzzle.simplify`. Takes one puzzle, prints
// its solving trace and classification, then drives the surgical
// easing loop and re-displays after each accepted addition.
//
// The heavy lifting (candidate generation, "first too-hard step"
// targeting, candidate.apply probe on the replayed pre-state, full
// classification with strict-drop acceptance) lives in
// `Puzzle.simplify` — this script is purely the verbose presentation
// layer.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  final parsed = _parseArgs(args);
  final puzzleArg = parsed['puzzle'] as String;
  final allowedSlugs = parsed['allow'] as Set<String>?;
  final maxSteps = parsed['maxSteps'] as int;
  final targetLevel = parsed['targetLevel'] as PuzzleLevel;
  final verbose = parsed['verbose'] as bool;

  // Accept either a file (first non-empty line) or an inline puzzle
  // representation, like `bin/solve.dart`. Multi-line files keep the
  // first puzzle only — this tool is intentionally single-puzzle.
  final String line;
  final file = File(puzzleArg);
  if (file.existsSync()) {
    final lines = file
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      stderr.writeln('File $puzzleArg has no puzzle lines');
      exit(1);
    }
    if (lines.length > 1) {
      stderr.writeln('Note: file has ${lines.length} puzzles, using first');
    }
    line = lines.first;
  } else {
    try {
      Puzzle(puzzleArg);
    } catch (e) {
      stderr.writeln(
        'Argument is neither an existing file nor a valid puzzle line: '
        '$puzzleArg',
      );
      stderr.writeln('Parse error: $e');
      exit(1);
    }
    line = puzzleArg;
  }

  _run(
    line,
    allowedSlugs: allowedSlugs,
    maxSteps: maxSteps,
    targetLevel: targetLevel,
    verbose: verbose,
  );
}

void _run(
  String line, {
  Set<String>? allowedSlugs,
  required int maxSteps,
  required PuzzleLevel targetLevel,
  required bool verbose,
}) {
  final pu = Puzzle(line);
  print('Puzzle: $line');
  print(
    'Grid ${pu.width}x${pu.height}, '
    'initial constraints (${pu.constraints.length}):',
  );
  for (final c in pu.constraints) {
    print('  ${c.serialize()} — ${c.toHuman(pu)}');
  }
  print('Target level: ${targetLevel.name}');
  print('');

  // Initial trace, computed and printed by us. Subsequent traces are
  // shown after each accepted addition via the simplify callback.
  final initial = _trace(pu);
  print('==== Initial trace ====');
  _printFullTrace(pu, initial);

  if (initial.level.index <= targetLevel.index) {
    print('');
    print('Already at or below target level — nothing to do.');
    return;
  }

  // Hand off to the surgical loop on Puzzle.simplify. The onStep
  // callback fires after each accepted addition, giving us the
  // constraint, the new level, and the cell whose too-hard step it
  // replaced. Re-tracing inside the callback is a small redundancy
  // (simplify already ran solveExplained internally) but keeps the
  // display logic isolated to this script.
  var prevLevel = initial.level;
  var step = 0;
  final result = pu.simplify(
    targetLevel: targetLevel,
    maxSteps: maxSteps,
    allowedSlugs: allowedSlugs,
    onStep: (added, newLevel, focusCell) {
      step++;
      final r = _trace(pu);
      print('');
      final focusLabel = focusCell < 0
          ? ''
          : '  [pass focused on too-hard step at '
                '(${focusCell ~/ pu.width},${focusCell % pu.width})]';
      print(
        '==== Step +$step: ADD ${added.serialize()} '
        '— ${added.toHuman(pu)}$focusLabel ====',
      );
      if (verbose || r.level != prevLevel) {
        _printFullTrace(pu, r);
      } else {
        print('  ${_summaryLine(r)}  → ${r.level.name}');
      }
      if (r.level != prevLevel) {
        print('  level: ${prevLevel.name} → ${r.level.name}');
      }
      prevLevel = r.level;
    },
  );

  print('');
  print('==== Result ====');
  if (result.reachedTarget) {
    print(
      'Reached target level ${targetLevel.name} after '
      '${result.additionsCount} addition(s).',
    );
  } else {
    print(
      'Plateaued at ${result.finalLevel.name} after '
      '${result.additionsCount} addition(s) '
      '(target was ${targetLevel.name}).',
    );
    final r = _trace(pu);
    final reasons = <String>[];
    if (r.forceMoves > 0) reasons.add('forceMoves=${r.forceMoves}');
    if (r.maxComplCx > 0) reasons.add('maxComplCx=${r.maxComplCx}');
    if (r.maxPropCx >= 3) reasons.add('maxPropCx=${r.maxPropCx} (≥3)');
    if (reasons.isNotEmpty) {
      print('Blocking factors: ${reasons.join(', ')}');
    }
  }
}

class _TraceResult {
  final List<SolveStep> steps;
  final int forceMoves;
  final int maxForceDepth;
  final int maxComplCx;
  final int maxPropCx;
  final int propCount;
  final int complicityCount;
  final PuzzleLevel level;
  _TraceResult({
    required this.steps,
    required this.forceMoves,
    required this.maxForceDepth,
    required this.maxComplCx,
    required this.maxPropCx,
    required this.propCount,
    required this.complicityCount,
    required this.level,
  });
}

_TraceResult _trace(Puzzle pu) {
  // Trace on a clone so the original puzzle stays in its initial state
  // (no cells set during solveExplained's internal replay).
  final clone = pu.clone();
  final steps = clone.solveExplained();
  int forceMoves = 0;
  int maxForceDepth = 0;
  int maxComplCx = 0;
  int maxPropCx = 0;
  int propCount = 0;
  int complicityCount = 0;
  for (final s in steps) {
    if (s.method == SolveMethod.force) {
      forceMoves++;
      if (s.forceDepth > maxForceDepth) maxForceDepth = s.forceDepth;
    } else if (s.isComplicity) {
      complicityCount++;
      if (s.complexity > maxComplCx) maxComplCx = s.complexity;
    } else {
      propCount++;
      if (s.complexity > maxPropCx) maxPropCx = s.complexity;
    }
  }
  final replay = pu.clone();
  for (final s in steps) {
    replay.setValue(s.cellIdx, s.value);
  }
  final completed = replay.complete && replay.check(saveResult: false).isEmpty;
  final prefillRatio =
      pu.cells.where((c) => c.readonly).length / pu.cells.length;
  final level = classifyTrace(
    steps: steps,
    prefillRatio: prefillRatio,
    solved: completed,
  );
  return _TraceResult(
    steps: steps,
    forceMoves: forceMoves,
    maxForceDepth: maxForceDepth,
    maxComplCx: maxComplCx,
    maxPropCx: maxPropCx,
    propCount: propCount,
    complicityCount: complicityCount,
    level: level,
  );
}

void _printFullTrace(Puzzle pu, _TraceResult r) {
  for (int i = 0; i < r.steps.length; i++) {
    final s = r.steps[i];
    final row = s.cellIdx ~/ pu.width;
    final col = s.cellIdx % pu.width;
    final color = s.value == 1 ? 'B' : 'W';
    final String kind;
    if (s.method == SolveMethod.force) {
      kind = 'force depth=${s.forceDepth}';
    } else if (s.isComplicity) {
      kind = 'complicity cplx=${s.complexity}';
    } else {
      kind = 'prop cplx=${s.complexity}';
    }
    print('Step ${i + 1}: ($row,$col) = $color  [$kind by ${s.constraint}]');
  }
  print(
    'Total moves: ${r.steps.length} '
    '(prop:${r.propCount} complicity:${r.complicityCount} '
    'force:${r.forceMoves})',
  );
  print('Classification: ${_summaryLine(r)} → ${r.level.name}');
}

String _summaryLine(_TraceResult r) {
  return 'forceMoves=${r.forceMoves} maxForceDepth=${r.maxForceDepth} '
      'maxComplCx=${r.maxComplCx} maxPropCx=${r.maxPropCx}';
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final result = <String, dynamic>{
    'puzzle': null,
    'allow': null,
    'maxSteps': 50,
    'targetLevel': PuzzleLevel.beginner,
    'verbose': false,
  };
  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      case '--allow':
        result['allow'] = args[++i].split(',').toSet();
      case '--max-steps':
        result['maxSteps'] = int.parse(args[++i]);
      case '--target-level':
        final name = args[++i];
        final lvl = playableCollectionKeyToLevel[name];
        if (lvl == null) {
          stderr.writeln(
            '--target-level must be one of: '
            '${playableCollectionKeyToLevel.keys.join(', ')} '
            '(got "$name")',
          );
          exit(1);
        }
        result['targetLevel'] = lvl;
      case '--verbose':
        result['verbose'] = true;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('Unknown option: $a');
          _printUsage();
          exit(1);
        }
        if (result['puzzle'] != null) {
          stderr.writeln('Only one puzzle argument is allowed.');
          exit(1);
        }
        result['puzzle'] = a;
    }
  }
  if (result['puzzle'] == null) {
    stderr.writeln('Missing puzzle argument.');
    _printUsage();
    exit(1);
  }
  return result;
}

void _printUsage() {
  final levels = playableCollectionKeyToLevel.keys.join(', ');
  stderr.writeln('''
Usage: dart run bin/simplify_puzzle.dart <puzzle_or_file> [options]

Shows the solving trace of a puzzle, then drives `Puzzle.simplify`:
identify the first "too hard" step for the target level, look for
candidates that can produce a move on that same cell from the
pre-step state, accept the first one that strictly drops the
classified level without overshooting. Re-display after each accepted
addition.

Options:
  --allow RULES        Comma-separated whitelist of slugs to try as
                       candidates (e.g. FM,PA,NC). Default: every slug
                       in the registry.
  --max-steps N        Stop after N successful additions (default: 50).
  --target-level NAME  Stop as soon as the level reaches NAME or
                       simpler. NAME ∈ { $levels }. Default: 1-easy.
  --verbose            Print the full trace after every addition.
                       Default: full trace at start and on level
                       change, one-line summary otherwise.
  -h, --help           Show this help.
''');
}
