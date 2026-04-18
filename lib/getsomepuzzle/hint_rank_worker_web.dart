import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintRankResult {
  final List<String> ranked;
  final int usefulCount;
  HintRankResult(this.ranked, this.usefulCount);
}

class HintRankWorker {
  bool _cancelled = false;

  Future<HintRankResult> rank({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> cellValues,
    required List<String> existingConstraints,
    required List<String> candidateConstraints,
  }) async {
    _cancelled = false;

    final puzzle = Puzzle.empty(width, height, domain);
    for (int i = 0; i < cellValues.length; i++) {
      if (cellValues[i] != 0) {
        puzzle.cells[i].setForSolver(cellValues[i]);
      }
    }
    for (final cs in existingConstraints) {
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

    int processed = 0;
    for (final cs in candidateConstraints) {
      if (_cancelled) {
        notUseful.addAll(
          candidateConstraints.skip(useful.length + notUseful.length),
        );
        break;
      }

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

      processed++;
      if (processed % 5 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    return HintRankResult([...useful, ...notUseful], useful.length);
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
