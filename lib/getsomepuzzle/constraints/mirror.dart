import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Mirror constraint (`MI`): a mirror line splits the grid in two and both
/// halves must contain the same number of cells of a chosen colour.
///
/// A horizontal mirror (`H`) requires an even number of rows and balances the
/// top half against the bottom half; a vertical mirror (`V`) requires an even
/// number of columns and balances the left half against the right half. The
/// constraint type is only available on puzzles with at least one even
/// dimension (see [generateAllParameters]).
///
/// Global constraint: no `indices`, no coexistence restriction — any number of
/// mirrors of any colour/direction may share a puzzle.
class MirrorConstraint extends Constraint {
  @override
  String get slug => 'MI';
  CellValue color = CellValue.free;
  String direction =
      'H'; // 'H' horizontal mirror (top/bottom halves), 'V' vertical (left/right)

  MirrorConstraint(String strParams) {
    final parts = strParams.split('.');
    color = cellRepresentationToValue(parts[0]);
    if (parts.length > 1) direction = parts[1];
  }

  bool get isHorizontal => direction == 'H';

  @override
  Set<CellValue> get referencedColors => {color};

  @override
  String serialize() => 'MI:${cellValueToString(color)}.$direction';

  @override
  String toString() => '$direction ${cellValueToString(color)}'; // e.g. "H 1"

  @override
  Constraint rotated(int origWidth, int origHeight) => MirrorConstraint(
    '${cellValueToString(color)}.${isHorizontal ? 'V' : 'H'}',
  );

  /// No `conflictsWith` override: any number of mirrors (any colour/direction)
  /// may coexist in one puzzle (user decision).

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final result = <String>[];
    for (final value in domain) {
      if (height.isEven) result.add('${cellValueToString(value)}.H');
      if (width.isEven) result.add('${cellValueToString(value)}.V');
    }
    return result; // empty on odd×odd grids → MI never generated there
  }

  /// Half of cell [idx]: 0 for top/left, 1 for bottom/right.
  ///
  /// Horizontal: half 1 iff `idx >= width * (height ~/ 2)` (half 0 = top rows
  /// `0..h~/2-1`). Vertical: half 1 iff `idx % width >= width ~/ 2` (half 0 =
  /// left columns). `height`/`width` are even whenever the constraint is used;
  /// guard mistrust not needed.
  int _halfOf(int idx, int width, int height) {
    if (isHorizontal) {
      return idx >= width * (height ~/ 2) ? 1 : 0;
    }
    return idx % width >= width ~/ 2 ? 1 : 0;
  }

  int _countOf(Puzzle puzzle, int half, {bool freeWithOption = false}) {
    var count = 0;
    final target = freeWithOption ? CellValue.free : color;
    for (int idx = 0; idx < puzzle.cells.length; idx++) {
      if (puzzle.cells[idx].value == target &&
          _halfOf(idx, puzzle.width, puzzle.height) == half &&
          (freeWithOption ? puzzle.cells[idx].options.contains(color) : true)) {
        count++;
      }
    }
    return count;
  }

  @override
  bool verify(Puzzle puzzle) {
    final firstHalf = _countOf(puzzle, 0);
    final secondHalf = _countOf(puzzle, 1);
    final firstHalfEmpty = _countOf(puzzle, 0, freeWithOption: true);
    final secondHalfEmpty = _countOf(puzzle, 1, freeWithOption: true);
    if (firstHalf + firstHalfEmpty < secondHalf) return false;
    if (secondHalf + secondHalfEmpty < firstHalf) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    // Single pass: count colour cells per half, collect live indices per half.
    final count = [0, 0];
    final live = [<int>[], <int>[]];
    for (int idx = 0; idx < puzzle.cells.length; idx++) {
      final cell = puzzle.cells[idx];
      final h = _halfOf(idx, puzzle.width, puzzle.height);
      if (cell.value == color) {
        count[h]++;
      } else if (cell.value == CellValue.free && cell.options.contains(color)) {
        live[h].add(idx);
      }
    }
    if (live[0].isEmpty && live[1].isEmpty) return null;
    // Rule 1 (generalized): deficient half's deficit == its live cells → they take the colour.
    if (count[0] < count[1] && live[0].length == count[1] - count[0]) {
      return SetValue(live[0].first, color, this, complexity: 1);
    }
    if (count[1] < count[0] && live[1].length == count[0] - count[1]) {
      return SetValue(live[1].first, color, this, complexity: 1);
    }
    // Rule 2: counts equal, one half closed (no live cells), other still live → prune colour.
    if (count[0] == count[1]) {
      if (live[0].isEmpty && live[1].isNotEmpty) {
        return RemoveOption(live[1].first, color, this, complexity: 2);
      }
      if (live[1].isEmpty && live[0].isNotEmpty) {
        return RemoveOption(live[0].first, color, this, complexity: 2);
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    return !puzzle.cells.any(
      (c) => c.value == CellValue.free && c.options.contains(color),
    );
  }
}
