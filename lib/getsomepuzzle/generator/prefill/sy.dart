// SY-based puzzle pre-fill.
//
// Generates a "SY-based" puzzle dominated by SymmetryConstraint. The
// pipeline (see docs/dev/prefill_sy.md):
//
// 1. Pick a background colour (uniform over the domain) and sample N
//    seed cells in the grid interior, well-separated from each other.
// 2. For each seed, pick a feasible SY axis (one that allows growth).
// 3. Grow each island by adding free cells in pairs (cell + its
//    mirror), maintaining a forbidden halo around other islands so
//    they cannot merge.
// 4. Build the solved grid: background colour everywhere, each island
//    in its own colour drawn from domain \ {bg} (on 3-colour domains,
//    at least two distinct island colours are guaranteed), and attach
//    one SY per seed.
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
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

// Guardrail slugs allowed in the SY pipeline. SY is excluded (dominant
// slug, already placed). SH is excluded — two shape-flavored
// constraints would compete. LT is included but inter-island candidates
// get filtered out (would force a merge that breaks symmetry).
const _guardRailSlugs = [
  'CH',
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
  final List<CellValue> solution;
  final int numIslands;
  final int seedRevealedCount;
  final int islandCellRevealedCount;
  final int guardRailCount;

  SyPrefillResult({
    required this.puzzle,
    required this.solution,
    required this.numIslands,
    required this.seedRevealedCount,
    required this.islandCellRevealedCount,
    required this.guardRailCount,
  });

  int get revealedCount => seedRevealedCount + islandCellRevealedCount;
}

class _Island {
  final int seed;
  final int axis;
  final Set<int> cells = <int>{};
  bool frozen = false;
  CellValue color = CellValue.free;
  _Island(this.seed, this.axis);
}

/// Generate one SY-based puzzle. Returns null on any failure.
SyPrefillResult? preFillSy(
  int width,
  int height,
  List<CellValue> domain,
  Random rng, {
  int? numIslands,
  int edgeMargin = 1,
  int? minSeedDist,
  double stopProb = 0.2,
  int minIslandSize = 3,
  int? maxIslandSize,
  int maxRetries = 30,
  int? bipartiteMaxReveals,
  // Deadline hook: checked between attempts, cascade iterations and
  // candidate probes, and forwarded to every inner `solve()`. On
  // 3-colour domains a single solve can degenerate into a massive
  // force sweep (weak propagation → `_forceOneCell` fires at nearly
  // every step), so an unbounded attempt can run for minutes — far
  // beyond any caller deadline.
  bool Function()? shouldStop,
  // Optional instrumentation hook (used by bin/validate_sy_domain3.dart):
  // receives one line per attempt / cascade event. Inert when null.
  void Function(String message)? debugLog,
}) {
  final n = numIslands ?? (width * height >= 40 ? 3 : 2);
  final minDist = minSeedDist ?? max(3, ((min(width, height)) / 2).ceil());
  final maxSize = maxIslandSize ?? max(4, ((width * height) / (2 * n)).ceil());

  for (int attempt = 0; attempt < maxRetries; attempt++) {
    if (shouldStop?.call() == true) {
      debugLog?.call('bail: shouldStop (attempt $attempt)');
      return null;
    }
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

    final colors = pickIslandColors(islands.length, domain, rng);
    for (int i = 0; i < islands.length; i++) {
      islands[i].color = colors.islandColors[i];
    }
    debugLog?.call(
      'attempt $attempt: islands='
      '${islands.map((i) => '${i.cells.length}c/ax${i.axis}/${i.color.name}').join(' ')} '
      'bg=${colors.bg.name}',
    );

    final solution = List<CellValue>.filled(width * height, colors.bg);
    for (final isl in islands) {
      for (final c in isl.cells) {
        solution[c] = isl.color;
      }
    }

    // Build the player-facing puzzle: empty grid + SY anchors.
    final puzzle = Puzzle.empty(width, height, domain);
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
    final solved = _buildSolvedPuzzle(width, height, domain, solution);
    final candidates = _enumerateGuardRail(
      width,
      height,
      domain,
      solved,
      islandOf,
      rng,
    );
    debugLog?.call('  candidates=${candidates.length}');

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
      shouldStop: shouldStop,
      debugLog: debugLog,
    );

    if (result == null) continue;

    return SyPrefillResult(
      puzzle: puzzle,
      solution: solution,
      numIslands: islands.length,
      seedRevealedCount: result.$1,
      islandCellRevealedCount: result.$2,
      guardRailCount: result.$3,
    );
  }
  return null;
}

/// Pick the background colour and one colour per island.
///
/// The background is uniform over [domain]; each island draws its own
/// colour from `domain \ {bg}`. On a 2-colour domain this degenerates
/// to the classic bg/fg dichotomy. On 3-colour domains, a puzzle whose
/// islands all share one colour is functionally 2-colour and would be
/// auto-shrunk at export — a wasted domain-3 attempt — so when at
/// least two islands exist, one random island is recoloured to
/// guarantee at least two distinct island colours.
///
/// Public so the colour logic can be unit-tested without running the
/// full (stochastic, expensive) pre-fill pipeline.
({CellValue bg, List<CellValue> islandColors}) pickIslandColors(
  int nIslands,
  List<CellValue> domain,
  Random rng,
) {
  final bg = domain[rng.nextInt(domain.length)];
  final fgChoices = domain.where((c) => c != bg).toList();
  final islandColors = [
    for (int i = 0; i < nIslands; i++) fgChoices[rng.nextInt(fgChoices.length)],
  ];
  if (fgChoices.length >= 2 &&
      nIslands >= 2 &&
      islandColors.toSet().length == 1) {
    final i = rng.nextInt(nIslands);
    final others = fgChoices.where((c) => c != islandColors[i]).toList();
    islandColors[i] = others[rng.nextInt(others.length)];
  }
  return (bg: bg, islandColors: islandColors);
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

Puzzle _buildSolvedPuzzle(
  int width,
  int height,
  List<CellValue> domain,
  List<CellValue> solution,
) {
  final pu = Puzzle.empty(width, height, domain);
  for (int i = 0; i < pu.cells.length; i++) {
    pu.cells[i].setForSolver(solution[i]);
  }
  return pu;
}

/// Enumerate guardrail candidates valid against the solution. LT
/// candidates whose anchors span more than one region (one specific
/// island OR ocean) are filtered out — they would force an
/// island-merging route that breaks SY.
List<Constraint> _enumerateGuardRail(
  int width,
  int height,
  List<CellValue> domain,
  Puzzle solved,
  List<int> islandOf,
  Random rng,
) {
  final out = <Constraint>[];
  for (final slug in _guardRailSlugs) {
    final params = generateAllParameters(slug, width, height, domain, null);
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
  required List<CellValue> solution,
  required List<int> seedPool,
  required List<int> islandCellPool,
  required List<Constraint> candidates,
  required int maxReveals,
  required Random rng,
  bool Function()? shouldStop,
  void Function(String message)? debugLog,
}) {
  int seedReveals = 0;
  int islandCellReveals = 0;
  int guardRail = 0;
  final sw = Stopwatch()..start();

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
    if (shouldStop?.call() == true) {
      debugLog?.call('  bail: shouldStop');
      return null;
    }
    final tUnique = sw.elapsedMilliseconds;
    if (puzzle.isDeductivelyUnique(shouldStop: shouldStop)) {
      debugLog?.call(
        '  cascade: unique at iter $iter '
        '(reveals=$seedReveals+$islandCellReveals guard=$guardRail '
        '${sw.elapsedMilliseconds}ms)',
      );
      return (seedReveals, islandCellReveals, guardRail);
    }
    final uniqueMs = sw.elapsedMilliseconds - tUnique;

    final revealedTotal = seedReveals + islandCellReveals;
    // Solved snapshot of the current puzzle. Reused as the base state of
    // every probe in this iteration (reveal and guardrail candidates):
    // the puzzle does not change between here and the accepted phase, so
    // re-solving it per candidate — the dominant cascade cost on weakly
    // propagating (3-colour) states — would be pure waste.
    var solvedBase = puzzle.clone();
    solvedBase.solve(shouldStop: shouldStop);
    int freeRemaining = solvedBase.freeCells().length;
    debugLog?.call(
      '  iter $iter: free=$freeRemaining reveals=$revealedTotal '
      'guard=$guardRail uniqueProbe=${uniqueMs}ms total=${sw.elapsedMilliseconds}ms',
    );

    // Rollback the last guardrail if it regressed the real puzzle. We
    // only rollback when free strictly grew: equal stays accepted (the
    // constraint may still constrain the solution space without
    // visible propagation gain). Reveals (phase 1/2) are never rolled
    // back: they materialise actual cell values from the solution and
    // cannot regress propagation by construction.
    if (prevFree >= 0 && freeRemaining > prevFree && guardRail > 0) {
      puzzle.removeConstraintAt(puzzle.constraints.length - 1);
      guardRail--;
      // The puzzle changed: refresh the solved snapshot.
      solvedBase = puzzle.clone();
      solvedBase.solve(shouldStop: shouldStop);
      freeRemaining = solvedBase.freeCells().length;
      consecutiveRollbacks++;
      debugLog?.call('  rollback #$consecutiveRollbacks (free=$freeRemaining)');
      if (consecutiveRollbacks >= maxConsecutiveRollbacks) {
        debugLog?.call('  bail: maxConsecutiveRollbacks');
        return null;
      }
    }

    if (freeRemaining < bestFree) {
      bestFree = freeRemaining;
      consecutiveRollbacks = 0;
    }
    if (guardRail >= maxGuardrails) {
      debugLog?.call('  bail: maxGuardrails');
      return null;
    }

    bool advanced = false;
    final tPhase = sw.elapsedMilliseconds;
    String phase = 'none';
    if (revealedTotal < maxReveals &&
        _tryRevealStrict(puzzle, solution, seedPool, solvedBase, shouldStop)) {
      seedReveals++;
      advanced = true;
      phase = 'seedReveal';
    } else if (revealedTotal < maxReveals &&
        _tryRevealStrict(
          puzzle,
          solution,
          islandCellPool,
          solvedBase,
          shouldStop,
        )) {
      islandCellReveals++;
      advanced = true;
      phase = 'islandReveal';
    } else if (_tryAddGcOrQa(puzzle, candidates, rng, solvedBase, shouldStop)) {
      guardRail++;
      advanced = true;
      phase = 'gcQa';
    } else if (_tryAddOtherGuardrail(
      puzzle,
      candidates,
      solvedBase,
      shouldStop,
    )) {
      guardRail++;
      advanced = true;
      phase = 'otherGuardrail';
    }
    debugLog?.call(
      '  phase=$phase ${sw.elapsedMilliseconds - tPhase}ms '
      'candidatesLeft=${candidates.length}',
    );
    prevFree = freeRemaining;
    if (!advanced) {
      debugLog?.call('  bail: noAdvance (pools/candidates exhausted)');
      return null;
    }
  }
  debugLog?.call('  bail: maxIterations');
  return null;
}

/// Reveal a cell from [pool] iff doing so propagates beyond itself
/// (free-cell count drops by ≥ 2). Failed candidates stay in the pool —
/// a later guardrail may unlock their propagation.
bool _tryRevealStrict(
  Puzzle puzzle,
  List<CellValue> solution,
  List<int> pool,
  Puzzle solvedBase,
  bool Function()? shouldStop,
) {
  for (int i = 0; i < pool.length; i++) {
    if (shouldStop?.call() == true) return false;
    final idx = pool[i];
    if (puzzle.cells[idx].readonly) {
      pool.removeAt(i);
      i--;
      continue;
    }
    if (_revealPropagates(solvedBase, solution, idx, shouldStop)) {
      puzzle.cells[idx].setForSolver(solution[idx]);
      puzzle.cells[idx].readonly = true;
      pool.removeAt(i);
      return true;
    }
  }
  return false;
}

/// Accept iff revealing [idx] propagates beyond itself (free-cell count
/// drops by ≥ 2). [solvedBase] is the pre-solved snapshot of the current
/// puzzle, shared across the whole cascade iteration.
bool _revealPropagates(
  Puzzle solvedBase,
  List<CellValue> solution,
  int idx,
  bool Function()? shouldStop,
) {
  final freeBefore = solvedBase.freeCells().length;
  if (!solvedBase.cells[idx].isFree) return false;
  final probe = solvedBase.clone();
  probe.cells[idx].setForSolver(solution[idx]);
  probe.cells[idx].readonly = true;
  probe.solve(shouldStop: shouldStop);
  final freeAfter = probe.freeCells().length;
  return freeBefore - freeAfter >= 2;
}

bool _tryAddGcOrQa(
  Puzzle puzzle,
  List<Constraint> candidates,
  Random rng,
  Puzzle solvedBase,
  bool Function()? shouldStop,
) {
  final occupied = <(String, CellValue)>{};
  for (final c in puzzle.constraints) {
    if (c is GroupCountConstraint) occupied.add(('GC', c.color));
    if (c is QuantityConstraint) occupied.add(('QA', c.color));
  }
  // 2 slugs (GC, QA) × one slot per domain colour.
  if (occupied.length >= 2 * puzzle.domain.length) return false;

  // Classic-style consumption: a candidate is permanently removed from the
  // list even if it doesn't help. Avoids repeatedly re-scanning non-helpers
  // on every cascade iteration.
  final tryOrder = rng.nextBool() ? ['GC', 'QA'] : ['QA', 'GC'];
  for (final preferredSlug in tryOrder) {
    int i = 0;
    while (i < candidates.length) {
      final c = candidates[i];
      if (c.slug != preferredSlug) {
        i++;
        continue;
      }
      CellValue color;
      if (c is GroupCountConstraint) {
        color = c.color;
      } else if (c is QuantityConstraint) {
        color = c.color;
      } else {
        i++;
        continue;
      }
      if (occupied.contains((preferredSlug, color))) {
        // That (slug, colour) slot is already taken; candidate is useless.
        candidates.removeAt(i);
        continue;
      }
      candidates.removeAt(i);
      if (shouldStop?.call() == true) return false;
      if (_constraintHelps(solvedBase, c, shouldStop)) {
        puzzle.addConstraint(c);
        return true;
      }
    }
  }
  return false;
}

bool _tryAddOtherGuardrail(
  Puzzle puzzle,
  List<Constraint> candidates,
  Puzzle solvedBase,
  bool Function()? shouldStop,
) {
  // Classic-style consumption: every non-GC/QA candidate is removed even if
  // it doesn't help. Avoids repeatedly scanning thousands of useless
  // candidates on every cascade iteration.
  int i = 0;
  while (i < candidates.length) {
    if (shouldStop?.call() == true) return false;
    final c = candidates[i];
    if (c.slug == 'GC' || c.slug == 'QA') {
      i++;
      continue;
    }
    candidates.removeAt(i);
    if (_constraintHelps(solvedBase, c, shouldStop)) {
      puzzle.addConstraint(c);
      return true;
    }
  }
  return false;
}

bool _constraintHelps(
  Puzzle solvedBase,
  Constraint c,
  bool Function()? shouldStop,
) {
  // Fast (approximate) check used to greedy-filter the candidate pool.
  // [solvedBase] is the pre-solved snapshot of the current puzzle,
  // computed once per cascade iteration and shared by every candidate
  // probe; the candidate is added on top and solve is re-run. This
  // re-uses the propagation work of the base solve and is ~2× cheaper
  // than two independent solves, but it is *not* monotonic: a candidate
  // can pass this check yet make the real puzzle (which is *not*
  // pre-solved) regress at the next iteration. The cascade compensates
  // by tracking the free-cell count between iterations and rolling back
  // any addition that regressed.
  final before = solvedBase.computeRatio();
  final cloned = solvedBase.clone();
  cloned.addConstraint(c);
  cloned.solve(shouldStop: shouldStop);
  final after = cloned.computeRatio();
  return after < before;
}
