import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

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
}
