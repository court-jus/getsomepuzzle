import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class NeighborCountConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'NC';

  int color = 0;
  int count = 0;

  NeighborCountConstraint(String strParams) {
    final params = strParams.split(".");
    indices = [int.parse(params[0])];
    color = int.parse(params[1]);
    count = int.parse(params[2]);
  }

  @override
  String serialize() => '$slug:${indices.first}.$color.$count';

  @override
  String toString() => '$count';

  @override
  String toHuman(Puzzle puzzle) =>
      '${indices.first + 1} has $count $color neighbors';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int col = 0; col < width; col++) {
      for (int row = 0; row < height; row++) {
        final idx = row * width + col;
        final nc =
            1 +
            (col > 0 ? 1 : 0) +
            (row > 0 ? 1 : 0) +
            (col < width - 1 ? 1 : 0) +
            (row < height - 1 ? 1 : 0);
        for (final c in domain) {
          for (int ct = 0; ct < nc; ct++) {
            result.add('$idx.$c.$ct');
          }
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final myNeighbors = puzzle.getNeighbors(indices.first);
    final targetColorNeighbors = myNeighbors
        .where((i) => puzzle.cellValues[i] == color)
        .length;
    final freeNeighbors = myNeighbors
        .where((i) => puzzle.cellValues[i] == 0)
        .length;
    if (puzzle.complete) return targetColorNeighbors == count;
    if (targetColorNeighbors > count) return false;
    if (targetColorNeighbors + freeNeighbors < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myNeighbors = puzzle.getNeighbors(indices.first);
    final targetColorNeighbors = myNeighbors.where(
      (i) => puzzle.cellValues[i] == color,
    );
    final freeNeighbors = myNeighbors.where((i) => puzzle.cellValues[i] == 0);

    if (freeNeighbors.isEmpty) {
      // I already have all my neighbors filled, nothing to deduce.
      return null;
    }

    if (targetColorNeighbors.length > count) {
      // There is an error, I have too many colored neighbors
      return Move(0, 0, this, isImpossible: this);
    }

    if (targetColorNeighbors.length == count) {
      // I already have all my colored neighbors, the rest must be the opposite color
      final opposite = puzzle.domain.whereNot((i) => i == color).first;
      return Move(freeNeighbors.first, opposite, this);
    }

    if (targetColorNeighbors.length + freeNeighbors.length < count) {
      // There are not enough cells to satisfy my constraint
      return Move(0, 0, this, isImpossible: this);
    }

    if (targetColorNeighbors.length + freeNeighbors.length == count) {
      // All my free neighbors must match my target color
      return Move(freeNeighbors.first, color, this);
    }

    // I don't have all my colored neighbors but there are more free cells than
    // the difference. Nothing can be deduced.
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final myNeighbors = puzzle.getNeighbors(indices.first);
    final freeNeighbors = myNeighbors
        .where((i) => puzzle.cellValues[i] == 0)
        .length;
    return freeNeighbors == 0;
  }
}
