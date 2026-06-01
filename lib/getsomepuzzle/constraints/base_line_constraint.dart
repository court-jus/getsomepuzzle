import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

base class LineCentricConstraint extends Constraint {
  // A common class for Row/Column constraints
  CellValue color = CellValue.free;
  int count = 0;

  // Covers CC/RC (count of `color`) and RT/CT (transitions carry a nominal
  // `color`, kept conservatively so auto-shrink never drops it).
  @override
  Set<CellValue> get referencedColors => {color};

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
    // Only free cells that can still take `color` count toward reachability.
    final free = line
        .where(
          (cell) =>
              cell.value == CellValue.free && cell.options.contains(color),
        )
        .length;
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
      return Impossible(this);
    }
    if (colorCount == count) {
      // All color cells placed — remaining free cells get an opposite color
      for (var freeCell in freeCells) {
        if (freeCell.options.contains(color)) {
          return RemoveOption(freeCell.idx, color, this, complexity: 0);
        }
      }
      // No free cell still has `color` in options — the line is already
      // closed. The constraint is satisfied; nothing more to do. (Reporting
      // `isImpossible` here was the same domain-3 trap as in SH Level 2:
      // domain-2 auto-sets when only one option remains, so free cells
      // disappear after one round of removeOption; domain-3+ leaves the
      // cell free with two options and we loop back here with nothing to do.)
      return null;
    }
    if (count - colorCount == freeCells.length) {
      // Exactly as many free cells as needed — they must all be color.
      // The cell may have lost the option earlier (3-colour puzzles): in
      // that case the target is no longer reachable.
      final target = freeCells.first;
      if (!target.options.contains(color)) {
        return Impossible(this);
      }
      return SetValue(target.idx, color, this, complexity: 0);
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
