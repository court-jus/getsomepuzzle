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

import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Enumerates up to [limit] valid completions of [puzzle] by exhaustive
/// backtracking over free cells. Each completion is returned as a list
/// of cell values in cell-index order.
///
/// Used for uniqueness verification: pass `limit: 2` and inspect the
/// result — `length == 1` ⇒ deductively unique, `length >= 2` ⇒
/// ambiguous.
List<List<CellValue>> enumerateSolutions(Puzzle puzzle, {int limit = 2}) {
  final out = <List<CellValue>>[];
  _backtrack(
    puzzle,
    propagate: false,
    onSolution: (solved) {
      out.add(List<CellValue>.from(solved.cellValues));
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
/// `solution` is `null`. The returned [timedOut] distinguishes a search
/// aborted by the deadline (`true`) from one that genuinely exhausted the
/// tree without a completion (`false`); it is only meaningful when
/// `solution == null`. Callers use it to separate routing-timeout from
/// routing-infeasibility (see `preFillPath` instrumentation).
({List<CellValue>? solution, bool timedOut}) findOneSolutionByDpll(
  Puzzle puzzle, {
  int? timeoutMs,
}) {
  final deadline = timeoutMs != null
      ? DateTime.now().add(Duration(milliseconds: timeoutMs))
      : null;
  List<CellValue>? result;
  _backtrack(
    puzzle,
    propagate: true,
    deadline: deadline,
    onSolution: (solved) {
      result = List<CellValue>.from(solved.cellValues);
      return false; // stop at the first solution
    },
  );
  // A null result past the deadline means the search was cut short by the
  // timeout rather than proving infeasibility.
  final timedOut =
      result == null && deadline != null && DateTime.now().isAfter(deadline);
  return (solution: result, timedOut: timedOut);
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
    // consistency below in either case. The deadline is forwarded as a
    // `shouldStop` so a single propagation pass can't overrun the routing
    // budget: without it the deadline is only checked between backtrack
    // nodes, and one `solve()` on a large 3-colour grid can run for tens of
    // seconds past a 3 s budget.
    puzzle.solve(
      shouldStop: deadline == null
          ? null
          : () => DateTime.now().isAfter(deadline),
    );
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
  // Branch over the cell's remaining options, not the full puzzle domain: in a
  // 3-colour domain a free cell can keep a strict subset of the domain after
  // pruning, and setValue throws on an out-of-options value. (In 2 colours a
  // single-option cell is force-set before branching, so options == domain for
  // every free cell — this is a no-op there.)
  for (final v in puzzle.cells[freeIdx].options) {
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

/// First free cell, or `-1` if every cell is set.
int _firstFreeCell(Puzzle puzzle) {
  for (int i = 0; i < puzzle.cells.length; i++) {
    if (puzzle.cells[i].value == CellValue.free) return i;
  }
  return -1;
}
