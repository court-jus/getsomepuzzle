// Collection-balance orchestrator: an "endless loop" that alternates
// generation and recycling to move the six playable collections toward a
// common target size.
//
// Background (docs/dev/collection_management.md, "Collection orchestrator
// and puzzle recycling", decision #5): free generation over-produces 1-easy
// and 6-mad while 3-advanced / 4-strong trickle in. Instead of running
// generate → maintain by hand forever, this script loops the *cheap* cycle
// (generate → cluster_puzzles --mode recycle → recycle_mad) and only runs a
// full `bin/maintain.dart` every `--maintain-every` iterations to re-vectorize
// authoritatively, dedup, cleanup and refresh the onboarding bank.
//
// Because the CLI generator now emits one inline vector row per accepted
// puzzle (see lib/getsomepuzzle/vector.dart), the recycle step sees fresh
// vectors without re-running the 20-30 min `vectorize_puzzles` every loop
// iteration.
//
// Loop per iteration:
//   1. count the six collections; stop when all *fillable* ones are within
//      [0.9·target, 1.1·target] (see [_fillable]).
//   2. generate a batch (`-n --batch`). Every `--strong-every` iterations,
//      when 4-strong is under target, a `--target-collection 4-strong` batch
//      is run instead, to squeeze strong up as far as the easing loop allows.
//   3. `cluster_puzzles --mode recycle --apply` — FPS-prune any over-target
//      collection (6-mad) back to target, moving the excess to
//      `assets/6-mad-recycled.txt`.
//   4. `recycle_mad --apply` — ease the recycled feed down into the deficient
//      collections and consume the routed lines from the feed.
//   5. every `--maintain-every` iterations, run the full `bin/maintain.dart`.
//
// 3-advanced and 4-strong are structurally hard to fill with current tooling
// (see docs "Pilot results": advanced is unreachable by down-easing, strong
// only inches up). They are therefore tracked and generated-toward
// best-effort, but NOT required for convergence — otherwise the loop would
// churn forever.
//
// Usage:
//   dart run bin/balance_collections.dart [--batch N] [--target N]
//                                          [--maintain-every N]
//                                          [--strong-every N]
//                                          [--easing-budget S]
//                                          [--max-iterations N]
//                                          [--dry-run] [--verbose] [--help]

import 'dart:io';

const _playableLevels = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
];

const _levelNames = [
  '1-easy',
  '2-player',
  '3-advanced',
  '4-strong',
  '5-expert',
  '6-mad',
];

/// Collections that can actually reach the ~20k target with current
/// generation + recycling. 3-advanced is structurally starved (complicity
/// without force is rare) and 4-strong only inches up via easing, so those
/// two are tracked / generated-toward best-effort but never block
/// convergence.
const _fillable = {'1-easy', '2-player', '5-expert', '6-mad'};

class _Args {
  int batch = 3000;
  int target = 20000;
  int maintainEvery = 5;
  int maxIterations = 100;
  int strongEvery = 3;
  int easingBudget = 30;
  bool dryRun = false;
  bool verbose = false;
}

int _countLines(String path) {
  final f = File(path);
  if (!f.existsSync()) return 0;
  var n = 0;
  for (final l in f.readAsLinesSync()) {
    if (l.trim().isNotEmpty && !l.startsWith('#')) n++;
  }
  return n;
}

Map<String, int> _counts() {
  final out = <String, int>{};
  for (int i = 0; i < _playableLevels.length; i++) {
    out[_levelNames[i]] = _countLines(_playableLevels[i]);
  }
  return out;
}

int _floor(int target) => (target * 0.9).round();
int _ceiling(int target) => (target * 1.1).round();

bool _fillableInRange(Map<String, int> counts, int target) {
  final floor = _floor(target);
  final ceiling = _ceiling(target);
  for (final name in _fillable) {
    final c = counts[name] ?? 0;
    if (c < floor || c > ceiling) return false;
  }
  return true;
}

void _report(Map<String, int> counts, _Args a) {
  final floor = _floor(a.target);
  final ceiling = _ceiling(a.target);
  stdout.writeln('  (target ${a.target}, window $floor–$ceiling)');
  for (final name in _levelNames) {
    final c = counts[name] ?? 0;
    final String tag;
    if (!_fillable.contains(name)) {
      tag = 'best-effort';
    } else if (c < floor) {
      tag = 'UNDER';
    } else if (c > ceiling) {
      tag = 'OVER';
    } else {
      tag = 'ok';
    }
    stdout.writeln('    ${name.padRight(11)} $c  [$tag]');
  }
}

Future<int> _runScript(List<String> args) async {
  final proc = await Process.start('dart', [
    'run',
    ...args,
  ], mode: ProcessStartMode.inheritStdio);
  return proc.exitCode;
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run bin/balance_collections.dart [options]

Orchestrator: alternate generation and recycling to move the six playable
collections toward a common target size (default 20k, window ±10%).

Each iteration: generate a batch → cluster_puzzles --mode recycle --apply
(prune over-target, feed the excess) → recycle_mad --apply (ease the feed into
the deficient collections) → full bin/maintain.dart every --maintain-every
iterations. Stops when the *fillable* collections (1-easy, 2-player, 5-expert,
6-mad) are all within the window. 3-advanced / 4-strong are best-effort
(4-strong gets --target-collection batches every --strong-every iterations).

Options:
  --batch N             Puzzles generated per iteration (default: 3000)
  --target N            Per-collection balance target (default: 20000)
  --maintain-every N    Run full bin/maintain.dart every N iterations
                        (default: 5; 0 = never)
  --strong-every N      Every N iterations, use --target-collection 4-strong
                        for the batch when 4-strong is under target
                        (default: 3)
  --easing-budget S     Per-puzzle easing budget (s) for --target-collection
                        batches (default: 30)
  --max-iterations N    Safety cap on loop iterations (default: 100)
  --dry-run             Count and report only; run nothing
  -v, --verbose         Verbose
  -h, --help            Show this help
''');
}

Future<void> main(List<String> args) async {
  final a = _Args();
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--batch':
        a.batch = int.parse(args[++i]);
      case '--target':
        a.target = int.parse(args[++i]);
      case '--maintain-every':
        a.maintainEvery = int.parse(args[++i]);
      case '--strong-every':
        a.strongEvery = int.parse(args[++i]);
      case '--easing-budget':
        a.easingBudget = int.parse(args[++i]);
      case '--max-iterations':
        a.maxIterations = int.parse(args[++i]);
      case '--dry-run':
        a.dryRun = true;
      case '-v':
      case '--verbose':
        a.verbose = true;
      case '-h':
      case '--help':
        _printUsage();
        return;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        _printUsage();
        exit(1);
    }
  }

  final initial = _counts();
  stdout.writeln('=== Initial corpus ===');
  _report(initial, a);

  if (a.dryRun) {
    stdout.writeln('\n(dry-run — no commands run. Would start with:');
    stdout.writeln('  dart run bin/generate.dart -n ${a.batch}');
    stdout.writeln(
      '  dart run bin/cluster_puzzles.dart --mode recycle --apply',
    );
    stdout.writeln('  dart run bin/recycle_mad.dart --apply)');
    return;
  }

  for (int iter = 1; iter <= a.maxIterations; iter++) {
    final before = _counts();
    stdout.writeln('\n══════════════════════════════════════════════════');
    stdout.writeln('ITERATION $iter/${a.maxIterations}');
    stdout.writeln('══════════════════════════════════════════════════');

    if (_fillableInRange(before, a.target)) {
      stdout.writeln(
        '\n✓ All fillable collections in [${_floor(a.target)}, '
        '${_ceiling(a.target)}]. Balanced. Done.',
      );
      break;
    }

    // 1. Generate a batch. Every --strong-every iterations, when 4-strong is
    //    under target, target it directly (best-effort squeeze).
    final strongUnder = (before['4-strong'] ?? 0) < a.target;
    final targeted = strongUnder && (iter % a.strongEvery == 0);
    final genArgs = <String>['-n', '${a.batch}'];
    if (targeted) {
      genArgs.addAll([
        '--target-collection',
        '4-strong',
        '--easing-budget',
        '${a.easingBudget}',
      ]);
      stdout.writeln('\n  generate $a.batch (targeting 4-strong)…');
    } else {
      stdout.writeln('\n  generate $a.batch (equilibrium)…');
    }
    if (await _runScript(['bin/generate.dart', ...genArgs]) != 0) {
      stderr.writeln('generate failed — aborting.');
      exit(1);
    }

    // 2. Recycle: prune over-target collections, feed the excess.
    stdout.writeln('\n  recycle (prune over-target)…');
    if (await _runScript([
          'bin/cluster_puzzles.dart',
          '--mode',
          'recycle',
          '--apply',
        ]) !=
        0) {
      stderr.writeln('cluster_puzzles --mode recycle failed — aborting.');
      exit(1);
    }

    // 3. Ease the recycled feed into the deficient collections.
    stdout.writeln('\n  recycle_mad (ease the feed)…');
    if (await _runScript(['bin/recycle_mad.dart', '--apply']) != 0) {
      stderr.writeln('recycle_mad failed — aborting.');
      exit(1);
    }

    // 4. Periodic authoritative pass.
    if (a.maintainEvery > 0 && iter % a.maintainEvery == 0) {
      stdout.writeln(
        '\n  ⟳ full maintain (every $a.maintainEvery iterations)…',
      );
      if (await _runScript(['bin/maintain.dart']) != 0) {
        stderr.writeln('maintain failed — aborting.');
        exit(1);
      }
    }

    final after = _counts();
    stdout.writeln('\n  after iteration $iter:');
    _report(after, a);
  }

  final finalCounts = _counts();
  stdout.writeln('\n══════════════════════════════════════════════════');
  stdout.writeln('FINAL');
  _report(finalCounts, a);
  if (_fillableInRange(finalCounts, a.target)) {
    stdout.writeln('\n✓ Fillable collections in range.');
  } else {
    stdout.writeln(
      '\n✗ Not converged within $a.maxIterations iterations '
      '(or best-effort tiers 3-advanced/4-strong remain under — expected).',
    );
  }
}
