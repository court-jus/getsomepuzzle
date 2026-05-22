import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

class GeneratorWorker {
  StreamController<GeneratorMessage>? _controller;
  bool _cancelled = false;

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
    // Equilibrium, warm-up and the infeasibility blacklist are CLI-only for
    // now; the web/in-app generator keeps the legacy slug-only bias and
    // ignores all three.
    _controller = StreamController<GeneratorMessage>();
    _cancelled = false;

    _runWeb(config, usageStats);

    return _controller!.stream;
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
    _controller?.close();
  }

  Future<void> _runWeb(
    GeneratorConfig config,
    Map<String, int>? usageStats,
  ) async {
    int generated = 0;
    final stopwatch = Stopwatch()..start();

    while (generated < config.count &&
        !_cancelled &&
        stopwatch.elapsed < config.maxTime) {
      // Yield to event loop between attempts
      await Future.delayed(Duration.zero);
      if (_cancelled) break;

      try {
        final result = PuzzleGenerator.generateOne(
          config,
          usageStats: usageStats,
          onProgress: (p) {
            _controller?.add(
              GeneratorProgressMessage(
                GeneratorProgress(
                  puzzlesGenerated: generated,
                  totalRequested: config.count,
                  constraintsTried: p.constraintsTried,
                  constraintsTotal: p.constraintsTotal,
                  currentRatio: p.currentRatio,
                ),
              ),
            );
          },
          shouldStop: () => _cancelled || stopwatch.elapsed > config.maxTime,
        );

        if (result != null) {
          generated++;
          _controller?.add(GeneratorPuzzleMessage(result.line, result.level));
          _controller?.add(
            GeneratorProgressMessage(
              GeneratorProgress(
                puzzlesGenerated: generated,
                totalRequested: config.count,
                constraintsTried: 0,
                constraintsTotal: 0,
                currentRatio: 0,
              ),
            ),
          );
        }
      } catch (_) {
        // Generation failed for this attempt, retry
      }
    }

    _controller?.add(GeneratorDoneMessage(generated));
    _controller?.close();
  }
}
