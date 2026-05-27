import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

class GeneratorWorker {
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
    String? Function(int workerIndex)? assignTarget,
  }) => const Stream.empty();

  void cancel() {}

  void dispose() {}
}
