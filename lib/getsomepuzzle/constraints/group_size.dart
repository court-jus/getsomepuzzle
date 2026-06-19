import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

const _maxGroupSizeRatio = 0.5;
const _maxGroupSizeAbsolute = 15;

class GroupSize extends CellsCentricConstraint {
  @override
  String get slug => 'GS';

  // Colour-agnostic: constrains group sizes, not a specific colour.
  @override
  Set<CellValue> get referencedColors => const {};

  int size = 0;

  GroupSize(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
    size = int.parse(strParams.split(".")[1]);
  }

  @override
  String serialize() => 'GS:${indices.first}.$size';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIdx = rotateIdx90CW(indices.first, origWidth, origHeight);
    return GroupSize('$newIdx.$size');
  }

  @override
  String toString() {
    return size.toString();
  }

  @override
  String toHuman(Puzzle puzzle) {
    final idx = indices.first;
    return "Group at ${idx + 1} = $size";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final maxSize = min(
      _maxGroupSizeAbsolute,
      max(1, (width * height * _maxGroupSizeRatio).toInt()),
    );
    final List<String> result = [];
    for (int idx = 0; idx < width * height; idx++) {
      for (int size = 1; size < maxSize; size++) {
        result.add('$idx.$size');
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) {
      return !puzzle.complete;
    }
    if (puzzle.complete) {
      return myGroup.length == size;
    } else {
      // The group can only grow through a free neighbour that can still take
      // the group's colour. On a 3+-colour puzzle a free cell whose `myColor`
      // option has been pruned can never join the group, so it does not keep
      // the group growable.
      final myColor = puzzle.cellValues[idx];
      for (var member in myGroup) {
        final growableNeighbors = puzzle
            .getNeighbors(member)
            .where(
              (nei) =>
                  puzzle.cellValues[nei] == CellValue.free &&
                  puzzle.cells[nei].options.contains(myColor),
            );
        if (growableNeighbors.isNotEmpty) {
          return myGroup.length <= size;
        }
      }
      // No growable neighbour left: the group must be exactly the target size.
      return myGroup.length == size;
    }
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myColor = puzzle.cellValues[idx];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myColor == CellValue.free) {
      final neighbors = puzzle.getNeighbors(idx);
      for (var neighbor in neighbors) {
        final neighborGroup = groups.firstWhereOrNull(
          (grp) => grp.contains(neighbor),
        );
        if (neighborGroup != null && neighborGroup.length >= size) {
          final neighborColor = puzzle.cellValues[neighbor];
          if (neighborColor != CellValue.free &&
              puzzle.cells[idx].options.contains(neighborColor)) {
            return RemoveOption(idx, neighborColor, this, complexity: 1);
          }
        }
      }
      // Per-color feasibility: combine two checks for each candidate color.
      //  (a) Reachability: flood-fill from idx through cells that have this color as an option
      //      OR already this color; the size of that component is the max
      //      group size idx could reach. < size ⇒ infeasible.
      //  (b) Mandatory-merge overshoot: if idx took this color, it would
      //      absorb every existing same-color group adjacent to idx. If that
      //      absorbed mass already exceeds size, OR if every free boundary
      //      cell of that mass would push it past size on its first growth
      //      step, the color is infeasible.
      for (final color in puzzle.domain) {
        // Only colours still in the anchor's options can be removed; an
        // already-pruned colour would make every emission below a no-op
        // move re-emitted forever (the solver then stalls on it). Only
        // reachable on 3+ colour domains — on 2 colours a pruned option
        // collapses the cell to a value and the anchor is no longer free.
        if (!puzzle.cells[idx].options.contains(color)) continue;
        final reachable = floodFill(puzzle, [idx], (i) {
          final c = puzzle.cells[i];
          return c.value == color || c.options.contains(color);
        });
        if (reachable.length < size) {
          return RemoveOption(idx, color, this, complexity: 3);
        }
        final mandatoryGroup = <int>{idx};
        for (final nei in puzzle.getNeighbors(idx)) {
          if (puzzle.cellValues[nei] == color) {
            final neiGroup = groups.firstWhereOrNull((g) => g.contains(nei));
            if (neiGroup != null) mandatoryGroup.addAll(neiGroup);
          }
        }
        if (mandatoryGroup.length > size) {
          return RemoveOption(idx, color, this, complexity: 3);
        } else if (mandatoryGroup.length < size) {
          final margin = size - mandatoryGroup.length;
          final boundary = <int>{};
          for (final m in mandatoryGroup) {
            for (final nei in puzzle.getNeighbors(m)) {
              if (puzzle.cellValues[nei] == CellValue.free) boundary.add(nei);
            }
          }
          if (boundary.isNotEmpty) {
            final externalGroups = groups
                .where(
                  (g) =>
                      g.any((c) => puzzle.cellValues[c] == color) &&
                      !g.any(mandatoryGroup.contains),
                )
                .toList();
            bool anyViable = false;
            for (final b in boundary) {
              final bNei = puzzle.getNeighbors(b);
              int addition = 1;
              for (final g in externalGroups) {
                if (bNei.any(g.contains)) addition += g.length;
              }
              if (addition <= margin) {
                anyViable = true;
                break;
              }
            }
            if (!anyViable) {
              return RemoveOption(idx, color, this, complexity: 3);
            }
          }
        }
      }
    }
    if (myGroup == null) return null;
    if (myGroup.length == size) {
      // My group is finished, we can remove my color from the neighbors' option
      for (var member in myGroup) {
        final freeNeighbors = puzzle
            .getNeighbors(member)
            .where(
              (nei) =>
                  puzzle.cellValues[nei] == CellValue.free &&
                  puzzle.cells[nei].options.contains(myColor),
            );
        if (freeNeighbors.isNotEmpty) {
          return RemoveOption(
            freeNeighbors.first,
            myColor,
            this,
            complexity: 0,
          );
        }
      }
    } else if (myGroup.length > size) {
      return Impossible(this);
    } else {
      // Find members that only have one empty neighbor
      final Set<int> groupFreeNeighbors = {};
      for (var member in myGroup) {
        groupFreeNeighbors.addAll(
          puzzle
              .getNeighbors(member)
              .where((idx) => puzzle.getValue(idx) == CellValue.free),
        );
      }
      if (groupFreeNeighbors.length == 1) {
        // Single-exit overshoot: if extending into the lone exit forces a
        // merge with same-colour groups whose total addition exceeds the
        // remaining margin, the group cannot grow at all → impossible.
        final boundary = groupFreeNeighbors.first;
        final margin = size - myGroup.length;
        int mergedSize = 0;
        for (final grp in groups) {
          if (!grp.any((cell) => puzzle.cellValues[cell] == myColor)) continue;
          if (grp.any((cell) => myGroup.contains(cell))) continue;
          if (puzzle.getNeighbors(boundary).any((nei) => grp.contains(nei))) {
            mergedSize += grp.length;
          }
        }
        if (1 + mergedSize > margin) {
          return Impossible(this);
        }
        // The single exit must take myColor. If options have already
        // excluded myColor (3-colour puzzles), the group can't grow.
        if (!puzzle.cells[boundary].options.contains(myColor)) {
          return Impossible(this);
        }
        return SetValue(boundary, myColor, this, complexity: 1);
      } else if (myGroup.length < size && groupFreeNeighbors.isEmpty) {
        return Impossible(this);
      }
      // If extending in a direction would merge me with other groups and create a "too big group",
      // then add a boundary in that direction, it is forbidden to grow there.
      // We sum the sizes of ALL same-color groups touching the free neighbor,
      // because coloring it would merge them all into one group.
      final margin = size - myGroup.length;
      final sameColorGroups = groups
          .where(
            (grp) =>
                grp.any((cell) => puzzle.cellValues[cell] == myColor) &&
                !grp.any((cell) => myGroup.contains(cell)),
          )
          .toList();
      for (final boundary in groupFreeNeighbors) {
        final boundaryNeighbors = puzzle.getNeighbors(boundary);
        int mergedSize = 0;
        for (final grp in sameColorGroups) {
          if (boundaryNeighbors.any((nei) => grp.contains(nei))) {
            mergedSize += grp.length;
          }
        }
        if (mergedSize >= margin &&
            puzzle.cells[boundary].options.contains(myColor)) {
          return RemoveOption(boundary, myColor, this, complexity: 2);
        }
      }
      // Path-based articulation: any empty cell whose blocking would shrink
      // the reachable myColor/empty region below `size` lies on every
      // possible growth path and must take myColor. Generalises the
      // single-exit rule to bottlenecks several steps away from the group.
      final seed = myGroup.first;
      if (reachableComponentSize(puzzle, seed, myColor) < size) {
        return Impossible(this);
      }
      for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (puzzle.cellValues[idx] != CellValue.free) continue;
        if (blockingShrinksReachableBelow(puzzle, idx, myColor, seed, size)) {
          // Articulation point must take myColor. If options exclude it,
          // the group cannot reach `size` along any growth path.
          if (!puzzle.cells[idx].options.contains(myColor)) {
            return Impossible(this);
          }
          return SetValue(idx, myColor, this, complexity: 4);
        }
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return false;
    final myColor = puzzle.cellValues[myGroup.first];
    for (var member in myGroup) {
      for (final nei in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[nei] == CellValue.free &&
            puzzle.cells[nei].options.contains(myColor)) {
          return false;
        }
      }
    }
    return myGroup.length == size;
  }
}
