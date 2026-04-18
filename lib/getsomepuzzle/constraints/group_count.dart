import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class GroupCountConstraint extends Constraint {
  @override
  String get slug => 'GC';

  int color = 0;
  int count = 0;

  GroupCountConstraint(String strParams) {
    final params = strParams.split(".");
    color = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'GC:$color.$count';

  @override
  String toString() {
    return "$color = $count groups";
  }

  @override
  String toHuman() {
    return "$count groups of color $color";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final maxCount = (width * height / 2).ceil();
    final List<String> result = [];
    for (int count = 1; count <= maxCount; count++) {
      for (final value in domain) {
        result.add('$value.$count');
      }
    }
    return result;
  }

  List<List<int>> _getColorGroups(Puzzle puzzle) {
    return puzzle.getGroups().where((grp) {
      if (grp.isEmpty) return false;
      return puzzle.cellValues[grp.first] == color;
    }).toList();
  }

  int _getGroupCount(Puzzle puzzle) {
    return _getColorGroups(puzzle).length;
  }

  @override
  bool verify(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);
    if (puzzle.complete) {
      return currentCount == count;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    return null;
  }
}
