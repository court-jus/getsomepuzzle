// Boss (seed-and-grow) pre-fill: creates coherent blobs on large grids.
//
// The default random prefill produces white-noise grids that are
// uninteresting at large scale (≥ 30×20). This prefill replaces that
// first step with a "plant seeds, grow each one" algorithm that builds
// coherent same-colour blobs, then fills the remaining ~30 % at random
// and posts one GroupSize constraint per seeded group with its final
// (post-fusion) size. See `docs/dev/boss.md`.

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Fill ratio target: ~70 % of cells are seeded and grown; the rest are
/// random-filled in phase 2a.
const _fillRatio = 0.70;

/// Seeded groups are grown to a target size drawn uniformly from
/// [_minGroupSize, _maxGroupSize].
const _minGroupSize = 15;
const _maxGroupSize = 25;

/// After phase 2a's random fill, several seeds may end up sharing the same
/// connected component (their same-colour blobs merge through the random
/// fill). Posting one GS per seed in that case yields N copies of the same
/// "this component has size K" statement. We cap the number of GS constraints
/// that can target the same component to [_maxSameGroup].
const _maxSameGroup = 3;

/// Experimental "seed-and-grow" prefill used for large "Boss" grids.
///
/// Phase 1 (until ~70 % of cells are filled): plant seeds — choose an empty
/// cell weighted by Chebyshev distance to the nearest edge AND to the nearest
/// already-filled cell. Assign a random colour and a target group size in
/// [_minGroupSize, _maxGroupSize], then grow the seed by painting random free
/// neighbours until the target is reached (or the group runs out of free
/// neighbours).
///
/// Phase 2a (remaining ~30 %): paint every still-empty cell with a random
/// colour. This can grow some of the seeded groups (when the random colour
/// matches a neighbouring seeded group's colour).
///
/// Phase 2b: for each seeded pivot, recompute the actual final group size
/// and post a GroupSize constraint reflecting reality.
Puzzle preFillBoss(int width, int height, List<CellValue> domain, Random rng) {
  final solved = Puzzle.empty(width, height, domain);
  final size = width * height;
  final targetFilled = (size * _fillRatio).round();

  // Distance to the nearest edge in Chebyshev metric: 0 on the border,
  // grows toward the centre. Used as the seed-weight floor.
  int distToEdge(int idx) {
    final x = idx % width;
    final y = idx ~/ width;
    return min(min(x, width - 1 - x), min(y, height - 1 - y));
  }

  // BFS-based Chebyshev distance from every cell to the nearest filled cell.
  // Recomputed before each seed (cheap: O(size)). Empty grid returns -1
  // everywhere, signalling "no constraint from this term".
  List<int> distToFilled() {
    final dist = List<int>.filled(size, -1);
    final queue = <int>[];
    for (int i = 0; i < size; i++) {
      if (solved.cells[i].value != CellValue.free) {
        dist[i] = 0;
        queue.add(i);
      }
    }
    if (queue.isEmpty) return dist;
    int head = 0;
    while (head < queue.length) {
      final cur = queue[head++];
      final cx = cur % width;
      final cy = cur ~/ width;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final nIdx = ny * width + nx;
          if (dist[nIdx] != -1) continue;
          dist[nIdx] = dist[cur] + 1;
          queue.add(nIdx);
        }
      }
    }
    return dist;
  }

  // Pick a free cell with weight = min(distToEdge, distToFilled). +1 so
  // border cells still have a tiny chance to be picked.
  int? pickSeed() {
    final dEdge = List<int>.generate(size, distToEdge);
    final dFilled = distToFilled();
    final weights = List<double>.filled(size, 0);
    double total = 0;
    for (int i = 0; i < size; i++) {
      if (solved.cells[i].value != CellValue.free) continue;
      final fillTerm = dFilled[i] == -1 ? dEdge[i] : dFilled[i];
      final w = (min(dEdge[i], fillTerm) + 1).toDouble();
      weights[i] = w;
      total += w;
    }
    if (total <= 0) return null;
    var r = rng.nextDouble() * total;
    for (int i = 0; i < size; i++) {
      if (weights[i] == 0) continue;
      r -= weights[i];
      if (r <= 0) return i;
    }
    for (int i = size - 1; i >= 0; i--) {
      if (weights[i] > 0) return i;
    }
    return null;
  }

  int filled = 0;
  final List<({int pivot, CellValue color})> seeds = [];

  // Phase 1: plant seeds and grow.
  while (filled < targetFilled) {
    final seed = pickSeed();
    if (seed == null) break;
    final color = domain[rng.nextInt(domain.length)];
    final target =
        _minGroupSize + rng.nextInt(_maxGroupSize - _minGroupSize + 1);
    solved.cells[seed].setForSolver(color);
    filled++;
    seeds.add((pivot: seed, color: color));
    final groupCells = <int>[seed];

    while (groupCells.length < target) {
      final frontier = <int>{};
      for (final c in groupCells) {
        for (final n in solved.getNeighbors(c)) {
          if (solved.cells[n].value == CellValue.free) frontier.add(n);
        }
      }
      if (frontier.isEmpty) break;
      final frontierList = frontier.toList();
      final pick = frontierList[rng.nextInt(frontierList.length)];
      solved.cells[pick].setForSolver(color);
      groupCells.add(pick);
      filled++;
      if (filled >= size) break;
    }
    if (filled >= size) break;
  }

  // Phase 2a: random-fill the remaining ~30 %.
  for (int i = 0; i < size; i++) {
    if (solved.cells[i].value != CellValue.free) continue;
    solved.cells[i].setForSolver(domain[rng.nextInt(domain.length)]);
  }

  // Phase 2b: post one GroupSize per seed, using the post-fill actual size
  // of the connected same-colour blob anchored at the pivot. We cap GS
  // constraints per component at _maxSameGroup to avoid posting N redundant
  // copies of the same statement when several seeds collapsed into one
  // component during phase 2a.
  final componentCounts = <int, int>{};
  for (final seed in seeds) {
    final pivot = seed.pivot;
    final color = solved.cells[pivot].value;
    final visited = <int>{pivot};
    final stack = <int>[pivot];
    int canonical = pivot;
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (cur < canonical) canonical = cur;
      for (final n in solved.getNeighbors(cur)) {
        if (visited.contains(n)) continue;
        if (solved.cells[n].value != color) continue;
        visited.add(n);
        stack.add(n);
        if (n < canonical) canonical = n;
      }
    }
    final count = componentCounts[canonical] ?? 0;
    if (count >= _maxSameGroup) continue;
    componentCounts[canonical] = count + 1;
    solved.addConstraint(GroupSize('$pivot.${visited.length}'));
  }

  return solved;
}
