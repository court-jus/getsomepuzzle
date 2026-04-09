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

  bool get isFree => value == 0 && options.isNotEmpty;

  bool get isPossible => value != 0 || options.isNotEmpty;

  /// Sets value and clears options — used by the solver/generator.
  bool setForSolver(int val) {
    if (value == val && options.isEmpty) return false;
    value = val;
    options = [];
    return true;
  }

  Cell clone() {
    final c = Cell(0, idx, domain, readonly);
    c.value = value;
    c.options = options.toList();
    return c;
  }
}

class Move {
  int idx;
  int value;
  Constraint givenBy;
  Constraint? isImpossible;
  bool isForce;

  Move(
    this.idx,
    this.value,
    this.givenBy, {
    this.isImpossible,
    this.isForce = false,
  });
}
