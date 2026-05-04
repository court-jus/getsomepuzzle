import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

final class RowCountConstraint extends LineCentricConstraint {
  @override
  String get slug => 'RC';

  int rowIdx = 0;

  RowCountConstraint(String strParams) {
    final params = strParams.split(".");
    rowIdx = int.parse(params[0]);
    color = int.parse(params[1]);
    count = int.parse(params[2]);
  }

  @override
  int getIdx() => rowIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getRows()[getIdx()];

  @override
  String toHuman(Puzzle puzzle) => 'Row ${getIdx() + 1}: $count';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int row = 0; row < height; row++) {
      for (final c in domain) {
        for (int n = 1; n < width; n++) {
          result.add('$row.$c.$n');
        }
      }
    }
    return result;
  }
}
