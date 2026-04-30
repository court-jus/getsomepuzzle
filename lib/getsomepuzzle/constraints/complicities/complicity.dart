import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// A complicity combines information from multiple constraints to make
/// deductions that no single constraint can make alone.
///
/// Complicities act as a second level in the propagation loop:
/// individual constraints are exhausted first (level 1), then
/// complicities are tried (level 2). If a complicity produces a move,
/// control returns to level 1.
abstract class Complicity extends CanApply {
  /// Whether this complicity is relevant for the given puzzle, i.e. the
  /// puzzle has the right combination of constraints. Called once at
  /// puzzle construction time so we don't pay the cost on every apply().
  bool isPresent(Puzzle puzzle);

  /// Try to deduce a move by combining constraints. Returns a [Move] if
  /// a cross-constraint deduction is found, null otherwise.
  @override
  Move? apply(Puzzle puzzle);
}
