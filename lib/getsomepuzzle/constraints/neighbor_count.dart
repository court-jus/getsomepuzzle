import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

class NeighborCountConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'NC';

  CellValue color = CellValue.free;
  int count = 0;

  @override
  Set<CellValue> get referencedColors => {color};

  NeighborCountConstraint(String strParams) {
    final params = strParams.split(".");
    indices = [int.parse(params[0])];
    color = cellRepresentationToValue(params[1]);
    count = int.parse(params[2]);
  }

  @override
  String serialize() =>
      '$slug:${indices.first}.${cellValueToString(color)}.$count';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIdx = rotateIdx90CW(indices.first, origWidth, origHeight);
    return NeighborCountConstraint(
      '$newIdx.${cellValueToString(color)}.$count',
    );
  }

  @override
  String toString() => '$count';

  @override
  String toHuman(Puzzle puzzle) =>
      '${indices.first + 1} has $count ${color.name} neighbors';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
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
            result.add('$idx.${cellValueToString(c)}.$ct');
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
    // Only free neighbours that can still take `color` count toward
    // reachability — a neighbour with `color` pruned can never raise the
    // coloured-neighbour count.
    final freeNeighbors = myNeighbors
        .where(
          (i) =>
              puzzle.cellValues[i] == CellValue.free &&
              puzzle.cells[i].options.contains(color),
        )
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
    final freeNeighbors = myNeighbors.where(
      (i) => puzzle.cellValues[i] == CellValue.free,
    );

    if (freeNeighbors.isEmpty) {
      // I already have all my neighbors filled, nothing to deduce.
      return null;
    }

    if (targetColorNeighbors.length > count) {
      // There is an error, I have too many colored neighbors
      return Impossible(this);
    }

    if (targetColorNeighbors.length == count) {
      // I already have all my colored neighbors, the rest must be another color
      // we check all neighbors to see what options they have left
      for (var neiIdx in freeNeighbors) {
        final nei = puzzle.cells[neiIdx];
        if (nei.options.contains(color)) {
          return RemoveOption(neiIdx, color, this, complexity: 0);
        }
      }
    }

    if (targetColorNeighbors.length + freeNeighbors.length < count) {
      // There are not enough cells to satisfy my constraint
      return Impossible(this);
    }

    if (targetColorNeighbors.length + freeNeighbors.length == count) {
      // All my free neighbors must match my target color. If the chosen
      // one has excluded `color` (3-colour puzzles), the target count is
      // no longer reachable.
      final target = freeNeighbors.first;
      if (!puzzle.cells[target].options.contains(color)) {
        return Impossible(this);
      }
      return SetValue(target, color, this, complexity: 0);
    }

    // I don't have all my colored neighbors but there are more free cells than
    // the difference. Nothing can be deduced.
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final myNeighbors = puzzle.getNeighbors(indices.first);
    // Only free neighbours that can still become `color` keep apply() alive:
    // once verify passes, a free neighbour with `color` pruned can never
    // change the coloured-neighbour count, so apply() can no longer fire on
    // it. Counting it (plain `== free`) would block grey-out forever —
    // the same invariant the option-aware GC fix restores.
    final liveNeighbors = myNeighbors
        .where(
          (i) =>
              puzzle.cellValues[i] == CellValue.free &&
              puzzle.cells[i].options.contains(color),
        )
        .length;
    return liveNeighbors == 0;
  }
}
