import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
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
  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
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
    if (myGroup == null) return false;
    return myGroup.length == size;
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
  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
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
}
