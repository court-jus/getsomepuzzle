import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class QuantityConstraint extends Constraint {
  @override
  String get slug => 'QA';

  CellValue color = CellValue.free;
  int count = 0;

  @override
  Set<CellValue> get referencedColors => {color};

  QuantityConstraint(String strParams) {
    final params = strParams.split(".");
    color = cellRepresentationToValue(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'QA:${cellValueToString(color)}.$count';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      QuantityConstraint('${cellValueToString(color)}.$count');

  @override
  String toString() {
    return "${cellValueToString(color)} = $count";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final maxCount = width * height - 1;
    final List<String> result = [];
    for (int count = 1; count < maxCount; count++) {
      for (final value in domain) {
        result.add('${cellValueToString(value)}.$count');
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final have = puzzle.cellValues.where((val) => val == color).length;
    if (puzzle.complete) return have == count;
    if (have > count) return false;
    // Only free cells that can still take `color` count toward reachability:
    // a cell that has pruned `color` from its options can never raise `have`.
    final free = puzzle.cells
        .where((c) => c.value == CellValue.free && c.options.contains(color))
        .length;
    if (have + free < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myValues = puzzle.cellValues.where((val) => val == color);
    final freeCells = puzzle.cellValues.indexed.where(
      (val) => val.$2 == CellValue.free,
    );
    if (freeCells.isEmpty) return null;
    if (myValues.length > count) {
      return Impossible(this);
    }
    if (myValues.length == count) {
      // I'm already complete, all the rest of the puzzle should an opposite color
      for (var freeCell in freeCells) {
        if (puzzle.cells[freeCell.$1].options.contains(color)) {
          return RemoveOption(freeCell.$1, color, this, complexity: 0);
        }
      }
      // No free cell still has `color` in options — every remaining cell
      // already can't take this colour, so the count stays at target. The
      // constraint is satisfied; return null instead of reporting an
      // impossibility. (Same domain-3 trap as SH Level 2.)
      return null;
    } else if (count - myValues.length == freeCells.length) {
      // The number of free cells matches what I need: they all become color.
      // If the chosen cell has already excluded `color` (3-colour puzzles),
      // the target is unreachable.
      final target = freeCells.first;
      if (!puzzle.cells[target.$1].options.contains(color)) {
        return Impossible(this);
      }
      return SetValue(target.$1, color, this, complexity: 0);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final have = puzzle.cellValues.where((val) => val == color).length;
    if (have != count) return false;
    // Once the count is reached and no free cell can still take `color`,
    // the count can never change and apply() can never fire again.
    return puzzle.cells
        .where((c) => c.value == CellValue.free && c.options.contains(color))
        .isEmpty;
  }
}
