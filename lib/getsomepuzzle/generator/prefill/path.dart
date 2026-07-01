// Path-based puzzle pre-fill (constructive).
//
// Generates a "path-based" puzzle whose deduction is dominated by LT
// (LetterGroup) constraints. It maintains routing feasibility *by
// construction* rather than searching for it:
//
// 1. Assign a color to each letter (`assignColors`).
// 2. Build each letter's region incrementally in the *residual graph*: place
//    its first anchor, flood-fill the reachable component, pick the next
//    anchor inside it, and connect them with a winding self-avoiding walk.
//    The residual excludes cells already owned by another letter and, for a
//    letter sharing a color with an existing region, the one-cell moat around
//    that region (prevents the same-color merge that LT forbids). Different
//    color → adjacency allowed. A failure (empty reachable component) is
//    detected in O(cells), never via exponential search.
// 3. Complete the background with a single DPLL pass on a throwaway copy
//    carrying the LT constraints — feasible by construction, so near-instant.
//
// Returns a [PathPrefillResult] holding the PURE solved grid (no constraints
// attached) and the backbone LetterGroups separately, so the caller can seed
// them into the player puzzle without polluting the classic branch's candidate
// enumeration (which reads constraints off `solved`).

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

class PathPrefillResult {
  final Puzzle solved; // PURE colored grid: complete solution, no constraints
  final List<LetterGroup> letterGroups; // backbone LTs, to seed into `pu`
  final int backboneCells; // cells owned by a built region (excludes the DPLL
  // background fill) — a diagnostic and the observable for the sinuosity lever.
  PathPrefillResult({
    required this.solved,
    required this.letterGroups,
    required this.backboneCells,
  });
}

/// The constructed letter regions before background completion. The grid's
/// background is still free; `findOneSolutionByDpll` fills it later. Exposed
/// (with [owner]/[colors]) so the structural invariants — same-color
/// non-merge, monochrome connectivity, colour coverage — can be tested
/// atomically on the construction alone, without running the DPLL completion.
class PathBackbone {
  final Puzzle solved; // regions painted, background still free
  final List<String?> owner; // letter owning each cell, or null (background)
  final Map<String, List<int>> anchors;
  final Map<String, CellValue> colors;
  PathBackbone(this.solved, this.owner, this.anchors, this.colors);
  int get backboneCells => owner.where((o) => o != null).length;
}

/// Generate one constructive path-based solution. Returns null on any failure
/// (region placement ran out of room, or background completion failed). The
/// returned grid is fully colored and carries NO constraints; the backbone
/// LetterGroups are returned alongside.
///
/// [windingProb] in [0, 1] tunes path sinuosity: 0 ≈ shortest path (easy
/// puzzles, regions trivially separated), higher ≈ snakes that wind around
/// each other (topological tension, harder LT deductions).
PathPrefillResult? preFillPath(
  int width,
  int height,
  List<CellValue> domain,
  Random rng, {
  int? numLetters,
  int kMin = 2,
  int kMax = 3,
  double sameColorProb = 0.5,
  double windingProb = 0.5,
  int maxRetries = 30,
  int completionTimeoutMs = 2000,
  PathPrefillStats? stats,
  bool Function()? shouldStop,
}) {
  final sw = Stopwatch()..start();
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    stats?.retriesUsed = attempt + 1;
    if (shouldStop?.call() == true) break;
    final backbone = buildPathBackbone(
      width,
      height,
      domain,
      rng,
      numLetters: numLetters,
      kMin: kMin,
      kMax: kMax,
      sameColorProb: sameColorProb,
      windingProb: windingProb,
    );
    if (backbone == null) {
      _bump(stats, PathFailCause.placement);
      continue;
    }
    final result = _completeBackground(backbone, completionTimeoutMs, stats);
    if (result != null) {
      stats?.prefillMs = sw.elapsedMilliseconds;
      return result;
    }
  }
  stats?.prefillMs = sw.elapsedMilliseconds;
  return null;
}

/// Construct the letter regions (steps 1–4: colors, anchors, winding walks) on
/// a fresh grid, leaving the background free. Returns null if a region had no
/// room. PUBLIC so the construction invariants can be tested atomically (no
/// DPLL here — fast and deterministic for a given [rng]).
PathBackbone? buildPathBackbone(
  int width,
  int height,
  List<CellValue> domain,
  Random rng, {
  int? numLetters,
  int kMin = 2,
  int kMax = 3,
  double sameColorProb = 0.5,
  double windingProb = 0.5,
}) {
  // Letter-count floor is the domain size so every colour is owned by at least
  // one letter — a genuine N-colour outcome that survives `autoShrinkDomain`.
  // Surplus letters add same-colour pairs (the hard separation case).
  final maxExtra = domain.length >= 3 ? 1 : 2;
  final nLetters = numLetters ?? domain.length + rng.nextInt(maxExtra + 1);
  final minSameLetter = max(2, (min(width, height) / 2).ceil());

  final letters = pathLetterNames(nLetters);
  final colors = assignColors(letters, domain, sameColorProb, rng);
  final solved = Puzzle.empty(width, height, domain);
  final owner = List<String?>.filled(width * height, null);
  final anchorsByLetter = <String, List<int>>{};

  for (final letter in letters) {
    final color = colors[letter]!;
    final k = kMin + rng.nextInt(kMax - kMin + 1);
    final anchors = _buildRegion(
      solved,
      owner,
      letter,
      color,
      k,
      minSameLetter,
      windingProb,
      rng,
    );
    if (anchors == null) return null;
    anchorsByLetter[letter] = anchors;
  }
  return PathBackbone(solved, owner, anchorsByLetter, colors);
}

/// Fill the still-free background of [backbone] with a single DPLL pass on a
/// throwaway copy carrying the LT constraints (the originals stay on a copy so
/// `backbone.solved` is returned PURE). Feasible by construction, so this is a
/// near-instant solve; null on the defensive timeout/infeasible path.
PathPrefillResult? _completeBackground(
  PathBackbone backbone,
  int completionTimeoutMs,
  PathPrefillStats? stats,
) {
  final solved = backbone.solved;
  final lts = <LetterGroup>[
    for (final e in backbone.anchors.entries)
      LetterGroup('${e.key}.${e.value.join(".")}'),
  ];

  final copy = solved.clone();
  for (final lt in lts) {
    copy.addConstraint(lt);
  }
  final routingSw = Stopwatch()..start();
  final routed = findOneSolutionByDpll(copy, timeoutMs: completionTimeoutMs);
  routingSw.stop();
  if (stats != null) {
    stats.routingCalls++;
    final ms = routingSw.elapsedMilliseconds;
    stats.routingMsTotal += ms;
    if (ms > stats.routingMsMax) stats.routingMsMax = ms;
  }
  final solution = routed.solution;
  if (solution == null) {
    _bump(
      stats,
      routed.timedOut
          ? PathFailCause.routingTimeout
          : PathFailCause.routingInfeasible,
    );
    return null;
  }

  // Apply the completed background to the pure grid (painted cells already
  // match `solution`; only the free background cells need filling).
  for (int i = 0; i < solved.cells.length; i++) {
    if (solved.cellValues[i] == CellValue.free) {
      solved.cells[i].setForSolver(solution[i]);
    }
  }
  return PathPrefillResult(
    solved: solved,
    letterGroups: lts,
    backboneCells: backbone.backboneCells,
  );
}

/// Place [k] anchors for [letter] (color [color]) and wire them into a single
/// connected monochrome region. Returns the anchor indices, or null if there
/// was no room (residual empty / no reachable second anchor).
List<int>? _buildRegion(
  Puzzle solved,
  List<String?> owner,
  String letter,
  CellValue color,
  int k,
  int minSameLetter,
  double windingProb,
  Random rng,
) {
  final width = solved.width;
  final size = owner.length;

  // A cell is traversable for this letter iff it is free (or already ours, for
  // incremental connectivity) AND not adjacent to another letter's region of
  // the SAME color — the one-cell moat that prevents an LT-forbidden merge.
  bool canTraverse(int idx) {
    final o = owner[idx];
    if (o != null && o != letter) return false;
    for (final n in solved.getNeighbors(idx)) {
      final on = owner[n];
      if (on != null && on != letter && solved.cellValues[n] == color) {
        return false;
      }
    }
    return true;
  }

  // First anchor: any traversable free cell, lightly biased toward the
  // interior so regions have room to wind.
  final seeds = [
    for (int i = 0; i < size; i++)
      if (owner[i] == null && canTraverse(i)) i,
  ];
  if (seeds.isEmpty) return null;
  final first = _pickInterior(seeds, width, solved.height, rng);
  _paint(solved, owner, first, color, letter);
  final anchors = <int>[first];

  // Remaining anchors: flood from the current region, pick a reachable cell at
  // least `minSameLetter` away from existing anchors, connect it.
  for (int a = 1; a < k; a++) {
    final region = [
      for (int i = 0; i < size; i++)
        if (owner[i] == letter) i,
    ];
    final flood = floodFill(solved, region, canTraverse);
    final reachable = flood
        .where(
          (i) =>
              owner[i] == null &&
              anchors.every((an) => _manhattan(an, i, width) >= minSameLetter),
        )
        .toList();
    if (reachable.isEmpty) {
      // The mandatory second anchor failing means this attempt is dead; a
      // missing third anchor just yields a (still valid) k=2 region.
      if (a == 1) return null;
      break;
    }
    final dst = reachable[rng.nextInt(reachable.length)];
    final path = _connect(solved, dst, region, windingProb, rng, canTraverse);
    if (path == null) {
      if (a == 1) return null;
      break;
    }
    for (final p in path) {
      _paint(solved, owner, p, color, letter);
    }
    anchors.add(dst);
  }

  return anchors.length >= 2 ? anchors : null;
}

/// Winding self-avoiding walk from [dst] until it touches [region]. Returns
/// the cells to paint (including [dst]), or null if blocked. Every step keeps
/// the target reachable (`canReach`), so the walk never dead-ends.
List<int>? _connect(
  Puzzle solved,
  int dst,
  List<int> region,
  double windingProb,
  Random rng,
  bool Function(int idx) canTraverse,
) {
  final width = solved.width;
  final regionSet = region.toSet();
  final path = <int>[dst];
  final inPath = <int>{dst};
  int cur = dst;
  final guard = solved.width * solved.height + 1;

  bool touchesRegion(int idx) =>
      solved.getNeighbors(idx).any(regionSet.contains);

  for (int step = 0; step < guard; step++) {
    if (touchesRegion(cur)) return path;
    final candidates = solved.getNeighbors(cur).where((n) {
      if (inPath.contains(n)) return false;
      if (!canTraverse(n)) return false;
      // Keep a route to the region open, excluding cells already walked.
      return canReach(
        solved,
        [n],
        touchesRegion,
        (i) => !inPath.contains(i) && canTraverse(i),
      );
    }).toList();
    if (candidates.isEmpty) return null;

    // Order by distance to the nearest region cell; with probability
    // `windingProb` step AWAY (farthest) to wind, otherwise step toward.
    int distToRegion(int idx) =>
        region.map((r) => _manhattan(idx, r, width)).reduce(min);
    candidates.shuffle(rng);
    candidates.sort((x, y) => distToRegion(x).compareTo(distToRegion(y)));
    final next = (rng.nextDouble() < windingProb && candidates.length > 1)
        ? candidates.last
        : candidates.first;
    path.add(next);
    inPath.add(next);
    cur = next;
  }
  return null;
}

void _paint(
  Puzzle solved,
  List<String?> owner,
  int idx,
  CellValue c,
  String l,
) {
  if (owner[idx] == null) {
    solved.cells[idx].setForSolver(c);
  }
  owner[idx] = l;
}

/// Backbone letter names from a namespace DISJOINT from
/// `LetterGroup.generateAllParameters` (which uses A.. upward, skipping 'I'):
/// we take Z, Y, X, … downward, also skipping 'I'. Greedy-added LT candidates
/// then never collide/merge with the constructed regions. PUBLIC for testing.
List<String> pathLetterNames(int n) {
  final names = <String>[];
  int code = 90; // 'Z'
  while (names.length < n && code >= 65) {
    if (code != 73) names.add(String.fromCharCode(code)); // skip 'I'
    code--;
  }
  return names;
}

int _pickInterior(List<int> candidates, int width, int height, Random rng) {
  int best = candidates[rng.nextInt(candidates.length)];
  int bestScore = _interiorScore(best, width, height);
  for (int t = 0; t < 3; t++) {
    final cand = candidates[rng.nextInt(candidates.length)];
    final s = _interiorScore(cand, width, height);
    if (s > bestScore) {
      best = cand;
      bestScore = s;
    }
  }
  return best;
}

int _interiorScore(int idx, int width, int height) {
  final r = idx ~/ width;
  final c = idx % width;
  return min(min(r, height - 1 - r), min(c, width - 1 - c));
}

int _manhattan(int a, int b, int width) =>
    ((a ~/ width) - (b ~/ width)).abs() + ((a % width) - (b % width)).abs();

void _bump(PathPrefillStats? stats, PathFailCause cause) {
  if (stats == null) return;
  stats.causeCounts[cause] = (stats.causeCounts[cause] ?? 0) + 1;
}

/// Why a single [preFillPath] retry failed. Aggregated across retries and
/// surfaced to the generator so the catch-all `pathPrefillFailed` reject can
/// be split into actionable causes.
enum PathFailCause { placement, routingTimeout, routingInfeasible, bipartite }

/// Per-[preFillPath]-call diagnostics, filled on success and failure alike.
/// The cause tally feeds the reject-reason breakdown; the timing / try counts
/// feed default calibration via the stats CSV and worker log.
class PathPrefillStats {
  /// Failure tally per cause. Public so tests can seed it directly.
  final Map<PathFailCause, int> causeCounts = {};

  int retriesUsed = 0; // loop iterations consumed (winning attempt on success)
  int routingCalls = 0;
  int routingMsMax = 0;
  int routingMsTotal = 0;
  int prefillMs = 0;

  /// Most frequent failure cause across retries, or null if none was recorded
  /// (e.g. success on the first try). Ties resolve to the first cause that
  /// reached the max count (map insertion order) — deterministic.
  PathFailCause? get dominantCause {
    PathFailCause? best;
    var bestN = 0;
    for (final e in causeCounts.entries) {
      if (e.value > bestN) {
        bestN = e.value;
        best = e.key;
      }
    }
    return best;
  }
}

/// Assigns a colour to each letter for the path-based pre-fill.
///
/// On a domain of ≥ 3 colours every colour is guaranteed to be owned by at
/// least one letter (so the routed solution is genuinely N-colour and
/// survives `autoShrinkDomain`); surplus letters share colours, producing the
/// hard same-colour separation case. On a 2-colour domain the historical
/// behaviour is preserved (L=2 same/different sub-cases; L≥3 random partition).
///
/// Public — exercised directly by `test/prefill_path_test.dart`, mirroring how
/// `pickIslandColors` is tested for the SY pre-fill.
Map<String, CellValue> assignColors(
  List<String> letters,
  List<CellValue> domain,
  double sameColorProb,
  Random rng,
) {
  final colors = <String, CellValue>{};
  // Domain ≥ 3 colours: guarantee every colour is owned by at least one
  // letter so the solution is genuinely N-colour and survives
  // `autoShrinkDomain`. Surplus letters (L > |domain|) draw a random colour,
  // creating same-colour pairs — the hard separation case. The caller floors
  // the letter count at |domain|, so full coverage is always achievable.
  if (domain.length >= 3) {
    final assign = <CellValue>[
      ...domain,
      for (int i = domain.length; i < letters.length; i++)
        domain[rng.nextInt(domain.length)],
    ]..shuffle(rng);
    for (int i = 0; i < letters.length; i++) {
      colors[letters[i]] = assign[i];
    }
    return colors;
  }
  // For L=2, two sub-cases: same-color (both black or both white) or
  // different. For L>=3 with 2 colors, at least one same-color pair
  // exists by pigeonhole — we partition into two color groups randomly.
  if (letters.length == 2) {
    if (rng.nextDouble() < sameColorProb) {
      final shared = rng.nextBool() ? CellValue.black : CellValue.white;
      colors[letters[0]] = shared;
      colors[letters[1]] = shared;
    } else {
      final c0 = rng.nextBool() ? CellValue.black : CellValue.white;
      colors[letters[0]] = c0;
      colors[letters[1]] = c0 == CellValue.black
          ? CellValue.white
          : CellValue.black;
    }
  } else {
    // For L>=3: assign each letter a random color independently.
    for (final l in letters) {
      colors[l] = rng.nextBool() ? CellValue.black : CellValue.white;
    }
  }
  return colors;
}
