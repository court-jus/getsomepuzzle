import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

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

  /// Rotation-90°-CW remap of axis IDs:
  ///   1 (⟍ diag) ↔ 3 (⟋ diag)
  ///   2 (| vertical) ↔ 4 (― horizontal)
  ///   5 (🞋 point) is invariant.
  static const Map<int, int> _rotatedAxis = {1: 3, 2: 4, 3: 1, 4: 2, 5: 5};

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIdx = rotateIdx90CW(indices.first, origWidth, origHeight);
    final newAxis = _rotatedAxis[axis] ?? axis;
    return SymmetryConstraint('$newIdx.$newAxis');
  }

  @override
  String toString() {
    return axisRepresentation[axis] ?? "🕱";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
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
    if (myValue == CellValue.free) return true;
    for (final cellidx in myGroup) {
      final sym = computeSymmetry(puzzle, cellidx);
      if (sym == null) return false;
      if (puzzle.getValue(sym) == CellValue.free) continue;
      if (puzzle.getValue(sym) != myValue) return false;
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myValue = puzzle.getValue(idx);
    if (myValue == CellValue.free) {
      // Anchor still empty: a coloured direct neighbour `n` of value
      // `nv` constrains the anchor's possible colours.
      //
      // Two cases on what the anchor will eventually become:
      //   - anchor = nv : `n` joins the anchor's group, so sym(n) must
      //     also be nv (group is symmetric).
      //   - anchor = c (some non-nv colour) : `n` is on G's frontier;
      //     sym(n) must NOT be in G, i.e. sym(n) ≠ c. (On 2-colour
      //     domains this collapses to "sym(n) = the other colour =
      //     nv", but on 3+ colours we cannot conclude sym(n) = nv —
      //     sym(n) can be any non-c colour.)
      //
      // What we can locally deduce on the anchor depends on the state
      // of sym(n):
      //   sym(n) null            → anchor ≠ nv  (case 1 needs sym to exist)
      //   sym(n) free, nv ∉ opts → anchor ≠ nv  (case 1 needs nv there)
      //   sym(n) coloured nv     → no constraint on anchor
      //   sym(n) coloured c'≠nv  → anchor ≠ nv (case 1 needs sym=nv)
      //                          AND anchor ≠ c' (case 2 needs sym ≠ c')
      // We emit one removeOption at a time; the loop will pick the
      // others on subsequent iterations.
      for (final neighbor in puzzle.getNeighbors(idx)) {
        final nv = puzzle.cellValues[neighbor];
        if (nv == CellValue.free) continue;
        final sym = computeSymmetry(puzzle, neighbor);

        bool anchorCannotBeNv = false;
        CellValue? otherExcluded;

        if (sym == null) {
          anchorCannotBeNv = true;
        } else {
          final sv = puzzle.cellValues[sym];
          if (sv == CellValue.free) {
            if (!puzzle.cells[sym].options.contains(nv)) {
              anchorCannotBeNv = true;
            }
          } else if (sv != nv) {
            anchorCannotBeNv = true;
            otherExcluded = sv;
          }
        }

        if (anchorCannotBeNv && puzzle.cells[idx].options.contains(nv)) {
          return Move(idx, removeOption: nv, this, complexity: 2);
        }
        if (otherExcluded != null &&
            puzzle.cells[idx].options.contains(otherExcluded)) {
          return Move(idx, removeOption: otherExcluded, this, complexity: 2);
        }
      }
      return null;
    }
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return null;
    // Step 1: every cell of the anchor's group needs a same-colour mirror.
    for (final cellidx in myGroup) {
      final sym = computeSymmetry(puzzle, cellidx);
      if (sym == null) {
        return Move(0, this, isImpossible: this);
      }
      final sv = puzzle.getValue(sym);
      if (sv == CellValue.free) {
        if (!puzzle.cells[sym].options.contains(myValue)) {
          return Move(0, this, isImpossible: this);
        }
        return Move(sym, value: myValue, this, complexity: 1);
      }
      if (sv != myValue) {
        // sym(member) is already coloured something else → group cannot
        // be symmetric.
        return Move(0, this, isImpossible: this);
      }
    }
    // Step 2: rules on cells adjacent to G, derived from "G is
    // symmetric → for every n adjacent to G, sym(n) is in G iff n is".
    //
    // We do NOT generalize the 2-colour "frontier coloured = mirror
    // coloured the same" rule. On a 2-colour domain "non-myValue" was
    // a single colour so that rule worked, but on 3+ colours a
    // frontier neighbour coloured `c` does not force its mirror to
    // also be `c`: the constraint only requires sym(n) ∉ G, which
    // simply means sym(n) ≠ myValue. The two sides of G can be
    // surrounded by different non-myValue colours.
    for (var member in myGroup) {
      for (var neighbor in puzzle.getNeighbors(member)) {
        final nv = puzzle.cellValues[neighbor];
        if (nv == myValue) continue; // same colour: in G, no deduction here
        final sym = computeSymmetry(puzzle, neighbor);

        if (nv == CellValue.free) {
          // Free neighbour: if it becomes myValue it joins G, so its
          // mirror would also need to be in G (i.e. coloured myValue).
          // If the mirror is out of bounds, or is already coloured
          // something other than myValue, the neighbour cannot become
          // myValue.
          final blocked =
              sym == null ||
              (puzzle.cellValues[sym] != CellValue.free &&
                  puzzle.cellValues[sym] != myValue);
          if (blocked && puzzle.cells[neighbor].options.contains(myValue)) {
            return Move(neighbor, removeOption: myValue, this, complexity: 2);
          }
          continue;
        }

        // nv is coloured, and ≠ myValue: neighbour is on G's frontier
        // (it is not in G). sym(n) is adjacent to sym(member) ∈ G; by
        // group symmetry, sym(n) must also be outside G — therefore
        // not myValue. If sym(n) is out of bounds, nothing to deduce
        // (no cell to constrain).
        if (sym == null) continue;
        final sv = puzzle.cellValues[sym];
        if (sv == myValue) {
          // sym(n) is colored myValue and adjacent to G → would be in
          // G → forces n into G by symmetry, contradicting n's colour.
          return Move(0, this, isImpossible: this);
        }
        if (sv == CellValue.free) {
          // Mirror is free: it must not become myValue.
          if (puzzle.cells[sym].options.contains(myValue)) {
            return Move(sym, removeOption: myValue, this, complexity: 2);
          }
        }
        // sv coloured ≠ myValue → consistent, no deduction.
      }
    }

    // Step 3 (look-ahead): a free cell `n` adjacent to the group whose
    // own mirror is free can still be impossible to colour myValue.
    // Setting `n = myValue` would pull every myValue cell reachable from
    // `n` (through cells already coloured myValue) into the anchor's
    // group. If any cell in that closure has its mirror out of bounds or
    // coloured something other than myValue, the merged group could
    // never be symmetric — so `n` must not be myValue.
    for (var member in myGroup) {
      for (var neighbor in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[neighbor] != CellValue.free) continue;
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
        // The single-cell case is handled by step 2.
        if (merged.length == 1) continue;
        for (final m in merged) {
          final sym = computeSymmetry(puzzle, m);
          if (sym == null ||
              (puzzle.cellValues[sym] != CellValue.free &&
                  puzzle.cellValues[sym] != myValue)) {
            if (puzzle.cells[neighbor].options.contains(myValue)) {
              return Move(neighbor, removeOption: myValue, this, complexity: 3);
            }
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
          .where((nei) => puzzle.cellValues[nei] == CellValue.free);
      if (freeNeighbors.isNotEmpty) return false;
    }
    return true;
  }
}
