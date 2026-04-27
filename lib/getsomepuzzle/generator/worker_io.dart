import 'dart:async';
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
    bool equilibriumEnabled = false,
  }) {
    _controller = StreamController<GeneratorMessage>();

    _runIsolate(config, usageStats, puzzleLines, equilibriumEnabled);

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
    bool equilibriumEnabled,
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
        equilibriumEnabled: equilibriumEnabled,
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
  final bool equilibriumEnabled;

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
    this.equilibriumEnabled = false,
  });
}

void _isolateEntryPoint(_IsolateParams params) {
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

  // Equilibrium state
  EquilibriumStats? equiStats;
  TargetUniverse? universe;
  final failureCounts = <String, int>{};
  final blacklist = <String>{};
  if (params.equilibriumEnabled) {
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
    Set<String> required = requiredSet;
    int? exactNTypes;

    if (params.equilibriumEnabled && universe != null && equiStats != null) {
      target = pickTarget(equiStats, universe, blacklistedKeys: blacklist);
      // Random width/height by default; target may override.
      w = effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
      h = effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);
      if (target != null) {
        final resolved = _resolveTarget(target, universe, requiredSet, rng);
        w = resolved.width ?? w;
        h = resolved.height ?? h;
        allowedSlugs = resolved.allowedSlugs;
        required = resolved.required;
        exactNTypes = resolved.exactNTypes;
      }
    } else {
      w = effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
      h = effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);
    }

    final config = GeneratorConfig(
      width: w,
      height: h,
      requiredRules: required,
      allowedSlugs: allowedSlugs,
      exactNTypes: exactNTypes,
      maxTime: maxTime,
      count: 1,
    );

    String? line;
    try {
      line = PuzzleGenerator.generateOne(
        config,
        usageStats: usageStats,
        onProgress: (p) {
          params.sendPort.send({
            'type': 'progress',
            'generated': generated,
            'total': params.count,
            'tried': p.constraintsTried,
            'totalConstraints': p.constraintsTotal,
            'ratio': p.currentRatio,
          });
        },
        shouldStop: () => stopwatch.elapsed > maxTime,
      );
    } catch (e) {
      print("Generation failed for this attempt, retry");
      line = null;
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
      // Update equilibrium stats (used to pick the next target).
      if (params.equilibriumEnabled && equiStats != null) {
        equiStats = equiStats.withPuzzle(
          slugs: producedSlugs,
          width: w,
          height: h,
        );
        if (target != null) failureCounts.remove(target.key);
      }
    } else if (target != null) {
      // Track consecutive failures per target; blacklist after threshold.
      final next = (failureCounts[target.key] ?? 0) + 1;
      failureCounts[target.key] = next;
      if (next >= kBlacklistAfterFailures) {
        blacklist.add(target.key);
      }
    }
  }

  params.sendPort.send({'type': 'done', 'generated': generated});
}

class _ResolvedTarget {
  final int? width;
  final int? height;
  final Set<String>? allowedSlugs;
  final Set<String> required;
  final int? exactNTypes;

  const _ResolvedTarget({
    this.width,
    this.height,
    this.allowedSlugs,
    required this.required,
    this.exactNTypes,
  });
}

/// Translate an abstract [Target] into the concrete restrictions
/// [PuzzleGenerator.generateOne] understands. SH pre-fill is decided by the
/// generator based on whether 'SH' ends up in [required], so we don't need
/// to surface it here.
_ResolvedTarget _resolveTarget(
  Target target,
  TargetUniverse universe,
  Set<String> baseRequired,
  Random rng,
) {
  switch (target) {
    case SlugTarget(:final slug):
      // Push this slug: keep all other slugs available, just require this one.
      return _ResolvedTarget(required: {...baseRequired, slug});

    case NTypesTarget():
      // n==7 represents the "7+" bucket — try to use as many slugs as possible.
      final desired = target.isSevenPlus ? 7 : target.n;
      final pool = [...universe.allowedSlugs]..shuffle(rng);
      final n = desired > pool.length ? pool.length : desired;
      final chosen = pool.take(n).toSet();
      return _ResolvedTarget(
        allowedSlugs: chosen,
        required: {...baseRequired, ...chosen},
        exactNTypes: n,
      );

    case PairTarget(:final slugA, :final slugB):
      final pair = {slugA, slugB};
      return _ResolvedTarget(
        allowedSlugs: pair,
        required: {...baseRequired, ...pair},
        exactNTypes: 2,
      );

    case SizeTarget(:final width, :final height):
      // Size axis only constrains dimensions — slugs stay free, slug-bias
      // (legacy usageStats sort) keeps doing its thing.
      return _ResolvedTarget(
        width: width,
        height: height,
        required: baseRequired,
      );
  }
}
