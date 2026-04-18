import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  Isolate? _isolate;

  Future<List<String>> compute({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> solution,
    required Set<String> existingConstraints,
    required Set<int> readonlyIndices,
  }) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _HintParams(
        sendPort: receivePort.sendPort,
        width: width,
        height: height,
        domain: domain,
        solution: solution,
        existingConstraints: existingConstraints.toList(),
        readonlyIndices: readonlyIndices.toList(),
      ),
    );

    final result = await receivePort.first;
    receivePort.close();
    _isolate = null;
    return (result as List).cast<String>();
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void dispose() {
    cancel();
  }
}

class _HintParams {
  final SendPort sendPort;
  final int width;
  final int height;
  final List<int> domain;
  final List<int> solution;
  final List<String> existingConstraints;
  final List<int> readonlyIndices;

  _HintParams({
    required this.sendPort,
    required this.width,
    required this.height,
    required this.domain,
    required this.solution,
    required this.existingConstraints,
    required this.readonlyIndices,
  });
}

void _isolateEntryPoint(_HintParams params) {
  final existing = params.existingConstraints.toSet();
  final readonlySet = params.readonlyIndices.toSet();

  // Build a solved puzzle for verification
  final solved = Puzzle.empty(params.width, params.height, params.domain);
  for (int i = 0; i < params.solution.length; i++) {
    solved.cells[i].setForSolver(params.solution[i]);
  }

  final List<String> validConstraints = [];

  for (final entry in constraintRegistry) {
    final allParameters = entry.generateAllParameters(
      params.width,
      params.height,
      params.domain,
      readonlySet,
    );
    for (final param in allParameters) {
      final constraint = createConstraint(entry.slug, param);
      if (constraint == null) continue;
      final serialized = constraint.serialize();
      if (existing.contains(serialized)) continue;
      if (constraint.verify(solved)) {
        validConstraints.add(serialized);
      }
    }
  }

  params.sendPort.send(validConstraints);
}
