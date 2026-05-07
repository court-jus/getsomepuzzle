import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';

enum CellValue { free, black, white, purple }

/// Every colour the engine knows about, in canonical order. Every concrete
/// puzzle domain is a prefix of this list. Used by the generator's
/// `--domain 3` mode and by the option-pruning machinery.
const fullDomain = [CellValue.black, CellValue.white, CellValue.purple];

/// 2-colour domain. *Must* stay equal to `fullDomain.sublist(0, 2)` — Dart
/// doesn't let us write that as a const expression (no const indexing of
/// a List), so the relationship is enforced by a `dart:test` assertion at
/// the bottom of this file's unit tests, not the type system.
const defaultDomain = [CellValue.black, CellValue.white];

class Cell {
  CellValue value = CellValue.free;
  int idx = 0;
  List<CellValue> domain = [];
  List<CellValue> options = [];
  bool readonly = false;
  bool isHighlighted = false;

  /// Invoked whenever `value` or `options` change. Puzzle wires this to its
  /// group cache invalidation so that mutations via `puzzle.cells[i].setX`
  /// remain cache-safe even when they bypass Puzzle's own mutators.
  void Function()? onMutate;

  Cell(this.value, this.idx, this.domain, this.readonly) {
    if (readonly) {
      options = [];
    } else {
      options = domain.toList();
    }
  }

  @override
  String toString() {
    return "${idx + 1} = ${value.name}";
  }

  bool setValue(CellValue newValue, {bool ignoreOptions = false}) {
    if (readonly) return false;
    if (value == newValue) return false;
    if (!options.contains(newValue) && !ignoreOptions) {
      throw RangeError(
        "Cell set to value $newValue which is not in its options : $options.",
      );
    }
    value = newValue;
    options = [];
    onMutate?.call();
    return true;
  }

  bool removeOption(CellValue option) {
    if (readonly) return false;
    if (!options.contains(option)) return false;
    options.remove(option);
    if (options.length == 1) {
      // Only one option remains, setValue
      value = options.first;
      options = [];
    }
    onMutate?.call();
    return true;
  }

  void reset() {
    value = CellValue.free;
    options = domain.toList();
    onMutate?.call();
  }

  bool get isFree => value == CellValue.free && options.isNotEmpty;

  bool get isPossible => value != CellValue.free || options.isNotEmpty;

  /// Sets value and clears options — used by the solver/generator.
  bool setForSolver(CellValue val) {
    if (value == val && options.isEmpty) return false;
    value = val;
    options = [];
    onMutate?.call();
    return true;
  }

  bool removeOptionForSolver(CellValue val) {
    if (!options.contains(val)) return false;
    options.remove(val);
    onMutate?.call();
    return true;
  }

  Cell clone() {
    final c = Cell(CellValue.free, idx, domain, readonly);
    c.value = value;
    c.options = options.toList();
    return c;
  }
}

CellValue cellRepresentationToValue(String cellRepresentation) {
  switch (cellRepresentation) {
    case "1":
      return CellValue.black;
    case "2":
      return CellValue.white;
    case "3":
      return CellValue.purple;
    default:
      return CellValue.free;
  }
}

String cellValueToString(CellValue value) {
  switch (value) {
    case CellValue.black:
      return "1";
    case CellValue.white:
      return "2";
    case CellValue.purple:
      return "3";
    default:
      return "0";
  }
}

class Move {
  int idx;
  CellValue? value;
  CellValue? removeOption;
  CanApply givenBy;
  CanApply? isImpossible;
  bool isForce;
  // For a force move, length of the propagation chain that exposed the
  // contradiction (shorter = easier for a human to verify). 0 for
  // propagation moves and for force moves whose refutation is immediate.
  int forceDepth;
  // Player-effort tier of this propagation deduction (0..5). 0 = trivial
  // saturation, 5 = combinatorial probing. See docs/dev/complexity.md for
  // the per-deduction inventory. Always 0 for force moves (scoring branches
  // on `isForce`).
  int complexity;

  @override
  String toString() {
    if (value != null) {
      return "Move: Set $idx = $value ($givenBy)";
    } else if (removeOption != null) {
      return "Move: Set $idx != $removeOption ($givenBy)";
    } else if (isImpossible != null) {
      return "Move isImpossible ($givenBy)";
    } else {
      return "Move bizarre";
    }
  }

  Move(
    this.idx,
    this.givenBy, {
    this.value,
    this.isImpossible,
    this.isForce = false,
    this.forceDepth = 0,
    this.complexity = 0,
    this.removeOption,
  });
}
