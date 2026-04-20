import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';

class Cell {
  int value = 0;
  int idx = 0;
  List<int> domain = [];
  List<int> options = [];
  bool readonly = false;
  bool isHighlighted = false;

  /// Invoked whenever `value` or `options` change. Puzzle wires this to its
  /// group cache invalidation so that mutations via `puzzle.cells[i].setX`
  /// remain cache-safe even when they bypass Puzzle's own mutators.
  void Function()? onMutate;

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
    onMutate?.call();
    return true;
  }

  void reset() {
    value = 0;
    options = domain.toList();
    onMutate?.call();
  }

  bool get isFree => value == 0 && options.isNotEmpty;

  bool get isPossible => value != 0 || options.isNotEmpty;

  /// Sets value and clears options — used by the solver/generator.
  bool setForSolver(int val) {
    if (value == val && options.isEmpty) return false;
    value = val;
    options = [];
    onMutate?.call();
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
