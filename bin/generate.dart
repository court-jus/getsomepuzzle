import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);

  final mode = parsed['mode'] as String;
  switch (mode) {
    case 'generate':
      await _runGenerate(parsed);
    case 'check':
      await _runCheck(
        parsed['checkFile'] as String,
        debug: parsed['debug'] as bool,
      );
    case 'read-stats':
      _runReadStats(parsed['statsDir'] as String);
  }
}

// --- Generate mode ---

Future<void> _runGenerate(Map<String, dynamic> parsed) async {
  final debug = parsed['debug'] as bool;
  final count = parsed['count'] as int;
  final minWidth = parsed['minWidth'] as int;
  final maxWidth = parsed['maxWidth'] as int;
  final minHeight = parsed['minHeight'] as int;
  final maxHeight = parsed['maxHeight'] as int;
  final maxTime = parsed['maxTime'] as int;
  final output = parsed['output'] as String?;
  final bannedRules = (parsed['banned'] as String?)?.split(',').toSet() ?? {};
  final allowedSlugsArg = (parsed['allowed'] as String?)?.split(',').toSet();
  final requiredRules =
      (parsed['required'] as String?)?.split(',').toSet() ?? {};
  final equilibriumRequested = parsed['equilibrium'] as bool;
  final jobs = (parsed['jobs'] as int).clamp(1, count);
  final logDir = parsed['logDir'] as String?;
  final domainSize = parsed['domain'] as int;
  final domain = domainSize == 3 ? fullDomain : defaultDomain;
  final strategies = parsed['strategy'] as List<GenerationStrategy>;
  final maxStall = parsed['maxStall'] as int;
  if (logDir != null) {
    final dir = Directory(logDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  // Two output modes:
  //   * `--output FILE` → all puzzles appended to a single file (legacy).
  //   * no `--output`   → puzzles are auto-routed by difficulty palier
  //                       to `assets/<level>.txt` (1-easy.txt … 6-mad.txt).
  //                       The classification is computed during generation
  //                       (no extra solve), see lib/getsomepuzzle/level.dart.
  IOSink? sink;
  Map<PuzzleLevel, IOSink>? levelSinks;
  // Per-sink write chain. Multiple worker consumers share the same
  // IOSink (per output, or per level in split mode); without
  // serialization, two concurrent `writeln + await flush` pairs race
  // inside IOSink (flush internally binds a stream — a concurrent
  // writeln then crashes with "Bad state: StreamSink is bound to a
  // stream"). We funnel each sink's writes through a Future chain so
  // only one writeln+flush pair runs at a time per sink. Different
  // sinks (different levels) still parallelise.
  Future<void> singleSinkChain = Future.value();
  final levelSinkChains = <PuzzleLevel, Future<void>>{};
  if (output != null) {
    sink = File(output).openWrite(mode: FileMode.append);
  } else {
    levelSinks = {};
    for (final level in PuzzleLevel.values) {
      final fname = levelFilenames[level];
      if (fname == null) continue;
      // Skip `undetermined`: classifyTrace returns it only when the
      // trace doesn't complete, which the generator already filters
      // out before emitting a `GeneratorPuzzleMessage`. The two
      // `overfilled*` buckets *do* get sinks: the live generator may
      // emit them when it produces a high-prefill puzzle (its
      // `ratio` knob mostly bounds prefill but small grids still
      // sometimes overshoot the 30 % cap, especially with a
      // `--require` slug).
      if (level == PuzzleLevel.undetermined) continue;
      final dir = Directory('assets');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      levelSinks[level] = File(
        'assets/$fname',
      ).openWrite(mode: FileMode.append);
    }
  }

  // Initial corpus: read the output file if it exists, otherwise start empty.
  // This list is the source of truth for stats display; we refresh it after
  // every newly generated puzzle (re-read from disk when writing to a file,
  // append in-memory when writing to stdout).
  List<String> currentLines = const [];
  if (output != null && File(output).existsSync()) {
    currentLines = File(output).readAsLinesSync();
  } else if (output == null) {
    // Aggregate stats across the per-level files so the dashboard shows
    // the full corpus, not just one bucket.
    final aggregate = <String>[];
    for (final s in levelSinks!.entries) {
      final fname = levelFilenames[s.key]!;
      final f = File('assets/$fname');
      if (f.existsSync()) aggregate.addAll(f.readAsLinesSync());
    }
    currentLines = aggregate;
  }
  // usageStats passed to workers stays a flat slug→count map for the legacy
  // slug bias; recomputed once from the initial corpus.
  final usageStats = PuzzleGenerator.computeUsageStats(currentLines);

  /// Build the equilibrium status line for the dashboard. Recomputed on every
  /// render so the warm-up / equilibrium switch tracks the live corpus —
  /// workers flip modes themselves as they cross [kEquilibriumWarmupSize].
  String currentEquilibriumLine(int liveCount) {
    if (!equilibriumRequested) {
      return 'Equilibrium: OFF (legacy slug-only bias)';
    }
    if (liveCount >= kEquilibriumWarmupSize) {
      return 'Equilibrium: ON (use --no-equilibrium to disable)';
    }
    return 'Warmup: small grids (≤$kWarmupMaxWidth×$kWarmupMaxHeight), '
        '1-2 types — $liveCount/$kEquilibriumWarmupSize';
  }

  int generated = 0;
  final totalSw = Stopwatch()..start();
  final durations = <int>[];
  int lastPuzzleMs = 0;

  // Per-worker current target labels, indexed by worker index j. Updated by
  // GeneratorTargetMessage; null means "not started yet".
  final currentTargets = List<String?>.filled(jobs, null);
  // Per-worker counters: how many `generateOne` attempts the worker has
  // started (one per GeneratorTargetMessage), and how many of those produced
  // a puzzle. Their ratio is a live failure-rate signal.
  final attemptCounts = List<int>.filled(jobs, 0);
  final successCounts = List<int>.filled(jobs, 0);
  // Global rejection breakdown — keyed by `GenerationRejectReason`,
  // aggregated across all workers. The delta between
  // `sum(attemptCounts) - generated - sum(rejectCounts.values)`
  // approximates in-flight attempts; usually small.
  final rejectCounts = <GenerationRejectReason, int>{
    for (final r in GenerationRejectReason.values) r: 0,
  };
  // Per-stage wall-time totals (microseconds) and invocation counts,
  // summed across all workers and all attempts (success + failure).
  // Together they yield "total time" and "average µs per call" — the
  // dashboard prints both at end-of-run alongside the rejection
  // breakdown so the bottleneck is obvious.
  final stageTotalsMicros = <String, int>{};
  final stageTotalsCalls = <String, int>{};
  // Cached corpus stats — only recomputed when a puzzle is appended, so
  // target-only updates (which happen many times per second) avoid the
  // O(N) rescan.
  var cachedStats = _CollectionStats.fromLines(currentLines);

  // Universe of slugs the equilibrium picker considers — same logic as the
  // worker (registry filtered by `--allow` whitelist if any, then minus
  // `--ban`). Used by the dashboard to compute per-axis targets that
  // match what `pickTarget` actually optimizes, and re-used below to
  // drive worker config. `null` means "all registered slugs" — kept as
  // the sentinel so downstream code can short-circuit when no filter is
  // active.
  Set<String>? allowedSlugs;
  if (allowedSlugsArg != null || bannedRules.isNotEmpty) {
    allowedSlugs = allowedSlugsArg ?? constraintSlugs.toSet();
    allowedSlugs = allowedSlugs.difference(bannedRules);
  }
  final universeSlugs = allowedSlugs ?? constraintSlugs.toSet();

  void render() {
    if (debug) return;
    final liveCount = currentLines.where((l) => l.trim().isNotEmpty).length;
    _renderDashboard(
      generated: generated,
      count: count,
      jobs: jobs,
      elapsed: totalSw.elapsed,
      durations: durations,
      equilibriumLine: currentEquilibriumLine(liveCount),
      existingPuzzles: liveCount,
      stats: cachedStats,
      universeSlugs: universeSlugs,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      targets: currentTargets,
      attemptCounts: attemptCounts,
      successCounts: successCounts,
      rejectCounts: rejectCounts,
      stageTotalsMicros: stageTotalsMicros,
      stageTotalsCalls: stageTotalsCalls,
      domainSize: domainSize,
      requiredRules: requiredRules,
      bannedRules: bannedRules,
      strategies: strategies,
      allowedRules: allowedSlugsArg,
    );
  }

  // Initial dashboard render (corpus stats before generation starts).
  render();

  final workers = <GeneratorWorker>[];
  bool finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    stderr.writeln('');
    stderr.writeln(
      'Done: $generated puzzles in ${_fmt(totalSw.elapsed)} (jobs=$jobs)',
    );
    if (durations.isNotEmpty) {
      stderr.writeln(
        '  avg: ${_avgMs(durations)}ms, median: ${_medianMs(durations)}ms, '
        'min: ${durations.reduce(min)}ms, max: ${durations.reduce(max)}ms',
      );
    }
    // sink?.close();
    exit(0);
  }

  // Split the requested count across [jobs] workers. The first
  // (count % jobs) workers get one extra puzzle so the sum stays exactly
  // [count].
  final base = count ~/ jobs;
  final remainder = count % jobs;

  ProcessSignal.sigint.watch().listen((_) {
    for (final w in workers) {
      w.cancel();
    }
    finish();
    exit(0);
  });

  final consumers = <Future<void>>[];
  for (int j = 0; j < jobs; j++) {
    final workerCount = base + (j < remainder ? 1 : 0);
    if (workerCount == 0) continue;
    // Round-robin strategy assignment across workers so a heterogeneous
    // pool (e.g. `--strategy phase-gate,phase-1-oneshot,prop-only`)
    // splits the work between strategies. With a single-element list
    // every worker gets the same strategy.
    final workerStrategy = strategies[j % strategies.length];
    final config = GeneratorConfig(
      width: minWidth,
      height: minHeight,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      maxTime: Duration(seconds: maxTime),
      requiredRules: requiredRules,
      allowedSlugs: allowedSlugs,
      count: workerCount,
      domain: domain,
      strategy: workerStrategy,
      maxStall: Duration(seconds: maxStall),
    );
    final worker = GeneratorWorker();
    workers.add(worker);
    final stream = worker.start(
      config,
      usageStats: usageStats,
      puzzleLines: currentLines,
      equilibriumRequested: equilibriumRequested,
      jobsCount: jobs,
      workerIndex: j,
      logFilePath: logDir != null ? '$logDir/worker_$j.log' : null,
    );

    consumers.add(() async {
      await for (final message in stream) {
        switch (message) {
          case GeneratorProgressMessage():
            // Real-time constraint counter intentionally suppressed; the
            // dashboard refreshes only on completed puzzles for clarity.
            break;
          case GeneratorTargetMessage(:final label):
            // Each target message marks the start of a new generateOne
            // attempt — bump the counter unconditionally, even if the label
            // is identical to the previous one (worker may re-pick the same
            // bin with a different sub-config).
            attemptCounts[j]++;
            currentTargets[j] = label;
            if (debug) {
              stderr.writeln('[w$j] -> ${label ?? '(idle)'}');
            } else {
              render();
            }
          case GeneratorPuzzleMessage(:final puzzleLine, :final level):
            successCounts[j]++;
            generated++;
            final now = totalSw.elapsedMilliseconds;
            durations.add(now - lastPuzzleMs);
            lastPuzzleMs = now;

            if (sink != null) {
              singleSinkChain = singleSinkChain.then((_) async {
                sink!.writeln(puzzleLine);
                await sink.flush();
              });
              await singleSinkChain;
              // Re-read the file so stats reflect what's actually on disk.
              currentLines = File(output!).readAsLinesSync();
            } else {
              final levelSink = levelSinks![level];
              if (levelSink != null) {
                final prev = levelSinkChains[level] ?? Future.value();
                final next = prev.then((_) async {
                  levelSink.writeln(puzzleLine);
                  await levelSink.flush();
                });
                levelSinkChains[level] = next;
                await next;
              } else {
                // Should not happen — generator only emits cascade levels.
                stderr.writeln(
                  'WARN: out-of-cascade level $level for $puzzleLine',
                );
              }
              currentLines = [...currentLines, puzzleLine];
            }
            cachedStats = _CollectionStats.fromLines(currentLines);
            if (debug) {
              stderr.writeln(
                '[w$j] + generated ${level.name} '
                'in ${_fmt(totalSw.elapsed)}',
              );
            } else {
              render();
            }
          case GeneratorRejectMessage(:final reason):
            rejectCounts[reason] = (rejectCounts[reason] ?? 0) + 1;
            if (debug) {
              stderr.writeln('[w$j] reject: ${reason.name}');
            } else {
              render();
            }
          case GeneratorTimingsMessage(:final micros, :final calls):
            for (final entry in micros.entries) {
              stageTotalsMicros[entry.key] =
                  (stageTotalsMicros[entry.key] ?? 0) + entry.value;
            }
            for (final entry in calls.entries) {
              stageTotalsCalls[entry.key] =
                  (stageTotalsCalls[entry.key] ?? 0) + entry.value;
            }
          case GeneratorDoneMessage():
            currentTargets[j] = null;
            if (debug) {
              stderr.writeln('[w$j] finished');
            } else {
              render();
            }
        }
      }
    }());
  }

  await Future.wait(consumers);
  finish();
}

/// Aggregated corpus stats across all axes the equilibrium engine watches:
/// per-slug usage, grid-area buckets, and number-of-distinct-types.
class _CollectionStats {
  final Map<String, int> slugs;
  // Bucket counts in fixed display order: ≤20, 21-40, 41-80, >80.
  final List<int> sizeBuckets;
  // n=1..5 mapped to '1'..'5'; n>=6 collapsed into '6+' (reliquat bucket,
  // never targeted by equilibrium).
  final Map<String, int> nTypes;

  _CollectionStats(this.slugs, this.sizeBuckets, this.nTypes);

  factory _CollectionStats.fromLines(List<String> lines) {
    final slugs = {for (final s in constraintSlugs) s: 0};
    final sizeBuckets = [0, 0, 0, 0];
    final nTypes = <String, int>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final fields = trimmed.split('_');
      if (fields.length < 5) continue;

      final dims = fields[2].split('x');
      if (dims.length == 2) {
        final w = int.tryParse(dims[0]) ?? 0;
        final h = int.tryParse(dims[1]) ?? 0;
        final area = w * h;
        if (area <= 20) {
          sizeBuckets[0]++;
        } else if (area <= 40) {
          sizeBuckets[1]++;
        } else if (area <= 80) {
          sizeBuckets[2]++;
        } else {
          sizeBuckets[3]++;
        }
      }

      final puzzleSlugs = fields[4]
          .split(';')
          .map((c) => c.split(':').first)
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final s in puzzleSlugs) {
        slugs[s] = (slugs[s] ?? 0) + 1;
      }
      final n = puzzleSlugs.length;
      final key = n >= 6 ? '6+' : n.toString();
      nTypes[key] = (nTypes[key] ?? 0) + 1;
    }

    return _CollectionStats(slugs, sizeBuckets, nTypes);
  }
}

/// Clear the screen and redraw the full dashboard: header, progress,
/// per-worker targets, then three histograms (constraints / sizes / types).
void _renderDashboard({
  required int generated,
  required int count,
  required int jobs,
  required Duration elapsed,
  required List<int> durations,
  required String equilibriumLine,
  required int existingPuzzles,
  required _CollectionStats stats,
  required Set<String> universeSlugs,
  required int minWidth,
  required int maxWidth,
  required int minHeight,
  required int maxHeight,
  required int domainSize,
  required Set<String> requiredRules,
  required Set<String> bannedRules,
  required List<GenerationStrategy> strategies,
  Set<String>? allowedRules,
  List<String?> targets = const [],
  List<int> attemptCounts = const [],
  List<int> successCounts = const [],
  Map<GenerationRejectReason, int> rejectCounts = const {},
  Map<String, int> stageTotalsMicros = const {},
  Map<String, int> stageTotalsCalls = const {},
}) {
  // \x1B[2J clears the screen, \x1B[H homes the cursor.
  stderr.write('\x1B[2J\x1B[H');
  stderr.writeln('Corpus: $existingPuzzles puzzles (live count)');
  stderr.writeln(equilibriumLine);
  stderr.writeln('Jobs: $jobs parallel worker(s)');
  // Surface the CLI knobs that drove this run, so a glance at the
  // dashboard explains where the histograms come from. "any" stands in
  // for an unset filter (no `--require` / no `--ban`).
  final sizeLabel = (minWidth == maxWidth && minHeight == maxHeight)
      ? '${minWidth}x$minHeight'
      : '$minWidth-$maxWidth × $minHeight-$maxHeight';
  final reqLabel = requiredRules.isEmpty ? 'any' : requiredRules.join(',');
  final banLabel = bannedRules.isEmpty ? 'none' : bannedRules.join(',');
  final allowLabel = (allowedRules == null || allowedRules.isEmpty)
      ? 'all'
      : allowedRules.join(',');
  String labelFor(GenerationStrategy s) => switch (s) {
    GenerationStrategy.singleTier => 'single-tier',
    GenerationStrategy.phaseGate => 'phase-gate',
    GenerationStrategy.phase1Oneshot => 'phase-1-oneshot',
    GenerationStrategy.propOnly => 'prop-only',
  };
  stderr.writeln(
    'Config: size $sizeLabel | domain $domainSize | '
    'allow $allowLabel | require $reqLabel | ban $banLabel',
  );
  stderr.writeln('');
  if (durations.isEmpty) {
    stderr.writeln('[${_fmt(elapsed)}] $generated/$count');
  } else {
    stderr.writeln(
      '[${_fmt(elapsed)}] $generated/$count '
      '| avg ${_avgMs(durations)}ms, med ${_medianMs(durations)}ms',
    );
  }
  if (targets.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln('Workers:');
    for (int i = 0; i < targets.length; i++) {
      final t = targets[i] ?? '(idle)';
      // "att/ok" shows total attempts and successful ones — their delta
      // is the failure count, a live signal of how aggressive the bin is.
      final att = i < attemptCounts.length ? attemptCounts[i] : 0;
      final ok = i < successCounts.length ? successCounts[i] : 0;
      final counter = 'att $att/ok $ok';
      // Strategy assigned to this worker (round-robin from the
      // user-supplied list). Same logic as bin/generate.dart's
      // GeneratorConfig builder, repeated here so the dashboard
      // stays decoupled from the worker spawn loop.
      final strat = labelFor(strategies[i % strategies.length]);
      stderr.writeln(
        '  #${i.toString().padLeft(2)} [$counter] '
        '<${strat.padRight(15)}> → $t',
      );
    }
  }

  // Aggregate rejection breakdown — `att - ok` tells you how often a
  // worker rejected; this line tells you *why*. A run dominated by
  // `ratioTooHigh` means the iterative loop isn't picking strong-enough
  // constraints (or the threshold is too tight) — see `docs/dev/third_color.md`
  // for the targeted constraint generation plan that addresses this.
  // Always print the rejection line, even with zero rejects: when
  // staring at the dashboard mid-run, "no Rejects line" is ambiguous
  // (no rejects yet? or did I forget to enable that view?). Showing
  // "Rejects (0)" removes the ambiguity until the run completes.
  final totalRejects = rejectCounts.values.fold<int>(0, (a, b) => a + b);
  stderr.writeln('');
  final parts = <String>[];
  for (final r in GenerationRejectReason.values) {
    final n = rejectCounts[r] ?? 0;
    if (n > 0) parts.add('${r.name}=$n');
  }
  final partsStr = parts.isEmpty ? '-' : parts.join(', ');
  stderr.writeln('Rejects ($totalRejects): $partsStr');

  // Per-stage timing breakdown — summed across every worker and every
  // attempt (success + failure). Columns:
  //   * pct       share of CPU time
  //   * total     cumulative wall time
  //   * calls     total invocations of the stage across all attempts
  //                (loop stages run many times per attempt; one-shot
  //                 stages match the attempt count)
  //   * avg       µs per call — the per-call cost, the actual "is this
  //                worth optimising?" signal
  // Sorted by total time descending so the dominant stage is on top.
  final totalStageMicros = stageTotalsMicros.values.fold<int>(
    0,
    (a, b) => a + b,
  );
  if (totalStageMicros > 0) {
    stderr.writeln('');
    stderr.writeln(
      'Timing breakdown (sum across $jobs workers, '
      '${(totalStageMicros / 1000000).toStringAsFixed(1)}s of CPU):',
    );
    stderr.writeln(
      '  ${'stage'.padRight(18)}'
      '${'pct'.padLeft(7)}'
      '${'total'.padLeft(11)}'
      '${'calls'.padLeft(11)}'
      '${'avg'.padLeft(11)}',
    );
    final entries = stageTotalsMicros.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries) {
      if (e.value == 0) continue;
      final calls = stageTotalsCalls[e.key] ?? 0;
      final pct = '${(e.value * 100 / totalStageMicros).toStringAsFixed(1)}%';
      final secs = '${(e.value / 1000000).toStringAsFixed(2)}s';
      final avg = calls > 0 ? _humanMicros((e.value / calls).round()) : '-';
      stderr.writeln(
        '  ${e.key.padRight(18)}'
        '${pct.padLeft(7)}'
        '${secs.padLeft(11)}'
        '${calls.toString().padLeft(11)}'
        '${avg.padLeft(11)}',
      );
    }

    // Two-tier acceptance breakdown — derived from the timer counts.
    // `loop_candidate_prop.calls` runs once per candidate tested.
    // `loop_candidate_full.calls` runs only when the cheap signal was
    // silent, so `prop - full` is the count of cheap-path accepts.
    // The remaining calls fall to the expensive path, which itself
    // either accepts (updating cachedRatioBefore) or rejects to
    // secondChance. The cheap-accept ratio is the headline number to
    // decide whether the cheap path is paying off in this run.
    final propCalls = stageTotalsCalls['loop_candidate_prop'] ?? 0;
    final fullCalls = stageTotalsCalls['loop_candidate_full'] ?? 0;
    if (propCalls > 0) {
      final cheapAccepts = propCalls - fullCalls;
      final cheapPct = (cheapAccepts * 100 / propCalls).toStringAsFixed(1);
      stderr.writeln('');
      stderr.writeln(
        'Two-tier breakdown: $propCalls candidates tested → '
        '$cheapAccepts cheap accepts ($cheapPct%), '
        '$fullCalls fell to expensive path',
      );
    }
  }

  // Targets are absolute counts: what each bin's count would be if the
  // current corpus matched the equilibrium profile exactly. Showing them
  // alongside the observed value makes "which bin is most under-represented"
  // visually obvious — it's the row with the largest negative gap.
  final axisTargets = _computeAxisTargets(
    totalCorpus: existingPuzzles,
    slugCounts: stats.slugs,
    universeSlugs: universeSlugs,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
  );

  // Force a stable display order 1, 2, ..., 5, 6+ even when some buckets are 0.
  final orderedTypes = <String, int>{
    for (final k in ['1', '2', '3', '4', '5', '6+']) k: stats.nTypes[k] ?? 0,
  };
  final sizeBuckets = {
    '≤20': stats.sizeBuckets[0],
    '21-40': stats.sizeBuckets[1],
    '41-80': stats.sizeBuckets[2],
    '>80': stats.sizeBuckets[3],
  };

  // Bars now visualize the *gap to target* (= target - observed, clamped to
  // ≥ 0), not the raw count. The longest bar across all histograms marks
  // the bin the picker is most likely to chase next. Target=0 buckets (e.g.
  // ntypes 6+) always have gap=0 → no bar, which is the right signal: they
  // are reliquats, never pushed.
  final globalMaxGap = [
    _maxGap(stats.slugs, axisTargets.slug),
    _maxGap(sizeBuckets, axisTargets.size),
    _maxGap(orderedTypes, axisTargets.ntypes),
  ].fold<double>(0.0, max);

  stderr.writeln('');
  stderr.writeln('Constraints:');
  _writeHistogram(
    stats.slugs,
    sortByValue: true,
    targets: axisTargets.slug,
    globalMaxGap: globalMaxGap,
  );
  stderr.writeln('');
  stderr.writeln('Sizes (width×height):');
  _writeHistogram(
    sizeBuckets,
    sortByValue: false,
    targets: axisTargets.size,
    globalMaxGap: globalMaxGap,
  );
  stderr.writeln('');
  stderr.writeln('Distinct types per puzzle:');
  _writeHistogram(
    orderedTypes,
    sortByValue: false,
    targets: axisTargets.ntypes,
    globalMaxGap: globalMaxGap,
  );
}

class _AxisTargets {
  final Map<String, double> slug;
  final Map<String, double> size;
  final Map<String, double> ntypes;
  const _AxisTargets({
    required this.slug,
    required this.size,
    required this.ntypes,
  });
}

/// Compute the equilibrium-target *absolute count* for each bin shown in the
/// dashboard, given the current corpus size. Mirrors the formulas used by
/// `equilibrium.dart` so the dashboard reflects exactly what the picker sees.
_AxisTargets _computeAxisTargets({
  required int totalCorpus,
  required Map<String, int> slugCounts,
  required Set<String> universeSlugs,
  required int minWidth,
  required int maxWidth,
  required int minHeight,
  required int maxHeight,
}) {
  // Slug axis: each puzzle contributes to multiple slug bins (one per
  // distinct slug). The "balanced" target per slug is therefore the
  // average slug-uses spread evenly: `totalSlugUses / nSlugs`, not
  // `totalCorpus / nSlugs`. Mirrors the formula used by `_scoreAll`.
  final slug = <String, double>{};
  if (universeSlugs.isNotEmpty) {
    final totalSlugUses = slugCounts.values.fold<int>(0, (a, b) => a + b);
    final perSlug = totalSlugUses / universeSlugs.length;
    for (final s in universeSlugs) {
      slug[s] = perSlug;
    }
  }

  // Size axis: build the universe (clamped to [kMinSide, kMaxSide]) then
  // aggregate the per-size target (asymmetric-Gaussian-on-area) into the
  // same display buckets the observed counts use. Smalls are favored over
  // larges by construction — see `sizeTargetShare` in equilibrium.dart.
  final universe = TargetUniverse(
    allowedSlugs: universeSlugs,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
  );
  final size = <String, double>{'≤20': 0, '21-40': 0, '41-80': 0, '>80': 0};
  for (final (w, h) in universe.allowedSizes) {
    final area = w * h;
    final bucket = area <= 20
        ? '≤20'
        : area <= 40
        ? '21-40'
        : area <= 80
        ? '41-80'
        : '>80';
    size[bucket] =
        (size[bucket] ?? 0) + totalCorpus * sizeTargetShare(w, h, universe);
  }

  // Ntypes axis: explicit profile from kTargetNTypesProfile (1..5). The 6+
  // reliquat bucket has target 0 — surfaced so the dashboard can show
  // drift without the picker ever pushing those puzzles.
  final ntypes = <String, double>{};
  for (final entry in kTargetNTypesProfile.entries) {
    ntypes['${entry.key}'] = totalCorpus * entry.value;
  }
  ntypes['6+'] = 0;

  return _AxisTargets(slug: slug, size: size, ntypes: ntypes);
}

/// Largest `target - observed` across all rows of one histogram, clamped to 0.
/// Rows whose target is missing or 0 contribute 0 (the 6+ reliquat bucket
/// must never be flagged as "to push" since its objective is 0 by design).
double _maxGap(Map<String, int> stats, Map<String, double> targets) {
  double m = 0.0;
  for (final entry in stats.entries) {
    final t = targets[entry.key] ?? 0.0;
    if (t <= 0) continue;
    final gap = t - entry.value;
    if (gap > m) m = gap;
  }
  return m;
}

/// Render one histogram. The bar length encodes the *gap to target*
/// (= target − observed, clamped to ≥ 0), normalized by [globalMaxGap]
/// across all displayed histograms so bars are visually comparable
/// across axes — the longest bar anywhere on the dashboard is the bin
/// the equilibrium picker is most likely to chase next.
void _writeHistogram(
  Map<String, int> stats, {
  required bool sortByValue,
  required double globalMaxGap,
  Map<String, double>? targets,
}) {
  if (stats.isEmpty) return;
  final entries = stats.entries.toList();
  if (sortByValue) {
    entries.sort((a, b) => b.value.compareTo(a.value));
  }
  const barWidth = 30;
  // Fixed label column so the bars align horizontally across all three
  // histograms (constraints / sizes / ntypes), regardless of which has the
  // longest key. 10 characters is wide enough for every current label.
  const keyWidth = 10;
  // Pre-compute the value column width so the "value / target" suffix lines
  // up across rows even when counts have different digit lengths.
  final valWidth = entries.map((e) => '${e.value}'.length).fold<int>(0, max);
  for (final entry in entries) {
    final target = targets?[entry.key];
    final gap = (target == null || target <= 0)
        ? 0.0
        : (target - entry.value).clamp(0.0, double.infinity).toDouble();
    final bar = globalMaxGap > 0
        ? '█' * ((gap / globalMaxGap * barWidth).round())
        : '';
    final suffix = target == null
        ? '${entry.value}'
        : '${'${entry.value}'.padLeft(valWidth)} / ${target.round()}';
    stderr.writeln('  ${entry.key.padRight(keyWidth)} $bar $suffix');
  }
}

// --- Check mode ---

Future<void> _runCheck(String filePath, {bool debug = false}) async {
  final file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $filePath');
    exit(1);
  }

  final goodPath = _suffixedPath(filePath, 'good');
  final badPath = _suffixedPath(filePath, 'bad');
  final goodSink = File(goodPath).openWrite();
  final badSink = File(badPath).openWrite();

  final lines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();

  int valid = 0;
  int invalid = 0;
  int errored = 0;
  final sw = Stopwatch()..start();
  final goodLines = <String>[];
  var stats = _CollectionStats.fromLines(goodLines);

  void render() {
    if (debug) {
      final pct = lines.isEmpty
          ? 0
          : (100 * (valid + invalid + errored) ~/ lines.length);
      stderr.writeln(
        '[${valid + invalid + errored}/${lines.length} ($pct%)] '
        'valid $valid | invalid $invalid | errors $errored',
      );
      return;
    }
    _renderCheckDashboard(
      filePath: filePath,
      goodPath: goodPath,
      badPath: badPath,
      checked: valid + invalid + errored,
      total: lines.length,
      valid: valid,
      invalid: invalid,
      errored: errored,
      elapsed: sw.elapsed,
      stats: stats,
    );
  }

  render();

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    try {
      final p = Puzzle(line);
      if (p.isDeductivelyUnique()) {
        valid++;
        goodSink.writeln(line);
        goodLines.add(line);
      } else {
        invalid++;
        badSink.writeln('# INVALID (not deductively unique)');
        badSink.writeln(line);
      }
    } catch (e) {
      errored++;
      badSink.writeln('# ERROR: $e');
      badSink.writeln(line);
    }
    // Re-render every 10 puzzles (and at the end) to amortize the O(N)
    // corpus rescan and avoid screen flicker on fast checks.
    if ((i + 1) % 10 == 0 || i + 1 == lines.length) {
      stats = _CollectionStats.fromLines(goodLines);
      render();
    }
  }

  await goodSink.flush();
  await goodSink.close();
  await badSink.flush();
  await badSink.close();

  stderr.writeln('');
  stderr.writeln(
    'Done in ${_fmt(sw.elapsed)}: $valid valid, $invalid invalid'
    '${errored > 0 ? ', $errored errored' : ''} out of ${lines.length}',
  );
  stderr.writeln('  good → $goodPath');
  stderr.writeln('  bad  → $badPath');
  if (invalid + errored > 0) exit(1);
}

/// Insert [suffix] before the .txt extension, or append it when there is none.
/// E.g. `assets/foo.txt` + `good` → `assets/foo.good.txt`.
String _suffixedPath(String filePath, String suffix) {
  if (filePath.endsWith('.txt')) {
    return '${filePath.substring(0, filePath.length - 4)}.$suffix.txt';
  }
  return '$filePath.$suffix';
}

/// Same shape as [_renderDashboard] but tailored for check mode: progress on
/// top, then count-only histograms of the puzzles kept in the .good file.
void _renderCheckDashboard({
  required String filePath,
  required String goodPath,
  required String badPath,
  required int checked,
  required int total,
  required int valid,
  required int invalid,
  required int errored,
  required Duration elapsed,
  required _CollectionStats stats,
}) {
  stderr.write('\x1B[2J\x1B[H');
  stderr.writeln('Checking $filePath');
  stderr.writeln('  good → $goodPath');
  stderr.writeln('  bad  → $badPath');
  stderr.writeln('');
  final pct = total == 0 ? 0 : (100 * checked / total).round();
  stderr.writeln(
    '[${_fmt(elapsed)}] $checked/$total ($pct%) | '
    'valid $valid | invalid $invalid'
    '${errored > 0 ? ' | errors $errored' : ''}',
  );

  final orderedTypes = <String, int>{
    for (final k in ['1', '2', '3', '4', '5', '6+']) k: stats.nTypes[k] ?? 0,
  };
  final sizeBuckets = {
    '≤20': stats.sizeBuckets[0],
    '21-40': stats.sizeBuckets[1],
    '41-80': stats.sizeBuckets[2],
    '>80': stats.sizeBuckets[3],
  };

  stderr.writeln('');
  stderr.writeln('Constraints (kept):');
  _writeCountHistogram(stats.slugs, sortByValue: true);
  stderr.writeln('');
  stderr.writeln('Sizes (width×height):');
  _writeCountHistogram(sizeBuckets, sortByValue: false);
  stderr.writeln('');
  stderr.writeln('Distinct types per puzzle:');
  _writeCountHistogram(orderedTypes, sortByValue: false);
}

/// Bar length proportional to the largest value in the row set — unlike
/// [_writeHistogram], which encodes a target gap.
void _writeCountHistogram(Map<String, int> stats, {required bool sortByValue}) {
  if (stats.isEmpty) return;
  final entries = stats.entries.toList();
  if (sortByValue) {
    entries.sort((a, b) => b.value.compareTo(a.value));
  }
  const barWidth = 30;
  const keyWidth = 10;
  final maxVal = entries.map((e) => e.value).fold<int>(0, max);
  final valWidth = entries.map((e) => '${e.value}'.length).fold<int>(0, max);
  for (final entry in entries) {
    final bar = maxVal > 0
        ? '█' * ((entry.value / maxVal * barWidth).round())
        : '';
    stderr.writeln(
      '  ${entry.key.padRight(keyWidth)} ${bar.padRight(barWidth)} '
      '${'${entry.value}'.padLeft(valWidth)}',
    );
  }
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

/// Compact microseconds → `12µs` / `3.4ms` / `1.2s`, picking the unit
/// so 2-3 significant digits show. Used by the timing-breakdown table
/// where space is tight but the dynamic range spans 1µs → 10s.
String _humanMicros(int micros) {
  if (micros < 1000) return '$micros µs';
  if (micros < 1000000) return '${(micros / 1000).toStringAsFixed(1)}ms';
  return '${(micros / 1000000).toStringAsFixed(2)}s';
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
    'allowed': null,
    'required': null,
    'checkFile': null,
    'statsDir': null,
    'equilibrium': true,
    'jobs': Platform.numberOfProcessors,
    'logDir': null,
    'debug': false,
    'domain': 2,
    'strategy': <GenerationStrategy>[GenerationStrategy.phaseGate],
    'maxStall': 15,
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
      case '--allow':
        result['allowed'] = args[++i];
      case '--require':
        result['required'] = args[++i];
      case '--no-equilibrium':
        result['equilibrium'] = false;
      case '-j':
      case '--jobs':
        result['jobs'] = int.parse(args[++i]);
      case '--log-dir':
        result['logDir'] = args[++i];
      case '--debug':
        result['debug'] = true;
      case '--domain':
        final v = int.parse(args[++i]);
        if (v != 2 && v != 3) {
          stderr.writeln('--domain must be 2 or 3 (got $v)');
          exit(1);
        }
        result['domain'] = v;
      case '--max-stall':
        result['maxStall'] = int.parse(args[++i]);
      case '--strategy':
        final v = args[++i];
        // Comma-separated list → round-robin across workers. Single
        // value → all workers use the same strategy.
        result['strategy'] = v.split(',').map((p) {
          switch (p.trim()) {
            case 'single-tier':
              return GenerationStrategy.singleTier;
            case 'phase-gate':
              return GenerationStrategy.phaseGate;
            case 'phase-1-oneshot':
              return GenerationStrategy.phase1Oneshot;
            case 'prop-only':
              return GenerationStrategy.propOnly;
            default:
              stderr.writeln(
                "--strategy values must be from "
                "'single-tier', 'phase-gate', 'phase-1-oneshot', "
                "'prop-only' (got '$p')",
              );
              exit(1);
          }
        }).toList();
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
  --check FILE            Validate puzzles. Writes valid puzzles to
                          FILE.good.txt and invalid ones to FILE.bad.txt.
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
      --allow RULES       Comma-separated whitelist — when set, only these
                          slugs are eligible (e.g. NC,EY,RC,CC for a small
                          subset). Combines with --ban: the effective set
                          is (allow minus ban). Useful for bisecting which
                          constraint is making generation slow.
      --require RULES     Comma-separated rule slugs to require (e.g. PA,GS)
      --domain N          Colour domain size: 2 (black/white, default) or 3
                          (adds purple). 3-colour puzzles use option-pruning
                          deductions; see docs/dev/third_color.md.
      --strategy S        Candidate-acceptance strategy (default: phase-gate).
                          Accepts a single value or a comma-separated list;
                          a list is distributed round-robin across workers
                          for a heterogeneous pool (e.g.
                          --strategy phase-gate,phase-1-oneshot,prop-only
                          on -j 4 → 2× phase-gate + 1× each others). Slugs
                          unreachable by one strategy (e.g. prop-only on
                          FM) are picked up by sibling strategies via the
                          shared equilibrium picker.
                          Values:
                            single-tier      Pre-everything baseline. Full
                                             cloned.solve() per candidate;
                                             accept iff post-solve ratio
                                             strictly drops. No cleanup.
                            phase-gate       Phase 1 cheap prop-only accepts
                                             then phase 2 full-solve fallback
                                             + removeUselessRules post-loop.
                            phase-1-oneshot  Phase 1 limited to one sweep,
                                             then unconditional transition
                                             to phase 2. Caps phase-1 cost
                                             when cheap accepts are sparse.
                            prop-only        Phase 1 only — no fallback to
                                             phase 2. Rejects puzzles that
                                             need force; produces only
                                             pure-propagation puzzles.
      --max-stall S       No-progress watchdog: abandon an attempt that
                          has spent S seconds without accepting a
                          candidate. Avoids pathological cases where
                          one worker burns the entire budget on a single
                          plateaued attempt. Default 15 s. Pass 0 to
                          disable.
      --no-equilibrium    Disable the multi-axis equilibrium bias.
                          Default: ON. When OFF, only the legacy slug-usage
                          bias is applied (matches pre-equilibrium behavior).
  -j, --jobs N            Number of parallel worker isolates
                          (default: number of CPU cores, currently
                          ${Platform.numberOfProcessors}). Clamped to [1, count].
                          Each worker starts from the same initial corpus
                          and evolves its equilibrium state independently.
      --log-dir DIR       Write per-worker diagnostic logs to
                          DIR/worker_<n>.log (one file per parallel
                          worker, append mode). Useful to investigate
                          why a worker is stuck without producing
                          puzzles. Default: no logging.

General:
      --debug             Enable debug mode: sequential output
                          instead of the real-time dashboard.
  -h, --help              Show this help

Rule slugs: $rules

Examples:
  dart run bin/generate.dart -n 100 -o puzzles.txt
  dart run bin/generate.dart --check assets/try_me.txt
  dart run bin/generate.dart --read-stats ~/Documents/getsomepuzzle/
''');
}
