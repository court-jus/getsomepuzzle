import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
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
  Widget toWidget(Color defaultColor) {
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
    return Text(toString(), style: TextStyle(fontSize: 36, color: fgcolor));
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
  Widget toWidget(Color defaultColor) {
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
    return Text(letter, style: TextStyle(fontSize: 36, color: fgcolor));
  }

  @override
  bool verify(Puzzle puzzle) {
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
    final lettersInMyGroup = myGroup.where((idx) {
      final constraintAtIdx = puzzle.cellConstraints[idx];
      if (constraintAtIdx == null) return false;
      if (constraintAtIdx is! LetterGroup) return false;
      return true;
    }).map((idx) => (puzzle.cellConstraints[idx] as LetterGroup).letter).toSet();
    if (lettersInMyGroup.length != 1) return false;
    return true;
  }
}