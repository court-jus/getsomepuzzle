import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// `JR` — Row majority: enforces a strict ordering of colours by count in
/// a row. The first colour in [colorOrder] must have more cells than the
/// second, which must have more than the third, etc. No ties allowed.
///
/// Mirror of [ColumnMajorityConstraint] for rows.
final class RowMajorityConstraint extends JRCConstraint {
  @override
  String get slug => 'JR';

  int rowIdx = 0;

  RowMajorityConstraint(String strParams) {
    final parts = strParams.split(".");
    rowIdx = int.parse(parts[0]);
    colorOrder = parts[1].split("").map(cellRepresentationToValue).toList();
  }

  @override
  Set<CellValue> get referencedColors => colorOrder.toSet();

  @override
  int getIdx() => rowIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getRows()[getIdx()];

  @override
  String serialize() =>
      'JR:$rowIdx.${colorOrder.map(cellValueToString).join()}';

  @override
  String toHuman(Puzzle puzzle) {
    final names = colorOrder.map(cellValueToString).join(" > ");
    return 'Row ${rowIdx + 1}: $names';
  }

  @override
  String toString() => 'JR';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    // JR at row r on (W, H) → JC at column (H-1-r) on the rotated (H, W) grid.
    return ColumnMajorityConstraint(
      '${origHeight - 1 - rowIdx}.${colorOrder.map(cellValueToString).join()}',
    );
  }

  @override
  bool conflictsWith(Constraint other) {
    if (other is! LineCentricConstraint) return false;
    return other.getIdx() == rowIdx && _isSameAxis(other);
  }

  /// True when [other] is row-based (RC, RT, or another JR).
  static bool _isSameAxis(LineCentricConstraint other) {
    return other is RowMajorityConstraint ||
        other.slug == 'RC' ||
        other.slug == 'RT';
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final result = <String>[];
    for (var row = 0; row < height; row++) {
      for (final perm in _permutations(domain)) {
        result.add('$row.${perm.map(cellValueToString).join()}');
      }
    }
    return result;
  }

  static List<List<CellValue>> _permutations(List<CellValue> items) {
    if (items.length <= 1) return [items];
    final result = <List<CellValue>>[];
    for (var i = 0; i < items.length; i++) {
      final rest = [...items.sublist(0, i), ...items.sublist(i + 1)];
      for (final perm in _permutations(rest)) {
        result.add([items[i], ...perm]);
      }
    }
    return result;
  }
}
