import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

const Map<int, String> axisRepresentation = {
  0: "🕱",
  1: "⟍",
  2: "|",
  3: "⟋",
  4: "―",
  5: "🞋",
};

class SymmetryConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'SY';

  int axis = 0;

  SymmetryConstraint(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
    axis = int.parse(strParams.split(".")[1]);
  }

  @override
  String serialize() => 'SY:${indices.first}.$axis';

  @override
  String toString() {
    return axisRepresentation[axis] ?? "🕱";
  }

  static List<String> generateAllParameters(int width, int height) {
    final List<String> result = [];
    for (int idx = 0; idx < width * height; idx++) {
      for (int axis = 1; axis <= 5; axis++) {
        result.add('$idx.$axis');
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final groups = puzzle.getGroups();
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return true;
    final myValue = puzzle.getValue(idx);
    if (myValue == 0) return true;
    for (final cellidx in myGroup) {
      final sym = _computeSymmetry(puzzle, cellidx);
      if (sym == null) return false;
      if (puzzle.getValue(sym) == 0) continue;
      if (puzzle.getValue(sym) != myValue) return false;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = puzzle.getGroups();
    final idx = indices[0];
    final myValue = puzzle.getValue(idx);
    if (myValue == 0) return null;
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return null;
    final myOpposite = puzzle.domain.whereNot((e) => e == myValue).first;
    for (final cellidx in myGroup) {
      final sym = _computeSymmetry(puzzle, cellidx);
      // This cell's symmetry is outside the boundaries of the puzzle
      if (sym == null) {
        return Move(0, 0, this, isImpossible: this);
      }
      // This cell's symmetry is free
      if (puzzle.getValue(sym) == 0) {
        return Move(sym, myValue, this);
      }
    }
    // Now, look for cells neighboring my group
    for (var member in myGroup) {
      final neighbors = puzzle.getNeighbors(member);
      for (var neighbor in neighbors) {
        if (puzzle.cellValues[neighbor] == myOpposite) {
          // This cell is filled with my opposite color
          // so its symmetry should be myOpposite too (if it exists and is free)
          final sym = _computeSymmetry(puzzle, neighbor);
          if (sym != null && puzzle.cellValues[sym] == 0) {
            return Move(sym, myOpposite, this);
          }
        } else if (puzzle.cellValues[neighbor] == 0) {
          // This cell is free. If its symmetry is not free, we know
          // that it cannot be made part of our group
          final sym = _computeSymmetry(puzzle, neighbor);
          if (sym == null || puzzle.cellValues[sym] != 0) {
            return Move(neighbor, myOpposite, this);
          }
        }
      }
    }

    return null;
  }

  int? _computeSymmetry(Puzzle puzzle, int cellidx) {
    final idx = indices[0];
    final int x = idx % puzzle.width;
    final int y = (idx / puzzle.width).floor();
    final int cx = cellidx % puzzle.width;
    final int cy = (cellidx / puzzle.width).floor();
    final int dx = x - cx;
    final int dy = y - cy;
    int sx = 0;
    int sy = 0;
    if (axis == 1) {
      // ⟍ symmetry
      sx = x - dy;
      sy = y - dx;
    } else if (axis == 2) {
      // | symmetry
      sx = x + dx;
      sy = cy;
    } else if (axis == 3) {
      // ⟋ symmetry
      sx = x + dy;
      sy = y + dx;
    } else if (axis == 4) {
      // ― symmetry
      sx = cx;
      sy = y + dy;
    } else if (axis == 5) {
      // 🞋 symmetry
      sx = x + dx;
      sy = y + dy;
    }
    final int newidx = sy * puzzle.width + sx;
    if (sx < 0 || sy < 0 || sx >= puzzle.width || sy >= puzzle.height) {
      return null;
    }
    return newidx;
  }
}
