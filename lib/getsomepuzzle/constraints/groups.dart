import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class GroupSize extends CellCentricConstraint {
  int size = 0;

  GroupSize(String strParams) {
    idx = int.parse(strParams.split(".")[0]);
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
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return false;
    return myGroup.length == size;
  }
}
