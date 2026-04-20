import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

class GroupCountConstraint extends Constraint {
  @override
  String get slug => 'GC';

  int color = 0;
  int count = 0;

  GroupCountConstraint(String strParams) {
    final params = strParams.split(".");
    color = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'GC:$color.$count';

  @override
  String toString() {
    return "$color = $count groups";
  }

  @override
  String toHuman(Puzzle puzzle) {
    return "$count groups of color $color";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final maxCount = (width * height / 2).ceil();
    final List<String> result = [];
    for (int count = 1; count <= maxCount; count++) {
      for (final value in domain) {
        result.add('$value.$count');
      }
    }
    return result;
  }

  int _getGroupCount(Puzzle puzzle) {
    return getColorGroups(puzzle, color).length;
  }

  @override
  bool verify(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);
    if (puzzle.complete) {
      return currentCount == count;
    }
    if (currentCount > count) {
      final reachable = _safeReachableCountsByMerges(puzzle);
      if (reachable != null) {
        if (!reachable.contains(count)) return false;
      } else if (calculateMinGroups(puzzle, color) > count) {
        return false;
      }
    }
    if (currentCount < count) {
      // Look for free cells where we could put a 'color' cell without
      // merging into an existing group
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.length + currentCount < count) {
        return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);

    if (currentCount > count) {
      final reachable = _safeReachableCountsByMerges(puzzle);
      if (reachable != null) {
        if (!reachable.contains(count)) {
          return Move(0, 0, this, isImpossible: this);
        }
      } else if (calculateMinGroups(puzzle, color) > count) {
        return Move(0, 0, this, isImpossible: this);
      }
      // Force on a single direct merge-cell only if colouring it opposite
      // would make the target unreachable. The direct-merge enumeration
      // ignores multi-step paths through chains of free cells, which can
      // merge groups without going through the direct merge-cell.
      final mergeableCells = getCellsThatMergeColorGroups(puzzle, color);
      if (mergeableCells.length == 1) {
        final mergeCell = mergeableCells.first;
        final opposite = puzzle.domain.firstWhere((v) => v != color);
        final probe = puzzle.clone();
        probe.cells[mergeCell].setForSolver(opposite);
        if (calculateMinGroups(probe, color) > count) {
          return Move(mergeCell, color, this);
        }
      }
    }

    if (currentCount < count) {
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.length + currentCount < count) {
        return Move(0, 0, this, isImpossible: this);
      }
      if (candidates.length + currentCount == count && candidates.isNotEmpty) {
        // Every candidate would need to become its own isolated group for the
        // target to be reached. Two adjacent candidates coloured together
        // merge into one group, so any adjacency among candidates makes the
        // target unreachable.
        if (_candidatesHaveAdjacency(puzzle, candidates)) {
          return Move(0, 0, this, isImpossible: this);
        }
        return Move(candidates.first, color, this);
      }
    }

    if (currentCount == count && !puzzle.complete) {
      final opposite = puzzle.domain.firstWhereOrNull((c) => c != color)!;
      final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
      if (candidates.isEmpty) {
        // Candidate set is monotone decreasing: empty now means empty
        // forever, so no new group can ever form. Colouring a merge-cell
        // would drop the count below target with no way to compensate, so
        // every merge-cell must be opposite.
        final forcedCells = getCellsThatMergeColorGroups(puzzle, color);
        if (forcedCells.isNotEmpty) {
          return Move(forcedCells.first, opposite, this);
        }
      } else {
        // Simulation-based probe: for each candidate, simulate colouring
        // it with `color`. In the resulting state the group count is
        // currentCount + 1 (a new isolated group appeared). To recover
        // the target we'd need merges. If even the minimum achievable
        // count in the new state exceeds the target, the target is
        // unreachable → force the candidate to opposite.
        //
        // We use `calculateMinGroups` (flood-fill via free-or-same-color
        // cells) rather than enumerating direct merge-cells, because the
        // new state may require multi-step merges through intermediate
        // free cells.
        for (final cand in candidates) {
          final clone = puzzle.clone();
          clone.cells[cand].setForSolver(color);
          if (calculateMinGroups(clone, color) > count) {
            return Move(cand, opposite, this);
          }
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final currentCount = _getGroupCount(puzzle);
    if (currentCount != count) return false;
    final candidates = getFreeCellsWithoutNeighborColor(puzzle, color);
    // Candidate set is monotone decreasing: an empty set now stays empty
    // forever, so no new group can ever form. Otherwise future play could
    // raise the count above target and apply() would fire.
    if (candidates.isNotEmpty) return false;
    // calculateMinGroups is monotone increasing (flood-fill reachability
    // through free-or-same-color cells only shrinks as cells are coloured),
    // so minGroups == currentCount now guarantees the count stays at target
    // forever. It also implies that no merge-cell exists now or can appear
    // later, so apply() will never fire again.
    return calculateMinGroups(puzzle, color) == currentCount;
  }

  /// True iff at least two candidates are adjacent cells in the grid.
  /// Used to detect cases where colouring all candidates as `color` would
  /// produce fewer groups than `candidates.length` (merged into one).
  bool _candidatesHaveAdjacency(Puzzle puzzle, List<int> candidates) {
    final set = candidates.toSet();
    for (final idx in candidates) {
      for (final nei in puzzle.getNeighbors(idx)) {
        if (set.contains(nei)) return true;
      }
    }
    return false;
  }

  /// Returns the enumerated reachable-counts set *only* when it is safe
  /// to use (every mergeable pair of groups has a direct merge-cell, so
  /// the direct-merge enumeration captures every possible partition).
  ///
  /// If some pair of groups can only be merged via a multi-step flood-fill
  /// path (no single free cell is adjacent to both), the direct-merge
  /// enumeration would under-count reachable partitions and falsely flag
  /// valid states as impossible — so we return `null` and callers fall
  /// back to the weaker `calculateMinGroups > target` check.
  Set<int>? _safeReachableCountsByMerges(Puzzle puzzle) {
    if (!_mergesAreDirectOnly(puzzle)) return null;
    return _reachableCountsByMerges(puzzle);
  }

  /// True iff every mergeable pair of groups (via flood-fill through
  /// free-or-same-color cells) has at least one direct merge-cell — a
  /// free cell adjacent to a member of each group. When this holds, the
  /// direct-merge enumeration captures all reachable partitions.
  bool _mergesAreDirectOnly(Puzzle puzzle) {
    final groups = getColorGroups(puzzle, color);
    for (int i = 0; i < groups.length; i++) {
      for (int j = i + 1; j < groups.length; j++) {
        if (!canMergeGroups(puzzle, groups[i], groups[j])) continue;
        final setI = groups[i].toSet();
        final setJ = groups[j].toSet();
        bool found = false;
        for (int idx = 0; idx < puzzle.cellValues.length; idx++) {
          if (puzzle.cellValues[idx] != 0) continue;
          final neighbors = puzzle.getNeighbors(idx);
          final adjI = neighbors.any(setI.contains);
          final adjJ = neighbors.any(setJ.contains);
          if (adjI && adjJ) {
            found = true;
            break;
          }
        }
        if (!found) return false;
      }
    }
    return true;
  }

  /// Enumerate the set of group counts reachable from `puzzle`'s current
  /// state by colouring any subset of current merge-cells with `color`.
  ///
  /// Each merge-cell acts as a hyperedge over the set of group indices it
  /// touches; colouring a subset of these cells amounts to union-finding
  /// those group indices. The reachable count is the number of remaining
  /// distinct components.
  ///
  /// Returns `null` when there are too many merge-cells to enumerate
  /// (2^k would blow up); callers should fall back to weaker checks.
  ///
  /// **Not safe to call directly** on states with multi-step merges —
  /// use `_safeReachableCountsByMerges` instead, which guards against
  /// that case.
  Set<int>? _reachableCountsByMerges(Puzzle puzzle) {
    final groups = getColorGroups(puzzle, color);
    final n = groups.length;
    if (n == 0) return {0};

    final cellToGroup = <int, int>{};
    for (int gi = 0; gi < n; gi++) {
      for (final cell in groups[gi]) {
        cellToGroup[cell] = gi;
      }
    }

    final mergeableCells = getCellsThatMergeColorGroups(puzzle, color);
    final cellGroupSets = <List<int>>[];
    for (final mc in mergeableCells) {
      final adj = <int>{};
      for (final nei in puzzle.getNeighbors(mc)) {
        final gi = cellToGroup[nei];
        if (gi != null) adj.add(gi);
      }
      cellGroupSets.add(adj.toList());
    }

    final k = cellGroupSets.length;
    if (k == 0) return {n};
    // 2^k enumeration: guard against combinatorial explosion.
    if (k > 15) return null;

    final reachable = <int>{};
    for (int mask = 0; mask < (1 << k); mask++) {
      final parent = List<int>.generate(n, (i) => i);
      int find(int x) {
        var root = x;
        while (parent[root] != root) {
          root = parent[root];
        }
        var cur = x;
        while (parent[cur] != root) {
          final next = parent[cur];
          parent[cur] = root;
          cur = next;
        }
        return root;
      }

      for (int i = 0; i < k; i++) {
        if ((mask >> i) & 1 == 0) continue;
        final adj = cellGroupSets[i];
        final pa = find(adj[0]);
        for (int j = 1; j < adj.length; j++) {
          final pb = find(adj[j]);
          if (pa != pb) parent[pb] = pa;
        }
      }
      final roots = <int>{};
      for (int i = 0; i < n; i++) {
        roots.add(find(i));
      }
      reachable.add(roots.length);
    }
    return reachable;
  }
}
