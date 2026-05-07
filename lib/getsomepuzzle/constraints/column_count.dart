import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

final class ColumnCountConstraint extends LineCentricConstraint {
  @override
  String get slug => 'CC';

  int columnIdx = 0;

  ColumnCountConstraint(String strParams) {
    final params = strParams.split(".");
    columnIdx = int.parse(params[0]);
    color = cellRepresentationToValue(params[1]);
    count = int.parse(params[2]);
  }

  @override
  int getIdx() => columnIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getColumns()[getIdx()];

  @override
  String toHuman(Puzzle puzzle) => 'Col ${getIdx() + 1}: $count ${cellValueToString(color)}';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    // CC at column c on a (W, H) grid → RC at row c on the rotated (H, W)
    // grid. The cells of column c become row c after 90° CW rotation: each
    // (c, r) maps to (newCol = H-1-r, newRow = c), so they all share row c.
    return RowCountConstraint('$columnIdx.${cellValueToString(color)}.$count');
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int col = 0; col < width; col++) {
      for (final c in domain) {
        for (int n = 1; n < height; n++) {
          result.add('$col.${cellValueToString(c)}.$n');
        }
      }
    }
    return result;
  }
}
