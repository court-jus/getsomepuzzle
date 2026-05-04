import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

base class LineCentricConstraint extends Constraint {
  // A common class for Row/Column constraints
  int color = 0;
  int count = 0;

  @override
  String serialize() => '$slug:${getIdx()}.$color.$count';

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
    final free = line.where((cell) => cell.value == 0).length;
    if (have + free < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final line = getLine(puzzle);
    final colorCount = line.where((cell) => cell.value == color).length;
    final freeCells = line.where((cell) => cell.value == 0);
    if (freeCells.isEmpty) return null;

    final opposite = puzzle.domain.firstWhere((v) => v != color);

    if (colorCount > count) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (colorCount == count) {
      // All color cells placed — remaining free cells get the opposite value
      return Move(freeCells.first.idx, opposite, this, complexity: 0);
    }
    if (count - colorCount == freeCells.length) {
      // Exactly as many free cells as needed — they must all be color
      return Move(freeCells.first.idx, color, this, complexity: 0);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final line = getLine(puzzle);
    return line.every((cell) => cell.value != 0);
  }
}
