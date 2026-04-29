import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

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
            return Move(idx, oppositeColor, this);
          }
        }
      }
      // Reachability check: for each color, flood-fill from idx through cells
      // that are empty OR already this color. The size of that connected
      // component is the max group size idx could reach if colored this color.
      // If it's < size for a color, that color is impossible.
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
        if (reachable.length < size) {
          if (forcedColor != null) {
            return Move(0, 0, this, isImpossible: this);
          }
          forcedColor = puzzle.domain.whereNot((v) => v == color).first;
        }
      }
      if (forcedColor != null) {
        return Move(idx, forcedColor, this);
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
          return Move(freeNeighbors.first, myOpposite, this);
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
        return Move(groupFreeNeighbors.first, myColor, this);
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
          return Move(boundary, myOpposite, this);
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
  String toHuman(Puzzle puzzle) {
    final hIndices = indices.map((i) => i + 1);
    return "$hIndices = $letter";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
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
    if (indices.any((i) => puzzle.cellValues[i] == 0)) return true;
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
        .where((value) => value != 0);
    if (myColors.isEmpty) return null;
    final myColor = myColors.first;
    final otherLetters = puzzle.constraints
        .whereType<LetterGroup>()
        .where((c) => c.letter != letter)
        .map((c) => c.indices)
        .flattenedToList;
    final myOpposite = puzzle.domain.whereNot((v) => v == myColor).first;
    // 1. Every member must take myColor; opposite-coloured ones are an error.
    for (var member in indices) {
      final memberValue = puzzle.getValue(member);
      if (memberValue == myOpposite) {
        return Move(member, myColor, this, isImpossible: this);
      }
      if (memberValue == 0) {
        return Move(member, myColor, this);
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
        return Move(nei, myOpposite, this, isImpossible: this);
      }
      if (neiValue == 0) {
        return Move(nei, myOpposite, this);
      }
    }

    // 3. Feasibility: my members must all share one virtual group anchored
    //    on myColor (i.e. there must be SOME path of myColor + empty cells
    //    connecting them).
    final canConnect = toVirtualGroups(
      puzzle,
    ).any((vg) => indices.every((m) => vg.contains(m)));
    if (!canConnect) {
      return Move(0, 0, this, isImpossible: this);
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
        if (puzzle.getValue(idx) != 0) continue;
        if (blockingDisconnectsMembers(puzzle, idx, myColor, indices)) {
          return Move(idx, myColor, this);
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
                .where((idx) => puzzle.getValue(idx) == 0),
          );
        }
      }
      for (final groupFreeNeighbor in groupFreeNeighbors) {
        final neighborsWithOther = puzzle
            .getNeighbors(groupFreeNeighbor)
            .where((nei) => otherGroups.contains(nei));
        if (neighborsWithOther.isNotEmpty) {
          return Move(groupFreeNeighbor, myOpposite, this);
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
    if (myCellValues.contains(0)) return false;
    final groups = getGroups(puzzle);
    final myGroup = groups.firstWhereOrNull(
      (grp) =>
          grp.toSet().intersection(indices.toSet()).length == indices.length,
    );
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

class CannotApplyConstraint extends Error {
  CannotApplyConstraint(String message);
}
