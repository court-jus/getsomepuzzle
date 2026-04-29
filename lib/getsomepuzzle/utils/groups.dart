import 'dart:collection';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Set<int> getMyColorGroup(Puzzle puzzle, int idx) {
  final myValue = puzzle.cellValues[idx];
  if (myValue == 0) return {};
  final List<int> result = [idx];
  result.addAll(
    puzzle.getNeighbors(idx).where((e) => puzzle.cellValues[e] == myValue),
  );
  return result.toSet();
}

List<List<int>> getGroups(Puzzle puzzle) {
  final cached = puzzle.cachedGroups;
  if (cached != null) return cached;
  final List<Set<int>> sameValues = [
    for (var idx in Iterable.generate(puzzle.cellValues.length))
      getMyColorGroup(puzzle, idx),
  ];
  final Map<int, Set<int>> groups = {};
  var groupCount = 0;
  for (var others in sameValues) {
    if (others.isEmpty) continue;
    final existing = {
      for (var item in groups.entries)
        if (others.intersection(item.value).isNotEmpty) item.key: item.value,
    };
    if (existing.isEmpty) {
      groupCount += 1;
      groups[groupCount] = others;
      continue;
    }
    // Merge the groups
    final newIdx = existing.keys.toList()[0];
    var newGrp = existing[newIdx]!.union(others);
    final indicesRemove = existing.keys.where((i) => i != newIdx);
    for (var indexRemove in indicesRemove) {
      final removeGrp = existing[indexRemove];
      if (removeGrp != null) {
        groups.remove(indexRemove);
        newGrp = newGrp.union(removeGrp);
      }
    }
    groups[newIdx] = groups[newIdx]!.union(newGrp);
  }
  final List<List<int>> result = groups.values.map((grp) {
    final indices = grp.toList();
    indices.sort();
    return indices;
  }).toList();
  puzzle.cachedGroups = result;
  return result;
}

List<List<int>> getColorGroups(Puzzle puzzle, int color) {
  return getGroups(puzzle).where((grp) {
    if (grp.isEmpty) return false;
    return puzzle.cellValues[grp.first] == color;
  }).toList();
}

/// Compute the "virtual groups" of a puzzle: for each value V in
/// `{0} ∪ puzzle.domain`, the connected components of the subgraph of
/// cells whose value is V or 0, anchored on cells whose value is exactly V.
///
/// Intuition: a virtual group of color V is the maximum set of cells that
/// could end up in a single same-color group of color V after colouring
/// some free cells with V. For V = 0 the anchors are free cells themselves,
/// so the components are the connected regions of free cells.
///
/// A free cell may appear in multiple virtual groups (one per non-zero
/// color it can reach, plus the free-only component). Each component is
/// returned as a sorted `List<int>` of cell indices. The returned list
/// aggregates components across all values; callers that need to know
/// which value a component belongs to should inspect its cells.
///
/// Use case: checking whether a set of cells can all live in one same-color
/// group (e.g. a letter group), given the current opposite-color obstacles.
List<List<int>> toVirtualGroups(Puzzle puzzle) {
  final result = <List<int>>[];
  final values = <int>{0, ...puzzle.domain};
  for (final v in values) {
    _componentsAnchoredOnValue(puzzle, v, result);
  }
  return result;
}

/// Append to [out] each connected component of cells whose value is [v] or
/// 0, where every component is anchored by at least one cell whose value
/// is exactly [v]. Components are discovered via BFS.
void _componentsAnchoredOnValue(Puzzle puzzle, int v, List<List<int>> out) {
  final cellValues = puzzle.cellValues;
  final visited = <int>{};
  for (int start = 0; start < cellValues.length; start++) {
    if (cellValues[start] != v) continue;
    if (visited.contains(start)) continue;
    final component = <int>{start};
    final queue = Queue<int>()..add(start);
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      for (final nei in puzzle.getNeighbors(cur)) {
        final nv = cellValues[nei];
        if (nv != v && nv != 0) continue;
        if (!component.add(nei)) continue;
        queue.add(nei);
      }
    }
    visited.addAll(component);
    out.add(component.toList()..sort());
  }
}

/// True iff treating [blocked] as the opposite colour (removing it from the
/// merge graph) would prevent at least one of [members] from being reachable
/// from `members.first`.
///
/// The merge graph spans every cell whose value is [color] or 0 (uncoloured).
/// Used by constraints that require a set of cells to end up in the same
/// same-colour group (`LT`, future `GC`) to detect articulation points —
/// cells that lie on every possible merge path between [members] and must
/// therefore take [color].
///
/// Returns false when [members] has fewer than two cells or when [blocked]
/// itself is one of the members. Callers must ensure [members] are
/// reachable from one another in the unblocked graph; otherwise the result
/// is vacuously true (the puzzle is already infeasible).
bool blockingDisconnectsMembers(
  Puzzle puzzle,
  int blocked,
  int color,
  List<int> members,
) {
  if (members.length < 2) return false;
  if (members.contains(blocked)) return false;
  final start = members.first;
  final visited = <int>{start};
  final queue = Queue<int>()..add(start);
  while (queue.isNotEmpty) {
    final cur = queue.removeFirst();
    for (final nei in puzzle.getNeighbors(cur)) {
      if (nei == blocked) continue;
      if (visited.contains(nei)) continue;
      final v = puzzle.cellValues[nei];
      if (v != color && v != 0) continue;
      visited.add(nei);
      queue.add(nei);
    }
  }
  return members.any((m) => !visited.contains(m));
}

bool canMergeGroups(Puzzle puzzle, List<int> groupA, List<int> groupB) {
  // Check if there exists a path of free cells (value 0 or same color) connecting groupA and groupB
  // Perform flood fill from all cells in groupA, through cells that are either empty (0) or same color
  final targetColor = puzzle.cellValues[groupA.first];
  final otherColor = puzzle.cellValues[groupB.first];
  if (targetColor != otherColor) return false;

  final Set<int> visited = {};
  final Queue<int> queue = Queue();

  // Start flood fill from all cells in groupA
  for (var cell in groupA) {
    queue.add(cell);
    visited.add(cell);
  }

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    // Check neighbors
    for (var neighbor in puzzle.getNeighbors(current)) {
      if (visited.contains(neighbor)) continue;
      final neighborValue = puzzle.cellValues[neighbor];
      // Can traverse through empty cells or cells of the same color
      if (neighborValue == 0 || neighborValue == targetColor) {
        visited.add(neighbor);
        queue.add(neighbor);
        // If we reach any cell in groupB, they can merge
        if (groupB.contains(neighbor)) {
          return true;
        }
      }
    }
  }
  return false;
}

int calculateMinGroups(Puzzle puzzle, int color) {
  // Calculate the minimum possible number of groups of that color
  // that can be made by merging existing groups in puzzle.
  final groups = getColorGroups(puzzle, color);
  if (groups.isEmpty) return 0;

  // Union-Find to group mergeable groups together
  final parent = List<int>.generate(groups.length, (i) => i);

  int find(int x) {
    if (parent[x] != x) parent[x] = find(parent[x]);
    return parent[x];
  }

  void unite(int x, int y) {
    final px = find(x);
    final py = find(y);
    if (px != py) parent[px] = py;
  }

  // Check each pair of groups
  for (int i = 0; i < groups.length; i++) {
    for (int j = i + 1; j < groups.length; j++) {
      if (canMergeGroups(puzzle, groups[i], groups[j])) {
        unite(i, j);
      }
    }
  }

  // Count distinct components
  final Set<int> roots = {};
  for (int i = 0; i < groups.length; i++) {
    roots.add(find(i));
  }
  return roots.length;
}

List<int> getFreeCellsWithoutNeighborColor(Puzzle puzzle, int color) {
  final List<int> result = [];
  for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
    if (puzzle.cellValues[idx] != 0) continue;
    final neighbors = puzzle.getNeighbors(idx);
    if (!neighbors.any((n) => puzzle.cellValues[n] == color)) {
      result.add(idx);
    }
  }
  return result;
}

List<int> getCellsThatMergeColorGroups(Puzzle puzzle, int color) {
  final List<int> result = [];
  final groups = getColorGroups(puzzle, color);

  for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
    if (puzzle.cellValues[idx] != 0) continue;

    final neighbors = puzzle.getNeighbors(idx);
    final neighborGroups = <int>{};

    for (final n in neighbors) {
      if (puzzle.cellValues[n] != color) continue;
      for (int g = 0; g < groups.length; g++) {
        if (groups[g].contains(n)) {
          neighborGroups.add(g);
        }
      }
    }

    if (neighborGroups.length > 1) {
      result.add(idx);
    }
  }

  return result;
}
