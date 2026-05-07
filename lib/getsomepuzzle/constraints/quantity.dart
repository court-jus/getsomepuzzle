import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class QuantityConstraint extends Constraint {
  @override
  String get slug => 'QA';

  CellValue color = CellValue.free;
  int count = 0;

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
    final free = puzzle.cellValues.where((val) => val == CellValue.free).length;
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
      return Move(0, this, isImpossible: this);
    }
    if (myValues.length == count) {
      // I'm already complete, all the rest of the puzzle should an opposite color
      for (var freeCell in freeCells) {
        if (puzzle.cells[freeCell.$1].options.contains(color)) {
          return Move(freeCell.$1, removeOption: color, this, complexity: 0);
        }
      }
      // No freecell has the option to remove, that's impossible
      return Move(0, this, isImpossible: this);
    } else if (count - myValues.length == freeCells.length) {
      // The number of free cells matches what I need: they all become color.
      // If the chosen cell has already excluded `color` (3-colour puzzles),
      // the target is unreachable.
      final target = freeCells.first;
      if (!puzzle.cells[target.$1].options.contains(color)) {
        return Move(0, this, isImpossible: this);
      }
      return Move(target.$1, value: color, this, complexity: 0);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    // Complete only when apply() cannot fire again for any future state.
    // QA keeps producing deductions whenever either myValues == count (force
    // remaining to opposite) or count - myValues == freeCells (force
    // remaining to value). Both states can be reached by future play as long
    // as any free cell remains, so grayout is only safe once the grid is full.
    return puzzle.complete;
  }
}
