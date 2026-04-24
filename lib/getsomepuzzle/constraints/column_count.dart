import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class ColumnCountConstraint extends Constraint {
  @override
  String get slug => 'CC';

  int columnIdx = 0;
  int color = 0;
  int count = 0;

  ColumnCountConstraint(String strParams) {
    final params = strParams.split(".");
    columnIdx = int.parse(params[0]);
    color = int.parse(params[1]);
    count = int.parse(params[2]);
  }

  @override
  String serialize() => 'CC:$columnIdx.$color.$count';

  @override
  String toString() => '$count';

  @override
  String toHuman(Puzzle puzzle) => 'Col ${columnIdx + 1}: $count';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int col = 0; col < width; col++) {
      for (final c in domain) {
        for (int n = 1; n < height; n++) {
          result.add('$col.$c.$n');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final column = puzzle.getColumns()[columnIdx];
    final have = column.where((cell) => cell.value == color).length;
    if (puzzle.complete) return have == count;
    if (have > count) return false;
    final free = column.where((cell) => cell.value == 0).length;
    if (have + free < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final column = puzzle.getColumns()[columnIdx];
    final colorCount = column.where((cell) => cell.value == color).length;
    final freeCells = column.where((cell) => cell.value == 0);
    if (freeCells.isEmpty) return null;

    final opposite = puzzle.domain.firstWhere((v) => v != color);

    if (colorCount > count) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (colorCount == count) {
      // All color cells placed — remaining free cells get the opposite value
      return Move(freeCells.first.idx, opposite, this);
    }
    if (count - colorCount == freeCells.length) {
      // Exactly as many free cells as needed — they must all be color
      return Move(freeCells.first.idx, color, this);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final column = puzzle.getColumns()[columnIdx];
    return column.every((cell) => cell.value != 0);
  }
}
