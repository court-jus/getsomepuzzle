// SY-based puzzle pre-fill.
//
// Generates a "SY-based" puzzle dominated by SymmetryConstraint. The
// pipeline (see docs/dev/prefill_sy.md):
//
// 1. Pick a background colour (50/50) and sample N seed cells in the
//    grid interior, well-separated from each other.
// 2. For each seed, pick a feasible SY axis (one that allows growth).
// 3. Grow each island by adding free cells in pairs (cell + its
//    mirror), maintaining a forbidden halo around other islands so
//    they cannot merge.
// 4. Build the solved grid (background colour everywhere, fg in
//    islands) and attach one SY per seed.
// 5. Bipartite-desambiguate via a 4-step priority cascade analogous to
//    path.dart: seed reveal → island-cell reveal → GC/QA → other
//    guardrails (with LT filtered to same-region anchors only and
//    SY/SH excluded).
//
// Returns a [SyPrefillResult] with the player-facing puzzle and the
// complete solution, or null on failure.

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

const _domain = [1, 2];

// Guardrail slugs allowed in the SY pipeline. SY is excluded (dominant
// slug, already placed). SH is excluded — two shape-flavored
// constraints would compete. LT is included but inter-island candidates
// get filtered out (would force a merge that breaks symmetry).
const _gardeFouSlugs = [
  'GC',
  'CC',
  'RC',
  'QA',
  'GS',
  'PA',
  'NC',
  'DF',
  'LT',
  'EY',
  'FM',
];

class SyPrefillResult {
  final Puzzle puzzle;
  final List<int> solution;
  final int numIslands;
  final int seedRevealedCount;
  final int islandCellRevealedCount;
  final int gardeFouCount;

  SyPrefillResult({
    required this.puzzle,
    required this.solution,
    required this.numIslands,
    required this.seedRevealedCount,
    required this.islandCellRevealedCount,
    required this.gardeFouCount,
  });

  int get revealedCount => seedRevealedCount + islandCellRevealedCount;
}

class _Island {
  final int seed;
  final int axis;
  final Set<int> cells = <int>{};
  bool frozen = false;
  _Island(this.seed, this.axis);
}

/// Generate one SY-based puzzle. Returns null on any failure.
SyPrefillResult? preFillSy(
  int width,
  int height,
  Random rng, {
  int? numIslands,
  int edgeMargin = 1,
  int? minSeedDist,
  double stopProb = 0.2,
  int minIslandSize = 3,
  int? maxIslandSize,
  int maxRetries = 30,
  int? bipartiteMaxReveals,
}) {
  final n = numIslands ?? (width * height >= 40 ? 3 : 2);
  final minDist = minSeedDist ?? max(3, ((min(width, height)) / 2).ceil());
  final maxSize = maxIslandSize ?? max(4, ((width * height) / (2 * n)).ceil());

  for (int attempt = 0; attempt < maxRetries; attempt++) {
    final seeds = _sampleSeeds(width, height, n, edgeMargin, minDist, rng);
    if (seeds == null) continue;

    // Pick a feasible axis for each seed (one that allows at least one
    // growth pair to land in-bounds).
    final islands = <_Island>[];
    bool axisFailed = false;
    for (final seed in seeds) {
      final axis = _pickAxis(seed, width, height, rng);
      if (axis == null) {
        axisFailed = true;
        break;
      }
      islands.add(_Island(seed, axis));
    }
    if (axisFailed) continue;

    // Seed each island with {seed} ∪ {mirror(seed)}.
    for (final isl in islands) {
      isl.cells.add(isl.seed);
      final m = _mirror(width, height, isl.seed, isl.axis, isl.seed);
      if (m != null && m != isl.seed) isl.cells.add(m);
    }

    // Verify no overlap between seed configurations before growth.
    final allSeedCells = <int>{};
    bool overlap = false;
    for (final isl in islands) {
      for (final c in isl.cells) {
        if (!allSeedCells.add(c)) {
          overlap = true;
          break;
        }
      }
      if (overlap) break;
    }
    if (overlap) continue;

    _growIslands(width, height, islands, maxSize, stopProb, rng);

    // Reject if any island is too small to be visually meaningful.
    if (islands.any((isl) => isl.cells.length < minIslandSize)) continue;

    // 50/50 background colour. Islands take the opposite.
    final bg = rng.nextBool() ? 1 : 2;
    final fg = bg == 1 ? 2 : 1;

    final solution = List<int>.filled(width * height, bg);
    for (final isl in islands) {
      for (final c in isl.cells) {
        solution[c] = fg;
      }
    }

    // Build the player-facing puzzle: empty grid + SY anchors.
    final puzzle = Puzzle.empty(width, height, _domain);
    for (final isl in islands) {
      puzzle.addConstraint(SymmetryConstraint('${isl.seed}.${isl.axis}'));
    }

    // Standard-style readonly prefill: like preFillRegular, sprinkle a
    // few solved-value readonly cells across the grid. Without this the
    // SY puzzle starts with zero anchored cells and the bipartite
    // cascade has to brute-force unicity entirely from guardrails —
    // expensive and rarely converges.
    final size = width * height;
    final ratio = 0.75 + rng.nextDouble() * 0.25;
    final prefilled = (size * (1 - ratio)).ceil();
    final indices = List<int>.generate(size, (i) => i)..shuffle(rng);
    for (int i = 0; i < prefilled && i < indices.length; i++) {
      final idx = indices[i];
      puzzle.cells[idx].setForSolver(solution[idx]);
      puzzle.cells[idx].readonly = true;
    }

    // Per-cell island index for LT inter-island filtering. -1 = ocean.
    final islandOf = List<int>.filled(width * height, -1);
    for (int i = 0; i < islands.length; i++) {
      for (final c in islands[i].cells) {
        islandOf[c] = i;
      }
    }

    // Solved puzzle used to validate guardrail candidates.
    final solved = _buildSolvedPuzzle(width, height, solution);
    final candidates = _enumerateGardeFou(width, height, solved, islandOf, rng);

    // Bipartite reveal pools.
    final seedPool = <int>[for (final isl in islands) isl.seed]..shuffle(rng);
    final islandCellPool = <int>[
      for (final isl in islands) ...isl.cells.where((c) => c != isl.seed),
    ]..shuffle(rng);

    final result = _bipartiteDesambiguate(
      puzzle: puzzle,
      solution: solution,
      seedPool: seedPool,
      islandCellPool: islandCellPool,
      candidates: candidates,
      maxReveals: bipartiteMaxReveals ?? (islands.length * 2),
      rng: rng,
    );

    if (result == null) continue;

    return SyPrefillResult(
      puzzle: puzzle,
      solution: solution,
      numIslands: islands.length,
      seedRevealedCount: result.$1,
      islandCellRevealedCount: result.$2,
      gardeFouCount: result.$3,
    );
  }
  return null;
}

/// Sample [n] seed cells from the grid interior (`edgeMargin` cells off
/// each wall), pairwise Manhattan-distant by ≥ [minDist].
List<int>? _sampleSeeds(
  int width,
  int height,
  int n,
  int edgeMargin,
  int minDist,
  Random rng,
) {
  const maxLocalTries = 200;
  final zone = <int>[];
  for (int r = edgeMargin; r < height - edgeMargin; r++) {
    for (int c = edgeMargin; c < width - edgeMargin; c++) {
      zone.add(c + r * width);
    }
  }
  if (zone.length < n * 2) return null;
  final placed = <int>[];
  for (int i = 0; i < n; i++) {
    bool ok = false;
    for (int t = 0; t < maxLocalTries; t++) {
      final idx = zone[rng.nextInt(zone.length)];
      if (placed.contains(idx)) continue;
      bool tooClose = false;
      for (final p in placed) {
        if (_manhattan(p, idx, width) < minDist) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;
      placed.add(idx);
      ok = true;
      break;
    }
    if (!ok) return null;
  }
  return placed;
}

/// Pick a random feasible axis (one that admits at least one growth
/// pair in-bounds). Returns null if no axis is feasible.
int? _pickAxis(int seed, int width, int height, Random rng) {
  final feasible = <int>[];
  for (int a = 1; a <= 5; a++) {
    if (_axisHasGrowthRoom(seed, a, width, height)) feasible.add(a);
  }
  if (feasible.isEmpty) return null;
  return feasible[rng.nextInt(feasible.length)];
}

/// True iff at least one 4-neighbour of the seed has its mirror in-bounds.
/// Without that, growth is impossible and the island would stay at the
/// trivial 1-2 cell size.
bool _axisHasGrowthRoom(int seed, int axis, int width, int height) {
  for (final n in _neighbors(seed, width, height)) {
    final m = _mirror(width, height, seed, axis, n);
    if (m != null) return true;
  }
  return false;
}

/// Compute the mirror of [cell] under the symmetry anchored at [seed]
/// with the given [axis]. Returns null if the mirror falls outside the
/// grid. Matches the math in `SymmetryConstraint.computeSymmetry`.
int? _mirror(int width, int height, int seed, int axis, int cell) {
  final ax = seed % width;
  final ay = seed ~/ width;
  final cx = cell % width;
  final cy = cell ~/ width;
  final dx = ax - cx;
  final dy = ay - cy;
  int sx;
  int sy;
  switch (axis) {
    case 1: // ⟍ diagonal
      sx = ax - dy;
      sy = ay - dx;
      break;
    case 2: // | vertical
      sx = ax + dx;
      sy = cy;
      break;
    case 3: // ⟋ anti-diagonal
      sx = ax + dy;
      sy = ay + dx;
      break;
    case 4: // ― horizontal
      sx = cx;
      sy = ay + dy;
      break;
    case 5: // 🞋 point
      sx = ax + dx;
      sy = ay + dy;
      break;
    default:
      return null;
  }
  if (sx < 0 || sx >= width || sy < 0 || sy >= height) return null;
  return sy * width + sx;
}

/// Grow every island in random round-robin until each can no longer
/// grow (no valid pair) or hits [maxSize] or randomly stops.
void _growIslands(
  int width,
  int height,
  List<_Island> islands,
  int maxSize,
  double stopProb,
  Random rng,
) {
  while (islands.any((isl) => !isl.frozen)) {
    final active = islands.where((isl) => !isl.frozen).toList();
    final isl = active[rng.nextInt(active.length)];

    // Cells that this island must avoid: every cell of every other
    // island + a 1-cell halo around them (the merge buffer).
    final forbidden = <int>{};
    for (final other in islands) {
      if (identical(other, isl)) continue;
      for (final c in other.cells) {
        forbidden.add(c);
        for (final n in _neighbors(c, width, height)) {
          forbidden.add(n);
        }
      }
    }

    // Candidate cells: 4-neighbours of the island, not in island, not in
    // forbidden, with their mirror also not in forbidden.
    final candidates = <int>{};
    for (final c in isl.cells) {
      for (final n in _neighbors(c, width, height)) {
        if (isl.cells.contains(n)) continue;
        if (forbidden.contains(n)) continue;
        candidates.add(n);
      }
    }
    final orderedCandidates = candidates.toList()..shuffle(rng);

    bool grew = false;
    for (final c in orderedCandidates) {
      final m = _mirror(width, height, isl.seed, isl.axis, c);
      if (m == null) continue;
      if (forbidden.contains(m)) continue;
      if (m == c || isl.cells.contains(m)) {
        // Self-mirror or mirror already in island: add only c.
        isl.cells.add(c);
        grew = true;
        break;
      }
      isl.cells.add(c);
      isl.cells.add(m);
      grew = true;
      break;
    }

    if (!grew || isl.cells.length >= maxSize) {
      isl.frozen = true;
      continue;
    }
    if (rng.nextDouble() < stopProb) isl.frozen = true;
  }
}

Iterable<int> _neighbors(int idx, int width, int height) sync* {
  final x = idx % width;
  final y = idx ~/ width;
  if (x > 0) yield idx - 1;
  if (x < width - 1) yield idx + 1;
  if (y > 0) yield idx - width;
  if (y < height - 1) yield idx + width;
}

int _manhattan(int a, int b, int width) {
  final ca = a % width;
  final ra = a ~/ width;
  final cb = b % width;
  final rb = b ~/ width;
  return (ca - cb).abs() + (ra - rb).abs();
}

Puzzle _buildSolvedPuzzle(int width, int height, List<int> solution) {
  final pu = Puzzle.empty(width, height, _domain);
  for (int i = 0; i < pu.cells.length; i++) {
    pu.cells[i].setForSolver(solution[i]);
  }
  return pu;
}

/// Enumerate guardrail candidates valid against the solution. LT
/// candidates whose anchors span more than one region (one specific
/// island OR ocean) are filtered out — they would force an
/// island-merging route that breaks SY.
List<Constraint> _enumerateGardeFou(
  int width,
  int height,
  Puzzle solved,
  List<int> islandOf,
  Random rng,
) {
  final out = <Constraint>[];
  for (final slug in _gardeFouSlugs) {
    final params = generateAllParameters(slug, width, height, _domain, null);
    if (params == null) continue;
    for (final p in params) {
      final c = createConstraint(slug, p);
      if (c == null) continue;
      if (c is LetterGroup) {
        final regions = c.indices.map((idx) => islandOf[idx]).toSet();
        if (regions.length > 1) continue;
      }
      if (c.verify(solved)) out.add(c);
    }
  }
  out.shuffle(rng);
  return out;
}

/// 4-step bipartite cascade, SY-flavoured:
///   1. reveal a seed
///   2. reveal a non-seed island cell
///   3. add GC or QA (50/50), capped at one per (slug, color)
///   4. add any other guardrail
(int, int, int)? _bipartiteDesambiguate({
  required Puzzle puzzle,
  required List<int> solution,
  required List<int> seedPool,
  required List<int> islandCellPool,
  required List<Constraint> candidates,
  required int maxReveals,
  required Random rng,
}) {
  int seedReveals = 0;
  int islandCellReveals = 0;
  int gardeFou = 0;

  const maxIterations = 200;
  // Hard cap on guardrails. Empirically, a 6×6 SY puzzle that hasn't
  // converged after 8 guardrails almost never converges in this attempt
  // — the topology is structurally ambiguous and we're better off
  // bailing out and letting the outer retry pick a fresh seed/axis.
  const maxGuardrails = 8;
  // Abort attempt after this many consecutive rollbacks without `free`
  // making progress: indicates the cascade is consuming candidates
  // without lowering the deduction floor.
  const maxConsecutiveRollbacks = 5;
  int iter = 0;
  // Track the post-solve free-cell count from iteration to iteration.
  // The fast `_constraintHelps` greedy filter is non-monotonic (an
  // accepted candidate can make the real puzzle regress at the next
  // solve), so we measure free again here and **rollback** the last
  // guardrail if it made things worse.
  int prevFree = -1;
  int bestFree = 1 << 30;
  int consecutiveRollbacks = 0;

  while (iter < maxIterations) {
    iter++;
    if (puzzle.isDeductivelyUnique()) {
      return (seedReveals, islandCellReveals, gardeFou);
    }

    final revealedTotal = seedReveals + islandCellReveals;
    final probe = puzzle.clone();
    probe.solve();
    int freeRemaining = probe.freeCells().length;

    // Rollback the last guardrail if it regressed the real puzzle. We
    // only rollback when free strictly grew: equal stays accepted (the
    // constraint may still constrain the solution space without
    // visible propagation gain). Reveals (phase 1/2) are never rolled
    // back: they materialise actual cell values from the solution and
    // cannot regress propagation by construction.
    if (prevFree >= 0 && freeRemaining > prevFree && gardeFou > 0) {
      puzzle.removeConstraintAt(puzzle.constraints.length - 1);
      gardeFou--;
      final reProbe = puzzle.clone();
      reProbe.solve();
      freeRemaining = reProbe.freeCells().length;
      consecutiveRollbacks++;
      if (consecutiveRollbacks >= maxConsecutiveRollbacks) return null;
    }

    if (freeRemaining < bestFree) {
      bestFree = freeRemaining;
      consecutiveRollbacks = 0;
    }
    if (gardeFou >= maxGuardrails) return null;

    bool advanced = false;
    if (revealedTotal < maxReveals &&
        _tryRevealStrict(puzzle, solution, seedPool)) {
      seedReveals++;
      advanced = true;
    } else if (revealedTotal < maxReveals &&
        _tryRevealStrict(puzzle, solution, islandCellPool)) {
      islandCellReveals++;
      advanced = true;
    } else if (_tryAddGcOrQa(puzzle, candidates, rng)) {
      gardeFou++;
      advanced = true;
    } else if (_tryAddOtherGuardrail(puzzle, candidates)) {
      gardeFou++;
      advanced = true;
    }
    prevFree = freeRemaining;
    if (!advanced) return null;
  }
  return null;
}

/// Reveal a cell from [pool] iff doing so propagates beyond itself
/// (free-cell count drops by ≥ 2). Failed candidates stay in the pool —
/// a later guardrail may unlock their propagation.
bool _tryRevealStrict(Puzzle puzzle, List<int> solution, List<int> pool) {
  for (int i = 0; i < pool.length; i++) {
    final idx = pool[i];
    if (puzzle.cells[idx].readonly) {
      pool.removeAt(i);
      i--;
      continue;
    }
    if (_revealPropagates(puzzle, solution, idx)) {
      puzzle.cells[idx].setForSolver(solution[idx]);
      puzzle.cells[idx].readonly = true;
      pool.removeAt(i);
      return true;
    }
  }
  return false;
}

bool _revealPropagates(Puzzle puzzle, List<int> solution, int idx) {
  final probe = puzzle.clone();
  probe.solve();
  final freeBefore = probe.freeCells().length;
  if (!probe.cells[idx].isFree) return false;
  probe.cells[idx].setForSolver(solution[idx]);
  probe.cells[idx].readonly = true;
  probe.solve();
  final freeAfter = probe.freeCells().length;
  return freeBefore - freeAfter >= 2;
}

bool _tryAddGcOrQa(Puzzle puzzle, List<Constraint> candidates, Random rng) {
  final occupied = <(String, int)>{};
  for (final c in puzzle.constraints) {
    if (c is GroupCountConstraint) occupied.add(('GC', c.color));
    if (c is QuantityConstraint) occupied.add(('QA', c.value));
  }
  if (occupied.length >= 4) return false;

  // Classic-style consumption: a candidate parcouru est définitivement
  // retiré de la liste, même s'il n'aide pas. Évite le retest coûteux des
  // non-helpers à chaque itération de la cascade.
  final tryOrder = rng.nextBool() ? ['GC', 'QA'] : ['QA', 'GC'];
  for (final preferredSlug in tryOrder) {
    int i = 0;
    while (i < candidates.length) {
      final c = candidates[i];
      if (c.slug != preferredSlug) {
        i++;
        continue;
      }
      int color;
      if (c is GroupCountConstraint) {
        color = c.color;
      } else if (c is QuantityConstraint) {
        color = c.value;
      } else {
        i++;
        continue;
      }
      if (occupied.contains((preferredSlug, color))) {
        // Slot color déjà pris : candidat définitivement inutile.
        candidates.removeAt(i);
        continue;
      }
      candidates.removeAt(i);
      if (_constraintHelps(puzzle, c)) {
        puzzle.addConstraint(c);
        return true;
      }
    }
  }
  return false;
}

bool _tryAddOtherGuardrail(Puzzle puzzle, List<Constraint> candidates) {
  // Classic-style consumption: chaque non-GC/QA parcouru est retiré, même
  // s'il n'aide pas. Évite le scan répété des milliers de candidats inutiles
  // à chaque itération de la cascade.
  int i = 0;
  while (i < candidates.length) {
    final c = candidates[i];
    if (c.slug == 'GC' || c.slug == 'QA') {
      i++;
      continue;
    }
    candidates.removeAt(i);
    if (_constraintHelps(puzzle, c)) {
      puzzle.addConstraint(c);
      return true;
    }
  }
  return false;
}

bool _constraintHelps(Puzzle puzzle, Constraint c) {
  // Fast (approximate) check used to greedy-filter the candidate pool.
  // The puzzle is solved once, then the candidate is added on top and
  // solve is re-run. This re-uses the propagation work of the first
  // solve and is ~2× cheaper than two independent solves, but it is
  // *not* monotonic: a candidate can pass this check yet make the real
  // puzzle (which is *not* pre-solved) regress at the next iteration.
  // The cascade compensates by tracking the free-cell count between
  // iterations and rolling back any addition that regressed.
  final cloned = puzzle.clone();
  cloned.solve();
  final before = cloned.computeRatio();
  cloned.addConstraint(c);
  cloned.solve();
  final after = cloned.computeRatio();
  return after < before;
}
