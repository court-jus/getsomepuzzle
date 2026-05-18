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
    List<int> domain,
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
      // If it has free neighbors it can still grow
      for (var member in myGroup) {
        final freeNeighbors = puzzle
            .getNeighbors(member)
            .where((nei) => puzzle.cellValues[nei] == 0);
        if (freeNeighbors.isNotEmpty) {
          return myGroup.length <= size;
        }
      }
      // The group has no free neighbor, it needs to be exactly the target size
      return myGroup.length == size;
    }
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final idx = indices[0];
    final myColor = puzzle.cellValues[idx];
    final myOpposite = puzzle.domain.whereNot((v) => v == myColor).first;
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myColor == 0) {
      final neighbors = puzzle.getNeighbors(idx);
      for (var neighbor in neighbors) {
        final neighborGroup = groups.firstWhereOrNull(
          (grp) => grp.contains(neighbor),
        );
        if (neighborGroup != null && neighborGroup.length >= size) {
          final neighborColor = puzzle.cellValues[neighbor];
          if (neighborColor != 0) {
            final oppositeColor = puzzle.domain
                .whereNot((v) => v == neighborColor)
                .first;
            return Move(idx, oppositeColor, this, complexity: 1);
          }
        }
      }
      // Per-color feasibility: combine two checks for each candidate color.
      //  (a) Reachability: flood-fill from idx through cells that are empty
      //      OR already this color; the size of that component is the max
      //      group size idx could reach. < size ⇒ infeasible.
      //  (b) Mandatory-merge overshoot: if idx took this color, it would
      //      absorb every existing same-color group adjacent to idx. If that
      //      absorbed mass already exceeds size, OR if every free boundary
      //      cell of that mass would push it past size on its first growth
      //      step, the color is infeasible.
      int? forcedColor;
      for (final color in puzzle.domain) {
        final reachable = <int>{idx};
        final queue = [idx];
        while (queue.isNotEmpty) {
          final current = queue.removeLast();
          for (final nei in puzzle.getNeighbors(current)) {
            final v = puzzle.cellValues[nei];
            if ((v == 0 || v == color) && reachable.add(nei)) {
              queue.add(nei);
            }
          }
        }
        bool infeasible = reachable.length < size;
        if (!infeasible) {
          final mandatoryGroup = <int>{idx};
          for (final nei in puzzle.getNeighbors(idx)) {
            if (puzzle.cellValues[nei] == color) {
              final neiGroup = groups.firstWhereOrNull((g) => g.contains(nei));
              if (neiGroup != null) mandatoryGroup.addAll(neiGroup);
            }
          }
          if (mandatoryGroup.length > size) {
            infeasible = true;
          } else if (mandatoryGroup.length < size) {
            final margin = size - mandatoryGroup.length;
            final boundary = <int>{};
            for (final m in mandatoryGroup) {
              for (final nei in puzzle.getNeighbors(m)) {
                if (puzzle.cellValues[nei] == 0) boundary.add(nei);
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
              if (!anyViable) infeasible = true;
            }
          }
        }
        if (infeasible) {
          if (forcedColor != null) {
            return Move(0, 0, this, isImpossible: this);
          }
          forcedColor = puzzle.domain.whereNot((v) => v == color).first;
        }
      }
      if (forcedColor != null) {
        return Move(idx, forcedColor, this, complexity: 3);
      }
    }
    if (myGroup == null) return null;
    if (myGroup.length == size) {
      // My group is finished, we can fill the neighbors
      for (var member in myGroup) {
        final freeNeighbors = puzzle
            .getNeighbors(member)
            .where((nei) => puzzle.cellValues[nei] == 0);
        if (freeNeighbors.isNotEmpty) {
          return Move(freeNeighbors.first, myOpposite, this, complexity: 0);
        }
      }
    } else if (myGroup.length > size) {
      return Move(0, 0, this, isImpossible: this);
    } else {
      // Find members that only have one empty neighbor
      final Set<int> groupFreeNeighbors = {};
      for (var member in myGroup) {
        groupFreeNeighbors.addAll(
          puzzle.getNeighbors(member).where((idx) => puzzle.getValue(idx) == 0),
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
          return Move(0, 0, this, isImpossible: this);
        }
        return Move(boundary, myColor, this, complexity: 1);
      } else if (myGroup.length < size && groupFreeNeighbors.isEmpty) {
        return Move(0, 0, this, isImpossible: this);
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
        if (mergedSize >= margin) {
          return Move(boundary, myOpposite, this, complexity: 2);
        }
      }
      // Path-based articulation: any empty cell whose blocking would shrink
      // the reachable myColor/empty region below `size` lies on every
      // possible growth path and must take myColor. Generalises the
      // single-exit rule to bottlenecks several steps away from the group.
      final seed = myGroup.first;
      if (reachableComponentSize(puzzle, seed, myColor) < size) {
        return Move(0, 0, this, isImpossible: this);
      }
      for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (puzzle.cellValues[idx] != 0) continue;
        if (blockingShrinksReachableBelow(puzzle, idx, myColor, seed, size)) {
          return Move(idx, myColor, this, complexity: 4);
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
    for (var member in myGroup) {
      final freeNeighbors = puzzle
          .getNeighbors(member)
          .where((nei) => puzzle.cellValues[nei] == 0);
      if (freeNeighbors.isNotEmpty) return false;
    }
    return myGroup.length == size;
  }
}
