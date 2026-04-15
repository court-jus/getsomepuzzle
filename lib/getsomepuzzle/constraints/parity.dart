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
  String toHuman() {
    final idx = indices.first + 1;
    return "$idx = ${toString()}";
  }

  /// Generate all valid parity constraint parameters for a given grid size.
  static List<String> generateAllParameters(int width, int height) {
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

  @override
  bool verify(Puzzle puzzle) {
    final w = puzzle.width;
    final idx = indices[0];
    final ridx = idx ~/ w;
    final cidx = idx % w;
    final rows = puzzle.getRows();
    final row = rows[ridx];
    final columns = puzzle.getColumns();
    final column = columns[cidx];
    final rowValuesAndIndices = row.indexed.map((e) => (e.$1, e.$2.value));
    final colValuesAndIndices = column.indexed.map((e) => (e.$1, e.$2.value));
    final List<Iterable<int>> sides = [];
    if (side == "left" || side == "horizontal") {
      sides.add(rowValuesAndIndices.where((e) => e.$1 < cidx).map((e) => e.$2));
    }
    if (side == "right" || side == "horizontal") {
      sides.add(rowValuesAndIndices.where((e) => e.$1 > cidx).map((e) => e.$2));
    }
    if (side == "top" || side == "vertical") {
      sides.add(colValuesAndIndices.where((e) => e.$1 < ridx).map((e) => e.$2));
    }
    if (side == "bottom" || side == "vertical") {
      sides.add(colValuesAndIndices.where((e) => e.$1 > ridx).map((e) => e.$2));
    }
    for (var side in sides) {
      if (side.contains(0)) {
        continue;
      }
      final int even = side.where((v) => v % 2 == 0).length;
      final int odd = side.where((v) => v % 2 != 0).length;
      if (even != odd) {
        return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
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
    final List<Iterable<(int, Cell)>> sides = [];
    if (side == "left" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 < cidx));
    }
    if (side == "right" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 > cidx));
    }
    if (side == "top" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 < ridx));
    }
    if (side == "bottom" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 > ridx));
    }
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
        return Move(firstFreeCell.$2.idx, 1, this);
      }
      if (odd == half) {
        // Empty cells should be even
        return Move(firstFreeCell.$2.idx, 2, this);
      }
    }
    return null;
  }
}
