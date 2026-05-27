import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Per-puzzle context shared by every candidate evaluation.
///
/// Built once at the start of a hint-computation pass and reused for
/// every `(slug, param)` pair the registry produces, so we don't
/// re-walk `cachedSolution` or re-solve the baseline on every candidate.
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
  /// against the canonical solution — we never offer a constraint that
  /// the puzzle's own solution would violate.
  final Puzzle solved;

  /// Player-effort weight of the deduction trace that solves [puzzle]
  /// from its current state (see [Puzzle.traceEffort]). A candidate is
  /// "helpful" when adding it lowers this value — i.e. it simplifies the
  /// remaining resolution.
  final int baselineEffort;

  HintContext._(
    this.puzzle,
    this.existingSerialized,
    this.readonlyIndices,
    this.solved,
    this.baselineEffort,
  );

  factory HintContext.forPuzzle(Puzzle puzzle) {
    final existing = puzzle.constraints.map((c) => c.serialize()).toSet();
    final readonly = <int>{};
    for (int i = 0; i < puzzle.cells.length; i++) {
      if (puzzle.cells[i].readonly) readonly.add(i);
    }
    // Clone the puzzle (so its constraints are attached, hence
    // `cellConstraints` is populated) and force every cell to the canonical
    // solution. The constraints are needed so a candidate's compatibility with
    // the *existing* constraints can be checked — e.g. two LT letters that
    // cannot share a cell/group, a conflict invisible on a constraint-free grid.
    final solved = puzzle.clone();
    for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
      solved.cells[i].setForSolver(puzzle.cachedSolution![i]);
    }
    return HintContext._(
      puzzle,
      existing,
      readonly,
      solved,
      puzzle.traceEffort(),
    );
  }
}

/// Whether `(slug, param)` is a *valid* additional constraint to offer: it
/// parses, isn't already present, isn't already trivially satisfied, and is
/// *compatible* with the constraints already on the puzzle. Returns the
/// constraint instance on success (so the caller can reuse it), or null.
Constraint? validHintCandidate(HintContext ctx, String slug, String param) {
  final constraint = createConstraint(slug, param);
  if (constraint == null) return null;
  if (ctx.existingSerialized.contains(constraint.serialize())) return null;
  if (constraint.isCompleteFor(ctx.puzzle)) return null;
  // The canonical solution, carrying every existing constraint PLUS this
  // candidate, must still satisfy all of them. This subsumes a plain
  // `verify(solved)` check and additionally catches inter-constraint
  // incompatibilities invisible to a verify-in-isolation — e.g. two LT letters
  // that cannot coexist on the same cell/group (the conflict lives in
  // `LetterGroup.verify`, which reads `cellConstraints`).
  final probe = ctx.solved.clone();
  probe.addConstraint(constraint);
  // No-op candidate: it leaves the constraint set unchanged — e.g. an LT
  // permutation that merges into an existing same-letter group without adding
  // a cell (escapes the exact-serialize dedup above), or a plain duplicate.
  // Offering it would claim "constraint added" while nothing changes.
  final probeSerialized = probe.constraints.map((c) => c.serialize()).toSet();
  if (probeSerialized.length == ctx.existingSerialized.length &&
      probeSerialized.containsAll(ctx.existingSerialized)) {
    return null;
  }
  if (probe.check(saveResult: false).isNotEmpty) return null;
  return constraint;
}

/// Pick a single constraint to offer as an `addConstraint` hint.
///
/// Strategy: enumerate the registry (roughly simplest type first), shuffling
/// each type's parameter list. For every *valid* candidate, check whether
/// adding it lowers the remaining-trace effort ([HintContext.baselineEffort]).
///
/// - Returns the **first candidate that reduces the effort** (early stop —
///   the common, cheap case): it makes a hard deduction simpler for the
///   player, and being early in registry order it's also an easy-to-grasp
///   constraint type.
/// - If no candidate reduces the effort, returns a **random valid candidate**
///   as a fallback — never leave the player with nothing; an extra valid
///   constraint can still open different deduction paths.
/// - Returns null only when no valid candidate exists at all.
///
/// [shouldStop] aborts the pass (cancellation) → returns null. [yieldEvery]
/// is awaited periodically so the web (main-thread) path stays responsive;
/// the native isolate path passes neither.
Future<String?> pickHintConstraint(
  HintContext ctx, {
  bool Function()? shouldStop,
  Future<void> Function()? yieldEvery,
}) async {
  final valid = <String>[];
  int evaluated = 0;
  for (final entry in constraintRegistry) {
    final params = entry.generateAllParameters(
      ctx.puzzle.width,
      ctx.puzzle.height,
      ctx.puzzle.domain,
      ctx.readonlyIndices,
    )..shuffle();
    for (final param in params) {
      if (shouldStop?.call() == true) return null;
      final constraint = validHintCandidate(ctx, entry.slug, param);
      if (constraint == null) continue;
      valid.add(constraint.serialize());

      // Expensive part: does adding this constraint simplify the rest of the
      // resolution? Worst case enumerates everything — accepted; only runs on
      // explicit hint request.
      final test = ctx.puzzle.clone();
      test.addConstraint(constraint);
      if (test.traceEffort() < ctx.baselineEffort) {
        return constraint.serialize();
      }

      evaluated++;
      if (yieldEvery != null && evaluated % 10 == 0) await yieldEvery();
    }
  }
  if (valid.isEmpty) return null;
  return valid[Random().nextInt(valid.length)];
}
