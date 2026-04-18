import 'dart:async';
import 'dart:isolate';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintRankResult {
  final List<String> ranked;
  final int usefulCount;
  HintRankResult(this.ranked, this.usefulCount);
}

class HintRankWorker {
  Isolate? _isolate;

  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _RankParams(
        sendPort: receivePort.sendPort,
        width: width,
        height: height,
        domain: domain,
        cellValues: cellValues,
        existingConstraints: existingConstraints,
        candidateConstraints: candidateConstraints,
      ),
    );

    final result = await receivePort.first as Map<String, dynamic>;
    receivePort.close();
    _isolate = null;
    return HintRankResult(
      (result['ranked'] as List).cast<String>(),
      result['usefulCount'] as int,
    );
  }

  void cancel() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  void dispose() {
    cancel();
  }
}

class _RankParams {
  final SendPort sendPort;
  final int width;
  final int height;
  final List<int> domain;
  final List<int> cellValues;
  final List<String> existingConstraints;
  final List<String> candidateConstraints;

  _RankParams({
    required this.sendPort,
    required this.width,
    required this.height,
    required this.domain,
    required this.cellValues,
    required this.existingConstraints,
    required this.candidateConstraints,
  });
}

void _isolateEntryPoint(_RankParams params) {
  // Reconstruct the puzzle in its current player state
  final puzzle = Puzzle.empty(params.width, params.height, params.domain);
  for (int i = 0; i < params.cellValues.length; i++) {
    if (params.cellValues[i] != 0) {
      puzzle.cells[i].setForSolver(params.cellValues[i]);
    }
  }
  for (final cs in params.existingConstraints) {
    final colonIdx = cs.indexOf(':');
    if (colonIdx < 0) continue;
    final slug = cs.substring(0, colonIdx);
    final p = cs.substring(colonIdx + 1);
    final c = createConstraint(slug, p);
    if (c != null) puzzle.constraints.add(c);
  }

  // Compute baseline: how many cells get filled by propagation without any candidate
  final baseline = puzzle.clone();
  try {
    baseline.applyConstraintsPropagation();
  } on SolverContradiction {
    // ignore
  }
  final baselineFilled = baseline.cellValues.where((v) => v != 0).length;

  final useful = <String>[];
  final notUseful = <String>[];

  for (final cs in params.candidateConstraints) {
    final colonIdx = cs.indexOf(':');
    if (colonIdx < 0) {
      notUseful.add(cs);
      continue;
    }
    final slug = cs.substring(0, colonIdx);
    final p = cs.substring(colonIdx + 1);
    final constraint = createConstraint(slug, p);
    if (constraint == null) {
      notUseful.add(cs);
      continue;
    }

    // Clone the original puzzle (not the propagated one), add candidate,
    // run full propagation, and check if more cells get filled than baseline.
    final test = puzzle.clone();
    test.constraints.add(constraint);
    try {
      test.applyConstraintsPropagation();
    } on SolverContradiction {
      // ignore
    }
    final testFilled = test.cellValues.where((v) => v != 0).length;
    if (testFilled > baselineFilled) {
      useful.add(cs);
    } else {
      notUseful.add(cs);
    }
  }

  params.sendPort.send({
    'ranked': [...useful, ...notUseful],
    'usefulCount': useful.length,
  });
}
