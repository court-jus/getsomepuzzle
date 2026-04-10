import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class DifferentFromConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'DF';

  final String direction;

  DifferentFromConstraint(String strParams)
    : direction = strParams.split(".")[1] {
    indices.add(int.parse(strParams.split(".")[0]));
  }

  int getNeighborIndex(int width) {
    final idx = indices.first;
    if (direction == 'right') {
      return idx + 1;
    } else {
      return idx + width;
    }
  }

  @override
  String toString() {
    return "≠";
  }

  @override
  String toHuman() {
    final idx = indices.first + 1;
    final nidx =
        getNeighborIndex(100) +
        1; // Approximation, actual width used in verify/apply
    return "$idx ≠ $nidx";
  }

  @override
  String serialize() => 'DF:${indices.first}.$direction';

  static List<String> generateAllParameters(
    int width,
    int height, {
    Set<int>? excludedIndices,
  }) {
    final List<String> result = [];
    final excluded = excludedIndices ?? {};
    for (int idx = 0; idx < width * height; idx++) {
      if (excluded.contains(idx)) continue;
      final ridx = idx ~/ width;
      final cidx = idx % width;
      if (cidx < width - 1) {
        final neighbor = idx + 1;
        if (!excluded.contains(neighbor)) {
          result.add('$idx.right');
        }
      }
      if (ridx < height - 1) {
        final neighbor = idx + width;
        if (!excluded.contains(neighbor)) {
          result.add('$idx.down');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final idx = indices.first;
    final nidx = getNeighborIndex(puzzle.width);
    final val1 = puzzle.cells[idx].value;
    final val2 = puzzle.cells[nidx].value;
    if (val1 == 0 || val2 == 0) return true;
    return val1 != val2;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final idx = indices.first;
    final nidx = getNeighborIndex(puzzle.width);
    final cell1 = puzzle.cells[idx];
    final cell2 = puzzle.cells[nidx];

    if (cell1.value != 0 && cell2.value != 0) {
      if (cell1.value == cell2.value) {
        return Move(0, 0, this, isImpossible: this);
      }
      return null;
    }

    if (cell1.value != 0) {
      final opposite = puzzle.domain.firstWhere((v) => v != cell1.value);
      return Move(nidx, opposite, this);
    }

    if (cell2.value != 0) {
      final opposite = puzzle.domain.firstWhere((v) => v != cell2.value);
      return Move(idx, opposite, this);
    }

    return null;
  }
}
