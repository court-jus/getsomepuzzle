import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/collections.dart';

List<int> getNeighborsSameValue(Puzzle puzzle, int idx) {
  final myValue = puzzle.cellValues[idx];
  if (myValue == 0) return [];
  final List<int> result = [idx];
  result.addAll(
    puzzle.getNeighbors(idx).where((e) => puzzle.cellValues[e] == myValue),
  );
  return result;
}

List<int> getNeighborsSameValueOrEmpty(Puzzle puzzle, int idx, int myValue) {
  final List<int> result = [idx];
  result.addAll(
    puzzle
        .getNeighbors(idx)
        .where(
          (e) => puzzle.cellValues[e] == myValue || puzzle.cellValues[e] == 0,
        ),
  );
  return result;
}

List<List<int>> getGroups(Puzzle puzzle) {
  final List<Set<int>> sameValues = [
    for (var idx in Iterable.generate(puzzle.cellValues.length))
      getNeighborsSameValue(puzzle, idx).toSet(),
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
  return result;
}

List<List<int>> getColorGroups(Puzzle puzzle, int color) {
  return getGroups(puzzle).where((grp) {
    if (grp.isEmpty) return false;
    return puzzle.cellValues[grp.first] == color;
  }).toList();
}

List<List<int>> toVirtualGroups(Puzzle puzzle) {
  // Explore the puzzle to find all the groups that could be made possible
  // by growing existing groups to free cells or cells of the same color
  final idxToExplore = puzzle.cellValues.indexed.toList();
  final Map<int, List<int>> explored = {};
  final Map<int, Map<int, List<int>>> groupsPerValuePerCell = {};
  while (idxToExplore.isNotEmpty) {
    final exploring = idxToExplore.removeAt(0);
    final exploreIdx = exploring.$1;
    final value = exploring.$2;
    final others = explored[value] ?? [];
    if (others.contains(exploreIdx)) {
      continue;
    }
    others.add(exploreIdx);
    explored[value] = others;
    final sameOrEmpty = getNeighborsSameValueOrEmpty(puzzle, exploreIdx, value);
    if (groupsPerValuePerCell[value] == null) {
      groupsPerValuePerCell[value] = {};
    }
    if (groupsPerValuePerCell[value]![exploreIdx] == null) {
      groupsPerValuePerCell[value]![exploreIdx] = [];
    }
    groupsPerValuePerCell[value]![exploreIdx]!.addAll(sameOrEmpty);
    for (var neighbor in sameOrEmpty) {
      if (neighbor != exploreIdx) {
        idxToExplore.add((neighbor, value));
      }
    }
  } // while
  final Map<int, List<Set<int>>> setsPerValue = {};
  for (var valueEntry in groupsPerValuePerCell.entries) {
    final value = valueEntry.key;
    final valueData = valueEntry.value;
    for (var dataEntry in valueData.entries) {
      final idx = dataEntry.key;
      final newGroup = dataEntry.value.toSet();
      if (setsPerValue[value] == null) {
        setsPerValue[value] = [];
      }
      for (var existing in findAndPop(setsPerValue[value]!, idx)) {
        newGroup.addAll(existing);
      }
      setsPerValue[value]!.add(newGroup);
    }
  }
  return setsPerValue.values.flattenedToList
      .map((grp) => grp.toList())
      .toList();
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
