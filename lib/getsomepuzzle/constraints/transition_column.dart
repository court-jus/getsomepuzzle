import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_utils.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';

final class ColumnTransitionConstraint extends LineCentricConstraint {
  @override
  String get slug => 'CT';

  int columnIdx = 0;

  ColumnTransitionConstraint(String strParams) {
    final params = strParams.split(".");
    columnIdx = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'CT:$columnIdx.$count';

  @override
  int getIdx() => columnIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getColumns()[getIdx()];

  @override
  String toHuman(Puzzle puzzle) => 'Col ${getIdx() + 1}: ~$count';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    return RowTransitionConstraint('$columnIdx.$count');
  }

  @override
  bool conflictsWith(Constraint other) {
    if (other is ColumnCountConstraint && other.columnIdx == columnIdx) {
      return true;
    }
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
    return generateAllTransitionParams(width, height - 1);
  }
}
