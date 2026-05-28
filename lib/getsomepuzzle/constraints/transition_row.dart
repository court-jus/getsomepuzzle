import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_utils.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

final class RowTransitionConstraint extends LineCentricConstraint {
  @override
  String get slug => 'RT';

  int rowIdx = 0;

  RowTransitionConstraint(String strParams) {
    final params = strParams.split(".");
    rowIdx = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'RT:$rowIdx.$count';

  @override
  int getIdx() => rowIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getRows()[getIdx()];

  @override
  String toHuman(Puzzle puzzle) => 'Row ${getIdx() + 1}: ~$count';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    return ColumnTransitionConstraint('${origHeight - 1 - rowIdx}.$count');
  }

  @override
  bool conflictsWith(Constraint other) {
    if (other is RowCountConstraint && other.rowIdx == rowIdx) return true;
    return false;
  }

  @override
  bool verify(Puzzle puzzle) =>
      verifyTransitionLine(puzzle, getLine(puzzle), count);

  @override
  Move? apply(Puzzle puzzle) =>
      applyTransitionLine(puzzle, getLine(puzzle), count, this);

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    return generateAllTransitionParams(height, width - 1);
  }
}
