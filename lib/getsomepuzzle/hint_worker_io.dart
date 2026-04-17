import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/constraint_registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

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

  final slugsAndParams = <String, List<String>>{
    'FM': ForbiddenMotif.generateAllParameters(
      params.width,
      params.height,
      params.domain,
    ),
    'PA': ParityConstraint.generateAllParameters(params.width, params.height),
    'GS': GroupSize.generateAllParameters(params.width, params.height),
    'LT': LetterGroup.generateAllParameters(params.width, params.height),
    'QA': QuantityConstraint.generateAllParameters(
      params.width,
      params.height,
      params.domain,
    ),
    'SY': SymmetryConstraint.generateAllParameters(params.width, params.height),
    'DF': DifferentFromConstraint.generateAllParameters(
      params.width,
      params.height,
      excludedIndices: readonlySet,
    ),
    'SH': ShapeConstraint.generateAllParameters(params.width, params.height),
  };

  for (final entry in slugsAndParams.entries) {
    for (final param in entry.value) {
      final constraint = createConstraint(entry.key, param);
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
