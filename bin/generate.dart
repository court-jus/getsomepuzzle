import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/feasibility.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/worker.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
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
        detailed: parsed['detailed'] as bool,
      );
    case 'read-stats':
      _runReadStats(parsed['statsDir'] as String);
  }
}

// --- Generate mode ---

Future<void> _runGenerate(Map<String, dynamic> parsed) async {
  final count = parsed['count'] as int;
  final minWidth = parsed['minWidth'] as int;
  final maxWidth = parsed['maxWidth'] as int;
  final minHeight = parsed['minHeight'] as int;
  final maxHeight = parsed['maxHeight'] as int;
  final maxTime = parsed['maxTime'] as int;
  final maxAttemptTime = parsed['maxAttemptTime'] as int;
  final output = parsed['output'] as String?;
  final bannedRules = (parsed['banned'] as String?)?.split(',').toSet() ?? {};
  final allowedSlugsArg = (parsed['allowed'] as String?)?.split(',').toSet();
  final requiredRules =
      (parsed['required'] as String?)?.split(',').toSet() ?? {};
  final equilibriumRequested = parsed['equilibrium'] as bool;
  final jobs = (parsed['jobs'] as int).clamp(1, count);
  final logDir = parsed['logDir'] as String?;
  final targetLevel = parsed['targetLevel'] as PuzzleLevel?;
  final easingBudget = parsed['easingBudget'] as int;
  final scenarioPathBased = (parsed['scenario'] as String?) == 'path-based';
  final scenarioSyBased = (parsed['scenario'] as String?) == 'sy-based';
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
  // Wall-clock timestamp (ms since the run started) when the worker last
  // received a `'target'` event. The periodic redraw turns this into a
  // "running Xs" annotation on each worker line — visibility into how long
  // the current attempt has been chewing. Null between attempts (after
  // `'puzzle'` or `'done'`, before the next `'target'`).
  final attemptStartMs = List<int?>.filled(jobs, null);
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

  // Coordinator for the cross-worker bucket rotation. Lives here in the main
  // isolate because it needs (a) the *global* corpus stats — workers only see
  // their own output — and (b) a shared claim ledger so each worker chases a
  // distinct deficient bucket. `globalEquiStats` is rebuilt whenever a puzzle
  // lands (same cadence as `cachedStats`), so the rotation always ranks gaps
  // against the live corpus. Only active in equilibrium mode.
  var globalEquiStats = EquilibriumStats.fromLines(currentLines);
  final coordinatorUniverse = TargetUniverse(
    allowedSlugs: universeSlugs,
    minWidth: minWidth,
    maxWidth: maxWidth,
    minHeight: minHeight,
    maxHeight: maxHeight,
  );
  final bucketRotation = BucketRotation();
  // Answers a worker's `requestTarget`: hands out the next deficient bucket
  // key, or null to let the worker decide locally (no positive-gap bucket).
  String? assignBucket(int workerIndex) =>
      bucketRotation.next(globalEquiStats, coordinatorUniverse)?.key;

  void render() {
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
      attemptStartMs: attemptStartMs,
      nowMs: totalSw.elapsedMilliseconds,
      maxAttemptTimeMs: maxAttemptTime * 1000,
    );
  }

  // Initial dashboard render (corpus stats before generation starts).
  render();

  final workers = <GeneratorWorker>[];
  // Periodic redraw — the dashboard now updates every 10s even when no
  // worker emits a message, so a worker stuck on a slow attempt still
  // shows live "running Xs" feedback. Set after the workers spawn,
  // cancelled in `finish()`.
  Timer? dashboardTimer;
  bool finished = false;
  void finish() {
    if (finished) return;
    finished = true;
    dashboardTimer?.cancel();
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

  // Append-only telemetry of every attempt (success + abandon). The file
  // is opened in append mode so re-runs accumulate; the header is emitted
  // only on creation — re-runs preserve everything already written. The
  // `commit` column lets us bucket rows by generator version, the `date`
  // column by run timestamp.
  final commitHash = _readCommitHash();
  final statsFile = File('generator_stats.csv');
  final statsExists = statsFile.existsSync();
  final statsSink = statsFile.openWrite(mode: FileMode.append);
  if (!statsExists) {
    statsSink.writeln(_statsHeader());
  }
  // Serializes writes across the parallel worker consumers — without this
  // chain, concurrent `writeln` calls on the same sink can interleave.
  Future<void> statsChain = Future.value();

  // Persistent seed for the infeasibility blacklist: combos that have been
  // tried ≥M times historically without a single success. Distributed to
  // every worker so they all start the run with the same view of what's
  // known-impossible. Empty when --no-blacklist or when no prior CSV exists.
  final useBlacklist = parsed['useBlacklist'] as bool;
  final blacklistMinAttempts = parsed['blacklistMinAttempts'] as int;
  final blacklistAdaptiveK = parsed['blacklistAdaptiveK'] as int;
  final blacklistSkipSafety = parsed['blacklistSkipSafety'] as int;
  final seedBlacklist = useBlacklist
      ? readPersistentBlacklist(
          csvPath: 'generator_stats.csv',
          minAttempts: blacklistMinAttempts,
        )
      : const <String>{};
  if (seedBlacklist.isNotEmpty) {
    stderr.writeln(
      'Blacklist seed: ${seedBlacklist.length} infeasible combo(s) loaded '
      'from generator_stats.csv (>=$blacklistMinAttempts tries, 0 success)',
    );
  }
  final seedBlacklistList = seedBlacklist.toList(growable: false);

  final consumers = <Future<void>>[];
  for (int j = 0; j < jobs; j++) {
    final workerCount = base + (j < remainder ? 1 : 0);
    if (workerCount == 0) continue;
    final config = GeneratorConfig(
      width: minWidth,
      height: minHeight,
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
      maxTime: Duration(seconds: maxTime),
      maxAttemptTime: Duration(seconds: maxAttemptTime),
      requiredRules: requiredRules,
      allowedSlugs: allowedSlugs,
      count: workerCount,
      targetLevel: targetLevel,
      easingBudget: Duration(seconds: easingBudget),
      pathBasedScenario: scenarioPathBased,
      syBasedScenario: scenarioSyBased,
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
      seedBlacklist: seedBlacklistList,
      adaptiveK: blacklistAdaptiveK,
      skipSafety: blacklistSkipSafety,
      // Cross-worker rotation: only wire the coordinator in equilibrium mode.
      // Off → workers keep the legacy local random/argmax path.
      assignTarget: equilibriumRequested ? assignBucket : null,
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
            attemptStartMs[j] = totalSw.elapsedMilliseconds;
            render();
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
            globalEquiStats = EquilibriumStats.fromLines(currentLines);
            render();
          case GeneratorAttemptMessage():
            // One row per attempt — both successes and abandons. Chained
            // through `statsChain` so concurrent worker streams don't
            // interleave their CSV writes. The attempt is finished, so
            // clear the "running …" timer on the dashboard.
            attemptStartMs[j] = null;
            final row = _statsRow(message, commitHash);
            statsChain = statsChain.then((_) async {
              statsSink.writeln(row);
              await statsSink.flush();
            });
          case GeneratorDoneMessage():
            currentTargets[j] = null;
            attemptStartMs[j] = null;
            render();
        }
      }
    }());
  }

  dashboardTimer = Timer.periodic(const Duration(seconds: 10), (_) {
    render();
  });

  await Future.wait(consumers);
  // Drain any pending CSV writes before letting `finish()` call exit(0).
  await statsChain;
  await statsSink.close();
  finish();
}

/// Short HEAD commit hash, captured once per CLI run and embedded in every
/// row of `generator_stats.csv` so post-hoc analysis can tell which version
/// of the generator produced each attempt. Falls back to `'unknown'` when
/// not running inside a git checkout (CI tarball, archive, …).
String _readCommitHash() {
  try {
    final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
    if (r.exitCode == 0) {
      return (r.stdout as String).trim();
    }
  } catch (_) {}
  return 'unknown';
}

const _statsColumns = [
  'date',
  'commit',
  'worker',
  'phase',
  'target_key',
  'width',
  'height',
  'ntypes_intended',
  'preferred_slugs',
  'allowed_slugs',
  'scenario',
  'outcome',
  'reason',
  'duration_ms',
  'level',
  'puzzle_line',
  // `slug:gap` pairs that biased the secondary candidate sort, joined with
  // `|`. Empty during warm-up and when equilibrium is off; zero-gap slugs
  // are not serialized.
  'slug_deficits',
];

String _statsHeader() => _statsColumns.join(',');

String _statsRow(GeneratorAttemptMessage m, String commitHash) {
  final phase = m.inWarmup
      ? 'warmup'
      : (m.targetKey != null ? 'equilibrium' : 'fixed');
  final level = m.puzzleLevelIndex != null
      ? PuzzleLevel.values[m.puzzleLevelIndex!].name
      : '';
  // Slugs joined with `|` (not `,`) so the column stays single-field even
  // without CSV-quoting; the escaper still kicks in for `puzzle_line`
  // (which contains commas via the constraint suffix).
  final deficits = m.slugDeficitScores;
  String deficitField = '';
  if (deficits != null && deficits.isNotEmpty) {
    final entries = deficits.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    deficitField = entries
        .map((e) => '${e.key}:${e.value.toStringAsFixed(4)}')
        .join('|');
  }
  final fields = <String>[
    _csvField(DateTime.now().toUtc().toIso8601String()),
    _csvField(commitHash),
    '${m.workerIndex}',
    _csvField(phase),
    _csvField(m.targetKey ?? ''),
    '${m.width}',
    '${m.height}',
    m.ntypesIntended?.toString() ?? '',
    _csvField(m.preferredSlugs.join('|')),
    _csvField(m.allowedSlugs?.join('|') ?? ''),
    _csvField(m.scenario),
    _csvField(m.success ? 'success' : 'failure'),
    _csvField(m.rejectReason ?? ''),
    '${m.durationMs}',
    _csvField(level),
    _csvField(m.puzzleLine ?? ''),
    _csvField(deficitField),
  ];
  return fields.join(',');
}

String _csvField(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Display order of the grid-area buckets. Used both to size the count list in
/// [_CollectionStats] and to label the rows in the dashboard, so observed
/// counts and equilibrium targets share the exact same partition.
const List<String> kSizeBucketLabels = [
  '≤12',
  '13-20',
  '21-30',
  '31-42',
  '43-56',
  '57-72',
  '73-80',
  '>80',
];

/// Map a grid area (width × height) to its display bucket label. The boundaries
/// match [kSizeBucketLabels] one-to-one.
String _sizeBucket(int area) {
  if (area <= 12) return '≤12';
  if (area <= 20) return '13-20';
  if (area <= 30) return '21-30';
  if (area <= 42) return '31-42';
  if (area <= 56) return '43-56';
  if (area <= 72) return '57-72';
  if (area <= 80) return '73-80';
  return '>80';
}

/// Aggregated corpus stats across all axes the equilibrium engine watches:
/// per-slug usage, grid-area buckets, and number-of-distinct-types.
class _CollectionStats {
  final Map<String, int> slugs;
  // Per-bucket counts keyed by [kSizeBucketLabels].
  final Map<String, int> sizeBuckets;
  // n=1..9 mapped to '1'..'9'; n>=10 collapsed into '10+' so the display order
  // stays stable. The '10+' bin's target follows whatever the equilibrium
  // profile declares for keys ≥ 10 (0 when none).
  final Map<String, int> nTypes;
  // Profile axis: classic / sh / pathBased / syBased (read off the
  // authoritative `scenario:` v2 suffix via `detectPuzzleProfile` in
  // equilibrium.dart). Keys match the `ProfileCategory.name` values.
  final Map<String, int> profiles;

  _CollectionStats(this.slugs, this.sizeBuckets, this.nTypes, this.profiles);

  factory _CollectionStats.fromLines(List<String> lines) {
    final slugs = {for (final s in constraintSlugs) s: 0};
    final sizeBuckets = {for (final l in kSizeBucketLabels) l: 0};
    final nTypes = <String, int>{};
    final profiles = <String, int>{
      'classic': 0,
      'sh': 0,
      'pathBased': 0,
      'syBased': 0,
    };

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final fields = trimmed.split('_');
      if (fields.length < 5) continue;

      final dims = fields[2].split('x');
      if (dims.length == 2) {
        final w = int.tryParse(dims[0]) ?? 0;
        final h = int.tryParse(dims[1]) ?? 0;
        final bucket = _sizeBucket(w * h);
        sizeBuckets[bucket] = (sizeBuckets[bucket] ?? 0) + 1;
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
      final key = n >= 10 ? '10+' : n.toString();
      nTypes[key] = (nTypes[key] ?? 0) + 1;

      final profile = detectPuzzleProfile(trimmed);
      profiles[profile.name] = (profiles[profile.name] ?? 0) + 1;
    }

    return _CollectionStats(slugs, sizeBuckets, nTypes, profiles);
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
  List<String?> targets = const [],
  List<int> attemptCounts = const [],
  List<int> successCounts = const [],
  List<int?> attemptStartMs = const [],
  int nowMs = 0,
  int maxAttemptTimeMs = 0,
}) {
  // \x1B[2J clears the screen, \x1B[H homes the cursor.
  stderr.write('\x1B[2J\x1B[H');
  stderr.writeln('Corpus: $existingPuzzles puzzles (live count)');
  stderr.writeln(equilibriumLine);
  stderr.writeln('Jobs: $jobs parallel worker(s)');
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
      // Live "running Xs / Ys" annotation: visible only while a target
      // is in flight (between `'target'` and the matching `'attempt'`).
      // The periodic redraw keeps it growing even when the worker is
      // not emitting messages — that's the whole point of having it.
      final startMs = i < attemptStartMs.length ? attemptStartMs[i] : null;
      String runtime = '';
      if (startMs != null) {
        final elapsedS = ((nowMs - startMs) / 1000).round();
        runtime = maxAttemptTimeMs > 0
            ? ' (running ${elapsedS}s / ${maxAttemptTimeMs ~/ 1000}s)'
            : ' (running ${elapsedS}s)';
      }
      stderr.writeln('  #${i.toString().padLeft(2)} [$counter]$runtime → $t');
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

  // Force a stable display order 1, 2, ..., 9, 10+ even when some buckets are 0.
  final orderedTypes = <String, int>{
    for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10+'])
      k: stats.nTypes[k] ?? 0,
  };
  final sizeBuckets = {
    for (final l in kSizeBucketLabels) l: stats.sizeBuckets[l] ?? 0,
  };

  // Bars now visualize the *gap to target* (= target - observed, clamped to
  // ≥ 0), not the raw count. The longest bar across all histograms marks
  // the bin the picker is most likely to chase next. Target=0 buckets always
  // have gap=0 → no bar, which is the right signal: they are reliquats,
  // never pushed.
  // Profile axis: ordered classic → sh → pathBased → syBased to match
  // the `ProfileCategory` enum order. Missing buckets default to 0
  // (e.g. early corpus).
  final orderedProfiles = <String, int>{
    for (final k in ['classic', 'sh', 'pathBased', 'syBased'])
      k: stats.profiles[k] ?? 0,
  };

  final globalMaxGap = [
    _maxGap(stats.slugs, axisTargets.slug),
    _maxGap(sizeBuckets, axisTargets.size),
    _maxGap(orderedTypes, axisTargets.ntypes),
    _maxGap(orderedProfiles, axisTargets.profile),
  ].fold<double>(0.0, max);

  stderr.writeln('');
  stderr.writeln('Constraints:');
  _writeHistogram(
    stats.slugs,
    sortByValue: true,
    targets: axisTargets.slug,
    globalMaxGap: globalMaxGap,
    columns: 2,
  );
  stderr.writeln('');
  stderr.writeln('Distinct types per puzzle:');
  _writeHistogram(
    orderedTypes,
    sortByValue: false,
    targets: axisTargets.ntypes,
    globalMaxGap: globalMaxGap,
    columns: 2,
  );
  // Sizes (left) and Pre-fill profile (right) are short axes, so render them
  // side by side to keep the dashboard compact.
  stderr.writeln('');
  _writeSideBySide(
    'Sizes (width×height):',
    _histogramLines(
      sizeBuckets,
      sortByValue: false,
      targets: axisTargets.size,
      globalMaxGap: globalMaxGap,
    ),
    'Pre-fill profile:',
    _histogramLines(
      orderedProfiles,
      sortByValue: false,
      targets: axisTargets.profile,
      globalMaxGap: globalMaxGap,
    ),
  );
}

/// Print two labelled blocks of pre-rendered lines next to each other: the
/// left block (title + [leftLines]) in a column wide enough for its widest
/// line plus [gap] spaces, the right block (title + [rightLines]) starting at
/// that boundary. Shorter block is padded with blank lines.
void _writeSideBySide(
  String leftTitle,
  List<String> leftLines,
  String rightTitle,
  List<String> rightLines, {
  int gap = 2,
}) {
  final left = [leftTitle, ...leftLines];
  final right = [rightTitle, ...rightLines];
  final leftWidth = left.map((l) => l.length).fold<int>(0, max) + gap;
  final rows = max(left.length, right.length);
  for (int i = 0; i < rows; i++) {
    final l = i < left.length ? left[i] : '';
    final r = i < right.length ? right[i] : '';
    stderr.writeln('${l.padRight(leftWidth)}$r');
  }
}

class _AxisTargets {
  final Map<String, double> slug;
  final Map<String, double> size;
  final Map<String, double> ntypes;
  final Map<String, double> profile;
  const _AxisTargets({
    required this.slug,
    required this.size,
    required this.ntypes,
    required this.profile,
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
  final size = <String, double>{for (final l in kSizeBucketLabels) l: 0};
  for (final (w, h) in universe.allowedSizes) {
    final bucket = _sizeBucket(w * h);
    size[bucket] =
        (size[bucket] ?? 0) + totalCorpus * sizeTargetShare(w, h, universe);
  }

  // Ntypes axis: explicit profile from kTargetNTypesProfile. Keys 1..9 each
  // get their own dashboard row; any key ≥ 10 (when the profile defines one)
  // is collapsed into the '10+' bin so the display order stays stable
  // (1, 2, ..., 9, 10+) regardless of how many high-n targets the profile
  // declares. The bin reads 0 when the profile has no ≥10 entry.
  final ntypes = <String, double>{};
  double tenPlusTargetShare = 0;
  for (final entry in kTargetNTypesProfile.entries) {
    if (entry.key <= 9) {
      ntypes['${entry.key}'] = totalCorpus * entry.value;
    } else {
      tenPlusTargetShare += entry.value;
    }
  }
  ntypes['10+'] = totalCorpus * tenPlusTargetShare;

  // Profile axis: three buckets (classic / sh / pathBased) with explicit
  // targets in kTargetProfile.
  final profile = <String, double>{};
  for (final entry in kTargetProfile.entries) {
    profile[entry.key.name] = totalCorpus * entry.value;
  }

  return _AxisTargets(slug: slug, size: size, ntypes: ntypes, profile: profile);
}

/// Largest `target - observed` across all rows of one histogram, clamped to 0.
/// Rows whose target is missing or 0 contribute 0 — so a bin with an
/// undeclared objective (e.g. the '10+' bucket when no ≥10 key is set in
/// `kTargetNTypesProfile`) is never flagged as "to push".
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

/// Write one histogram to stderr. Thin wrapper over [_histogramLines].
void _writeHistogram(
  Map<String, int> stats, {
  required bool sortByValue,
  required double globalMaxGap,
  Map<String, double>? targets,
  int columns = 1,
  int columnWidth = 64,
}) {
  for (final line in _histogramLines(
    stats,
    sortByValue: sortByValue,
    globalMaxGap: globalMaxGap,
    targets: targets,
    columns: columns,
    columnWidth: columnWidth,
  )) {
    stderr.writeln(line);
  }
}

/// Render one histogram into a list of lines (each already indented). The bar
/// length encodes the *gap to target* (= target − observed, clamped to ≥ 0),
/// normalized by [globalMaxGap] across all displayed histograms so bars are
/// visually comparable across axes — the longest bar anywhere on the dashboard
/// is the bin the equilibrium picker is most likely to chase next.
/// With [columns] == 2, entries are laid out in two side-by-side columns of
/// [columnWidth] characters each (column-major: the first half fills the left
/// column, the second half the right), to keep tall axes (slugs, ntypes)
/// compact.
List<String> _histogramLines(
  Map<String, int> stats, {
  required bool sortByValue,
  required double globalMaxGap,
  Map<String, double>? targets,
  int columns = 1,
  int columnWidth = 64,
}) {
  if (stats.isEmpty) return const [];
  final entries = stats.entries.toList();
  if (sortByValue) {
    entries.sort((a, b) => b.value.compareTo(a.value));
  }
  // Narrower bars in two-column mode so a label + bar + suffix fits within
  // [columnWidth]; full width when a single column spans the whole line.
  final barWidth = columns >= 2 ? 20 : 30;
  // Fixed label column so the bars align horizontally across all histograms
  // (constraints / sizes / ntypes), regardless of which has the longest key.
  // 10 characters is wide enough for every current label.
  const keyWidth = 10;
  // Pre-compute the value column width so the "value / target" suffix lines
  // up across rows even when counts have different digit lengths.
  final valWidth = entries.map((e) => '${e.value}'.length).fold<int>(0, max);

  String cell(MapEntry<String, int> entry) {
    final target = targets?[entry.key];
    final gap = (target == null || target <= 0)
        ? 0.0
        : (target - entry.value).clamp(0.0, double.infinity).toDouble();
    final bar = globalMaxGap > 0
        ? '█' * ((gap / globalMaxGap * barWidth).round())
        : '';
    String suffix;
    if (target == null) {
      suffix = '${entry.value}';
    } else {
      suffix = '${'${entry.value}'.padLeft(valWidth)} / ${target.round()}';
      // Show the observed/target ratio in percent next to the absolute
      // counts. Skip when target == 0 (e.g. an undeclared reliquat bin) to
      // avoid division by zero.
      if (target > 0) {
        final pct = (entry.value / target * 100).toStringAsFixed(1);
        suffix = '$suffix ($pct%)';
      }
    }
    return '${entry.key.padRight(keyWidth)} $bar $suffix';
  }

  final lines = <String>[];
  if (columns < 2) {
    for (final entry in entries) {
      lines.add('  ${cell(entry)}');
    }
    return lines;
  }

  // Two columns, column-major: left column = first half, right = second half.
  final leftCount = (entries.length + 1) ~/ 2;
  for (int i = 0; i < leftCount; i++) {
    final left = _clip(cell(entries[i]), columnWidth);
    final rightIdx = i + leftCount;
    final right = rightIdx < entries.length
        ? _clip(cell(entries[rightIdx]), columnWidth)
        : '';
    lines.add('  ${left.padRight(columnWidth)}$right');
  }
  return lines;
}

/// Truncate [s] to at most [width] characters (no-op when already short).
String _clip(String s, int width) =>
    s.length <= width ? s : s.substring(0, width);

// --- Check mode ---

/// Categories used by `--check-detailed` to explain each rejection.
///   * `unsolvable`     — 0 valid completions exist (puzzle is broken).
///   * `nonUnique`      — ≥2 valid completions (ambiguous).
///   * `needsBacktrack` — exactly 1 valid completion exists but the
///                        deductive solver couldn't reach it without
///                        backtracking (in-game hint system would fail).
///   * `cachedMismatch` — deductively unique, but the `_1:xxx` cached
///                        solution on the line doesn't match the deduced
///                        completion. Treated as invalid.
enum _DetailedCategory {
  unsolvable,
  nonUnique,
  needsBacktrack,
  cachedMismatch;

  String get label => switch (this) {
    _DetailedCategory.unsolvable => 'UNSOLVABLE',
    _DetailedCategory.nonUnique => 'NON-UNIQUE',
    _DetailedCategory.needsBacktrack => 'NEEDS-BACKTRACK',
    _DetailedCategory.cachedMismatch => 'CACHED MISMATCH',
  };
}

Future<void> _runCheck(String filePath, {bool detailed = false}) async {
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
  // Per-category counters used only in detailed mode. Populated as
  // rejections are classified; rendered in the dashboard breakdown.
  final categoryCounts = <_DetailedCategory, int>{
    for (final c in _DetailedCategory.values) c: 0,
  };
  final sw = Stopwatch()..start();
  final goodLines = <String>[];
  var stats = _CollectionStats.fromLines(goodLines);

  void render() {
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
      detailed: detailed,
      categoryCounts: categoryCounts,
    );
  }

  render();

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    try {
      final p = Puzzle(line);
      // Capture the on-line cached solution BEFORE any solving. `solve()`
      // itself doesn't overwrite `cachedSolution` (only computeComplexity
      // does), and `isDeductivelyUnique()` operates on a clone — but we
      // still snapshot the value here to make the dependency explicit and
      // protect against future changes to the solver.
      final lineCachedSolution = p.cachedSolution;
      if (p.isDeductivelyUnique()) {
        if (detailed && lineCachedSolution != null) {
          // Re-solve on a fresh clone to obtain the deduced completion,
          // then compare against the cached solution parsed from the line.
          final solved = p.clone();
          solved.solve();
          final deduced = solved.cellValues;
          bool match = deduced.length == lineCachedSolution.length;
          if (match) {
            for (int j = 0; j < deduced.length; j++) {
              if (deduced[j] != lineCachedSolution[j]) {
                match = false;
                break;
              }
            }
          }
          if (!match) {
            invalid++;
            categoryCounts[_DetailedCategory.cachedMismatch] =
                categoryCounts[_DetailedCategory.cachedMismatch]! + 1;
            badSink.writeln(
              '# INVALID (${_DetailedCategory.cachedMismatch.label} — '
              'cached _1: differs from deduced solution)',
            );
            badSink.writeln(line);
            if ((i + 1) % 10 == 0 || i + 1 == lines.length) {
              stats = _CollectionStats.fromLines(goodLines);
              render();
            }
            continue;
          }
        }
        valid++;
        goodSink.writeln(line);
        goodLines.add(line);
      } else {
        invalid++;
        if (detailed) {
          // Classify the rejection by enumerating up to 2 valid
          // completions. 0 → UNSOLVABLE, ≥2 → NON-UNIQUE, exactly 1 →
          // NEEDS-BACKTRACK (the puzzle has a unique mathematical
          // solution but the deductive solver can't reach it).
          final solutions = enumerateSolutions(p.clone(), limit: 2);
          final _DetailedCategory cat;
          if (solutions.isEmpty) {
            cat = _DetailedCategory.unsolvable;
          } else if (solutions.length >= 2) {
            cat = _DetailedCategory.nonUnique;
          } else {
            cat = _DetailedCategory.needsBacktrack;
          }
          categoryCounts[cat] = categoryCounts[cat]! + 1;
          final detail = switch (cat) {
            _DetailedCategory.unsolvable => '0 solutions found',
            _DetailedCategory.nonUnique => '≥2 solutions found',
            _DetailedCategory.needsBacktrack =>
              '1 solution found but solver can\'t deduce it',
            _DetailedCategory.cachedMismatch => '',
          };
          badSink.writeln('# INVALID (${cat.label} — $detail)');
        } else {
          badSink.writeln('# INVALID (not deductively unique)');
        }
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
  if (detailed && invalid > 0) {
    for (final c in _DetailedCategory.values) {
      final n = categoryCounts[c]!;
      if (n > 0) stderr.writeln('    ${c.label.padRight(16)} $n');
    }
  }
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
/// When [detailed] is true, [categoryCounts] is used to render an extra
/// breakdown of the four invalid categories (UNSOLVABLE / NON-UNIQUE /
/// NEEDS-BACKTRACK / CACHED MISMATCH).
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
  bool detailed = false,
  Map<_DetailedCategory, int> categoryCounts = const {},
}) {
  stderr.write('\x1B[2J\x1B[H');
  stderr.writeln('Checking $filePath${detailed ? ' (detailed)' : ''}');
  stderr.writeln('  good → $goodPath');
  stderr.writeln('  bad  → $badPath');
  stderr.writeln('');
  final pct = total == 0 ? 0 : (100 * checked / total).round();
  stderr.writeln(
    '[${_fmt(elapsed)}] $checked/$total ($pct%) | '
    'valid $valid | invalid $invalid'
    '${errored > 0 ? ' | errors $errored' : ''}',
  );

  if (detailed) {
    final breakdown = <String, int>{
      for (final c in _DetailedCategory.values) c.label: categoryCounts[c]!,
    };
    stderr.writeln('');
    stderr.writeln('Invalid breakdown:');
    _writeCountHistogram(breakdown, sortByValue: false);
  }

  final orderedTypes = <String, int>{
    for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10+'])
      k: stats.nTypes[k] ?? 0,
  };
  final sizeBuckets = {
    for (final l in kSizeBucketLabels) l: stats.sizeBuckets[l] ?? 0,
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

Map<String, dynamic> _parseArgs(List<String> args) {
  final result = <String, dynamic>{
    'mode': 'generate',
    'count': 10,
    'minWidth': 4,
    'maxWidth': 7,
    'minHeight': 4,
    'maxHeight': 8,
    'maxTime': 60,
    'maxAttemptTime': 120,
    'output': null,
    'banned': null,
    'allowed': null,
    'required': null,
    'targetLevel': null,
    'easingBudget': 30,
    'checkFile': null,
    'detailed': false,
    'statsDir': null,
    'equilibrium': true,
    'jobs': Platform.numberOfProcessors,
    'logDir': null,
    'useBlacklist': true,
    'blacklistMinAttempts': 30,
    'blacklistAdaptiveK': 20,
    'blacklistSkipSafety': 100,
  };

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        result['mode'] = 'check';
        result['checkFile'] = args[++i];
      case '--check-detailed':
        result['mode'] = 'check';
        result['detailed'] = true;
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
      case '--max-attempt-time':
        result['maxAttemptTime'] = int.parse(args[++i]);
      case '-o':
      case '--output':
        result['output'] = args[++i];
      case '--ban':
        result['banned'] = args[++i];
      case '--allow':
        result['allowed'] = args[++i];
      case '--require':
        result['required'] = args[++i];
      case '--target-collection':
        final name = args[++i];
        final level = playableCollectionKeyToLevel[name];
        if (level == null) {
          final valid = playableCollectionKeyToLevel.keys.join(', ');
          stderr.writeln(
            '--target-collection must be one of: $valid (got "$name")',
          );
          exit(1);
        }
        result['targetLevel'] = level;
      case '--easing-budget':
        result['easingBudget'] = int.parse(args[++i]);
      case '--no-equilibrium':
        result['equilibrium'] = false;
      case '--no-blacklist':
        result['useBlacklist'] = false;
      case '--blacklist-min-attempts':
        result['blacklistMinAttempts'] = int.parse(args[++i]);
      case '--blacklist-adaptive-k':
        result['blacklistAdaptiveK'] = int.parse(args[++i]);
      case '--blacklist-skip-safety':
        result['blacklistSkipSafety'] = int.parse(args[++i]);
      case '--scenario':
        final scenario = args[++i];
        const validScenarios = ['path-based', 'sy-based'];
        if (!validScenarios.contains(scenario)) {
          stderr.writeln(
            '--scenario must be one of: ${validScenarios.join(', ')} '
            '(got "$scenario")',
          );
          exit(1);
        }
        result['scenario'] = scenario;
      case '-j':
      case '--jobs':
        result['jobs'] = int.parse(args[++i]);
      case '--log-dir':
        result['logDir'] = args[++i];
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
  --check FILE            Validate puzzles via fast deductive solve. Writes
                          valid puzzles to FILE.good.txt and invalid ones to
                          FILE.bad.txt.
  --check-detailed FILE   Same outputs as --check, but rejected puzzles are
                          further classified via exhaustive backtracking
                          into UNSOLVABLE (0 completions), NON-UNIQUE
                          (≥2 completions) or NEEDS-BACKTRACK (1 completion
                          the deductive solver can't reach). Accepted
                          puzzles also have their cached _1: solution
                          cross-checked against the deduced one;
                          mismatches are reclassified as CACHED MISMATCH
                          and treated as invalid. Slower than --check.
  --read-stats DIR        Aggregate play stats, output puzzles sorted by difficulty

Generation options:
  -n, --count N           Number of puzzles to generate (default: 10)
  -W, --min-width N       Minimum grid width (default: 4)
      --max-width N       Maximum grid width (default: 7)
  -H, --min-height N      Minimum grid height (default: 4)
      --max-height N      Maximum grid height (default: 8)
  -T, --max-time S        Maximum generation time (in seconds, default: 60)
      --max-attempt-time S
                          Wall-clock cap for a single `generateOne` call (in
                          seconds, default: 120). Once exceeded the attempt
                          is aborted with reason=attemptTimeout. Prevents a
                          single slow combo (e.g. CH alone on a medium grid)
                          from monopolizing the --max-time budget.
  -o, --output FILE       Output file (default: stdout)
      --ban RULES         Comma-separated rule slugs to exclude (e.g. FM,LT)
      --allow RULES       Comma-separated whitelist — when set, only these
                          slugs are eligible (e.g. NC,EY,CC for a small
                          subset). Combines with --ban: the effective set
                          is (allow minus ban). Useful for bisecting which
                          constraint is making generation slow.
      --require RULES     Comma-separated rule slugs to require (e.g. PA,GS)
      --target-collection NAME
                          Only emit puzzles classified in NAME. NAME is
                          one of: 1-easy, 2-player, 3-advanced, 4-strong,
                          5-expert, 6-mad. Puzzles below this difficulty
                          are dropped; puzzles above enter an "easing"
                          loop (add more constraints until the trace
                          simplifies into the target). Overfilled and
                          undetermined puzzles are always dropped under
                          this filter. removeUselessRules is not called.
      --easing-budget S   Per-puzzle wall-clock budget (in seconds) for
                          the easing loop (default: 30). When exceeded,
                          the candidate is dropped and the worker moves
                          on. No effect without --target-collection.
      --no-equilibrium    Disable the multi-axis equilibrium bias.
                          Default: ON. When OFF, only the legacy slug-usage
                          bias is applied (matches pre-equilibrium behavior).
      --no-blacklist      Disable the infeasibility filter. By default the
                          CLI reads `generator_stats.csv` at startup and
                          skips any (target, slugs, scenario, size-bucket)
                          tuple that has been tried ≥ M times across past
                          runs with zero successes; each worker also marks
                          tuples that fail K times in-session. Use to
                          unblock a combo after fixing the solver.
      --blacklist-min-attempts N
                          M: a combo needs at least N historical tries with
                          zero successes to enter the persistent seed
                          blacklist (default: 30).
      --blacklist-adaptive-k N
                          K: in-session threshold — a combo joins the
                          worker's local blacklist after N failures without
                          success in this run (default: 20).
      --blacklist-skip-safety N
                          Safety brake: after N consecutive blacklist
                          skips, the worker runs the next blacklisted
                          combo anyway to avoid lock-up if every candidate
                          tuple has been filtered (default: 100).
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
  -h, --help              Show this help

Rule slugs: $rules

Examples:
  dart run bin/generate.dart -n 100 -o puzzles.txt
  dart run bin/generate.dart --check assets/try_me.txt
  dart run bin/generate.dart --check-detailed assets/try_me.txt
  dart run bin/generate.dart --read-stats ~/Documents/getsomepuzzle/
''');
}
