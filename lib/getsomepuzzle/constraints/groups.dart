import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

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
  String toHuman() {
    final idx = indices.first;
    return "${idx + 1} = $size";
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
    final groups = puzzle.getGroups();
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
    final groups = puzzle.getGroups();
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
  String toHuman() {
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
    // If any of my cells are not filled yet, there's no need to check further
    final myCellValues = puzzle.cellValues.indexed
        .where((elem) => indices.contains(elem.$1))
        .map((elem) => elem.$2);
    if (myCellValues.contains(0)) return true;
    final groups = puzzle.getGroups();
    final List<List<int>> myGroups = [];
    for (final group in groups) {
      final intersect = group.toSet().intersection(indices.toSet());
      if (intersect.isNotEmpty) {
        myGroups.add(group);
      }
    }
    // There should be no other letter in mygroup
    final myGroup = myGroups[0];
    final Set<String> lettersInMyGroup = {};
    for (final idx in myGroup) {
      final constraintsAtIdx = puzzle.cellConstraints[idx];
      if (constraintsAtIdx == null) continue;
      for (final constraint in constraintsAtIdx) {
        if (constraint is! LetterGroup) continue;
        lettersInMyGroup.add(constraint.letter);
      }
    }
    if (lettersInMyGroup.length != 1) return false;
    // If the puzzle is incomplete, disconnection is allowed
    if (!puzzle.complete) return true;
    // Only when complete: there should be exactly one group covering all my indices
    if (myGroups.length != 1) return false;
    return true;
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
    // Apply color to other members of the letter group
    for (var member in indices) {
      final memberValue = puzzle.getValue(member);
      if (memberValue == myOpposite) {
        return Move(member, myColor, this, isImpossible: this);
      }
      if (memberValue == 0) {
        return Move(member, myColor, this);
      }
    }
    final allGroups = puzzle.getGroups();
    final myGroupsJoined = allGroups
        .where((grp) => grp.toSet().intersection(indices.toSet()).isNotEmpty)
        .flattened;
    final neighborWithLetters = myGroupsJoined
        .map((idx) => puzzle.getNeighbors(idx))
        .flattened
        .where((nei) => otherLetters.contains(nei));
    // Apply opposite color to neighbors_with_letters
    for (var nei in neighborWithLetters) {
      final neiValue = puzzle.getValue(nei);
      if (neiValue == myColor) {
        return Move(nei, myOpposite, this, isImpossible: this);
      }
      if (neiValue == 0) {
        return Move(nei, myOpposite, this);
      }
    }
    // If not connected yet, find members that only have one empty neighbor
    final sameGroup = allGroups.where((grp) {
      return grp.toSet().intersection(indices.toSet()).length == indices.length;
    }).isNotEmpty;
    final Set<int> groupFreeNeighbors = {};
    for (var member in indices) {
      final memberGroup = allGroups.where((grp) => grp.contains(member)).first;
      for (var groupCell in memberGroup) {
        groupFreeNeighbors.addAll(
          puzzle
              .getNeighbors(groupCell)
              .where((idx) => puzzle.getValue(idx) == 0),
        );
      }
    }
    if (!sameGroup && groupFreeNeighbors.length == 1) {
      return Move(groupFreeNeighbors.first, myColor, this);
    }
    // Find cells that would create a conflict if set
    // We need to find all the neighbors of this letter group that
    // are also neighbor of another letter of the same color
    final otherSameColor = otherLetters.where(
      (idx) => puzzle.cellValues[idx] == myColor,
    );
    final otherGroups = allGroups
        .where(
          (grp) => grp.toSet().intersection(otherSameColor.toSet()).isNotEmpty,
        )
        .flattened;
    if (otherSameColor.isNotEmpty) {
      for (final groupFreeNeighbor in groupFreeNeighbors) {
        final neighborNeighborsWithOtherLetters = puzzle
            .getNeighbors(groupFreeNeighbor)
            .where((nei) => otherGroups.contains(nei));
        if (neighborNeighborsWithOtherLetters.isNotEmpty) {
          // We know that groupFreeNeighbor can't be myColor
          return Move(groupFreeNeighbor, myOpposite, this);
        }
      }
    }

    // Now, find if other members of the letter group are disconnected and raise
    var foundVGroup = false;
    for (var vgroup in puzzle.toVirtualGroups()) {
      final notInVgroup = indices.whereNot((member) => vgroup.contains(member));
      if (notInVgroup.isEmpty) {
        foundVGroup = true;
        break;
      }
    }
    if (!foundVGroup) {
      return Move(0, 0, this, isImpossible: this);
    }
    return null;
  }
}

class CannotApplyConstraint extends Error {
  CannotApplyConstraint(String message);
}
