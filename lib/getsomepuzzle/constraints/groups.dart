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
      // If it has free neighbors it can still grow
      for (var member in myGroup) {
        final freeNeighbors = puzzle
            .getNeighbors(member)
            .where((nei) => puzzle.cellValues[nei] == CellValue.free);
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
            return Move(idx, removeOption: neighborColor, this, complexity: 1);
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
        final reachable = <int>{idx};
        final queue = [idx];
        while (queue.isNotEmpty) {
          final current = queue.removeLast();
          for (final nei in puzzle.getNeighbors(current)) {
            final v = puzzle.cells[nei];
            if ((v.options.contains(color) || v.value == color) &&
                reachable.add(nei)) {
              queue.add(nei);
            }
          }
        }
        if (reachable.length < size) {
          return Move(idx, removeOption: color, this, complexity: 3);
        }
        final mandatoryGroup = <int>{idx};
        for (final nei in puzzle.getNeighbors(idx)) {
          if (puzzle.cellValues[nei] == color) {
            final neiGroup = groups.firstWhereOrNull((g) => g.contains(nei));
            if (neiGroup != null) mandatoryGroup.addAll(neiGroup);
          }
        }
        if (mandatoryGroup.length > size) {
          return Move(idx, removeOption: color, this, complexity: 3);
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
              return Move(idx, removeOption: color, this, complexity: 3);
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
          return Move(
            freeNeighbors.first,
            removeOption: myColor,
            this,
            complexity: 0,
          );
        }
      }
    } else if (myGroup.length > size) {
      return Move(0, this, isImpossible: this);
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
          return Move(0, this, isImpossible: this);
        }
        // The single exit must take myColor. If options have already
        // excluded myColor (3-colour puzzles), the group can't grow.
        if (!puzzle.cells[boundary].options.contains(myColor)) {
          return Move(0, this, isImpossible: this);
        }
        return Move(boundary, value: myColor, this, complexity: 1);
      } else if (myGroup.length < size && groupFreeNeighbors.isEmpty) {
        return Move(0, this, isImpossible: this);
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
          return Move(boundary, removeOption: myColor, this, complexity: 2);
        }
      }
      // Path-based articulation: any empty cell whose blocking would shrink
      // the reachable myColor/empty region below `size` lies on every
      // possible growth path and must take myColor. Generalises the
      // single-exit rule to bottlenecks several steps away from the group.
      final seed = myGroup.first;
      if (reachableComponentSize(puzzle, seed, myColor) < size) {
        return Move(0, this, isImpossible: this);
      }
      for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (puzzle.cellValues[idx] != CellValue.free) continue;
        if (blockingShrinksReachableBelow(puzzle, idx, myColor, seed, size)) {
          // Articulation point must take myColor. If options exclude it,
          // the group cannot reach `size` along any growth path.
          if (!puzzle.cells[idx].options.contains(myColor)) {
            return Move(0, this, isImpossible: this);
          }
          return Move(idx, value: myColor, this, complexity: 4);
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
          .where((nei) => puzzle.cellValues[nei] == CellValue.free);
      if (freeNeighbors.isNotEmpty) return false;
    }
    return myGroup.length == size;
  }
}

class LetterGroup extends CellsCentricConstraint {
  @override
  String get slug => 'LT';

  String letter = "";

  LetterGroup(String strParams) {
    final params = strParams.split(".");
    letter = params.removeAt(0);
    indices = params.map((e) => int.parse(e)).toList();
  }

  @override
  String serialize() => 'LT:$letter.${indices.join(".")}';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIndices = indices
        .map((i) => rotateIdx90CW(i, origWidth, origHeight))
        .toList();
    return LetterGroup('$letter.${newIndices.join(".")}');
  }

  @override
  String toHuman(Puzzle puzzle) {
    final hIndices = indices.map((i) => i + 1);
    return "$hIndices = $letter";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final size = width * height;
    final maxLetters = max(1, size ~/ 5);
    final List<String> result = [];
    for (int idx1 = 0; idx1 < size; idx1++) {
      for (int idx2 = 0; idx2 < size; idx2++) {
        if (idx1 == idx2) continue;
        for (int l = 0; l < maxLetters; l++) {
          result.add('${String.fromCharCode(65 + l)}.$idx1.$idx2');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    // Aggregation in `Puzzle` guarantees a single LetterGroup per letter, so
    // `indices` already lists every cell sharing this letter.
    if (indices.any((i) => puzzle.cellValues[i] == CellValue.free)) return true;
    final groups = getGroups(puzzle);
    final myIndicesSet = indices.toSet();
    final myGroups = groups
        .where((g) => g.toSet().intersection(myIndicesSet).isNotEmpty)
        .toList();
    if (myGroups.isEmpty) return false;
    // No cell carrying a different letter may share my group(s).
    for (final group in myGroups) {
      for (final idx in group) {
        if (myIndicesSet.contains(idx)) continue;
        final constraintsAtIdx = puzzle.cellConstraints[idx];
        if (constraintsAtIdx == null) continue;
        for (final constraint in constraintsAtIdx) {
          if (constraint is LetterGroup && constraint.letter != letter) {
            return false;
          }
        }
      }
    }
    if (!puzzle.complete) return true;
    // Complete state: a single connected group must cover all my indices.
    return myGroups.length == 1;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myColors = indices
        .map((idx) => puzzle.getValue(idx))
        .where((value) => value != CellValue.free);
    if (myColors.isEmpty) return null;
    if (myColors.toSet().length > 1) {
      return Move(0, this, isImpossible: this);
    }
    final myColor = myColors.first;
    final otherLetters = puzzle.constraints
        .whereType<LetterGroup>()
        .where((c) => c.letter != letter)
        .map((c) => c.indices)
        .flattenedToList;
    // 1. Every member must take myColor; other colors are an error.
    for (var member in indices) {
      final memberValue = puzzle.getValue(member);
      if (memberValue == CellValue.free) {
        // A free member must take myColor. If options no longer include
        // myColor (3-colour puzzles), the letter cannot be satisfied.
        if (!puzzle.cells[member].options.contains(myColor)) {
          return Move(member, this, isImpossible: this);
        }
        return Move(member, value: myColor, this, complexity: 0);
      } else if (memberValue != myColor) {
        return Move(member, this, isImpossible: this);
      }
    }
    final allGroups = getGroups(puzzle);
    final myIndicesSet = indices.toSet();
    final myGroupsJoined = allGroups
        .where((grp) => grp.toSet().intersection(myIndicesSet).isNotEmpty)
        .flattened;

    // 2. Cells of another letter touching my group cannot be the same colour
    //    (would merge two distinct letters).
    final neighborWithLetters = myGroupsJoined
        .map((idx) => puzzle.getNeighbors(idx))
        .flattened
        .where((nei) => otherLetters.contains(nei));
    for (var nei in neighborWithLetters) {
      final neiValue = puzzle.getValue(nei);
      if (neiValue == myColor) {
        return Move(nei, this, isImpossible: this);
      }
      if (puzzle.cells[nei].options.contains(myColor)) {
        return Move(nei, removeOption: myColor, this, complexity: 1);
      }
    }

    // 3. Feasibility: my members must all share one virtual group anchored
    //    on myColor (i.e. there must be SOME path of myColor + cells with myColor as an option
    //    connecting them).
    final canConnect = toVirtualGroups(
      puzzle,
    ).any((vg) => indices.every((m) => vg.contains(m)));
    if (!canConnect) {
      return Move(0, this, isImpossible: this);
    }

    final sameGroup = allGroups.any(
      (grp) => grp.toSet().intersection(myIndicesSet).length == indices.length,
    );

    // 4. Articulation: any empty cell whose blocking would disconnect the
    //    members must take myColor — it lies on every possible merge path.
    //    Subsumes the per-group "single exit" rule (a sealed-but-one group
    //    has its lone exit as articulation point).
    if (!sameGroup && indices.length > 1) {
      for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (!puzzle.cells[idx].options.contains(myColor)) continue;
        if (blockingDisconnectsMembers(puzzle, idx, myColor, indices)) {
          return Move(idx, value: myColor, this, complexity: 4);
        }
      }
    }

    // 5. Free neighbours of my group that also touch another letter's
    //    same-colour cells cannot take myColor (would merge two letters).
    final otherSameColor = otherLetters.where(
      (idx) => puzzle.cellValues[idx] == myColor,
    );
    if (otherSameColor.isNotEmpty) {
      final otherGroups = allGroups
          .where(
            (grp) =>
                grp.toSet().intersection(otherSameColor.toSet()).isNotEmpty,
          )
          .flattened;
      final Set<int> groupFreeNeighbors = {};
      for (var member in indices) {
        final memberGroup = allGroups
            .where((grp) => grp.contains(member))
            .first;
        for (var groupCell in memberGroup) {
          groupFreeNeighbors.addAll(
            puzzle
                .getNeighbors(groupCell)
                .where((idx) => puzzle.getValue(idx) == CellValue.free),
          );
        }
      }
      for (final groupFreeNeighbor in groupFreeNeighbors) {
        final neighborsWithOther = puzzle
            .getNeighbors(groupFreeNeighbor)
            .where((nei) => otherGroups.contains(nei));
        if (neighborsWithOther.isNotEmpty &&
            puzzle.cells[groupFreeNeighbor].options.contains(myColor)) {
          return Move(
            groupFreeNeighbor,
            removeOption: myColor,
            this,
            complexity: 2,
          );
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    if (indices.any((i) => i >= puzzle.cellValues.length)) return false;
    final myCellValues = indices.map((i) => puzzle.cellValues[i]).toList();
    if (myCellValues.contains(CellValue.free)) return false;
    final groups = getGroups(puzzle);
    final myGroup = groups.firstWhereOrNull(
      (grp) =>
          grp.toSet().intersection(indices.toSet()).length == indices.length,
    );
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

class CannotApplyConstraint extends Error {
  CannotApplyConstraint(String message);
}
