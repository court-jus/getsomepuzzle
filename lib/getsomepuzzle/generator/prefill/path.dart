// Path-based puzzle pre-fill.
//
// Generates a "path-based" puzzle whose deduction is dominated by LT
// (LetterGroup) constraints. The pipeline (see docs/dev/path_based.md):
//
// 1. Sample anchor positions (L letters × K anchors each)
// 2. Assign a color to each letter (same-color or different-color)
// 3. Use DPLL routing (findOneSolutionByDpll) to obtain a complete
//    grid satisfying the LT constraints; derive the "intended path"
//    of each letter (its colored connected component minus anchors)
// 4. Bipartite-desambiguate via a 4-step priority cascade:
//      step 1: reveal an LT anchor in readonly
//      step 2: reveal a cell from a letter's intended path
//      step 3: add GC or QA (50/50), capped at one per (slug, color)
//      step 4: add any other garde-fou (GC/QA excluded)
//    Steps 1/2 require propagation beyond the revealed cell to be
//    accepted; steps 3/4 require the puzzle ratio to drop.
//
// Returns a [PathPrefillResult] with the player-facing puzzle and
// the complete solution, or null on failure.

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

const _domain = [1, 2];

// Garde-fou slugs allowed during bipartite desambiguation. LT is
// explicitly excluded (already placed by the pre-fill). SH is
// excluded because it conflicts with the path-based scenario. MJ
// (majority) is excluded for now — to be re-evaluated.
const _guardRailSlugs = [
  'CH',
  'GC', // group count — most path-friendly per user feedback
  'CC', // column count
  'RC', // row count
  'QA', // quantity
  'GS', // group size
  'PA', // parity
  'NC', // neighbor count
  'DF', // different from
  'SY', // symmetry
  'EY', // eyes
  'FM', // forbidden motif
];

class PathPrefillResult {
  final Puzzle puzzle; // player-facing state: LT + garde-fou + reveals
  final List<int> solution; // full solution values, index-ordered
  final int anchorRevealedCount; // anchors revealed during bipartite
  final int pathRevealedCount; // path cells revealed during bipartite
  final int guardRailCount; // non-LT constraints added during bipartite
  PathPrefillResult({
    required this.puzzle,
    required this.solution,
    required this.anchorRevealedCount,
    required this.pathRevealedCount,
    required this.guardRailCount,
  });

  int get revealedCount => anchorRevealedCount + pathRevealedCount;
}

class _Anchor {
  final String letter;
  final int idx;
  _Anchor(this.letter, this.idx);
}

/// Generate one path-based puzzle. Returns null on any failure (placement,
/// routing, or bipartite desambiguation).
PathPrefillResult? preFillPath(
  int width,
  int height,
  Random rng, {
  int numLetters = 2,
  int kMin = 2,
  int kMax = 3,
  double sameColorProb = 0.5,
  int maxRetries = 30,
  int routingTimeoutMs = 3000,
  bool preferInterior = true,
  int? bipartiteMaxReveals,
}) {
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    final anchorMap = _sampleAnchors(
      width,
      height,
      numLetters,
      kMin,
      kMax,
      rng,
      preferInterior: preferInterior,
    );
    if (anchorMap == null) continue;

    final colors = _assignColors(anchorMap.keys.toList(), sameColorProb, rng);

    // Build a bootstrap puzzle with anchors readonly + LT constraints to
    // feed the DPLL router. This is throwaway — used only to find a valid
    // routing solution.
    final bootstrap = Puzzle.empty(width, height, _domain);
    for (final entry in anchorMap.entries) {
      final color = colors[entry.key]!;
      for (final idx in entry.value) {
        bootstrap.cells[idx].setForSolver(color);
        bootstrap.cells[idx].readonly = true;
      }
      bootstrap.addConstraint(
        LetterGroup('${entry.key}.${entry.value.join(".")}'),
      );
    }

    final solution = findOneSolutionByDpll(
      bootstrap,
      timeoutMs: routingTimeoutMs,
    );
    if (solution == null) continue; // routing infeasible

    // Build the actual player-facing puzzle: empty grid, LT only, no
    // anchors marked readonly yet. The bipartite loop will reveal as
    // needed.
    //
    // TODO(prefill-readonly): evaluate `preFillRegular`-style random
    // readonly sprinkling (ratio ∈ [0.75, 1.0]) here before the
    // bipartite cascade — same lever applied to SY in `sy.dart`
    // unblocked convergence for the majority of seeds. The 4400+
    // guardrail candidate scan is wasted when the puzzle starts with
    // zero anchored cells.
    final puzzle = Puzzle.empty(width, height, _domain);
    for (final entry in anchorMap.entries) {
      puzzle.addConstraint(
        LetterGroup('${entry.key}.${entry.value.join(".")}'),
      );
    }

    // Enumerate garde-fou candidates valid against our solution.
    final solved = _buildSolvedPuzzle(width, height, solution);
    final candidates = _enumerateGuardRail(width, height, solved, rng);

    // Flatten anchors for bipartite reveal pool.
    final anchors = <_Anchor>[
      for (final e in anchorMap.entries)
        for (final idx in e.value) _Anchor(e.key, idx),
    ];

    // Derive the "intended path" of each letter from the DPLL solution:
    // the colored connected component reaching its anchors, minus the
    // anchors themselves. Revealing one of these cells during bipartite
    // is the subtle alternative to revealing an anchor — it forces the
    // solver to reason about connectivity around a midpoint.
    final intendedPaths = _computeIntendedPaths(
      width,
      height,
      solution,
      anchorMap,
    );

    final result = _bipartiteDesambiguate(
      puzzle: puzzle,
      solution: solution,
      anchors: anchors,
      intendedPaths: intendedPaths,
      candidates: candidates,
      maxReveals: bipartiteMaxReveals ?? anchors.length,
      rng: rng,
    );

    if (result == null) continue; // bipartite exhausted

    return PathPrefillResult(
      puzzle: puzzle,
      solution: solution,
      anchorRevealedCount: result.anchorRevealedCount,
      pathRevealedCount: result.pathRevealedCount,
      guardRailCount: result.guardRailCount,
    );
  }
  return null;
}

/// For each letter, compute the connected component of its color in the
/// solution that contains its anchors, minus the anchors themselves.
/// BFS over 4-connected cells of color `solution[anchor_0]` starting from
/// any anchor.
Map<String, Set<int>> _computeIntendedPaths(
  int width,
  int height,
  List<int> solution,
  Map<String, List<int>> anchorMap,
) {
  final result = <String, Set<int>>{};
  for (final entry in anchorMap.entries) {
    final letter = entry.key;
    final anchors = entry.value;
    if (anchors.isEmpty) {
      result[letter] = <int>{};
      continue;
    }
    final color = solution[anchors.first];
    final visited = <int>{anchors.first};
    final queue = <int>[anchors.first];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final cx = cur % width;
      final cy = cur ~/ width;
      const dxs = [-1, 1, 0, 0];
      const dys = [0, 0, -1, 1];
      for (int d = 0; d < 4; d++) {
        final nx = cx + dxs[d];
        final ny = cy + dys[d];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final ni = ny * width + nx;
        if (visited.contains(ni)) continue;
        if (solution[ni] != color) continue;
        visited.add(ni);
        queue.add(ni);
      }
    }
    visited.removeAll(anchors);
    result[letter] = visited;
  }
  return result;
}

class _BipartiteResult {
  final int anchorRevealedCount;
  final int pathRevealedCount;
  final int guardRailCount;
  _BipartiteResult(
    this.anchorRevealedCount,
    this.pathRevealedCount,
    this.guardRailCount,
  );
}

_BipartiteResult? _bipartiteDesambiguate({
  required Puzzle puzzle,
  required List<int> solution,
  required List<_Anchor> anchors,
  required Map<String, Set<int>> intendedPaths,
  required List<Constraint> candidates,
  required int maxReveals,
  required Random rng,
}) {
  // Reveal pools (shuffled). Failed-but-still-eligible entries stay in
  // the pool so they can be retried after a later step adds a guardrail
  // that unlocks propagation through them.
  final unrevealedAnchors = [...anchors]..shuffle(rng);
  final unrevealedPathCells = <int>[
    for (final cells in intendedPaths.values) ...cells,
  ]..shuffle(rng);

  int anchorReveals = 0;
  int pathReveals = 0;
  int guardRail = 0;

  // Safety: cap total iterations to prevent infinite loops if a bug
  // makes neither action progressive but isDeductivelyUnique never
  // returns true.
  const maxIterations = 200;
  int iter = 0;

  while (iter < maxIterations) {
    iter++;
    if (puzzle.isDeductivelyUnique()) {
      return _BipartiteResult(anchorReveals, pathReveals, guardRail);
    }

    final revealedTotal = anchorReveals + pathReveals;

    // Step 1: anchor reveal (highest priority — most LT-aligned).
    if (revealedTotal < maxReveals &&
        _tryRevealAnchorStrict(
          puzzle: puzzle,
          solution: solution,
          unrevealed: unrevealedAnchors,
        )) {
      anchorReveals++;
      continue;
    }

    // Step 2: path cell reveal — subtle, forces connectivity reasoning.
    if (revealedTotal < maxReveals &&
        _tryRevealPathCellStrict(
          puzzle: puzzle,
          solution: solution,
          unrevealed: unrevealedPathCells,
        )) {
      pathReveals++;
      continue;
    }

    // Step 3: GC or QA (50/50), capped at one per (slug, color).
    if (_tryAddGcOrQa(puzzle, candidates, rng)) {
      guardRail++;
      continue;
    }

    // Step 4: any other garde-fou (GC and QA already handled).
    if (_tryAddOtherGuardrail(puzzle, candidates)) {
      guardRail++;
      continue;
    }

    return null; // bipartite exhausted
  }
  return null;
}

/// Reveal an anchor only if doing so propagates beyond the cell itself
/// (≥ 2 fewer free cells after solve). Failed candidates stay in the
/// pool: a later guardrail may unlock their propagation.
bool _tryRevealAnchorStrict({
  required Puzzle puzzle,
  required List<int> solution,
  required List<_Anchor> unrevealed,
}) {
  for (int i = 0; i < unrevealed.length; i++) {
    final a = unrevealed[i];
    if (puzzle.cells[a.idx].readonly) {
      // Stale (already revealed by some other path). Drop and skip.
      unrevealed.removeAt(i);
      i--;
      continue;
    }
    if (_revealPropagates(puzzle, solution, a.idx)) {
      puzzle.cells[a.idx].setForSolver(solution[a.idx]);
      puzzle.cells[a.idx].readonly = true;
      unrevealed.removeAt(i);
      return true;
    }
  }
  return false;
}

/// Same strict propagation check, but on path cells (non-anchor cells
/// of a letter's colored connected component).
bool _tryRevealPathCellStrict({
  required Puzzle puzzle,
  required List<int> solution,
  required List<int> unrevealed,
}) {
  for (int i = 0; i < unrevealed.length; i++) {
    final idx = unrevealed[i];
    if (puzzle.cells[idx].readonly) {
      unrevealed.removeAt(i);
      i--;
      continue;
    }
    if (_revealPropagates(puzzle, solution, idx)) {
      puzzle.cells[idx].setForSolver(solution[idx]);
      puzzle.cells[idx].readonly = true;
      unrevealed.removeAt(i);
      return true;
    }
  }
  return false;
}

/// Probe whether revealing [idx] propagates to at least one other cell.
/// Clones the puzzle, solves, counts free cells, then sets the cell and
/// re-solves. Accept iff the free-cell count drops by ≥ 2.
bool _revealPropagates(Puzzle puzzle, List<int> solution, int idx) {
  final probe = puzzle.clone();
  probe.solve();
  final freeBefore = probe.freeCells().length;
  if (!probe.cells[idx].isFree) {
    // Already determined by current state → revealing brings nothing.
    return false;
  }
  probe.cells[idx].setForSolver(solution[idx]);
  probe.cells[idx].readonly = true;
  probe.solve();
  final freeAfter = probe.freeCells().length;
  return freeBefore - freeAfter >= 2;
}

/// Step 3: try to add a GC or QA constraint (50/50), respecting the
/// cap of one per (slug, color). If the preferred slug yields no
/// helpful candidate, falls back to the other slug.
bool _tryAddGcOrQa(Puzzle puzzle, List<Constraint> candidates, Random rng) {
  final occupied = <(String, int)>{};
  for (final c in puzzle.constraints) {
    if (c is GroupCountConstraint) occupied.add(('GC', c.color));
    if (c is QuantityConstraint) occupied.add(('QA', c.value));
  }
  // 2 colors × 2 slugs = 4 max slots
  if (occupied.length >= 4) return false;

  final tryOrder = rng.nextBool() ? ['GC', 'QA'] : ['QA', 'GC'];
  for (final preferredSlug in tryOrder) {
    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c.slug != preferredSlug) continue;
      int color;
      if (c is GroupCountConstraint) {
        color = c.color;
      } else if (c is QuantityConstraint) {
        color = c.value;
      } else {
        continue;
      }
      if (occupied.contains((preferredSlug, color))) continue;
      if (_constraintHelps(puzzle, c)) {
        puzzle.addConstraint(c);
        candidates.removeAt(i);
        return true;
      }
    }
  }
  return false;
}

/// Step 4: any non-GC/QA guardrail that helps. Mirrors the original
/// `_tryAddConstraint` acceptance rule (ratio must drop).
bool _tryAddOtherGuardrail(Puzzle puzzle, List<Constraint> candidates) {
  for (int i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    if (c.slug == 'GC' || c.slug == 'QA') continue;
    if (_constraintHelps(puzzle, c)) {
      puzzle.addConstraint(c);
      candidates.removeAt(i);
      return true;
    }
  }
  return false;
}

bool _constraintHelps(Puzzle puzzle, Constraint c) {
  final cloned = puzzle.clone();
  cloned.solve();
  final before = cloned.computeRatio();
  cloned.addConstraint(c);
  cloned.solve();
  final after = cloned.computeRatio();
  return after < before;
}

/// Place [numLetters] × [k] anchors on the grid with the constraints:
/// - same-letter anchors are at Manhattan distance ≥ min_dist
/// - different-letter anchors are NOT 4-adjacent (would auto-violate LT)
/// - placement zone biased to interior when [preferInterior] is set
Map<String, List<int>>? _sampleAnchors(
  int width,
  int height,
  int numLetters,
  int kMin,
  int kMax,
  Random rng, {
  required bool preferInterior,
}) {
  const maxLocalTries = 200;
  final minSameLetter = max(2, ((min(width, height)) / 2).ceil());

  // Compute K per letter (each letter gets a fresh draw).
  final ksPerLetter = <int>[
    for (int i = 0; i < numLetters; i++)
      kMin + rng.nextInt(max(1, kMax - kMin + 1)),
  ];
  final totalAnchors = ksPerLetter.fold<int>(0, (s, k) => s + k);

  // Build placement zone (interior if applicable + large enough).
  List<int> zone;
  if (preferInterior && width >= 4 && height >= 4) {
    zone = <int>[];
    for (int r = 1; r < height - 1; r++) {
      for (int c = 1; c < width - 1; c++) {
        zone.add(c + r * width);
      }
    }
    if (zone.length < totalAnchors * 2) {
      // Interior too small — fall back to full grid.
      zone = List.generate(width * height, (i) => i);
    }
  } else {
    zone = List.generate(width * height, (i) => i);
  }

  final placed = <_Anchor>[];
  for (int li = 0; li < numLetters; li++) {
    final letter = String.fromCharCode(65 + li); // A, B, C, ...
    final k = ksPerLetter[li];
    for (int ki = 0; ki < k; ki++) {
      bool ok = false;
      for (int t = 0; t < maxLocalTries; t++) {
        final idx = zone[rng.nextInt(zone.length)];
        // Reject if any prior anchor at this index.
        if (placed.any((p) => p.idx == idx)) continue;
        // Reject if same-letter anchor too close.
        bool sameLetterTooClose = false;
        for (final p in placed) {
          if (p.letter == letter &&
              _manhattan(p.idx, idx, width) < minSameLetter) {
            sameLetterTooClose = true;
            break;
          }
        }
        if (sameLetterTooClose) continue;
        // Reject if different-letter anchor 4-adjacent.
        bool diffLetterAdjacent = false;
        for (final p in placed) {
          if (p.letter != letter && _manhattan(p.idx, idx, width) <= 1) {
            diffLetterAdjacent = true;
            break;
          }
        }
        if (diffLetterAdjacent) continue;
        placed.add(_Anchor(letter, idx));
        ok = true;
        break;
      }
      if (!ok) return null;
    }
  }

  // Group by letter (preserving placement order).
  final result = <String, List<int>>{};
  for (final p in placed) {
    result.putIfAbsent(p.letter, () => <int>[]).add(p.idx);
  }
  return result;
}

Map<String, int> _assignColors(
  List<String> letters,
  double sameColorProb,
  Random rng,
) {
  // For L=2, two sub-cases: same-color (both 1 or both 2) or different.
  // For L>=3 with 2 colors, at least one same-color pair exists by
  // pigeonhole — we partition into two color groups randomly.
  final colors = <String, int>{};
  if (letters.length == 2) {
    if (rng.nextDouble() < sameColorProb) {
      final shared = rng.nextBool() ? 1 : 2;
      colors[letters[0]] = shared;
      colors[letters[1]] = shared;
    } else {
      final c0 = rng.nextBool() ? 1 : 2;
      colors[letters[0]] = c0;
      colors[letters[1]] = 3 - c0;
    }
  } else {
    // For L>=3: assign each letter a random color independently.
    for (final l in letters) {
      colors[l] = rng.nextBool() ? 1 : 2;
    }
  }
  return colors;
}

List<Constraint> _enumerateGuardRail(
  int width,
  int height,
  Puzzle solved,
  Random rng,
) {
  final out = <Constraint>[];
  for (final slug in _guardRailSlugs) {
    final params = generateAllParameters(slug, width, height, _domain, null);
    if (params == null) continue;
    for (final p in params) {
      final c = createConstraint(slug, p);
      if (c == null) continue;
      if (c.verify(solved)) out.add(c);
    }
  }
  out.shuffle(rng);
  // Stable sort biasing GC to the front (user observation: most
  // path-friendly). Other slugs keep their shuffled order.
  out.sort((a, b) {
    final ga = a.slug == 'GC' ? 0 : 1;
    final gb = b.slug == 'GC' ? 0 : 1;
    return ga.compareTo(gb);
  });
  return out;
}

Puzzle _buildSolvedPuzzle(int width, int height, List<int> solution) {
  final pu = Puzzle.empty(width, height, _domain);
  for (int i = 0; i < pu.cells.length; i++) {
    pu.cells[i].setForSolver(solution[i]);
  }
  return pu;
}

int _manhattan(int a, int b, int width) {
  final ca = a % width;
  final ra = a ~/ width;
  final cb = b % width;
  final rb = b ~/ width;
  return (ca - cb).abs() + (ra - rb).abs();
}
