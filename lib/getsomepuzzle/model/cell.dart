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
      throw ArgumentError(
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
    // Mirror `removeOption`: collapse to the lone survivor so the solver
    // never leaves a cell in the degenerate `value == free, options == [x]`
    // state. Without this the CLI solver (`bin/solve.dart`) would disagree
    // with the in-app solver on completion for the same move stream, and a
    // `DifferentFrom.verify` of two free singleton cells would miss the
    // unreachable case.
    if (options.length == 1) {
      value = options.first;
      options = [];
    }
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

/// A deduction produced by a constraint, complicity or the solver. Its three
/// mutually-exclusive effects are modelled as sealed subtypes:
///
/// * [SetValue]     — assign a definitive colour to a cell.
/// * [RemoveOption] — prune one colour from a still-free cell's options.
/// * [Impossible]   — the current state contradicts [givenBy].
///
/// Consumers pattern-match the subtype. Constructed only through the
/// subtype constructors ([SetValue], [RemoveOption], [Impossible]).
///
/// The `idx` / `value` / `removeOption` / `isImpossible` / `isForce` /
/// `forceDepth` / `complexity` getters below are a thin read-only accessor
/// API over the subtypes, used mainly by tests; production code switches on
/// the subtype instead.
sealed class Move {
  final CanApply givenBy;
  final List<CanApply> contributors;
  const Move._(this.givenBy, {this.contributors = const []});

  int get idx => switch (this) {
    SetValue(:final idx) => idx,
    RemoveOption(:final idx) => idx,
    Impossible() => 0,
  };
  CellValue? get value => switch (this) {
    SetValue(:final value) => value,
    _ => null,
  };
  CellValue? get removeOption => switch (this) {
    RemoveOption(:final option) => option,
    _ => null,
  };
  CanApply? get isImpossible => this is Impossible ? givenBy : null;
  bool get isForce => switch (this) {
    RemoveOption(:final isForce) => isForce,
    _ => false,
  };
  int get forceDepth => switch (this) {
    RemoveOption(:final forceDepth) => forceDepth,
    _ => 0,
  };
  int get complexity => switch (this) {
    SetValue(:final complexity) => complexity,
    RemoveOption(:final complexity) => complexity,
    Impossible() => 0,
  };

  /// A copy of this move re-attributed to [by] instead of [givenBy], keeping
  /// every other field. Used by complicities to tag a deduction with the
  /// specific blocker constraint surfaced in the hint UI.
  Move retag(CanApply by) => switch (this) {
    SetValue(:final idx, :final value, :final complexity) => SetValue(
      idx,
      value,
      by,
      complexity: complexity,
      contributors: contributors,
    ),
    RemoveOption(
      :final idx,
      :final option,
      :final complexity,
      :final isForce,
      :final forceDepth,
    ) =>
      RemoveOption(
        idx,
        option,
        by,
        complexity: complexity,
        isForce: isForce,
        forceDepth: forceDepth,
        contributors: contributors,
      ),
    Impossible() => Impossible(by, contributors: contributors),
  };

  @override
  String toString() => switch (this) {
    SetValue(:final idx, :final value) => 'Move: Set $idx = $value ($givenBy)',
    RemoveOption(:final idx, :final option) =>
      'Move: Set $idx != $option ($givenBy)',
    Impossible() => 'Move impossible ($givenBy)',
  };
}

/// Assign a definitive colour to cell [idx]. [complexity] is the player-effort
/// tier of the deduction (0..5; 0 = trivial saturation, 5 = combinatorial
/// probing — see docs/dev/complexity.md).
final class SetValue extends Move {
  @override
  final int idx;
  @override
  final CellValue value;
  @override
  final int complexity;
  const SetValue(
    this.idx,
    this.value,
    super.givenBy, {
    this.complexity = 0,
    List<CanApply> contributors = const [],
  }) : super._(contributors: contributors);
}

/// Prune colour [option] from the still-free cell [idx]. Issued either by
/// ordinary propagation (with a [complexity] tier) or by forced deduction
/// ([isForce] true), in which case [forceDepth] is the length of the
/// propagation chain that exposed the contradiction (shorter = easier to
/// verify by hand). The two origins are mutually exclusive: a force move
/// always has `complexity == 0`, a propagation move `forceDepth == 0`.
final class RemoveOption extends Move {
  @override
  final int idx;
  final CellValue option;
  @override
  final int complexity;
  @override
  final bool isForce;
  @override
  final int forceDepth;
  const RemoveOption(
    this.idx,
    this.option,
    super.givenBy, {
    this.complexity = 0,
    this.isForce = false,
    this.forceDepth = 0,
    List<CanApply> contributors = const [],
  }) : super._(contributors: contributors);
}

/// The current state contradicts [givenBy] — either directly broken or with
/// future satisfaction now unreachable. Carries no cell target.
final class Impossible extends Move {
  const Impossible(super.givenBy, {List<CanApply> contributors = const []})
    : super._(contributors: contributors);
}
