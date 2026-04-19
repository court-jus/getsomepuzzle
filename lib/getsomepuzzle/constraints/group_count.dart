import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

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

  int _getGroupCount(Puzzle puzzle) {
    return getColorGroups(puzzle, color).length;
  }

  @override
  bool verify(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);
    if (puzzle.complete) {
      return currentCount == count;
    }
    if (currentCount > count) {
      // We have more groups than expected, see if they can merge
      final minGroupsPossible = calculateMinGroups(puzzle, color);
      if (minGroupsPossible > count) {
        return false;
      }
    }
    if (currentCount < count) {
      // Look for free cells where we could put a 'color' cell without
      // merging into an existing group
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.length + currentCount < count) {
        return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);

    if (currentCount > count) {
      final minGroupsPossible = calculateMinGroups(puzzle, color);
      if (minGroupsPossible > count) {
        return Move(0, 0, this, isImpossible: this);
      }

      final mergeableCells = getCellsThatMergeColorGroups(puzzle, color);
      if (mergeableCells.length == 1) {
        return Move(mergeableCells.first, color, this);
      }
    }

    if (currentCount < count) {
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.length + currentCount < count) {
        return Move(0, 0, this, isImpossible: this);
      }
      if (candidates.length + currentCount == count && candidates.isNotEmpty) {
        return Move(candidates.first, color, this);
      }
    }

    if (currentCount == count && !puzzle.complete) {
      final opposite = puzzle.domain.firstWhereOrNull((c) => c != color)!;
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.isEmpty) {
        final forcedCells = getCellsThatMergeColorGroups(puzzle, color);
        if (forcedCells.isNotEmpty) {
          return Move(forcedCells.first, opposite, this);
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final currentCount = _getGroupCount(puzzle);
    if (currentCount != count) return false;
    final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
    return candidates.isEmpty;
  }
}
