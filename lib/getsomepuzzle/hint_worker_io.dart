import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;

  Future<List<String>> compute({required Puzzle puzzle}) async {
    final port = ReceivePort();
    _receivePort = port;

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _HintParams(sendPort: port.sendPort, puzzle: puzzle),
    );

    try {
      final result = await port.first;
      return (result as List).cast<String>();
    } finally {
      port.close();
      if (identical(_receivePort, port)) _receivePort = null;
      _isolate = null;
    }
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

  void dispose() {
    cancel();
  }
}

class _HintParams {
  final SendPort sendPort;
  final Puzzle puzzle;

  _HintParams({required this.sendPort, required this.puzzle});
}

void _isolateEntryPoint(_HintParams params) {
  final ctx = HintContext.forPuzzle(params.puzzle);
  final validConstraints = <String>[];

  for (final entry in constraintRegistry) {
    final allParameters = entry.generateAllParameters(
      ctx.puzzle.width,
      ctx.puzzle.height,
      ctx.puzzle.domain,
      ctx.readonlyIndices,
    );
    for (final param in allParameters) {
      final serialized = classifyHintCandidate(ctx, entry.slug, param);
      if (serialized != null) validConstraints.add(serialized);
    }
  }

  params.sendPort.send(validConstraints);
}
