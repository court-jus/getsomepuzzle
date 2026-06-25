import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// IM — **Implication**: if the source cell is [color], the target cell
/// must also be [color] (unidirectional — the arrow shows which cell
/// drives the deduction). The contrapositive fires too — target ≠ colour
/// ⇒ source cannot be that colour — on grids with any number of colours.
class ImplicationConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'IM';

  @override
  Set<CellValue> get referencedColors => {color};

  CellValue color = CellValue.free;

  ImplicationConstraint(String strParams) {
    final parts = strParams.split(".");
    indices.add(int.parse(parts[0]));
    indices.add(int.parse(parts[1]));
    color = cellRepresentationToValue(parts[2]);
  }

  int get targetIdx => indices[1];

  @override
  String serialize() =>
      'IM:${indices.first}.${indices[1]}.${cellValueToString(color)}';

  @override
  String toString() =>
      '${indices.first + 1} → ${indices[1] + 1} (${cellValueToString(color)})';

  @override
  String toHuman(Puzzle puzzle) {
    final src = indices.first + 1;
    final tgt = indices[1] + 1;
    return '$src(${cellValueToString(color)}) → $tgt';
  }

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newSrc = rotateIdx90CW(indices.first, origWidth, origHeight);
    final newTgt = rotateIdx90CW(indices[1], origWidth, origHeight);
    return ImplicationConstraint('$newSrc.$newTgt.${cellValueToString(color)}');
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final excluded = excludedIndices ?? {};
    final result = <String>[];
    final colors = domain.where((v) => v != CellValue.free).toList();
    for (int src = 0; src < width * height; src++) {
      if (excluded.contains(src)) continue;
      for (int tgt = 0; tgt < width * height; tgt++) {
        if (src == tgt) continue;
        if (excluded.contains(tgt)) continue;
        final srcRow = src ~/ width;
        final srcCol = src % width;
        final tgtRow = tgt ~/ width;
        final tgtCol = tgt % width;
        final dist = (srcRow - tgtRow).abs() + (srcCol - tgtCol).abs();
        if (dist > 4) continue;
        for (final c in colors) {
          result.add('$src.$tgt.${cellValueToString(c)}');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final srcVal = puzzle.cellValues[indices.first];
    final tgtVal = puzzle.cellValues[indices[1]];

    // Both determined: violation only if source is color and target isn't.
    if (srcVal != CellValue.free && tgtVal != CellValue.free) {
      return !(srcVal == color && tgtVal != color);
    }

    // Source is determined to be color but target can never be → unreachable.
    if (srcVal == color && !puzzle.cells[indices[1]].options.contains(color)) {
      return false;
    }

    // Source is ≠ color or free → vacuously true or still reachable.
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final srcIdx = indices.first;
    final tgtIdx = indices[1];
    final srcVal = puzzle.cellValues[srcIdx];
    final tgtVal = puzzle.cellValues[tgtIdx];

    if (srcVal != CellValue.free && tgtVal != CellValue.free) {
      if (srcVal == color && tgtVal != color) return Impossible(this);
      return null;
    }

    // Forward: source is the constraint colour → target must follow.
    if (srcVal == color) {
      if (!puzzle.cells[tgtIdx].options.contains(color)) {
        return Impossible(this);
      }
      return SetValue(tgtIdx, color, this, complexity: 0);
    }

    // Contrapositive: target is definitely NOT the colour → source can't be.
    if (tgtVal != CellValue.free && tgtVal != color) {
      if (!puzzle.cells[srcIdx].options.contains(color)) return null;
      return RemoveOption(srcIdx, color, this, complexity: 1);
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;

    final srcIdx = indices.first;
    final tgtIdx = indices[1];
    final srcVal = puzzle.cellValues[srcIdx];
    final tgtVal = puzzle.cellValues[tgtIdx];

    // 1. Source determined a different colour → constraint will never fire.
    if (srcVal != CellValue.free && srcVal != color) return true;

    // 2. Source can never be the constraint colour → nothing to deduce.
    if (srcVal == CellValue.free &&
        !puzzle.cells[srcIdx].options.contains(color)) {
      return true;
    }

    // 3. Target is already the colour → forward satisfied, no contrapositive.
    if (tgtVal == color) return true;

    return false;
  }
}
