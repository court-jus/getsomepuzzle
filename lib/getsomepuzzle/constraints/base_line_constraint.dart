import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

base class LineCentricConstraint extends Constraint {
  // A common class for Row/Column constraints
  CellValue color = CellValue.free;
  int count = 0;

  @override
  String serialize() => '$slug:${getIdx()}.${cellValueToString(color)}.$count';

  @override
  String toString() => '$count';

  int getIdx() => 0;

  List<Cell> getLine(Puzzle puzzle) => [];

  @override
  bool verify(Puzzle puzzle) {
    final line = getLine(puzzle);
    final have = line.where((cell) => cell.value == color).length;
    if (puzzle.complete) return have == count;
    if (have > count) return false;
    final free = line.where((cell) => cell.value == CellValue.free).length;
    if (have + free < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final line = getLine(puzzle);
    final colorCount = line.where((cell) => cell.value == color).length;
    final freeCells = line.where((cell) => cell.value == CellValue.free);
    if (freeCells.isEmpty) return null;

    if (colorCount > count) {
      return Move(0, value: CellValue.free, this, isImpossible: this);
    }
    if (colorCount == count) {
      // All color cells placed — remaining free cells get an opposite color
      for (var freeCell in freeCells) {
        if (freeCell.options.contains(color)) {
          return Move(freeCell.idx, removeOption: color, this, complexity: 0);
        }
      }
      // No free cell has the option to remove
      return Move(0, this, isImpossible: this);
    }
    if (count - colorCount == freeCells.length) {
      // Exactly as many free cells as needed — they must all be color.
      // The cell may have lost the option earlier (3-colour puzzles): in
      // that case the target is no longer reachable.
      final target = freeCells.first;
      if (!target.options.contains(color)) {
        return Move(0, this, isImpossible: this);
      }
      return Move(target.idx, value: color, this, complexity: 0);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final line = getLine(puzzle);
    return line.every((cell) => cell.value != CellValue.free);
  }
}
