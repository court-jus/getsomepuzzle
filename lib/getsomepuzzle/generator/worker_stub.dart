import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

class GeneratorWorker {
  Stream<GeneratorMessage> start(
    GeneratorConfig config, {
    Map<String, int>? usageStats,
    List<String>? puzzleLines,
    bool equilibriumEnabled = false,
  }) => const Stream.empty();

  void cancel() {}

  void dispose() {}
}
