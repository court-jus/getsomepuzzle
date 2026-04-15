import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Constraint that excludes a known solution.
/// Used during generation to verify puzzle uniqueness.
class OtherSolutionConstraint extends Constraint {
  final List<int> solution;

  OtherSolutionConstraint(this.solution);

  @override
  String serialize() => 'OS:${solution.join('')}';

  @override
  bool verify(Puzzle puzzle) {
    final values = puzzle.cellValues;
    if (values.any((v) => v == 0)) return true;
    for (int i = 0; i < values.length; i++) {
      if (values[i] != solution[i]) return true;
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    // If only one free cell remains, and setting it to the excluded
    // solution's value would reproduce the banned solution, force
    // the opposite value.
    final free = <int>[];
    bool allMatchSoFar = true;
    for (int i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] == 0) {
        free.add(i);
      } else if (puzzle.cellValues[i] != solution[i]) {
        allMatchSoFar = false;
      }
    }
    if (!allMatchSoFar) return null;
    if (free.length == 1) {
      final idx = free.first;
      final opposite = puzzle.domain.firstWhere((v) => v != solution[idx]);
      return Move(idx, opposite, this);
    }
    return null;
  }
}
