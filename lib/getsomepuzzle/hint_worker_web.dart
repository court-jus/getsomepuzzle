import 'dart:async';

import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintWorker {
  bool _cancelled = false;

  Future<List<String>> compute({required Puzzle puzzle}) async {
    _cancelled = false;
    final existingConstraints = puzzle.constraints
        .map((c) => c.serialize())
        .toSet();
    final readonlyIndices = <int>{};
    for (int i = 0; i < puzzle.cells.length; i++) {
      if (puzzle.cells[i].readonly) readonlyIndices.add(i);
    }

    final solved = Puzzle.empty(puzzle.width, puzzle.height, puzzle.domain);
    for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
      solved.cells[i].setForSolver(puzzle.cachedSolution![i]);
    }

    final List<String> validConstraints = [];

    int processed = 0;
    for (final entry in constraintRegistry) {
      final allParameters = entry.generateAllParameters(
        puzzle.width,
        puzzle.height,
        puzzle.domain,
        readonlyIndices,
      );
      for (final param in allParameters) {
        if (_cancelled) return validConstraints;

        final constraint = createConstraint(entry.slug, param);
        if (constraint == null) continue;
        final serialized = constraint.serialize();
        if (existingConstraints.contains(serialized)) continue;
        if (constraint.verify(solved)) {
          final clone = puzzle.clone();
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
