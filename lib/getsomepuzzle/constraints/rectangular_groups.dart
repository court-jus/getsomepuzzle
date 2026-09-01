import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// Rectangular groups (RE): the connected same-colour group containing the
/// marked cell must be a rectangle that is not square — the group fills its
/// own bounding box and its width differs from its height.
class RectangularGroupsConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'RE';

  // Colour-agnostic: constrains the group's shape, not a specific colour.
  @override
  Set<CellValue> get referencedColors => const {};

  RectangularGroupsConstraint(String strParams) {
    indices.add(int.parse(strParams));
  }

  @override
  String serialize() => 'RE:${indices.first}';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      RectangularGroupsConstraint(
        '${rotateIdx90CW(indices.first, origWidth, origHeight)}',
      );

  @override
  String toString() => 'RE';

  @override
  String toHuman(Puzzle puzzle) =>
      "Group at ${indices.first + 1} must be rectangular but not square";

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) => [for (var idx = 0; idx < width * height; idx++) '$idx'];

  /// Bounds `(minR, maxR, minC, maxC)` of [group].
  (int, int, int, int) _bounds(List<int> group, int gridWidth) {
    int minR = group.first ~/ gridWidth, maxR = minR;
    int minC = group.first % gridWidth, maxC = minC;
    for (final idx in group.skip(1)) {
      final r = idx ~/ gridWidth;
      final c = idx % gridWidth;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
    }
    return (minR, maxR, minC, maxC);
  }

  /// Whether the group can still expand: some free neighbour carries [color]
  /// in its options.
  bool _canGrow(Puzzle puzzle, List<int> group, CellValue color) {
    for (final member in group) {
      for (final n in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[n] == CellValue.free &&
            puzzle.cells[n].options.contains(color)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  bool verify(Puzzle puzzle) {
    final idx = indices[0];
    final myColor = puzzle.cellValues[idx];
    if (myColor == CellValue.free) return !puzzle.complete;
    final myGroup = getGroups(puzzle).firstWhereOrNull((g) => g.contains(idx));
    if (myGroup == null) return !puzzle.complete;
    final (minR, maxR, minC, maxC) = _bounds(myGroup, puzzle.width);
    var boxFull = true;
    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        final i = r * puzzle.width + c;
        if (puzzle.complete) {
          if (puzzle.cellValues[i] != myColor) return false;
        } else {
          if (puzzle.cellValues[i] != CellValue.free &&
              puzzle.cellValues[i] != myColor) {
            return false;
          }
          if (puzzle.cellValues[i] == CellValue.free) {
            boxFull = false;
            if (!puzzle.cells[i].options.contains(myColor)) return false;
          }
        }
      }
    }
    // The final group must be a rectangle that is NOT square: reject a
    // square bounding box unless it can still grow to a non-square extent.
    if (maxR - minR == maxC - minC) {
      if (puzzle.complete) return false;
      if (minR == 0 &&
          maxR == puzzle.height - 1 &&
          minC == 0 &&
          maxC == puzzle.width - 1) {
        // The box is the whole grid — squareness is inescapable.
        return false;
      }
      if (boxFull && !_canGrow(puzzle, myGroup, myColor)) return false;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final idx = indices[0];
    if (puzzle.cellValues[idx] == CellValue.free) return null;
    final myColor = puzzle.cellValues[idx];
    final myGroup = getGroups(puzzle).firstWhereOrNull((g) => g.contains(idx));
    if (myGroup == null) return null;
    final (minR, maxR, minC, maxC) = _bounds(myGroup, puzzle.width);

    // Pass 1: fill the box, or fail. A set box cell of the wrong colour, or a
    // free box cell that can never take myColor, breaks the rectangle.
    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        final i = r * puzzle.width + c;
        if (puzzle.cellValues[i] != CellValue.free &&
            puzzle.cellValues[i] != myColor) {
          return Impossible(this);
        }
        if (puzzle.cellValues[i] == CellValue.free) {
          if (!puzzle.cells[i].options.contains(myColor)) {
            return Impossible(this);
          }
          return SetValue(i, myColor, this, complexity: 1);
        }
      }
    }
    // The final group must not be square: a full square box is only
    // repairable by growing, so a square box that cannot grow is dead.
    if (maxR - minR == maxC - minC && !_canGrow(puzzle, myGroup, myColor)) {
      return Impossible(this);
    }

    // Pass 2: prune. The box is now full (every free box cell was returned
    // above), so any free neighbour of the group lies outside the box.
    // Colouring it would expand the box; if the expansion overhangs a cell
    // that can never be myColor, the rectangle becomes unreachable.
    for (final member in myGroup) {
      for (final n in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[n] != CellValue.free) continue;
        if (!puzzle.cells[n].options.contains(myColor)) continue;
        final nR = n ~/ puzzle.width;
        final nC = n % puzzle.width;
        final expMinR = nR < minR ? nR : minR;
        final expMaxR = nR > maxR ? nR : maxR;
        final expMinC = nC < minC ? nC : minC;
        final expMaxC = nC > maxC ? nC : maxC;
        for (int r = expMinR; r <= expMaxR; r++) {
          for (int c = expMinC; c <= expMaxC; c++) {
            if (r >= minR && r <= maxR && c >= minC && c <= maxC) continue;
            final i = r * puzzle.width + c;
            if (puzzle.cellValues[i] != CellValue.free &&
                puzzle.cellValues[i] != myColor) {
              return RemoveOption(n, myColor, this, complexity: 2);
            }
            if (puzzle.cellValues[i] == CellValue.free &&
                !puzzle.cells[i].options.contains(myColor)) {
              return RemoveOption(n, myColor, this, complexity: 2);
            }
          }
        }

        // Growing into `n` would make the box square; if that box spans the
        // whole grid it can never grow out of squareness.
        if (expMaxR - expMinR == expMaxC - expMinC &&
            expMinR == 0 &&
            expMaxR == puzzle.height - 1 &&
            expMinC == 0 &&
            expMaxC == puzzle.width - 1) {
          return RemoveOption(n, myColor, this, complexity: 2);
        }
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (puzzle.cellValues[indices[0]] == CellValue.free) return false;
    if (!verify(puzzle)) return false;
    final idx = indices[0];
    final myColor = puzzle.cellValues[idx];
    final myGroup = getGroups(puzzle).firstWhereOrNull((g) => g.contains(idx));
    if (myGroup == null) return false;
    final (minR, maxR, minC, maxC) = _bounds(myGroup, puzzle.width);
    // A square group can never be the final shape, even while it could
    // still grow.
    if (maxR - minR == maxC - minC) return false;
    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        final i = r * puzzle.width + c;
        if (puzzle.cellValues[i] != myColor) return false;
      }
    }
    for (final member in myGroup) {
      for (final nei in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[nei] == CellValue.free &&
            puzzle.cells[nei].options.contains(myColor)) {
          return false;
        }
      }
    }
    return true;
  }
}
