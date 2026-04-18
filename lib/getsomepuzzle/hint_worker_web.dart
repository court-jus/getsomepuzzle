import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  bool _cancelled = false;

  Future<List<String>> compute({
    required int width,
    required int height,
    required List<int> domain,
    required List<int> solution,
    required Set<String> existingConstraints,
    required Set<int> readonlyIndices,
  }) async {
    _cancelled = false;

    final solved = Puzzle.empty(width, height, domain);
    for (int i = 0; i < solution.length; i++) {
      solved.cells[i].setForSolver(solution[i]);
    }

    final List<String> validConstraints = [];

    int processed = 0;
    for (final entry in constraintRegistry) {
      final allParameters = entry.generateAllParameters(
        width,
        height,
        domain,
        readonlyIndices,
      );
      for (final param in allParameters) {
        if (_cancelled) return validConstraints;

        final constraint = createConstraint(entry.slug, param);
        if (constraint == null) continue;
        final serialized = constraint.serialize();
        if (existingConstraints.contains(serialized)) continue;
        if (constraint.verify(solved)) {
          validConstraints.add(serialized);
        }

        // Yield to event loop periodically
        processed++;
        if (processed % 100 == 0) {
          await Future.delayed(Duration.zero);
        }
      }
    }

    return validConstraints;
  }

  void cancel() {
    _cancelled = true;
  }

  void dispose() {
    cancel();
  }
}
