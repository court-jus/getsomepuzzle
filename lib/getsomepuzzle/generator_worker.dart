import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator.dart';

/// Message types sent from the worker to the UI.
sealed class GeneratorMessage {}

class GeneratorProgressMessage extends GeneratorMessage {
  final GeneratorProgress progress;
  GeneratorProgressMessage(this.progress);
}

class GeneratorPuzzleMessage extends GeneratorMessage {
  final String puzzleLine;
  GeneratorPuzzleMessage(this.puzzleLine);
}

class GeneratorDoneMessage extends GeneratorMessage {
  final int totalGenerated;
  GeneratorDoneMessage(this.totalGenerated);
}

/// Runs puzzle generation, adapting to the platform:
/// - Native: uses Isolate for true background execution
/// - Web: uses chunked async execution
class GeneratorWorker {
  StreamController<GeneratorMessage>? _controller;
  bool _cancelled = false;
  Isolate? _isolate;

  Stream<GeneratorMessage> start(GeneratorConfig config) {
    _controller = StreamController<GeneratorMessage>();
    _cancelled = false;

    if (kIsWeb) {
      _runWeb(config);
    } else {
      _runIsolate(config);
    }

    return _controller!.stream;
  }

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void dispose() {
    cancel();
    _controller?.close();
  }

  // --- Web implementation: chunked async ---
  Future<void> _runWeb(GeneratorConfig config) async {
    int generated = 0;
    final stopwatch = Stopwatch()..start();

    while (generated < config.count && !_cancelled && stopwatch.elapsed < config.maxTime) {
      // Yield to event loop between attempts
      await Future.delayed(Duration.zero);
      if (_cancelled) break;

      try {
        final line = PuzzleGenerator.generateOne(
          config,
          onProgress: (p) {
            _controller?.add(GeneratorProgressMessage(GeneratorProgress(
              puzzlesGenerated: generated,
              totalRequested: config.count,
              constraintsTried: p.constraintsTried,
              constraintsTotal: p.constraintsTotal,
              currentRatio: p.currentRatio,
            )));
          },
          shouldStop: () => _cancelled || stopwatch.elapsed > config.maxTime,
        );

        if (line != null) {
          generated++;
          _controller?.add(GeneratorPuzzleMessage(line));
          _controller?.add(GeneratorProgressMessage(GeneratorProgress(
            puzzlesGenerated: generated,
            totalRequested: config.count,
            constraintsTried: 0,
            constraintsTotal: 0,
            currentRatio: 0,
          )));
        }
      } catch (_) {
        // Generation failed for this attempt, retry
      }
    }

    _controller?.add(GeneratorDoneMessage(generated));
    _controller?.close();
  }

  // --- Native implementation: Isolate ---
  Future<void> _runIsolate(GeneratorConfig config) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _IsolateParams(
        sendPort: receivePort.sendPort,
        width: config.width,
        height: config.height,
        requiredRules: config.requiredRules.toList(),
        bannedRules: config.bannedRules.toList(),
        maxTimeMs: config.maxTime.inMilliseconds,
        count: config.count,
      ),
    );

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;
        if (type == 'progress') {
          _controller?.add(GeneratorProgressMessage(GeneratorProgress(
            puzzlesGenerated: message['generated'] as int,
            totalRequested: message['total'] as int,
            constraintsTried: message['tried'] as int,
            constraintsTotal: message['totalConstraints'] as int,
            currentRatio: message['ratio'] as double,
          )));
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
  final List<String> requiredRules, bannedRules;
  final int maxTimeMs;
  final int count;

  _IsolateParams({
    required this.sendPort,
    required this.width,
    required this.height,
    required this.requiredRules,
    required this.bannedRules,
    required this.maxTimeMs,
    required this.count,
  });
}

void _isolateEntryPoint(_IsolateParams params) {
  final config = GeneratorConfig(
    width: params.width,
    height: params.height,
    requiredRules: params.requiredRules.toSet(),
    bannedRules: params.bannedRules.toSet(),
    maxTime: Duration(milliseconds: params.maxTimeMs),
    count: params.count,
  );

  int generated = 0;
  final stopwatch = Stopwatch()..start();

  while (generated < config.count && stopwatch.elapsed < config.maxTime) {
    try {
      final line = PuzzleGenerator.generateOne(
        config,
        onProgress: (p) {
          params.sendPort.send({
            'type': 'progress',
            'generated': generated,
            'total': config.count,
            'tried': p.constraintsTried,
            'totalConstraints': p.constraintsTotal,
            'ratio': p.currentRatio,
          });
        },
        shouldStop: () => stopwatch.elapsed > config.maxTime,
      );

      if (line != null) {
        generated++;
        params.sendPort.send({
          'type': 'puzzle',
          'line': line,
        });
      }
    } catch (e) {
      // Generation failed for this attempt, retry
    }
  }

  params.sendPort.send({
    'type': 'done',
    'generated': generated,
  });
}
