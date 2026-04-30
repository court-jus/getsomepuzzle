import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class ParityConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'PA';

  String side = "";

  ParityConstraint(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
    side = strParams.split(".")[1];
  }

  @override
  String toString() {
    if (side == "left") return "⬅";
    if (side == "right") return "⮕";
    if (side == "horizontal") return "⬌";
    if (side == "vertical") return "⬍";
    if (side == "top") return "⬆";
    if (side == "bottom") return "⬇";
    return "";
  }

  @override
  String serialize() => 'PA:${indices.first}.$side';

  @override
  String toHuman(Puzzle puzzle) {
    final idx = indices.first + 1;
    return "$idx = ${toString()}";
  }

  /// Generate all valid parity constraint parameters for a given grid size.
  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int idx = 0; idx < width * height; idx++) {
      final ridx = idx ~/ width;
      final cidx = idx % width;
      final leftSize = cidx;
      final rightSize = width - 1 - cidx;
      final topSize = ridx;
      final bottomSize = height - 1 - ridx;
      if (leftSize % 2 == 0 && leftSize > 0) {
        result.add('$idx.left');
      }
      if (rightSize % 2 == 0 && rightSize > 0) {
        result.add('$idx.right');
      }
      if (leftSize % 2 == 0 &&
          rightSize % 2 == 0 &&
          rightSize > 0 &&
          leftSize > 0) {
        result.add('$idx.horizontal');
      }
      if (topSize % 2 == 0 && topSize > 0) {
        result.add('$idx.top');
      }
      if (bottomSize % 2 == 0 && bottomSize > 0) {
        result.add('$idx.bottom');
      }
      if (topSize % 2 == 0 &&
          bottomSize % 2 == 0 &&
          bottomSize > 0 &&
          topSize > 0) {
        result.add('$idx.vertical');
      }
    }
    return result;
  }

  List<List<int>> _getSideValues(Puzzle puzzle) {
    return _getSideCells(
      puzzle,
    ).map((side) => side.map((e) => e.$2.value).toList()).toList();
  }

  List<List<(int, Cell)>> _getSideCells(Puzzle puzzle) {
    final w = puzzle.width;
    final idx = indices[0];
    final ridx = idx ~/ w;
    final cidx = idx % w;
    final rows = puzzle.getRows();
    final row = rows[ridx];
    final columns = puzzle.getColumns();
    final column = columns[cidx];
    final rowValuesAndCells = row.indexed;
    final colValuesAndCells = column.indexed;
    final List<List<(int, Cell)>> sides = [];
    if (side == "left" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 < cidx).toList());
    }
    if (side == "right" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 > cidx).toList());
    }
    if (side == "top" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 < ridx).toList());
    }
    if (side == "bottom" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 > ridx).toList());
    }
    return sides;
  }

  @override
  bool verify(Puzzle puzzle) {
    for (var side in _getSideValues(puzzle)) {
      final int even = side.where((v) => v != 0 && v % 2 == 0).length;
      final int odd = side.where((v) => v != 0 && v % 2 != 0).length;
      final int half = side.length ~/ 2;
      // Too many of one parity already → target `even == odd == half` is
      // unreachable from this state (monotone non-decreasing counts).
      if (even > half || odd > half) return false;
      // For a fully-filled side the counts must match exactly; for an
      // incomplete side, `even <= half && odd <= half` already guarantees the
      // remaining free cells can be coloured to reach the balanced target.
      if (!side.contains(0) && even != odd) return false;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final sides = _getSideCells(puzzle);
    // Weight by the largest side covered: with 2 cells per side, the second
    // cell is read directly off the first; 4 cells require parity counting;
    // 6+ cells need real bookkeeping. For 2-side variants (horizontal /
    // vertical) we take the max — the player must still scan the long side.
    final int maxSide = sides
        .map((s) => s.length)
        .reduce((a, b) => a > b ? a : b);
    final int weight = maxSide <= 2 ? 0 : (maxSide <= 4 ? 1 : 2);
    for (var side in sides) {
      final int even = side
          .where((v) => v.$2.value != 0 && v.$2.value % 2 == 0)
          .length;
      final int odd = side
          .where((v) => v.$2.value != 0 && v.$2.value % 2 != 0)
          .length;
      final int half = (side.length / 2).floor();
      if (even > half) return Move(0, 0, this, isImpossible: this);
      if (odd > half) return Move(0, 0, this, isImpossible: this);
      if (side.where((element) => element.$2.value == 0).isEmpty) {
        continue;
      }
      if (even < half && odd < half) continue;
      final firstFreeCell = side.firstWhere((element) => element.$2.value == 0);
      if (even == half) {
        // Empty cells should be odd
        return Move(firstFreeCell.$2.idx, 1, this, complexity: weight);
      }
      if (odd == half) {
        // Empty cells should be even
        return Move(firstFreeCell.$2.idx, 2, this, complexity: weight);
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final sides = _getSideValues(puzzle);
    for (var side in sides) {
      if (side.contains(0)) return false;
    }
    return true;
  }
}
