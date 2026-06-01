import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

class GroupCountConstraint extends Constraint {
  @override
  String get slug => 'GC';

  CellValue color = CellValue.free;
  int count = 0;

  @override
  Set<CellValue> get referencedColors => {color};

  GroupCountConstraint(String strParams) {
    final params = strParams.split(".");
    color = cellRepresentationToValue(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'GC:${cellValueToString(color)}.$count';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      GroupCountConstraint('${cellValueToString(color)}.$count');

  @override
  String toString() {
    return "${cellValueToString(color)} = $count groups";
  }

  @override
  String toHuman(Puzzle puzzle) {
    return "$count groups of color ${cellValueToString(color)}";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final maxCount = (width * height / 2).ceil();
    final List<String> result = [];
    for (int count = 1; count <= maxCount; count++) {
      for (final value in domain) {
        result.add('${cellValueToString(value)}.$count');
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
      if (_exceedingTargetIsImpossible(puzzle)) return false;
    }
    if (currentCount < count) {
      // Free cells where we could start a new 'color' group without merging
      // into an existing one. The helper is option-aware: a free cell with
      // `color` pruned can never become one, so it is not a candidate.
      final candidates = getFreeCellsThatCanStartNewColorGroup(
        puzzle,
        color,
      ).length;
      if (candidates + currentCount < count) {
        return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final currentCount = _getGroupCount(puzzle);

    if (currentCount > count) {
      if (_exceedingTargetIsImpossible(puzzle)) {
        return Impossible(this);
      }
      // Force on a single direct merge-cell only if colouring it opposite
      // would make the target unreachable. The direct-merge enumeration
      // ignores multi-step paths through chains of free cells, which can
      // merge groups without going through the direct merge-cell.
      final mergeableCells = getCellsThatMergeColorGroups(puzzle, color);
      if (mergeableCells.length == 1) {
        final mergeCell = mergeableCells.first;
        final anyOpposite = puzzle.domain.firstWhere((v) => v != color);
        final probe = puzzle.clone();
        probe.cells[mergeCell].setForSolver(anyOpposite);
        if (calculateMinGroups(probe, color) > count) {
          // Force the merge-cell to color. If color was already excluded
          // from its options (3-colour puzzles), the constraint cannot be
          // satisfied — neither merge nor non-merge keeps the count at
          // target.
          if (!puzzle.cells[mergeCell].options.contains(color)) {
            return Impossible(this);
          }
          return SetValue(mergeCell, color, this, complexity: 3);
        }
      }
    } else if (currentCount < count) {
      // Option-aware new-group candidates (see the verify-side filter): a
      // free cell pruned of `color` can never seed a new group, so it must
      // not inflate the count and mask a real impossibility.
      final candidates = getFreeCellsThatCanStartNewColorGroup(puzzle, color);
      if (candidates.length + currentCount < count) {
        return Impossible(this);
      }
      if (candidates.length + currentCount == count && candidates.isNotEmpty) {
        // Every candidate would need to become its own isolated group for the
        // target to be reached. Two adjacent candidates coloured together
        // merge into one group, so any adjacency among candidates makes the
        // target unreachable.
        if (_candidatesHaveAdjacency(puzzle, candidates)) {
          return Impossible(this);
        }
        // Candidates are already option-filtered; the head is therefore a
        // safe target for `value: color`.
        return SetValue(candidates.first, color, this, complexity: 3);
      }
    } else if (currentCount == count && !puzzle.complete) {
      // Option-aware: only cells that can still become `color` count as
      // able to start a new group. When this set is empty, no new group can
      // ever form (even if free cells remain, they have `color` pruned), so
      // every merge-cell must be forced to an opposite colour. Counting
      // pruned cells here would skip that deduction and route to the
      // simulation branch with nothing to find.
      final candidates = getFreeCellsThatCanStartNewColorGroup(puzzle, color);
      if (candidates.isEmpty) {
        // Candidate set is monotone decreasing: empty now means empty
        // forever, so no new group can ever form. Colouring a merge-cell
        // would drop the count below target with no way to compensate, so
        // every merge-cell must be an opposite color.
        final forcedCells = getCellsThatMergeColorGroups(puzzle, color);
        if (forcedCells.isNotEmpty) {
          for (var forcedCell in forcedCells) {
            if (puzzle.cells[forcedCell].options.contains(color)) {
              return RemoveOption(forcedCell, color, this, complexity: 3);
            }
          }
          // No forced cell still has `color` in options — every merge-cell
          // already can't take this colour, so the count is locked at target.
          // Constraint satisfied, nothing more to do. (Same domain-3 trap as
          // SH Level 2 and the base_line_constraint == count branch.)
          return null;
        }
      } else {
        // Simulation-based probe: for each candidate, simulate colouring
        // it with `color`. In the resulting state the group count is
        // currentCount + 1 (a new isolated group appeared). To recover
        // the target we'd need merges. If even the minimum achievable
        // count in the new state exceeds the target, the target is
        // unreachable → force the candidate to an opposite color.
        //
        // We use `calculateMinGroups` (flood-fill via free-or-same-color
        // cells) rather than enumerating direct merge-cells, because the
        // new state may require multi-step merges through intermediate
        // free cells.
        for (final cand in candidates) {
          final clone = puzzle.clone();
          clone.cells[cand].setForSolver(color);
          if (calculateMinGroups(clone, color) > count &&
              puzzle.cells[cand].options.contains(color)) {
            return RemoveOption(cand, color, this, complexity: 4);
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
    // Option-aware candidates: a free cell pruned of `color` can never start
    // a new group, so it must count as "settled" for grey-out — otherwise GC
    // would never grey out even though apply() can no longer fire.
    final candidates = getFreeCellsThatCanStartNewColorGroup(puzzle, color);
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

  /// Soundness check for the `currentCount > count` over-count case:
  /// returns `true` iff no future play can bring the count back down
  /// to the target.
  ///
  /// `_reachableCountsByMerges` only enumerates counts reachable by
  /// colouring existing merge-cells — it does NOT consider that new
  /// isolated groups can appear on free cells with no `color`
  /// neighbour. When such "addable" cells exist, the reachable set is
  /// an under-approximation and "target ∉ reachable" no longer proves
  /// impossibility (you can raise the count by adding, then merge the
  /// originals separately to land on the target). The strictly sound
  /// `calculateMinGroups > count` lower bound stays usable in both
  /// cases as a fallback.
  bool _exceedingTargetIsImpossible(Puzzle puzzle) {
    // Option-aware: a free cell pruned of `color` can never add a new group,
    // so it must not keep `canAddNewGroup` true. With it correctly false the
    // exact reachable-by-merges set is used instead of the loose
    // `calculateMinGroups > count` fallback, catching more over-counts.
    final canAddNewGroup = getFreeCellsThatCanStartNewColorGroup(
      puzzle,
      color,
    ).isNotEmpty;
    final reachable = _safeReachableCountsByMerges(puzzle);
    if (reachable != null && !canAddNewGroup) {
      return !reachable.contains(count);
    }
    return calculateMinGroups(puzzle, color) > count;
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
          if (puzzle.cellValues[idx] != CellValue.free) continue;
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
