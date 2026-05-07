import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

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

  /// Rotation-90°-CW mapping for the `side` parameter. Cells originally to
  /// the left of the anchor end up above it in the rotated grid, etc.
  static const Map<String, String> _rotatedSide = {
    'left': 'top',
    'right': 'bottom',
    'top': 'right',
    'bottom': 'left',
    'horizontal': 'vertical',
    'vertical': 'horizontal',
  };

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIdx = rotateIdx90CW(indices.first, origWidth, origHeight);
    final newSide = _rotatedSide[side] ?? side;
    return ParityConstraint('$newIdx.$newSide');
  }

  @override
  String toHuman(Puzzle puzzle) {
    final idx = indices.first + 1;
    return "$idx = ${toString()}";
  }

  /// Generate all valid parity constraint parameters for a given grid size.
  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
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
      if (leftSize % domain.length == 0 && leftSize > 0) {
        result.add('$idx.left');
      }
      if (rightSize % domain.length == 0 && rightSize > 0) {
        result.add('$idx.right');
      }
      if (leftSize % domain.length == 0 &&
          rightSize % domain.length == 0 &&
          rightSize > 0 &&
          leftSize > 0) {
        result.add('$idx.horizontal');
      }
      if (topSize % domain.length == 0 && topSize > 0) {
        result.add('$idx.top');
      }
      if (bottomSize % domain.length == 0 && bottomSize > 0) {
        result.add('$idx.bottom');
      }
      if (topSize % domain.length == 0 &&
          bottomSize % domain.length == 0 &&
          bottomSize > 0 &&
          topSize > 0) {
        result.add('$idx.vertical');
      }
    }
    return result;
  }

  List<List<CellValue>> _getSideValues(Puzzle puzzle) {
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
      // FXME: how does parity work with 3 colors?
      final int targetCount = side.length ~/ puzzle.domain.length;
      final bool hasFree = side.contains(CellValue.free);
      final Map<CellValue, int> perColor = {};
      for (var color in puzzle.domain) {
        perColor[color] = side
            .where((v) => v != CellValue.free && v == color)
            .length;
        // Too many of one color already → target is
        // unreachable from this state
        if (perColor[color]! > targetCount) return false;
        // For a fully-filled side the counts must match exactly
        if (!hasFree && perColor[color]! != targetCount) return false;
      }
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
    final int weight = maxSide <= puzzle.domain.length
        ? 0
        : (maxSide <= (puzzle.domain.length * 2) ? 1 : 2);
    for (var side in sides) {
      final int targetCount = side.length ~/ puzzle.domain.length;
      final freeCells = side.where(
        (element) => element.$2.value == CellValue.free,
      );
      final Map<CellValue, int> perColor = {};
      for (var color in puzzle.domain) {
        perColor[color] = side
            .where((v) => v.$2.value != CellValue.free && v.$2.value == color)
            .length;
        // If we're already above the target, it's an "isImpossible" move
        if (perColor[color]! > targetCount) {
          return Move(0, this, isImpossible: this);
        }
        // If this color has reached its target, all the free cells that still
        // have that option must remove it. Removing the last remaining option
        // has the side effect of applying the only remaining color.
        if (perColor[color]! == targetCount) {
          for (var freeCell in freeCells) {
            if (freeCell.$2.options.contains(color)) {
              return Move(
                freeCell.$2.idx,
                removeOption: color,
                this,
                complexity: weight,
              );
            }
          }
        }
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final sides = _getSideValues(puzzle);
    for (var side in sides) {
      if (side.contains(CellValue.free)) return false;
    }
    return true;
  }
}
