import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

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
        count: config.count,
        usageStats: usageStats,
        puzzleLines: puzzleLines,
        equilibriumRequested: equilibriumRequested,
        jobsCount: jobsCount,
        workerIndex: workerIndex,
        logFilePath: logFilePath,
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
          _controller?.add(GeneratorPuzzleMessage(message['line'] as String));
        } else if (type == 'target') {
          _controller?.add(GeneratorTargetMessage(message['label'] as String?));
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
  final int count;
  final Map<String, int>? usageStats;
  final List<String>? puzzleLines;
  final bool equilibriumRequested;
  final int jobsCount;
  final int workerIndex;
  final String? logFilePath;

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
    required this.count,
    this.usageStats,
    this.puzzleLines,
    this.equilibriumRequested = false,
    this.jobsCount = 1,
    this.workerIndex = 0,
    this.logFilePath,
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
    'maxTime=${maxTime.inSeconds}s',
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

  int generated = 0;
  final stopwatch = Stopwatch()..start();

  while (generated < params.count && stopwatch.elapsed < maxTime) {
    Target? target;
    int w;
    int h;
    Set<String>? allowedSlugs = baseAllowedSlugs;
    Set<String> preferredSlugs = const {};

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
    // show per-worker progress. Includes the resolved size when relevant.
    final String? targetLabel;
    if (inWarmup) {
      targetLabel = 'warmup ${w}x$h (${preferredSlugs.length}t)';
    } else if (target != null) {
      targetLabel = '${target.label} ${w}x$h';
    } else if (params.equilibriumRequested) {
      targetLabel = '(no target) ${w}x$h';
    } else {
      targetLabel = '${w}x$h';
    }
    params.sendPort.send({'type': 'target', 'label': targetLabel});

    final config = GeneratorConfig(
      width: w,
      height: h,
      requiredRules: requiredSet,
      allowedSlugs: allowedSlugs,
      preferredSlugs: preferredSlugs,
      maxTime: maxTime,
      count: 1,
    );

    final attemptStartMs = stopwatch.elapsedMilliseconds;
    log(
      'attempt #${generated + 1}: $targetLabel '
      'allowedSlugs=$allowedSlugs preferred=$preferredSlugs '
      'userRequired=$requiredSet',
    );

    // Throttle progress logs to one entry per [progressLogIntervalMs] inside
    // the same attempt. Without throttling, each constraint candidate would
    // emit a line.
    const progressLogIntervalMs = 2000;
    int lastProgressLogMs = attemptStartMs;
    int lastTried = 0;
    int lastTotalConstraints = 0;
    double lastRatio = 1.0;

    String? line;
    try {
      line = PuzzleGenerator.generateOne(
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
        shouldStop: () => stopwatch.elapsed > maxTime,
      );
    } catch (e, st) {
      log('  exception during generateOne: $e\n$st');
      line = null;
    }

    final attemptDurationMs = stopwatch.elapsedMilliseconds - attemptStartMs;
    if (line != null) {
      log(
        '  result: SUCCESS in ${attemptDurationMs}ms '
        '(tried=$lastTried/$lastTotalConstraints)',
      );
    } else {
      log(
        '  result: FAILURE in ${attemptDurationMs}ms '
        '(tried=$lastTried/$lastTotalConstraints, '
        'lastRatio=${lastRatio.toStringAsFixed(3)})',
      );
    }

    if (line != null) {
      generated++;
      params.sendPort.send({'type': 'puzzle', 'line': line});

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

  const _ResolvedTarget({
    this.width,
    this.height,
    this.allowedSlugs,
    this.preferredSlugs = const {},
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
  }
}
