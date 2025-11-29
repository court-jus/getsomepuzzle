import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class GroupSize extends CellsCentricConstraint {
  int size = 0;

  GroupSize(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
    size = int.parse(strParams.split(".")[1]);
  }

  @override
  String toString() {
    return size.toString();
  }

  @override
  String toHuman() {
    final idx = indices.first;
    return "${idx + 1} = $size";
  }

  @override
  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
    final fgcolor = isHighlighted ? Colors.deepPurple : (isValid ? defaultColor : Colors.redAccent);
    return SizedBox(
      width: cellSize / count,
      height: cellSize / count,
      child: Center(
        child: Text(
          toString(),
          style: TextStyle(fontSize: cellSize * cellSizeToFontSize / count, color: fgcolor),
        ),
      ),
    );
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
      return myGroup.length <= size;
    }
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = puzzle.getGroups();
    final idx = indices[0];
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return null;
    final myColor = puzzle.cellValues[myGroup.first];
    final myOpposite = puzzle.domain.whereNot((v) => v == myColor).first;
    if (myGroup.length == size) {
      // My group is finished, we can fill the neighbors
      for (var member in myGroup) {
        final freeNeighbors = puzzle.getNeighbors(member).where((nei) => puzzle.cellValues[nei] == 0);
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
        groupFreeNeighbors.addAll(puzzle.getNeighbors(member).where((idx) => puzzle.getValue(idx) == 0));
      }
      if (groupFreeNeighbors.length == 1) {
        return Move(groupFreeNeighbors.first, myColor, this);
      }
    }
    return null;
  }
}

class LetterGroup extends CellsCentricConstraint {
  String letter = "";

  LetterGroup(String strParams) {
    final params = strParams.split(".");
    letter = params.removeAt(0);
    indices = params.map((e) => int.parse(e)).toList();
  }

  @override
  String toHuman() {
    final hIndices = indices.map((i) => i + 1);
    return "$hIndices = $letter";
  }

  @override
  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
    final fgcolor = isHighlighted ? Colors.deepPurple : (isValid ? defaultColor : Colors.redAccent);
    return SizedBox(
      width: cellSize / count,
      height: cellSize / count,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(fontSize: cellSize * cellSizeToFontSize / count, color: fgcolor),
        ),
      ),
    );
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
    // There should be only one group that covers all my indices
    if (myGroups.length != 1) return false;
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
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myColors = indices.map((idx) => puzzle.getValue(idx)).where((value) => value != 0);
    if (myColors.isEmpty) return null;
    final myColor = myColors.first;
    final otherLetters = puzzle.constraints.whereType<LetterGroup>().where((c) => c.letter != letter).map((c) => c.indices).flattenedToList;
    final neighborWithLetters = indices.map((idx) => puzzle.getNeighbors(idx)).flattened.where((nei) => otherLetters.contains(nei));
    final myOpposite = puzzle.domain.whereNot((v) => v == myColor).first;
    // Apply opposite color to neighbors_with_letters
    for(var nei in neighborWithLetters) {
      final neiValue = puzzle.getValue(nei);
      if (neiValue == myColor) {
        return Move(nei, myOpposite, this, isImpossible: this);
      }
      if (neiValue == 0) {
        return Move(nei, myOpposite, this);
      }
    }
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
    // If not connected yet, find members that only have one empty neighbor
    final allGroups = puzzle.getGroups();
    final sameGroup = allGroups.where(
      (grp) {
        return grp.toSet().intersection(indices.toSet()).length == indices.length;
      }
    ).isNotEmpty;
    if (!sameGroup) {
      for (var member in indices) {
        final memberGroup = allGroups.where((grp) => grp.contains(member)).first;
        final Set<int> groupFreeNeighbors = {};
        for (var groupCell in memberGroup) {
          groupFreeNeighbors.addAll(puzzle.getNeighbors(groupCell).where((idx) => puzzle.getValue(idx) == 0));
        }
        if (groupFreeNeighbors.length == 1) {
          return Move(groupFreeNeighbors.first, myColor, this);
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
