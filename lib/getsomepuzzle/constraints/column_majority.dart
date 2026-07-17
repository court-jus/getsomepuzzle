import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// `JC` — Column majority: enforces a strict ordering of colours by count in
/// a column. The first colour in [colorOrder] must have more cells than the
/// second, which must have more than the third, etc. No ties allowed.
///
final class ColumnMajorityConstraint extends JRCConstraint {
  @override
  String get slug => 'JC';

  int columnIdx = 0;

  ColumnMajorityConstraint(String strParams) {
    final parts = strParams.split(".");
    columnIdx = int.parse(parts[0]);
    colorOrder = parts[1].split("").map(cellRepresentationToValue).toList();
  }

  @override
  Set<CellValue> get referencedColors => colorOrder.toSet();

  @override
  int getIdx() => columnIdx;

  @override
  List<Cell> getLine(Puzzle puzzle) => puzzle.getColumns()[getIdx()];

  @override
  String serialize() =>
      'JC:$columnIdx.${colorOrder.map(cellValueToString).join()}';

  @override
  String toHuman(Puzzle puzzle) {
    final names = colorOrder.map(cellValueToString).join(" > ");
    return 'Col ${columnIdx + 1}: $names';
  }

  @override
  String toString() => 'JC';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    // JC at column c on (W, H) → JR at row c on the rotated (H, W) grid.
    return RowMajorityConstraint(
      '$columnIdx.${colorOrder.map(cellValueToString).join()}',
    );
  }

  @override
  bool conflictsWith(Constraint other) {
    if (other is! LineCentricConstraint) return false;
    return other.getIdx() == columnIdx && _isSameAxis(other);
  }

  /// True when [other] is column-based (CC, CT, or another JC).
  static bool _isSameAxis(LineCentricConstraint other) {
    return other is ColumnMajorityConstraint ||
        other.slug == 'CC' ||
        other.slug == 'CT';
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final result = <String>[];
    for (var col = 0; col < width; col++) {
      for (final perm in _permutations(domain)) {
        result.add('$col.${perm.map(cellValueToString).join()}');
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
