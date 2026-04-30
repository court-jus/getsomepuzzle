import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

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

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
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
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return true;
    final myValue = puzzle.getValue(idx);
    if (myValue == 0) return true;
    for (final cellidx in myGroup) {
      final sym = computeSymmetry(puzzle, cellidx);
      if (sym == null) return false;
      if (puzzle.getValue(sym) == 0) continue;
      if (puzzle.getValue(sym) != myValue) return false;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myValue = puzzle.getValue(idx);
    if (myValue == 0) {
      // Anchor still empty: a coloured direct neighbour `n` of value `c`
      // already forces its mirror, regardless of what colour the anchor
      // eventually takes. If the anchor takes `c`, `n` joins the anchor's
      // group and SY forces sym(n) = c. If the anchor takes the opposite,
      // `n` is on the group's frontier as myOpposite = c, and SY's
      // frontier rule forces sym(n) = myOpposite = c. Both branches
      // agree on sym(n) = c. If sym(n) is out of bounds, the anchor
      // cannot take colour `c` (it would need n's mirror to exist), so
      // the anchor itself is forced to the opposite.
      for (final neighbor in puzzle.getNeighbors(idx)) {
        final nv = puzzle.cellValues[neighbor];
        if (nv == 0) continue;
        final sym = computeSymmetry(puzzle, neighbor);
        if (sym == null) {
          final opposite = puzzle.domain.firstWhere((v) => v != nv);
          return Move(idx, opposite, this, complexity: 2);
        }
        final sv = puzzle.cellValues[sym];
        if (sv == 0) {
          return Move(sym, nv, this, complexity: 2);
        }
        if (sv != nv) {
          return Move(0, 0, this, isImpossible: this);
        }
      }
      return null;
    }
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return null;
    final myOpposite = puzzle.domain.whereNot((e) => e == myValue).first;
    for (final cellidx in myGroup) {
      final sym = computeSymmetry(puzzle, cellidx);
      // This cell's symmetry is outside the boundaries of the puzzle
      if (sym == null) {
        return Move(0, 0, this, isImpossible: this);
      }
      // This cell's symmetry is free
      if (puzzle.getValue(sym) == 0) {
        return Move(sym, myValue, this, complexity: 1);
      }
    }
    // Now, look for cells neighboring my group
    for (var member in myGroup) {
      final neighbors = puzzle.getNeighbors(member);
      for (var neighbor in neighbors) {
        if (puzzle.cellValues[neighbor] == myOpposite) {
          // This cell is filled with my opposite color
          // so its symmetry should be myOpposite too (if it exists and is free)
          final sym = computeSymmetry(puzzle, neighbor);
          if (sym != null && puzzle.cellValues[sym] == 0) {
            return Move(sym, myOpposite, this, complexity: 2);
          }
        } else if (puzzle.cellValues[neighbor] == 0) {
          // This cell is free. If its symmetry is not free, we know
          // that it cannot be made part of our group
          final sym = computeSymmetry(puzzle, neighbor);
          if (sym == null || puzzle.cellValues[sym] != 0) {
            return Move(neighbor, myOpposite, this, complexity: 2);
          }
        }
      }
    }

    // Look-ahead: a free cell `n` adjacent to the group whose own
    // symmetry is free can still be impossible to colour myValue.
    // Setting `n = myValue` would also pull every myValue cell
    // reachable from `n` (through cells already coloured myValue) into
    // the anchor's group. If any cell in that closure has its
    // symmetry out of bounds or already filled with myOpposite, the
    // merged group could never be symmetric — so `n` must be
    // myOpposite.
    for (var member in myGroup) {
      for (var neighbor in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[neighbor] != 0) continue;
        final merged = <int>{neighbor};
        final queue = Queue<int>()..add(neighbor);
        while (queue.isNotEmpty) {
          final cur = queue.removeFirst();
          for (final nei in puzzle.getNeighbors(cur)) {
            if (merged.contains(nei)) continue;
            if (puzzle.cellValues[nei] == myValue) {
              merged.add(nei);
              queue.add(nei);
            }
          }
        }
        // The single-cell case is handled by the previous loop.
        if (merged.length == 1) continue;
        for (final m in merged) {
          final sym = computeSymmetry(puzzle, m);
          if (sym == null ||
              (puzzle.cellValues[sym] != 0 &&
                  puzzle.cellValues[sym] != myValue)) {
            return Move(neighbor, myOpposite, this, complexity: 3);
          }
        }
      }
    }

    return null;
  }

  int? computeSymmetry(Puzzle puzzle, int cellidx) {
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

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return false;
    for (final member in myGroup) {
      final freeNeighbors = puzzle
          .getNeighbors(member)
          .where((nei) => puzzle.cellValues[nei] == 0);
      if (freeNeighbors.isNotEmpty) return false;
    }
    return true;
  }
}
