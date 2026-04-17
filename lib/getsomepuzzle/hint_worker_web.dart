import 'dart:async';

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

    final slugsAndParams = <String, List<String>>{
      'FM': ForbiddenMotif.generateAllParameters(width, height, domain),
      'PA': ParityConstraint.generateAllParameters(width, height),
      'GS': GroupSize.generateAllParameters(width, height),
      'LT': LetterGroup.generateAllParameters(width, height),
      'QA': QuantityConstraint.generateAllParameters(width, height, domain),
      'SY': SymmetryConstraint.generateAllParameters(width, height),
      'DF': DifferentFromConstraint.generateAllParameters(
        width,
        height,
        excludedIndices: readonlyIndices,
      ),
      'SH': ShapeConstraint.generateAllParameters(width, height),
    };

    int processed = 0;
    for (final entry in slugsAndParams.entries) {
      for (final param in entry.value) {
        if (_cancelled) return validConstraints;

        final constraint = createConstraint(entry.key, param);
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
