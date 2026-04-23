import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

class GeneratorWorker {
  StreamController<GeneratorMessage>? _controller;
  Isolate? _isolate;

  Stream<GeneratorMessage> start(
    GeneratorConfig config, {
    Map<String, int>? usageStats,
  }) {
    _controller = StreamController<GeneratorMessage>();

    _runIsolate(config, usageStats);

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
        bannedRules: config.bannedRules.toList(),
        maxTimeMs: config.maxTime.inMilliseconds,
        count: config.count,
        usageStats: usageStats,
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
  final List<String> requiredRules, bannedRules;
  final int maxTimeMs;
  final int count;
  final Map<String, int>? usageStats;

  _IsolateParams({
    required this.sendPort,
    required this.width,
    required this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    required this.requiredRules,
    required this.bannedRules,
    required this.maxTimeMs,
    required this.count,
    this.usageStats,
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
      : null;

  int generated = 0;
  final stopwatch = Stopwatch()..start();

  while (generated < params.count && stopwatch.elapsed < maxTime) {
    final w = effectiveMinW + rng.nextInt(effectiveMaxW - effectiveMinW + 1);
    final h = effectiveMinH + rng.nextInt(effectiveMaxH - effectiveMinH + 1);

    final config = GeneratorConfig(
      width: w,
      height: h,
      requiredRules: params.requiredRules.toSet(),
      bannedRules: params.bannedRules.toSet(),
      maxTime: maxTime,
      count: 1,
    );

    try {
      final line = PuzzleGenerator.generateOne(
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

      if (line != null) {
        generated++;
        params.sendPort.send({'type': 'puzzle', 'line': line});

        // Update usage stats for next generation
        if (usageStats != null) {
          final parts = line.split('_');
          if (parts.length >= 5) {
            final slugs = parts[4]
                .split(';')
                .map((c) => c.split(':').first)
                .where((s) => s.isNotEmpty)
                .toSet();
            for (final slug in slugs) {
              usageStats[slug] = (usageStats[slug] ?? 0) + 1;
            }
          }
        }
      }
    } catch (e) {
      // Generation failed for this attempt, retry
      print("Generation failed for this attempt, retry");
    }
  }

  params.sendPort.send({'type': 'done', 'generated': generated});
}
