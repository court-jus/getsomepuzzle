import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Per-puzzle context shared by every candidate classification.
///
/// Built once at the start of a hint-computation pass and reused for
/// every `(slug, param)` pair the registry produces, so we don't
/// re-clone the puzzle or re-walk `cachedSolution` on every candidate.
class HintContext {
  /// The original puzzle in its current player state. Cloned per
  /// candidate before any mutation.
  final Puzzle puzzle;

  /// Serialized form of constraints already present on [puzzle]. A
  /// candidate matching one of these is a no-op and is skipped.
  final Set<String> existingSerialized;

  /// Indices of read-only (pre-filled) cells. Passed to
  /// `generateAllParameters` so candidate enumeration can avoid
  /// targeting cells the player cannot reason about.
  final Set<int> readonlyIndices;

  /// A pre-solved instance used to verify candidate constraints
  /// against the canonical solution before paying the cost of a
  /// full `clone().solve()` pass.
  final Puzzle solved;

  HintContext._(
    this.puzzle,
    this.existingSerialized,
    this.readonlyIndices,
    this.solved,
  );

  factory HintContext.forPuzzle(Puzzle puzzle) {
    final existing = puzzle.constraints.map((c) => c.serialize()).toSet();
    final readonly = <int>{};
    for (int i = 0; i < puzzle.cells.length; i++) {
      if (puzzle.cells[i].readonly) readonly.add(i);
    }
    final solved = Puzzle.empty(puzzle.width, puzzle.height, puzzle.domain);
    for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
      solved.cells[i].setForSolver(puzzle.cachedSolution![i]);
    }
    return HintContext._(puzzle, existing, readonly, solved);
  }
}

/// Decide whether the constraint described by `(slug, param)` is a
/// valid additional hint for [ctx.puzzle]. Returns the serialized
/// form on success, `null` if the candidate is invalid, already
/// present, useless (`isCompleteFor`), or doesn't preserve solvability.
///
/// Pure / side-effect-free aside from cloning [ctx.puzzle]. Safe to
/// call from an isolate or the main event loop.
String? classifyHintCandidate(HintContext ctx, String slug, String param) {
  final constraint = createConstraint(slug, param);
  if (constraint == null) return null;
  final serialized = constraint.serialize();
  if (ctx.existingSerialized.contains(serialized)) return null;
  if (!constraint.verify(ctx.solved)) return null;
  final clone = ctx.puzzle.clone();
  if (constraint.isCompleteFor(clone)) return null;
  clone.addConstraint(constraint);
  if (!clone.solve()) return null;
  if (!constraint.verify(clone)) return null;
  return serialized;
}
