import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';

class Cell {
  int value = 0;
  int idx = 0;
  List<int> domain = [];
  List<int> options = [];
  bool readonly = false;
  bool isHighlighted = false;

  Cell(this.value, this.idx, this.domain, this.readonly) {
    options = domain.toList();
  }

  @override
  String toString() {
    return "${idx + 1} = $value";
  }

  bool setValue(int newValue) {
    if (readonly) return false;
    if (value == newValue) return false;
    value = newValue;
    return true;
  }

  void reset() {
    value = 0;
    options = domain.toList();
  }
}

class Move {
  int idx;
  int value;
  Constraint givenBy;
  Constraint? isImpossible;

  Move(this.idx, this.value, this.givenBy, { this.isImpossible });
}