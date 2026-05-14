import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
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
  final puzzle = params.puzzle;

  final existingConstraints = puzzle.constraints
      .map((c) => c.serialize())
      .toSet();
  final readonlyIndices = <int>{};
  for (int i = 0; i < puzzle.cells.length; i++) {
    if (puzzle.cells[i].readonly) readonlyIndices.add(i);
  }

  final existing = existingConstraints.toSet();
  final readonlySet = readonlyIndices.toSet();

  // Build a solved puzzle for verification
  final solved = Puzzle.empty(puzzle.width, puzzle.height, puzzle.domain);
  for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
    solved.cells[i].setForSolver(puzzle.cachedSolution![i]);
  }

  final List<String> validConstraints = [];

  for (final entry in constraintRegistry) {
    final allParameters = entry.generateAllParameters(
      puzzle.width,
      puzzle.height,
      puzzle.domain,
      readonlySet,
    );
    for (final param in allParameters) {
      final constraint = createConstraint(entry.slug, param);
      if (constraint == null) continue;
      final serialized = constraint.serialize();
      if (existing.contains(serialized)) continue;
      if (constraint.verify(solved)) {
        final clone = params.puzzle.clone();
        if (constraint.isCompleteFor(clone)) {
          // This constraint is useless and won't help the player
          continue;
        }
        clone.addConstraint(constraint);
        // Now we check if the puzzle can be solved with the new constraint
        if (clone.solve()) {
          if (constraint.verify(clone)) {
            validConstraints.add(serialized);
          }
        }
      }
    }
  }

  params.sendPort.send(validConstraints);
}
