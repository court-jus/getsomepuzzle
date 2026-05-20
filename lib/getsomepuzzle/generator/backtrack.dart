// Backtracking primitives for the generator.
//
// Two flavours sharing a single recursive backbone (`_backtrack`):
//
// - [enumerateSolutions]: naïve check-then-recurse. Used when the input
//   puzzle is quasi-complete and the question is "how many distinct
//   completions exist?" (uniqueness verification). No propagation
//   between branches — that's the point, we want to explore every
//   leaf to count.
//
// - [findOneSolutionByDpll]: DPLL with unit propagation. Calls
//   `Puzzle.solve()` (propagation + force) at each node before
//   branching, leveraging the solver's intelligence (LetterGroup
//   articulation points, virtual groups, etc.). Used when the input
//   puzzle is quasi-empty (e.g. anchors + LT only in path-based
//   generation) and the question is "find any valid completion".
//
// The shared `_backtrack` uses cloning per branch (not mutate-then-
// untry) because `solve()` makes too many mutations to revert cheaply.
// The cost for the no-propagation case is negligible at the puzzle
// sizes we care about.

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Enumerates up to [limit] valid completions of [puzzle] by exhaustive
/// backtracking over free cells. Each completion is returned as a list
/// of cell values in cell-index order.
///
/// Used for uniqueness verification: pass `limit: 2` and inspect the
/// result — `length == 1` ⇒ deductively unique, `length >= 2` ⇒
/// ambiguous.
List<List<int>> enumerateSolutions(Puzzle puzzle, {int limit = 2}) {
  final out = <List<int>>[];
  _backtrack(
    puzzle,
    propagate: false,
    onSolution: (solved) {
      out.add(List<int>.from(solved.cellValues));
      return out.length < limit;
    },
  );
  return out;
}

/// Returns one valid completion of [puzzle] using DPLL with unit
/// propagation (calls `Puzzle.solve()` at each node before branching),
/// or `null` if none exists. The returned list is cell values in
/// cell-index order.
///
/// Designed for under-determined puzzles (most cells free, a few
/// constraints) — for example the partial puzzle built from anchors +
/// LT constraints during path-based pre-fill. Propagation between
/// branches makes the search tree manageable even on a quasi-empty
/// 7×7 grid.
///
/// If [timeoutMs] is set and elapses before a solution is found,
/// returns `null`.
List<int>? findOneSolutionByDpll(Puzzle puzzle, {int? timeoutMs}) {
  final deadline = timeoutMs != null
      ? DateTime.now().add(Duration(milliseconds: timeoutMs))
      : null;
  List<int>? result;
  _backtrack(
    puzzle,
    propagate: true,
    deadline: deadline,
    onSolution: (solved) {
      result = List<int>.from(solved.cellValues);
      return false; // stop at the first solution
    },
  );
  return result;
}

/// Shared backtracking backbone. Returns `true` to continue searching,
/// `false` to abort (propagated up the recursion).
///
/// - [propagate]: when `true`, runs `Puzzle.solve()` at each node
///   before branching (unit propagation à la DPLL).
/// - [onSolution]: called whenever a complete consistent state is
///   reached. Returns `true` to keep searching for more solutions,
///   `false` to stop immediately.
/// - [deadline]: optional wall-clock cutoff; once exceeded, the
///   recursion unwinds and returns the partial result already
///   accumulated by [onSolution].
bool _backtrack(
  Puzzle puzzle, {
  required bool propagate,
  required bool Function(Puzzle) onSolution,
  DateTime? deadline,
}) {
  if (deadline != null && DateTime.now().isAfter(deadline)) {
    return false;
  }
  if (propagate) {
    // `solve()` runs the propagation + force loop. It may complete the
    // puzzle, dead-end, or stop short of completion — we re-check
    // consistency below in either case.
    puzzle.solve();
  }
  if (puzzle.check(saveResult: false).isNotEmpty) {
    return true; // dead branch, keep searching elsewhere
  }
  if (puzzle.complete) {
    return onSolution(puzzle);
  }
  final freeIdx = _firstFreeCell(puzzle);
  if (freeIdx < 0) {
    // Should be unreachable: `complete` is false but no free cell? The
    // puzzle is in a strange state. Treat as dead branch.
    return true;
  }
  for (final v in puzzle.domain) {
    final branch = puzzle.clone();
    branch.cells[freeIdx].setValue(v);
    if (branch.check(saveResult: false).isNotEmpty) {
      // Immediate violation, skip without recursing.
      continue;
    }
    if (!_backtrack(
      branch,
      propagate: propagate,
      onSolution: onSolution,
      deadline: deadline,
    )) {
      return false;
    }
  }
  return true;
}

/// First cell whose value is `0` (free), or `-1` if every cell is set.
int _firstFreeCell(Puzzle puzzle) {
  for (int i = 0; i < puzzle.cells.length; i++) {
    if (puzzle.cells[i].value == 0) return i;
  }
  return -1;
}
