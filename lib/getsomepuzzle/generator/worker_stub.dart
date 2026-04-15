import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/messages.dart';

class GeneratorWorker {
  Stream<GeneratorMessage> start(
    GeneratorConfig config, {
    Map<String, int>? usageStats,
  }) => const Stream.empty();

  void cancel() {}

  void dispose() {}
}
