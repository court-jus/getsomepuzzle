import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// GS + (anything) complicity. For each `GroupSize` constraint we
/// enumerate every way to seal off a connected group of exactly
/// `gs.size` cells around the anchor (including merges with
/// same-colour cells reached via the added cells), drop the
/// sealings that violate **any** constraint of the puzzle (FMs,
/// other GSs, parity, symmetry, …), and force every cell whose
/// role (in-group / sealed) is identical across all surviving
/// sealings.
///
/// Anchor handling has two branches:
/// 1. **Coloured anchor** — usual case. Survivors are sealings of
///    the anchor's group; partial determination forces unanimous
///    cells.
/// 2. **Empty anchor** — try each domain colour. If only one
///    colour admits any surviving sealing, the anchor is forced to
///    that colour. (Other deductions cascade once the anchor is
///    coloured.)
class GSAllComplicity extends Complicity {
  /// Cap on `gs.size - |currentGroup|` — limits combinatorial cost.
  /// With merges the real number of decisions is often much smaller.
  static const int _maxGap = 6;

  @override
  String serialize() => "GSAllComplicity";

  @override
  bool isPresent(Puzzle puzzle) {
    return puzzle.constraints.whereType<GroupSize>().isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    for (final gs in puzzle.constraints.whereType<GroupSize>()) {
      final move = _solveGS(gs, puzzle);
      if (move != null) return move;
    }
    return null;
  }

  Move? _solveGS(GroupSize gs, Puzzle puzzle) {
    final anchor = gs.indices.first;
    final c = puzzle.cellValues[anchor];
    if (c != 0) {
      final survivors = _enumerateForColor(puzzle, gs, anchor, c);
      if (survivors == null) return null;
      if (survivors.isEmpty) return Move(0, 0, this, isImpossible: this);
      return _forceFromSurvivors(puzzle, survivors, c);
    }

    // Empty anchor: try each domain colour.
    final feasible = <int>[];
    for (final color in puzzle.domain) {
      final hyp = puzzle.clone();
      hyp.cells[anchor].setForSolver(color);
      final survivors = _enumerateForColor(hyp, gs, anchor, color);
      if (survivors == null) {
        // Gap too big to enumerate — assume feasible (don't risk a
        // false force).
        feasible.add(color);
      } else if (survivors.isNotEmpty) {
        feasible.add(color);
      }
    }
    if (feasible.isEmpty) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (feasible.length == 1) {
      // Tier 4: trying both colours and concluding only one works
      // is a step harder than the coloured-anchor case (per
      // docs/dev/constraint_complicity.md).
      return Move(anchor, feasible.first, this, complexity: 4);
    }
    return null;
  }

  /// Returns the list of surviving sealings for the given anchor
  /// colour, or null when the gap is too large to enumerate.
  List<_Survivor>? _enumerateForColor(
    Puzzle puzzle,
    GroupSize gs,
    int anchor,
    int color,
  ) {
    final group = _floodFill(puzzle, anchor, color);
    if (group.length > gs.size) return [];
    if (group.length == gs.size) {
      return _checkSealedTarget(puzzle, group, color);
    }
    final gap = gs.size - group.length;
    if (gap > _maxGap) return null;

    final survivors = <_Survivor>[];
    final opposite = puzzle.domain.firstWhere((v) => v != color);
    _enumerate(puzzle, group, <int>{}, gs.size, color, (g, s) {
      final clone = puzzle.clone();
      for (final idx in g) {
        if (puzzle.cellValues[idx] == 0) clone.cells[idx].setForSolver(color);
      }
      for (final idx in s) {
        if (puzzle.cellValues[idx] == 0) {
          clone.cells[idx].setForSolver(opposite);
        }
      }
      for (final cst in puzzle.constraints) {
        if (!cst.verify(clone)) return;
      }
      survivors.add(_Survivor(g, s));
    });
    return survivors;
  }

  /// Group already at target size — verify that sealing the frontier
  /// is consistent. Returns a single survivor or empty.
  List<_Survivor> _checkSealedTarget(Puzzle puzzle, Set<int> group, int color) {
    final opposite = puzzle.domain.firstWhere((v) => v != color);
    final sealed = <int>{};
    for (final m in group) {
      for (final nei in puzzle.getNeighbors(m)) {
        if (group.contains(nei)) continue;
        if (puzzle.cellValues[nei] != 0) continue;
        sealed.add(nei);
      }
    }
    final clone = puzzle.clone();
    for (final idx in sealed) {
      clone.cells[idx].setForSolver(opposite);
    }
    for (final cst in puzzle.constraints) {
      if (!cst.verify(clone)) return [];
    }
    return [_Survivor(group, sealed)];
  }

  Move? _forceFromSurvivors(Puzzle puzzle, List<_Survivor> survivors, int c) {
    final candidates = <int>{};
    for (final s in survivors) {
      for (final idx in s.group) {
        if (puzzle.cellValues[idx] == 0) candidates.add(idx);
      }
      for (final idx in s.sealed) {
        if (puzzle.cellValues[idx] == 0) candidates.add(idx);
      }
    }
    final opposite = puzzle.domain.firstWhere((v) => v != c);
    for (final idx in candidates) {
      bool allInGroup = true;
      bool allInSealed = true;
      for (final s in survivors) {
        if (!s.group.contains(idx)) allInGroup = false;
        if (!s.sealed.contains(idx)) allInSealed = false;
        if (!allInGroup && !allInSealed) break;
      }
      if (allInGroup) return Move(idx, c, this, complexity: 3);
      if (allInSealed) return Move(idx, opposite, this, complexity: 3);
    }
    return null;
  }

  /// Recursive sealing enumeration: at each step, pick the canonical
  /// (lowest-indexed) free cell adjacent to the current `group` and
  /// not yet sealed, then branch on whether it joins the group
  /// (with same-colour merges flooded in) or gets sealed. A branch
  /// terminates as soon as the group reaches the target size — every
  /// remaining frontier cell is auto-sealed.
  static void _enumerate(
    Puzzle puzzle,
    Set<int> group,
    Set<int> sealed,
    int target,
    int c,
    void Function(Set<int>, Set<int>) callback,
  ) {
    if (group.length > target) return;

    final frontier = <int>{};
    for (final m in group) {
      for (final nei in puzzle.getNeighbors(m)) {
        if (group.contains(nei)) continue;
        if (puzzle.cellValues[nei] != 0) continue;
        if (sealed.contains(nei)) continue;
        frontier.add(nei);
      }
    }

    if (group.length == target) {
      callback(group, {...sealed, ...frontier});
      return;
    }

    if (frontier.isEmpty) return;

    int pick = frontier.first;
    for (final f in frontier) {
      if (f < pick) pick = f;
    }

    final newGroup = _addWithMerges(puzzle, group, pick, c);
    _enumerate(puzzle, newGroup, sealed, target, c, callback);

    final newSealed = {...sealed, pick};
    _enumerate(puzzle, group, newSealed, target, c, callback);
  }

  /// Add [newCell] to [group], then flood-fill through every
  /// already-coloured `c`-cell reachable from [newCell] (merging
  /// previously-disconnected same-colour groups into one).
  static Set<int> _addWithMerges(
    Puzzle puzzle,
    Set<int> group,
    int newCell,
    int c,
  ) {
    final result = {...group, newCell};
    final queue = <int>[newCell];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final nei in puzzle.getNeighbors(cur)) {
        if (result.contains(nei)) continue;
        if (puzzle.cellValues[nei] == c) {
          result.add(nei);
          queue.add(nei);
        }
      }
    }
    return result;
  }

  /// All cells of colour [colour] connected (4-adjacency) to [seed].
  static Set<int> _floodFill(Puzzle puzzle, int seed, int colour) {
    final result = <int>{seed};
    final queue = <int>[seed];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final nei in puzzle.getNeighbors(cur)) {
        if (puzzle.cellValues[nei] != colour) continue;
        if (result.add(nei)) queue.add(nei);
      }
    }
    return result;
  }
}

class _Survivor {
  final Set<int> group;
  final Set<int> sealed;
  _Survivor(this.group, this.sealed);
}
