import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

class DifferentFromConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'DF';

  final String direction;

  DifferentFromConstraint(String strParams)
    : direction = strParams.split(".")[1] {
    indices.add(int.parse(strParams.split(".")[0]));
  }

  int getNeighborIndex(int width) {
    final idx = indices.first;
    if (direction == 'right') {
      return idx + 1;
    } else {
      return idx + width;
    }
  }

  @override
  String toString() {
    return "≠";
  }

  @override
  String toHuman(Puzzle puzzle) {
    final idx = indices.first + 1;
    final nidx = getNeighborIndex(puzzle.width) + 1;
    return "$idx ≠ $nidx";
  }

  @override
  String serialize() => 'DF:${indices.first}.$direction';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final idx = indices.first;
    if (direction == 'right') {
      // right@idx pairs (c, r) with (c+1, r). After rotation those become
      // (H-1-r, c) and (H-1-r, c+1) — same column, different rows. The pair
      // is now vertical, anchored at the top cell, which is the rotation of
      // the original anchor → emit `down` at rotated(idx).
      final newIdx = rotateIdx90CW(idx, origWidth, origHeight);
      return DifferentFromConstraint('$newIdx.down');
    } else {
      // down@idx pairs (c, r) with (c, r+1). After rotation those become
      // (H-1-r, c) and (H-2-r, c) — same row, different columns. The pair
      // is now horizontal; the LEFT cell is (H-2-r, c), which is the rotation
      // of the original `down` neighbor (c, r+1) = orig idx + W. So we re-
      // anchor on that cell and emit `right`.
      final neighborIdx = idx + origWidth;
      final newIdx = rotateIdx90CW(neighborIdx, origWidth, origHeight);
      return DifferentFromConstraint('$newIdx.right');
    }
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    final excluded = excludedIndices ?? {};
    for (int idx = 0; idx < width * height; idx++) {
      if (excluded.contains(idx)) continue;
      final ridx = idx ~/ width;
      final cidx = idx % width;
      if (cidx < width - 1) {
        final neighbor = idx + 1;
        if (!excluded.contains(neighbor)) {
          result.add('$idx.right');
        }
      }
      if (ridx < height - 1) {
        final neighbor = idx + width;
        if (!excluded.contains(neighbor)) {
          result.add('$idx.down');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final idx = indices.first;
    final nidx = getNeighborIndex(puzzle.width);
    final val1 = puzzle.cells[idx].value;
    final val2 = puzzle.cells[nidx].value;
    if (val1 == CellValue.free || val2 == CellValue.free) return true;
    return val1 != val2;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final cell1idx = indices.first;
    final cell2idx = getNeighborIndex(puzzle.width);
    final cell1 = puzzle.cells[cell1idx];
    final cell2 = puzzle.cells[cell2idx];

    if (cell1.value != CellValue.free && cell2.value != CellValue.free) {
      if (cell1.value == cell2.value) {
        return Move(0, this, isImpossible: this);
      }
      return null;
    }

    if (cell1.value != CellValue.free) {
      return Move(cell2idx, removeOption: cell1.value, this, complexity: 0);
    }

    if (cell2.value != CellValue.free) {
      return Move(cell1idx, removeOption: cell2.value, this, complexity: 0);
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final idx = indices.first;
    final nidx = getNeighborIndex(puzzle.width);
    return puzzle.cellValues[idx] != CellValue.free &&
        puzzle.cellValues[nidx] != CellValue.free;
  }
}
