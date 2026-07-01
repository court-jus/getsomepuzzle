import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Multi-source flood fill over the puzzle grid.
///
/// All [starts] are visited unconditionally (even when [canTraverse] would
/// reject them), then the fill expands through neighbors for which
/// [canTraverse] returns true. Returns the visited set.
Set<int> floodFill(
  Puzzle puzzle,
  Iterable<int> starts,
  bool Function(int idx) canTraverse,
) {
  final visited = <int>{...starts};
  final queue = List<int>.from(visited);
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    for (final nei in puzzle.getNeighbors(cur)) {
      if (visited.contains(nei)) continue;
      if (!canTraverse(nei)) continue;
      visited.add(nei);
      queue.add(nei);
    }
  }
  return visited;
}

/// True iff a cell satisfying [isTarget] is reachable from [starts] through
/// cells for which [canTraverse] returns true.
///
/// [isTarget] is also tested on the start cells themselves (a start can be
/// its own target, e.g. a cell lying on both borders of a 1-wide grid).
/// Early-exits on the first target reached. Empty [starts] returns false.
bool canReach(
  Puzzle puzzle,
  Iterable<int> starts,
  bool Function(int idx) isTarget,
  bool Function(int idx) canTraverse,
) {
  final visited = <int>{...starts};
  final queue = List<int>.from(visited);
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    if (isTarget(cur)) return true;
    for (final nei in puzzle.getNeighbors(cur)) {
      if (visited.contains(nei)) continue;
      if (!canTraverse(nei)) continue;
      visited.add(nei);
      queue.add(nei);
    }
  }
  return false;
}

Set<int> getMyColorGroup(Puzzle puzzle, int idx) {
  final myValue = puzzle.cellValues[idx];
  if (myValue == CellValue.free) return {};
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

List<List<int>> getColorGroups(Puzzle puzzle, CellValue color) {
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
  final values = <CellValue>{CellValue.free, ...puzzle.domain};
  for (final v in values) {
    _componentsAnchoredOnValue(puzzle, v, result);
  }
  return result;
}

/// Append to [out] each connected component of cells whose value is [v] or
/// has the option [v], where every component is anchored by at least one cell
/// whose value is exactly [v]. Components are discovered via flood fill.
void _componentsAnchoredOnValue(
  Puzzle puzzle,
  CellValue v,
  List<List<int>> out,
) {
  final cellValues = puzzle.cellValues;
  final visited = <int>{};
  for (int start = 0; start < cellValues.length; start++) {
    if (cellValues[start] != v) continue;
    if (visited.contains(start)) continue;
    final component = floodFill(puzzle, [
      start,
    ], (i) => cellValues[i] == v || puzzle.cells[i].options.contains(v));
    visited.addAll(component);
    out.add(component.toList()..sort());
  }
}

/// True iff treating [blocked] as the opposite colour (removing it from the
/// merge graph) would prevent at least one of [members] from being reachable
/// from `members.first`.
///
/// The merge graph spans every cell whose value is [color] or has the
/// option [color].
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
  CellValue color,
  List<int> members,
) {
  if (members.length < 2) return false;
  if (members.contains(blocked)) return false;
  final visited = floodFill(puzzle, [members.first], (i) {
    if (i == blocked) return false;
    final v = puzzle.cellValues[i];
    return v == color || puzzle.cells[i].options.contains(color);
  });
  return members.any((m) => !visited.contains(m));
}

/// Size of the connected component reachable from [seed] through cells of
/// value [color] or having option [color]. [seed] itself is included even when its own value
/// differs from [color] (callers typically pass a member of a [color] group).
int reachableComponentSize(Puzzle puzzle, int seed, CellValue color) {
  return floodFill(puzzle, [seed], (i) {
    final v = puzzle.cellValues[i];
    return v == color || puzzle.cells[i].options.contains(color);
  }).length;
}

/// True iff treating [blocked] as the opposite colour (removing it from the
/// merge graph) leaves fewer than [minSize] cells reachable from [seed]
/// through cells whose value is [color] or has the option [color].
///
/// Sibling of [blockingDisconnectsMembers]: same BFS, different post-check.
/// Used by `GS` to detect cells that lie on every possible growth path of
/// a group of target size [minSize] — if the seed's connected
/// [color]-or-empty region can't reach [minSize] cells without going
/// through [blocked], then [blocked] must take [color].
///
/// Returns false when [seed] equals [blocked] (vacuous: the seed itself is
/// excluded, so the predicate is undefined).
bool blockingShrinksReachableBelow(
  Puzzle puzzle,
  int blocked,
  CellValue color,
  int seed,
  int minSize,
) {
  if (seed == blocked) return false;
  final visited = floodFill(puzzle, [seed], (i) {
    if (i == blocked) return false;
    final v = puzzle.cellValues[i];
    return v == color || puzzle.cells[i].options.contains(color);
  });
  return visited.length < minSize;
}

bool canMergeGroups(Puzzle puzzle, List<int> groupA, List<int> groupB) {
  // Check if there exists a path of cells (same color or having that option) connecting groupA and groupB
  final targetColor = puzzle.cellValues[groupA.first];
  final otherColor = puzzle.cellValues[groupB.first];
  if (targetColor != otherColor) return false;

  return canReach(puzzle, groupA, groupB.contains, (i) {
    final v = puzzle.cellValues[i];
    return v == targetColor || puzzle.cells[i].options.contains(targetColor);
  });
}

int calculateMinGroups(Puzzle puzzle, CellValue color) {
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

/// Free cells that could still *start a new* `color` group: free, with no
/// `color` neighbour (colouring one `color` makes a fresh isolated group
/// rather than extending an existing one) **and** with `color` still in
/// their options.
///
/// The options filter matters on 3+ colour domains: a cell can be free yet
/// have `color` already pruned by another constraint's `removeOption`, in
/// which case it can never become `color` and is not a real new-group
/// candidate. Counting it would over-estimate how many groups can still
/// appear, masking real impossibilities and blocking grey-out. This mirrors
/// the option filter [getCellsThatMergeColorGroups] already applies, so GC's
/// reachability / completeness reasoning uses one consistent convention.
///
/// The returned set is monotone decreasing under forward play: a cell leaves
/// it when coloured, when it gains a `color` neighbour, or when `color` is
/// pruned from its options — and nothing can ever re-enter it.
List<int> getFreeCellsThatCanStartNewColorGroup(
  Puzzle puzzle,
  CellValue color,
) {
  final List<int> result = [];
  for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
    if (puzzle.cellValues[idx] != CellValue.free) continue;
    if (!puzzle.cells[idx].options.contains(color)) continue;
    final neighbors = puzzle.getNeighbors(idx);
    if (!neighbors.any((n) => puzzle.cellValues[n] == color)) {
      result.add(idx);
    }
  }
  return result;
}

List<int> getCellsThatMergeColorGroups(Puzzle puzzle, CellValue color) {
  final List<int> result = [];
  final groups = getColorGroups(puzzle, color);

  for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
    if (!puzzle.cells[idx].options.contains(color)) continue;

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
