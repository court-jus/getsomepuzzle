import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/feasibility.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';

class GeneratorWorker {
  StreamController<GeneratorMessage>? _controller;
  Isolate? _isolate;

  Stream<GeneratorMessage> start(
    GeneratorConfig config, {
    Map<String, int>? usageStats,
    List<String>? puzzleLines,
    bool equilibriumRequested = false,
    int jobsCount = 1,
    int workerIndex = 0,
    String? logFilePath,
    List<String> seedBlacklist = const <String>[],
    int adaptiveK = 20,
    int skipSafety = 100,
  }) {
    _controller = StreamController<GeneratorMessage>();

    _runIsolate(
      config,
      usageStats,
      puzzleLines,
      equilibriumRequested,
      jobsCount,
      workerIndex,
      logFilePath,
      seedBlacklist,
      adaptiveK,
      skipSafety,
    );

    return _controller!.stream;
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void dispose() {
    cancel();
    _controller?.close();
  }

  Future<void> _runIsolate(
    GeneratorConfig config,
    Map<String, int>? usageStats,
    List<String>? puzzleLines,
    bool equilibriumRequested,
    int jobsCount,
    int workerIndex,
    String? logFilePath,
    List<String> seedBlacklist,
    int adaptiveK,
    int skipSafety,
  ) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _IsolateParams(
        sendPort: receivePort.sendPort,
        width: config.width,
        height: config.height,
        minWidth: config.minWidth,
        maxWidth: config.maxWidth,
        minHeight: config.minHeight,
        maxHeight: config.maxHeight,
        requiredRules: config.requiredRules.toList(),
        allowedSlugs: config.allowedSlugs?.toList(),
        maxTimeMs: config.maxTime.inMilliseconds,
        maxAttemptTimeMs: config.maxAttemptTime.inMilliseconds,
        count: config.count,
        targetLevelIndex: config.targetLevel?.index,
        easingBudgetMs: config.easingBudget.inMilliseconds,
        pathBasedScenario: config.pathBasedScenario,
        syBasedScenario: config.syBasedScenario,
        usageStats: usageStats,
        puzzleLines: puzzleLines,
        equilibriumRequested: equilibriumRequested,
        jobsCount: jobsCount,
        workerIndex: workerIndex,
        logFilePath: logFilePath,
        seedBlacklist: seedBlacklist,
        adaptiveK: adaptiveK,
        skipSafety: skipSafety,
      ),
    );

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;
        if (type == 'progress') {
          _controller?.add(
            GeneratorProgressMessage(
              GeneratorProgress(
                puzzlesGenerated: message['generated'] as int,
                totalRequested: message['total'] as int,
                constraintsTried: message['tried'] as int,
                constraintsTotal: message['totalConstraints'] as int,
                currentRatio: message['ratio'] as double,
              ),
            ),
          );
        } else if (type == 'puzzle') {
          _controller?.add(
            GeneratorPuzzleMessage(
              message['line'] as String,
              PuzzleLevel.values[message['level'] as int],
            ),
          );
        } else if (type == 'target') {
          _controller?.add(GeneratorTargetMessage(message['label'] as String?));
        } else if (type == 'attempt') {
          final preferred = (message['preferredSlugs'] as List).cast<String>();
          final allowed = (message['allowedSlugs'] as List?)?.cast<String>();
          final rawDeficits = message['slugDeficits'] as Map?;
          final Map<String, double>? deficits = rawDeficits?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          );
          _controller?.add(
            GeneratorAttemptMessage(
              workerIndex: message['worker'] as int,
              inWarmup: message['inWarmup'] as bool,
              targetKey: message['targetKey'] as String?,
              width: message['width'] as int,
              height: message['height'] as int,
              ntypesIntended: message['ntypesIntended'] as int?,
              preferredSlugs: preferred,
              allowedSlugs: allowed,
              scenario: message['scenario'] as String,
              success: message['success'] as bool,
              rejectReason: message['rejectReason'] as String?,
              durationMs: message['durationMs'] as int,
              puzzleLevelIndex: message['puzzleLevel'] as int?,
              puzzleLine: message['puzzleLine'] as String?,
              slugDeficitScores: deficits,
            ),
          );
        } else if (type == 'done') {
          _controller?.add(GeneratorDoneMessage(message['generated'] as int));
          _controller?.close();
          _isolate = null;
          receivePort.close();
        }
      }
    });
  }
}

class _IsolateParams {
  final SendPort sendPort;
  final int width, height;
  final int? minWidth, maxWidth, minHeight, maxHeight;
  final List<String> requiredRules;
  final List<String>? allowedSlugs;
  final int maxTimeMs;

  /// Per-`generateOne` wall-clock cap. Caps any single attempt so a
  /// pathological combo can't monopolize [maxTimeMs].
  final int maxAttemptTimeMs;

  final int count;
  final int? targetLevelIndex;
  final int easingBudgetMs;
  final bool pathBasedScenario;
  final bool syBasedScenario;
  final Map<String, int>? usageStats;
  final List<String>? puzzleLines;
  final bool equilibriumRequested;
  final int jobsCount;
  final int workerIndex;
  final String? logFilePath;

  /// `AttemptKey.serialized` strings loaded at CLI startup from
  /// `generator_stats.csv` (combos with ≥ M tries and 0 successes across
  /// past runs). Each worker checks this set before every attempt.
  final List<String> seedBlacklist;

  /// In-session blacklist threshold: a worker blacklists a combo locally
  /// once it has attempted it [adaptiveK] times with no successes.
  final int adaptiveK;

  /// After [skipSafety] consecutive blacklist-skips, the worker runs the
  /// next blacklisted combo anyway. Avoids deadlocks when most candidate
  /// tuples have been filtered out.
  final int skipSafety;

  _IsolateParams({
    required this.sendPort,
    required this.width,
    required this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    required this.requiredRules,
    this.allowedSlugs,
    required this.maxTimeMs,
    required this.maxAttemptTimeMs,
    required this.count,
    this.targetLevelIndex,
    required this.easingBudgetMs,
    this.pathBasedScenario = false,
    this.syBasedScenario = false,
    this.usageStats,
    this.puzzleLines,
    this.equilibriumRequested = false,
    this.jobsCount = 1,
    this.workerIndex = 0,
    this.logFilePath,
    this.seedBlacklist = const <String>[],
    this.adaptiveK = 20,
    this.skipSafety = 100,
  });
}

void _isolateEntryPoint(_IsolateParams params) {
  // Each log line is written and flushed synchronously: this is the explicit
  // tradeoff for diagnosing hangs. If a worker is stuck inside `solve()` or
  // its inner constraint propagation, every line emitted before the hang
  // must be on disk already — IOSink-style buffering would hide exactly the
  // lines we want.
  final logFile = params.logFilePath != null ? File(params.logFilePath!) : null;
  void log(String message) {
    if (logFile == null) return;
    final ts = DateTime.now().toIso8601String();
    logFile.writeAsStringSync(
      '[$ts] [w${params.workerIndex}] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  final rng = Random();
  final effectiveMinW = params.minWidth ?? params.width;
  final effectiveMaxW = params.maxWidth ?? params.width;
  final effectiveMinH = params.minHeight ?? params.height;
  final effectiveMaxH = params.maxHeight ?? params.height;
  final maxTime = Duration(milliseconds: params.maxTimeMs);
  final usageStats = params.usageStats != null
      ? Map<String, int>.from(params.usageStats!)
      : <String, int>{};
  final baseAllowedSlugs = params.allowedSlugs?.toSet();
  final requiredSet = params.requiredRules.toSet();

  log(
    'worker start: count=${params.count}, jobsCount=${params.jobsCount}, '
    'sizeRange=${effectiveMinW}x$effectiveMinH..${effectiveMaxW}x$effectiveMaxH, '
    'allowedSlugs=${baseAllowedSlugs ?? "*"}, required=$requiredSet, '
    'equilibriumRequested=${params.equilibriumRequested}, '
    'maxTime=${maxTime.inSeconds}s, '
    'maxAttemptTime=${params.maxAttemptTimeMs / 1000}s',
  );

  // Equilibrium state. We always build it when equilibrium is requested —
  // even during warm-up — so the live switch from warm-up to equilibrium
  // is instantaneous (no rebuild from `puzzleLines`).
  EquilibriumStats? equiStats;
  TargetUniverse? universe;
  final initialCorpusSize = (params.puzzleLines ?? const [])
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .length;
  if (params.equilibriumRequested) {
    equiStats = EquilibriumStats.fromLines(params.puzzleLines ?? const []);
    universe = TargetUniverse(
      allowedSlugs: baseAllowedSlugs ?? constraintSlugs.toSet(),
      minWidth: effectiveMinW,
      maxWidth: effectiveMaxW,
      minHeight: effectiveMinH,
      maxHeight: effectiveMaxH,
    );
  }

  // Infeasibility plumbing. `seedSet` is the persistent CSV-loaded blacklist
  // (frozen for this run); `tracker` accumulates fresh in-session evidence.
  // A combo is skipped when either source flags it. `consecutiveSkips` is
  // the safety brake (see [skipSafety]).
  final seedSet = params.seedBlacklist.toSet();
  final tracker = InfeasibilityTracker();
  int consecutiveSkips = 0;
  if (seedSet.isNotEmpty) {
    log('seed blacklist: ${seedSet.length} combo(s) loaded');
  }

  int generated = 0;
  final stopwatch = Stopwatch()..start();

  while (generated < params.count && stopwatch.elapsed < maxTime) {
    Target? target;
    int w;
    int h;
    Set<String>? allowedSlugs = baseAllowedSlugs;
    Set<String> preferredSlugs = const {};
    bool attemptPathBased = false;
    bool attemptSyBased = false;

    // Estimate the global corpus size: this worker only sees its own output,
    // so we approximate other workers' contributions by `generated × jobsCount`.
    // The estimate is coarse but good enough to flip warm-up off around the
    // 100-puzzle threshold.
    final estimatedCorpus = initialCorpusSize + generated * params.jobsCount;
    final inWarmup =
        params.equilibriumRequested && estimatedCorpus < kEquilibriumWarmupSize;

    if (inWarmup) {
      final wc = pickWarmupConfig(
        minWidth: effectiveMinW,
        maxWidth: effectiveMaxW,
        minHeight: effectiveMinH,
        maxHeight: effectiveMaxH,
        baseAllowedSlugs: baseAllowedSlugs ?? constraintSlugs.toSet(),
        baseRequired: requiredSet,
        rng: rng,
      );
      w = wc.width;
      h = wc.height;
      allowedSlugs = wc.allowedSlugs;
      preferredSlugs = wc.preferredSlugs;
    } else if (params.equilibriumRequested &&
        universe != null &&
        equiStats != null) {
      target = pickTarget(equiStats, universe);
      if (target != null) {
        final resolved = _resolveTarget(
          target,
          universe,
          requiredSet,
          equiStats,
          rng,
        );
        allowedSlugs = resolved.allowedSlugs;
        preferredSlugs = resolved.preferredSlugs;
        attemptPathBased = resolved.pathBasedScenario;
        attemptSyBased = resolved.syBasedScenario;
        if (resolved.width != null && resolved.height != null) {
          w = resolved.width!;
          h = resolved.height!;
        } else {
          // Target leaves the size axis free — sample a size weighted by
          // its gap so the attempt advances both axes. Fall back to random
          // when no size has a positive gap.
          final picked = pickWeightedSize(equiStats, universe, rng);
          w =
              picked?.$1 ??
              effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
          h =
              picked?.$2 ??
              effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);
        }
      } else {
        // No target (every axis balanced) — random.
        w = effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
        h = effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);
      }
    } else {
      w = effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
      h = effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);
    }

    // Tell the UI what this worker is currently chasing so the dashboard can
    // show per-worker progress. We always report the 4 axes (size, ntypes,
    // slugs, scenario) so any attempt is fully identifiable, regardless of
    // which axis the equilibrium picker chose to push.
    final scenario = _resolveScenario(
      pathBased: params.pathBasedScenario || attemptPathBased,
      syBased: params.syBasedScenario || attemptSyBased,
      preferredSlugs: preferredSlugs,
    );
    final resolvedTarget = target;
    // `ntypesIntended` is the explicit target.n when chasing NTypesTarget,
    // otherwise the soft cap implied by the preferred slug set (`≤` in the
    // label). `null` when no slug preference is active.
    final int? ntypesIntended = resolvedTarget is NTypesTarget
        ? resolvedTarget.n
        : (preferredSlugs.isNotEmpty ? preferredSlugs.length : null);
    final ntypesLabel = ntypesIntended == null
        ? 'ntypes=free'
        : (resolvedTarget is NTypesTarget
              ? 'ntypes=$ntypesIntended'
              : 'ntypes≤$ntypesIntended');
    final slugsLabel = 'slugs={${preferredSlugs.join(',')}}';
    final body = '${w}x$h $ntypesLabel $slugsLabel scenario=$scenario';
    final String targetLabel;
    if (inWarmup) {
      targetLabel = 'warmup $body';
    } else if (target != null) {
      targetLabel = '[${target.label}] $body';
    } else if (params.equilibriumRequested) {
      targetLabel = '[balanced] $body';
    } else {
      targetLabel = body;
    }

    // Skip-then-continue when the combo is known infeasible (seeded by a
    // prior run's CSV, or learned in-session via the tracker). A skipped
    // iteration emits no `'target'` / `'attempt'` event — from the CLI's
    // point of view the attempt simply never happened. The safety brake
    // releases the filter after [skipSafety] consecutive skips so the
    // worker can't deadlock if every candidate tuple has been blacklisted.
    final attemptKey = AttemptKey(
      targetKey: resolvedTarget?.key ?? 'none',
      sortedSlugs: preferredSlugs.toList()..sort(),
      scenario: scenario,
      sizeBucket: bucketForArea(w, h),
    );
    final blacklisted =
        seedSet.contains(attemptKey.serialized) ||
        tracker.isBlacklisted(attemptKey, kThreshold: params.adaptiveK);
    if (blacklisted) {
      if (consecutiveSkips < params.skipSafety) {
        consecutiveSkips++;
        log('  skip blacklisted combo: ${attemptKey.serialized}');
        continue;
      }
      log(
        '  skip safety triggered after $consecutiveSkips skips — '
        'running blacklisted combo to avoid lockup: ${attemptKey.serialized}',
      );
    }
    consecutiveSkips = 0;

    params.sendPort.send({'type': 'target', 'label': targetLabel});

    // Snapshot the per-slug deficit map for this attempt. Equilibrium-only
    // (skipped during warm-up: corpus too sparse for meaningful gaps). The
    // map drives the generator's secondary candidate-sort key so under-
    // represented slugs are pulled into the puzzle alongside the target.
    final Map<String, double>? slugDeficitMap =
        (params.equilibriumRequested &&
            !inWarmup &&
            equiStats != null &&
            universe != null)
        ? slugDeficits(equiStats, universe)
        : null;

    final config = GeneratorConfig(
      width: w,
      height: h,
      requiredRules: requiredSet,
      allowedSlugs: allowedSlugs,
      preferredSlugs: preferredSlugs,
      maxTime: maxTime,
      count: 1,
      targetLevel: params.targetLevelIndex != null
          ? PuzzleLevel.values[params.targetLevelIndex!]
          : null,
      easingBudget: Duration(milliseconds: params.easingBudgetMs),
      // CLI flag (`--scenario path-based`) OR equilibrium-driven choice
      // (`ProfileTarget(pathBased)`) both activate the path-based pre-fill.
      pathBasedScenario: params.pathBasedScenario || attemptPathBased,
      // Same OR pattern for the SY-based scenario.
      syBasedScenario: params.syBasedScenario || attemptSyBased,
      slugDeficitScores: slugDeficitMap,
    );

    final attemptStartMs = stopwatch.elapsedMilliseconds;
    final attemptDeadlineMs = attemptStartMs + params.maxAttemptTimeMs;
    log(
      'attempt #${generated + 1}: $targetLabel '
      'allowedSlugs=$allowedSlugs preferred=$preferredSlugs '
      'userRequired=$requiredSet '
      'budget=${params.maxAttemptTimeMs}ms',
    );

    // Throttle progress logs to one entry per [progressLogIntervalMs] inside
    // the same attempt. Without throttling, each constraint candidate would
    // emit a line.
    const progressLogIntervalMs = 2000;
    int lastProgressLogMs = attemptStartMs;
    int lastTried = 0;
    int lastTotalConstraints = 0;
    double lastRatio = 1.0;
    // Captured by `onReject` inside the generator. Only the *last*
    // reason matters: generateOne exits at the first `return null`,
    // so the callback fires at most once per attempt. Reset every
    // iteration so a previous attempt's reason doesn't leak forward.
    GenerationRejectReason? lastReject;
    // Set inside `shouldStop` when the per-attempt deadline (not the
    // global maxTime) is what triggered the abort. Used after the
    // attempt to relabel the reject from `cancelled` to `attemptTimeout`.
    bool attemptDeadlineHit = false;

    ({String line, PuzzleLevel level})? result;
    try {
      result = PuzzleGenerator.generateOne(
        config,
        usageStats: usageStats,
        onProgress: (p) {
          lastTried = p.constraintsTried;
          lastTotalConstraints = p.constraintsTotal;
          lastRatio = p.currentRatio;
          params.sendPort.send({
            'type': 'progress',
            'generated': generated,
            'total': params.count,
            'tried': p.constraintsTried,
            'totalConstraints': p.constraintsTotal,
            'ratio': p.currentRatio,
          });
          final now = stopwatch.elapsedMilliseconds;
          if (now - lastProgressLogMs >= progressLogIntervalMs) {
            log(
              '  progress: tried=$lastTried/$lastTotalConstraints '
              'ratio=${lastRatio.toStringAsFixed(3)} '
              'elapsed=${now - attemptStartMs}ms',
            );
            lastProgressLogMs = now;
          }
        },
        shouldStop: () {
          final nowMs = stopwatch.elapsedMilliseconds;
          if (nowMs > params.maxTimeMs) return true;
          if (nowMs >= attemptDeadlineMs) {
            attemptDeadlineHit = true;
            return true;
          }
          return false;
        },
        onReject: (r, rejectedPu) {
          lastReject = r;
          // Persist every rejected puzzle to `assets/<reason>.txt` so
          // post-run analysis can inspect each failure mode (why did
          // the easing plateau? what did the ratio-too-high puzzles
          // look like?). One file per reason; appended. Append is
          // ~atomic on Linux for short lines so simultaneous worker
          // isolates writing to the same file shouldn't interleave
          // bytes within a single puzzle.
          //
          // `compute: false` skips the complexity solve we don't need
          // here — the line is for human inspection or for replay via
          // `bin/solve.dart`, not for the production corpus.
          try {
            final assetsDir = Directory('assets');
            if (!assetsDir.existsSync()) {
              assetsDir.createSync(recursive: true);
            }
            final line = rejectedPu.lineExport(compute: false);
            File(
              'assets/${r.name}.txt',
            ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
          } catch (e) {
            // Persistence failures shouldn't kill the worker — log and
            // move on. Common cause: assets/ unwritable in CI.
            log('  failed to persist reject (${r.name}): $e');
          }
        },
      );
    } catch (e, st) {
      log('  exception during generateOne: $e\n$st');
      result = null;
    }

    // When the abort was triggered by the per-attempt deadline rather than
    // the global maxTime, relabel `cancelled` → `attemptTimeout` so the
    // CSV row carries the more precise reason. The global maxTime case
    // keeps `cancelled` because the worker is about to exit the loop.
    if (attemptDeadlineHit &&
        result == null &&
        lastReject == GenerationRejectReason.cancelled) {
      lastReject = GenerationRejectReason.attemptTimeout;
    }

    final attemptDurationMs = stopwatch.elapsedMilliseconds - attemptStartMs;
    // `reason=unknown` covers the rare "exception during generateOne" path
    // (the catch above sets result=null without firing onReject). Anything
    // else points at a specific reject site — see `GenerationRejectReason`.
    final rejectReason = result != null
        ? null
        : (lastReject?.name ?? 'unknown');
    if (result != null) {
      log(
        '  result: SUCCESS in ${attemptDurationMs}ms '
        '(tried=$lastTried/$lastTotalConstraints)',
      );
    } else {
      log(
        '  result: FAILURE in ${attemptDurationMs}ms '
        '(tried=$lastTried/$lastTotalConstraints, '
        'lastRatio=${lastRatio.toStringAsFixed(3)}, '
        'reason=$rejectReason)',
      );
    }

    // Emit one attempt event per loop iteration so the CLI can append a row
    // to `generator_stats.csv` — both on success and on abandon. All values
    // are primitives so the Map passes cleanly through the SendPort.
    // Only forward slugs whose deficit was strictly positive — zero entries
    // would just inflate the payload and the downstream CSV column.
    final Map<String, double>? deficitsToReport = slugDeficitMap == null
        ? null
        : {
            for (final e in slugDeficitMap.entries)
              if (e.value > 0) e.key: e.value,
          };
    params.sendPort.send({
      'type': 'attempt',
      'worker': params.workerIndex,
      'inWarmup': inWarmup,
      'targetKey': resolvedTarget?.key,
      'width': w,
      'height': h,
      'ntypesIntended': ntypesIntended,
      'preferredSlugs': preferredSlugs.toList(),
      'allowedSlugs': allowedSlugs?.toList(),
      'scenario': scenario,
      'success': result != null,
      'rejectReason': rejectReason,
      'durationMs': attemptDurationMs,
      'puzzleLevel': result?.level.index,
      'puzzleLine': result?.line,
      'slugDeficits': deficitsToReport,
    });

    // Feed the in-session tracker so a combo with K failures and zero
    // successes joins the local blacklist for the rest of this run.
    tracker.record(attemptKey, success: result != null);

    if (result != null) {
      generated++;
      final line = result.line;
      params.sendPort.send({
        'type': 'puzzle',
        'line': line,
        'level': result.level.index,
      });

      // Update legacy usageStats (slug-only bias).
      final parts = line.split('_');
      Set<String> producedSlugs = {};
      if (parts.length >= 5) {
        producedSlugs = parts[4]
            .split(';')
            .map((c) => c.split(':').first)
            .where((s) => s.isNotEmpty)
            .toSet();
        for (final slug in producedSlugs) {
          usageStats[slug] = (usageStats[slug] ?? 0) + 1;
        }
      }
      // Update equilibrium stats (used to pick the next target). We keep
      // them current during warm-up too so the switch to equilibrium picks
      // up where the warm-up corpus left off.
      if (params.equilibriumRequested && equiStats != null) {
        equiStats = equiStats.withPuzzle(
          slugs: producedSlugs,
          width: w,
          height: h,
          profile: detectPuzzleProfile(line),
        );
      }
    }
  }

  log(
    'worker done: generated=$generated/${params.count}, '
    'elapsed=${stopwatch.elapsed.inMilliseconds}ms',
  );
  params.sendPort.send({'type': 'done', 'generated': generated});
}

class _ResolvedTarget {
  final int? width;
  final int? height;
  final Set<String>? allowedSlugs;

  /// Soft preference passed to the generator (sort priority + SH prefill).
  /// Strict user-required slugs are NOT included here — they ride along on
  /// the worker's `requiredSet` (CLI `--require`) and are enforced by
  /// `generateOne` separately.
  final Set<String> preferredSlugs;

  /// True when the equilibrium picked `ProfileTarget(pathBased)` — the
  /// next attempt should route through `preFillPath`. Combined with the
  /// CLI flag via OR.
  final bool pathBasedScenario;

  /// True when the equilibrium picked `ProfileTarget(syBased)` — the
  /// next attempt should route through `preFillSy`. Combined with the
  /// CLI flag via OR.
  final bool syBasedScenario;

  const _ResolvedTarget({
    this.width,
    this.height,
    this.allowedSlugs,
    this.preferredSlugs = const {},
    this.pathBasedScenario = false,
    this.syBasedScenario = false,
  });
}

/// Translate an abstract [Target] into the concrete restrictions
/// [PuzzleGenerator.generateOne] understands. Every axis the primary target
/// leaves *free* is filled by a secondary push: weighted-by-gap sampling on
/// the slug or size axis so each attempt advances multiple axes at once,
/// without making it deterministic enough that workers collide on the same
/// sub-config.
_ResolvedTarget _resolveTarget(
  Target target,
  TargetUniverse universe,
  Set<String> baseRequired,
  EquilibriumStats stats,
  Random rng,
) {
  switch (target) {
    case SlugTarget(:final slug):
      // Slug axis fixed (X). Size axis is filled by the worker loop after
      // resolve. allowedSlugs stays unrestricted so the iterative loop has
      // room to add other slugs naturally.
      return _ResolvedTarget(preferredSlugs: {slug});

    case NTypesTarget():
      // Ntypes axis fixed (N). Pick the N slugs by slug-axis gap so this
      // attempt also advances the slug axis. The 6+ bucket is never
      // targeted, so target.n is always in [1, 5] here.
      final chosen = pickWeightedSlugs(stats, universe, target.n, rng);
      return _ResolvedTarget(allowedSlugs: chosen, preferredSlugs: chosen);

    case PairTarget(:final slugA, :final slugB):
      // Slugs fixed (the pair). Size filled by worker loop.
      final pair = {slugA, slugB};
      return _ResolvedTarget(allowedSlugs: pair, preferredSlugs: pair);

    case SizeTarget(:final width, :final height):
      // Size axis fixed. Push one weighted slug as soft preference so this
      // attempt also nudges the slug axis. allowedSlugs stays unrestricted
      // (the iterative loop can still draw from the full pool).
      final extra = pickWeightedSlugs(stats, universe, 1, rng);
      return _ResolvedTarget(
        width: width,
        height: height,
        preferredSlugs: extra,
      );

    case ProfileTarget(:final profile):
      // Profile axis fixed. The pre-fill mode is picked up by the
      // generator config; other axes (slug / ntypes / pair / size) are
      // filled by the worker loop's secondary push.
      switch (profile) {
        case ProfileCategory.classic:
          // No special restriction — default flow. The profile axis is
          // "satisfied" by any non-SH non-path-based puzzle the loop
          // produces.
          return const _ResolvedTarget();
        case ProfileCategory.sh:
          // Push SH as soft preference; `_preFillSh` activates whenever
          // SH ∈ prioritySlugs (cf. `generator.dart` dispatch).
          return const _ResolvedTarget(preferredSlugs: {'SH'});
        case ProfileCategory.pathBased:
          // Activate path-based pre-fill. The path generator picks its
          // own L / K / colors / topology — slug-level preferences are
          // ignored.
          return const _ResolvedTarget(pathBasedScenario: true);
        case ProfileCategory.syBased:
          // Activate SY-based pre-fill. The SY generator picks its own
          // island count, axes and topology; slug-level preferences are
          // ignored.
          return const _ResolvedTarget(syBasedScenario: true);
      }
  }
}

// Effective pre-fill scenario for one attempt. Priority order matches
// `PuzzleGenerator.generateOne` dispatch: pathBased / syBased short-circuit
// the regular flow, and SH pre-fill activates whenever SH ∈ prioritySlugs
// (cf. generator.dart). When none apply we're in the classic grid-first flow.
String _resolveScenario({
  required bool pathBased,
  required bool syBased,
  required Set<String> preferredSlugs,
}) {
  if (pathBased) return 'pathBased';
  if (syBased) return 'syBased';
  if (preferredSlugs.contains('SH')) return 'sh';
  return 'classic';
}
