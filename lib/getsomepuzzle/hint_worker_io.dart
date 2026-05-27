import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/hint_worker_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;

  /// Returns the constraint (serialized `SLUG:params`) to offer as a hint, or
  /// null when none is available. Runs the search in a background isolate.
  Future<String?> compute({required Puzzle puzzle}) async {
    final port = ReceivePort();
    _receivePort = port;

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _HintParams(sendPort: port.sendPort, puzzle: puzzle),
    );

    try {
      final result = await port.first;
      return result as String?;
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

Future<void> _isolateEntryPoint(_HintParams params) async {
  final ctx = HintContext.forPuzzle(params.puzzle);
  // No yielding: the isolate has the whole core to itself.
  final result = await pickHintConstraint(ctx);
  params.sendPort.send(result);
}
