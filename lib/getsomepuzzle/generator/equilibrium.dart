/// Equilibrium: bias puzzle generation toward under-represented categories
/// across four independent axes (slug, number of types, pair of types, size).
///
/// All parameters are exposed as constants / pure functions at the top of the
/// file so the behavior can be retuned without touching the algorithm.
library;

import 'dart:math';

// ---------------------------------------------------------------------------
// Tunable parameters
// ---------------------------------------------------------------------------

/// Target distribution for the "profile" axis (pre-fill mode).
///
/// 90 % of puzzles come from the regular flow (`preFillRegular`); the
/// remaining 10 % is split equally between SH-themed and path-based-LT
/// scenarios. Each scenario has its own pre-fill function and the path
/// the puzzle takes through `generateOne` differs accordingly.
///
/// Identification of an existing puzzle's profile reads the
/// authoritative `scenario:` suffix written by the generator — see
/// [detectPuzzleProfile]. Lines without that suffix are treated as
/// `classic` (legacy corpus included).
const Map<ProfileCategory, double> kTargetProfile = {
  ProfileCategory.classic: 0.85,
  ProfileCategory.sh: 0.05,
  ProfileCategory.pathBased: 0.05,
  ProfileCategory.syBased: 0.05,
};

/// Target distribution for the "number of types per puzzle" axis.
/// Only keys 1..5 are pushed by the equilibrium engine. Puzzles with ≥ 6
/// distinct types are accepted (they can fall out of cross-axis recycling
/// when a SlugTarget or SizeTarget happens to span many slugs) but are
/// never explicitly targeted — their target share is implicitly 0. The
/// dashboard surfaces them as a single "6+" bucket so we can monitor
/// drift, not as a generation goal.
const Map<int, double> kTargetNTypesProfile = {
  1: 0.35,
  2: 0.30,
  3: 0.12,
  4: 0.12,
  5: 0.10,
  6: 0.02,
  7: 0.01,
  8: 0.01,
  9: 0.005,
  10: 0.005,
  11: 0.002,
  12: 0.002,
  13: 0.001,
  14: 0.001,
};

/// Inclusive bounds for the "size" axis. Sizes outside the range are still
/// counted (legacy data) but never become a target.
const int kMinSide = 3;
const int kMaxSide = 10;

/// Minimum number of puzzles that must already exist in the target corpus
/// before equilibrium kicks in. Below this threshold the distributions are
/// too sparse to drive meaningful targets — typically `pickTarget` would
/// chase impossible combinations and waste time blacklisting them. The CLI
/// falls back to the legacy slug-only bias until the corpus is warm.
const int kEquilibriumWarmupSize = 100;

/// Generated puzzles whose post-solve free ratio exceeds this threshold are
/// rejected. Mirrors the constant used by the generator.
const double kMaxAcceptableRatio = 0.25;

/// Maximum side dimensions used when generating warm-up puzzles. The generator
/// stays within the user-provided `[minWidth..maxWidth] / [minHeight..maxHeight]`
/// fork; these caps just clamp the upper end so warm-up puzzles remain small
/// and fast to generate.
const int kWarmupMaxWidth = 4;
const int kWarmupMaxHeight = 5;

/// Distribution of #types per puzzle during warm-up. Mono-constraint puzzles
/// generate fastest; bi-constraint puzzles seed the pair-axis stats so the
/// equilibrium engine has data on that axis as soon as it kicks in.
const List<int> kWarmupNTypesPool = [1, 1, 2, 2];

/// Size-axis target distribution: an asymmetric Gaussian on grid area, peak
/// at `kSizePeakArea` (small grids ≈ 4×5), with the right tail almost twice
/// as wide as the left so smalls are skewed-favored over larges. The exact
/// per-size shares are derived by normalizing this raw shape over
/// `universe.allowedSizes` (see `sizeTargetShare`); the integral over the
/// universe is therefore always 1.
///
/// Tuning these three constants reshapes the entire size axis without
/// touching the picker / dashboard plumbing.
const double kSizePeakArea = 20.0;
const double kSizeSigmaLeft = 8.0;
const double kSizeSigmaRight = 15.0;

/// Returns the target share for [category] on [axis].
/// - `slug` / `pair` axes: uniform over [categoryCount].
/// - `size` axis: legacy uniform value. The actual size-axis weighting is
///   non-uniform (asymmetric Gaussian on area — see `sizeTargetShare`);
///   this function keeps returning `1/categoryCount` only for callers that
///   need a single representative share (tests, generic axis APIs).
/// - `ntypes` axis: lookup in [kTargetNTypesProfile]. Anything outside the
///   profile (including the "6+" reliquat bucket) maps to 0 — we never push
///   those bins. [categoryCount] is ignored.
double targetShare(Axis axis, Object category, int categoryCount) {
  switch (axis) {
    case Axis.slug:
    case Axis.pair:
    case Axis.size:
      return categoryCount > 0 ? 1.0 / categoryCount : 0.0;
    case Axis.ntypes:
      final n = category as int;
      return kTargetNTypesProfile[n] ?? 0.0;
    case Axis.profile:
      final p = category as ProfileCategory;
      return kTargetProfile[p] ?? 0.0;
  }
}

/// Canonical orientation for the (unordered) size axis: width ≤ height, so a
/// `4x5` grid and its `5x4` transpose map to the same bin `(4, 5)`. The size
/// axis counts orientations together — only the grid *shape* matters for
/// variety — while the generator is still free to emit either orientation.
(int, int) canonicalSize(int width, int height) =>
    width <= height ? (width, height) : (height, width);

/// Raw (un-normalized) size weight: asymmetric Gaussian on grid area
/// peaking at [kSizePeakArea]. Public so callers without a [TargetUniverse]
/// (e.g. selection-time variety bias) can compute the same target shape and
/// normalize over their own size set.
double sizeRawWeight(int width, int height) {
  final area = (width * height).toDouble();
  final dx = area - kSizePeakArea;
  final sigma = dx <= 0 ? kSizeSigmaLeft : kSizeSigmaRight;
  return exp(-(dx * dx) / (2 * sigma * sigma));
}

/// Per-size target share, normalized so the sum over `universe.allowedSizes`
/// equals 1. This is what `_scoreAll` and `pickWeightedSize` consume — it
/// replaces the previous uniform `1/nSizes`.
double sizeTargetShare(int width, int height, TargetUniverse universe) {
  final raw = sizeRawWeight(width, height);
  if (raw <= 0) return 0.0;
  final total = universe.allowedSizes.fold<double>(
    0.0,
    (sum, p) => sum + sizeRawWeight(p.$1, p.$2),
  );
  return total > 0 ? raw / total : 0.0;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum Axis { slug, ntypes, pair, size, profile }

/// Pre-fill scenario categories. Each puzzle has exactly one profile,
/// determined either at generation time (when `pathBasedScenario` or
/// `prioritySlugs.contains("SH")` is set) or post-hoc via heuristic
/// detection on a v2 line (see [detectPuzzleProfile]).
enum ProfileCategory {
  /// Default: regular pre-fill (random grid) followed by the greedy
  /// constraint cherry-pick. The bulk of generated puzzles.
  classic,

  /// SH-themed: `preFillSh` seeds a Shape motif. The puzzle contains at
  /// least one SH constraint.
  sh,

  /// Path-based-LT: `preFillPath` builds a topology of LT constraints
  /// and runs the bipartite desambiguation. LT is the dominant
  /// deductive driver.
  pathBased,

  /// SY-themed: `preFillSy` grows symmetric islands and ambiguates via a
  /// bipartite cascade dominated by SY constraints. See
  /// `docs/dev/prefill_sy.md`.
  syBased,
}

/// A single target the equilibrium algorithm wants to push next.
sealed class Target {
  const Target();
  Axis get axis;

  /// Stable key used for blacklist lookup and identity comparison.
  String get key;
  String get label;
}

class SlugTarget extends Target {
  final String slug;
  const SlugTarget(this.slug);
  @override
  Axis get axis => Axis.slug;
  @override
  String get key => 'slug:$slug';
  @override
  String get label => 'slug=$slug';
}

class NTypesTarget extends Target {
  /// Only values present in [kTargetNTypesProfile] (currently 1..5) are ever
  /// emitted by `pickTarget` — the 6+ reliquat bucket has target share 0
  /// and is never pushed.
  final int n;
  const NTypesTarget(this.n);
  @override
  Axis get axis => Axis.ntypes;
  @override
  String get key => 'ntypes:$n';
  @override
  String get label => 'ntypes=$n';
}

class PairTarget extends Target {
  /// Sorted: [slugA] < [slugB] lexicographically.
  final String slugA;
  final String slugB;
  const PairTarget(this.slugA, this.slugB);

  factory PairTarget.from(String a, String b) {
    return a.compareTo(b) <= 0 ? PairTarget(a, b) : PairTarget(b, a);
  }

  @override
  Axis get axis => Axis.pair;
  @override
  String get key => 'pair:$slugA+$slugB';
  @override
  String get label => 'pair=$slugA+$slugB';
}

class SizeTarget extends Target {
  final int width;
  final int height;

  /// Canonicalized to `width <= height` so transposed sizes share one bin
  /// (see [canonicalSize]). The worker picks a concrete orientation when it
  /// generates.
  const SizeTarget(int width, int height)
    : width = width <= height ? width : height,
      height = width <= height ? height : width;
  @override
  Axis get axis => Axis.size;
  @override
  String get key => 'size:${width}x$height';
  @override
  String get label => 'size=${width}x$height';
}

class ProfileTarget extends Target {
  final ProfileCategory profile;
  const ProfileTarget(this.profile);
  @override
  Axis get axis => Axis.profile;
  @override
  String get key => 'profile:${profile.name}';
  @override
  String get label => 'profile=${profile.name}';
}

/// Detect a puzzle's profile from its v2 line by reading the
/// authoritative `scenario:<name>` suffix written by the generator at
/// emission time (see `Puzzle.lineExport`). Any trailing part starting
/// with `scenario:` is honoured, regardless of position relative to a
/// `p:` play-state suffix.
///
/// Lines without a `scenario:` suffix — including the entire legacy
/// corpus — are reported as [ProfileCategory.classic]. There is no
/// heuristic fallback: explicitness is what the equilibrium relies on
/// to avoid false `pathBased` positives.
ProfileCategory detectPuzzleProfile(String v2Line) {
  final parts = v2Line.split('_');
  for (int i = parts.length - 1; i >= 7; i--) {
    final field = parts[i];
    if (!field.startsWith('scenario:')) continue;
    final name = field.substring('scenario:'.length);
    for (final p in ProfileCategory.values) {
      if (p.name == name) return p;
    }
    break;
  }
  return ProfileCategory.classic;
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

/// Distributions over the 4 axes, computed from a corpus of puzzle lines.
class EquilibriumStats {
  final Map<String, int> slugCounts;
  final Map<int, int> ntypesCounts;
  final Map<(String, String), int> pairCounts;
  final Map<(int, int), int> sizeCounts;
  final Map<ProfileCategory, int> profileCounts;
  final int totalPuzzles;

  const EquilibriumStats({
    required this.slugCounts,
    required this.ntypesCounts,
    required this.pairCounts,
    required this.sizeCounts,
    required this.profileCounts,
    required this.totalPuzzles,
  });

  factory EquilibriumStats.empty() => const EquilibriumStats(
    slugCounts: {},
    ntypesCounts: {},
    pairCounts: {},
    sizeCounts: {},
    profileCounts: {},
    totalPuzzles: 0,
  );

  /// Total puzzles aggregated by the pair axis (= puzzles with exactly 2 types).
  int get totalPairs => pairCounts.values.fold(0, (a, b) => a + b);

  /// Build stats from raw puzzle file lines.
  /// Lines that don't parse are skipped silently.
  factory EquilibriumStats.fromLines(Iterable<String> lines) {
    final slug = <String, int>{};
    final ntypes = <int, int>{};
    final pairs = <(String, String), int>{};
    final sizes = <(int, int), int>{};
    final profiles = <ProfileCategory, int>{};
    int total = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('_');
      if (parts.length < 5) continue;

      // Size: parts[2] = "WxH"
      final dims = parts[2].split('x');
      if (dims.length != 2) continue;
      final w = int.tryParse(dims[0]);
      final h = int.tryParse(dims[1]);
      if (w == null || h == null) continue;

      // Slugs: parts[4] = "slug:params;slug:params;..."
      final slugs = <String>{};
      for (final c in parts[4].split(';')) {
        if (c.isEmpty) continue;
        final colon = c.indexOf(':');
        if (colon <= 0) continue;
        slugs.add(c.substring(0, colon));
      }
      if (slugs.isEmpty) continue;

      total++;
      for (final s in slugs) {
        slug[s] = (slug[s] ?? 0) + 1;
      }
      ntypes[slugs.length] = (ntypes[slugs.length] ?? 0) + 1;
      final sizeBin = canonicalSize(w, h);
      sizes[sizeBin] = (sizes[sizeBin] ?? 0) + 1;
      if (slugs.length == 2) {
        final sorted = slugs.toList()..sort();
        final pair = (sorted[0], sorted[1]);
        pairs[pair] = (pairs[pair] ?? 0) + 1;
      }
      final profile = detectPuzzleProfile(line);
      profiles[profile] = (profiles[profile] ?? 0) + 1;
    }

    return EquilibriumStats(
      slugCounts: slug,
      ntypesCounts: ntypes,
      pairCounts: pairs,
      sizeCounts: sizes,
      profileCounts: profiles,
      totalPuzzles: total,
    );
  }

  /// Returns a copy with one more puzzle's slugs/size/profile accounted for.
  ///
  /// [profile] defaults to [ProfileCategory.classic] so callers that don't
  /// care about the profile axis (and tests pre-dating it) stay terse.
  EquilibriumStats withPuzzle({
    required Set<String> slugs,
    required int width,
    required int height,
    ProfileCategory profile = ProfileCategory.classic,
  }) {
    final newSlug = Map<String, int>.from(slugCounts);
    final newNtypes = Map<int, int>.from(ntypesCounts);
    final newPairs = Map<(String, String), int>.from(pairCounts);
    final newSizes = Map<(int, int), int>.from(sizeCounts);
    final newProfiles = Map<ProfileCategory, int>.from(profileCounts);

    for (final s in slugs) {
      newSlug[s] = (newSlug[s] ?? 0) + 1;
    }
    newNtypes[slugs.length] = (newNtypes[slugs.length] ?? 0) + 1;
    final sizeBin = canonicalSize(width, height);
    newSizes[sizeBin] = (newSizes[sizeBin] ?? 0) + 1;
    if (slugs.length == 2) {
      final sorted = slugs.toList()..sort();
      final pair = (sorted[0], sorted[1]);
      newPairs[pair] = (newPairs[pair] ?? 0) + 1;
    }
    newProfiles[profile] = (newProfiles[profile] ?? 0) + 1;

    return EquilibriumStats(
      slugCounts: newSlug,
      ntypesCounts: newNtypes,
      pairCounts: newPairs,
      sizeCounts: newSizes,
      profileCounts: newProfiles,
      totalPuzzles: totalPuzzles + 1,
    );
  }
}

// ---------------------------------------------------------------------------
// Universe of categories
// ---------------------------------------------------------------------------

/// Static description of which categories are eligible as targets — built once
/// from the registry / config range; reused at every iteration.
class TargetUniverse {
  /// Slugs the algorithm is allowed to use. The caller is responsible for
  /// applying any user-facing ban list before constructing the universe.
  final List<String> allowedSlugs;

  /// Eligible size **bins**, canonicalized to `width <= height` and
  /// deduplicated (see [canonicalSize]): the shapes in [minW..maxW] ×
  /// [minH..maxH] intersected with [kMinSide..kMaxSide] on both dimensions,
  /// counting a size and its transpose once.
  final List<(int, int)> allowedSizes;

  TargetUniverse._(this.allowedSlugs, this.allowedSizes);

  factory TargetUniverse({
    required Iterable<String> allowedSlugs,
    required int minWidth,
    required int maxWidth,
    required int minHeight,
    required int maxHeight,
  }) {
    final slugs = allowedSlugs.toList();

    final w0 = minWidth < kMinSide ? kMinSide : minWidth;
    final w1 = maxWidth > kMaxSide ? kMaxSide : maxWidth;
    final h0 = minHeight < kMinSide ? kMinSide : minHeight;
    final h1 = maxHeight > kMaxSide ? kMaxSide : maxHeight;
    // Canonicalize to width ≤ height and dedup so a shape and its transpose
    // form a single bin. A LinkedHashSet keeps a stable, deterministic order.
    final sizes = <(int, int)>{};
    for (int w = w0; w <= w1; w++) {
      for (int h = h0; h <= h1; h++) {
        sizes.add(canonicalSize(w, h));
      }
    }
    return TargetUniverse._(slugs, sizes.toList());
  }

  /// All ordered pairs (a, b) with a < b among [allowedSlugs].
  List<(String, String)> get allowedPairs {
    final out = <(String, String)>[];
    final sorted = [...allowedSlugs]..sort();
    for (int i = 0; i < sorted.length; i++) {
      for (int j = i + 1; j < sorted.length; j++) {
        out.add((sorted[i], sorted[j]));
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Gap computation and target selection
// ---------------------------------------------------------------------------

/// A scored candidate target — used internally and exposed for diagnostics.
class _ScoredTarget {
  final Target target;
  final double gap;
  const _ScoredTarget(this.target, this.gap);
}

/// Pick the most under-represented (axis, category) across all axes.
///
/// Returns `null` if no target has a strictly positive gap (perfect balance —
/// extremely unlikely in practice) or if every candidate is blacklisted.
Target? pickTarget(
  EquilibriumStats stats,
  TargetUniverse universe, {
  Set<String> blacklistedKeys = const {},
}) {
  final scored = _scoreAll(stats, universe);
  scored.removeWhere((s) => blacklistedKeys.contains(s.target.key));
  if (scored.isEmpty) return null;
  scored.sort((a, b) => b.gap.compareTo(a.gap));
  if (scored.first.gap <= 0) return null;
  return scored.first.target;
}

/// Sample one (width, height) from `universe.allowedSizes`, weighted by the
/// per-size gap (target_share − observed_share, clamped to ≥ 0). Returns
/// null when no size has a positive gap (perfect balance, extremely rare).
///
/// Used as a *secondary* objective when the primary target leaves the size
/// axis free (Slug / NTypes / Pair). Stochastic sampling avoids workers
/// converging on the same hard sub-config the way deterministic argmax would.
(int, int)? pickWeightedSize(
  EquilibriumStats stats,
  TargetUniverse universe,
  Random rng,
) {
  final nSizes = universe.allowedSizes.length;
  if (nSizes == 0) return null;
  final total = stats.totalPuzzles;
  final candidates = <((int, int), double)>[];
  for (final (w, h) in universe.allowedSizes) {
    final c = stats.sizeCounts[(w, h)] ?? 0;
    final share = total > 0 ? c / total : 0.0;
    final expSize = sizeTargetShare(w, h, universe);
    final gap = expSize - share;
    if (gap > 0) candidates.add(((w, h), gap));
  }
  if (candidates.isEmpty) return null;
  return _weightedPick(candidates, rng);
}

/// Pick `n` distinct slugs from `universe.allowedSlugs`, drawing each one
/// weighted by its slug-axis gap. When fewer than `n` slugs have positive
/// gap, the remaining slots are filled with uniform random picks from the
/// rest of the universe so the returned set always has size `min(n, nSlugs)`.
///
/// Mirrors the `avgK / nSlugs` expected-share formula used in `_scoreAll`,
/// so a slug "sous-représenté" here is exactly what the picker thinks.
Set<String> pickWeightedSlugs(
  EquilibriumStats stats,
  TargetUniverse universe,
  int n,
  Random rng,
) {
  final nSlugs = universe.allowedSlugs.length;
  final desired = n > nSlugs ? nSlugs : (n < 0 ? 0 : n);
  if (desired == 0) return const {};

  final total = stats.totalPuzzles;
  final totalSlugUses = stats.slugCounts.values.fold<int>(0, (a, b) => a + b);
  final avgK = total > 0 ? totalSlugUses / total : 0.0;
  final expSlug = nSlugs > 0 ? avgK / nSlugs : 0.0;

  final candidates = <(String, double)>[];
  for (final s in universe.allowedSlugs) {
    final c = stats.slugCounts[s] ?? 0;
    final share = total > 0 ? c / total : 0.0;
    final gap = expSlug - share;
    if (gap > 0) candidates.add((s, gap));
  }

  final chosen = <String>{};
  while (chosen.length < desired && candidates.isNotEmpty) {
    final picked = _weightedPick(candidates, rng);
    chosen.add(picked);
    candidates.removeWhere((c) => c.$1 == picked);
  }

  if (chosen.length < desired) {
    final fill =
        universe.allowedSlugs.where((s) => !chosen.contains(s)).toList()
          ..shuffle(rng);
    for (final s in fill) {
      if (chosen.length >= desired) break;
      chosen.add(s);
    }
  }
  return chosen;
}

/// Sample one item from `(item, weight)` pairs. Caller guarantees that the
/// list is non-empty and at least one weight is positive.
T _weightedPick<T>(List<(T, double)> items, Random rng) {
  final totalWeight = items.fold<double>(0.0, (s, x) => s + x.$2);
  final pick = rng.nextDouble() * totalWeight;
  double cum = 0;
  for (final (item, w) in items) {
    cum += w;
    if (pick <= cum) return item;
  }
  return items.last.$1;
}

/// Sample one [Target] from `(target, gap)` pairs, weighted by gap. Public
/// wrapper over [_weightedPick] used by the CLI's cross-worker bucket
/// rotation (the coordinator picks among the unclaimed buckets). Returns
/// `null` when [candidates] is empty or every gap is ≤ 0.
Target? weightedPickTarget(
  List<({Target target, double gap})> candidates,
  Random rng,
) {
  final positive = [
    for (final c in candidates)
      if (c.gap > 0) (c.target, c.gap),
  ];
  if (positive.isEmpty) return null;
  return _weightedPick(positive, rng);
}

/// Cross-worker bucket rotation used by the CLI coordinator (main isolate).
///
/// Hands out the next deficient bucket to a requesting worker so the parallel
/// workers chase *distinct* under-represented buckets instead of all piling on
/// the single biggest gap. The guarantee: every positive-gap bucket is claimed
/// once per cycle before any bucket repeats. Only when the whole deficient set
/// has been handed out does the cycle reset and the sweep starts over — so we
/// don't come back to (say) the most-deficient slug until every other
/// deficient bucket, including the small-target profile buckets like
/// `profile:syBased`, has been served at least once.
///
/// This per-cycle coverage is what neutralizes the cross-axis scale imbalance
/// (a slug expected ~30 % vs a profile expected 5 %): rotation gives each
/// deficient bucket one turn per cycle regardless of the raw magnitude of its
/// gap. Selection *within* the not-yet-claimed set is weighted-random by gap
/// (via [weightedPickTarget]) so bigger deficits still tend to go first.
///
/// Single-threaded by construction: the coordinator lives in the main isolate
/// whose event loop serializes every worker's `requestTarget`, so the mutable
/// [claimedThisCycle] set needs no locking.
class BucketRotation {
  final Random _rng;
  final Set<String> _claimedThisCycle = <String>{};

  BucketRotation([Random? rng]) : _rng = rng ?? Random();

  /// Bucket keys already handed out in the current cycle. Exposed for
  /// diagnostics and tests.
  Set<String> get claimedThisCycle => Set.unmodifiable(_claimedThisCycle);

  /// Returns the next bucket to push, or `null` when no bucket has a positive
  /// gap (corpus perfectly balanced — extremely rare). Marks the returned
  /// bucket as claimed for this cycle.
  Target? next(EquilibriumStats stats, TargetUniverse universe) {
    final ranked = rankTargets(stats, universe);
    var pool = [
      for (final c in ranked)
        if (c.gap > 0 && !_claimedThisCycle.contains(c.target.key)) c,
    ];
    if (pool.isEmpty) {
      // Every deficient bucket has had its turn — start a fresh cycle.
      _claimedThisCycle.clear();
      pool = [
        for (final c in ranked)
          if (c.gap > 0) c,
      ];
      if (pool.isEmpty) return null;
    }
    final picked = weightedPickTarget(pool, _rng);
    if (picked == null) return null;
    _claimedThisCycle.add(picked.key);
    return picked;
  }
}

/// Rebuild a [Target] from its stable [Target.key]. Inverse of the `key`
/// getters on the concrete subclasses — used to ferry a target across the
/// isolate boundary (the coordinator picks it in the main isolate, the
/// worker reconstructs it). Returns `null` for an unrecognized or malformed
/// key so callers can fall back gracefully.
Target? parseTargetKey(String key) {
  final colon = key.indexOf(':');
  if (colon <= 0) return null;
  final kind = key.substring(0, colon);
  final rest = key.substring(colon + 1);
  switch (kind) {
    case 'slug':
      return rest.isEmpty ? null : SlugTarget(rest);
    case 'ntypes':
      final n = int.tryParse(rest);
      return n == null ? null : NTypesTarget(n);
    case 'pair':
      final plus = rest.indexOf('+');
      if (plus <= 0 || plus >= rest.length - 1) return null;
      return PairTarget.from(rest.substring(0, plus), rest.substring(plus + 1));
    case 'size':
      final x = rest.indexOf('x');
      if (x <= 0 || x >= rest.length - 1) return null;
      final w = int.tryParse(rest.substring(0, x));
      final h = int.tryParse(rest.substring(x + 1));
      return (w == null || h == null) ? null : SizeTarget(w, h);
    case 'profile':
      for (final p in ProfileCategory.values) {
        if (p.name == rest) return ProfileTarget(p);
      }
      return null;
    default:
      return null;
  }
}

/// All scored candidates, sorted by descending gap. Useful for diagnostics
/// (top-N, histograms).
List<({Target target, double gap})> rankTargets(
  EquilibriumStats stats,
  TargetUniverse universe, {
  Set<String> blacklistedKeys = const {},
}) {
  final scored = _scoreAll(stats, universe);
  scored.removeWhere((s) => blacklistedKeys.contains(s.target.key));
  scored.sort((a, b) => b.gap.compareTo(a.gap));
  return scored
      .map((s) => (target: s.target, gap: s.gap))
      .toList(growable: false);
}

double _gap(double observedShare, double expectedShare) {
  final g = expectedShare - observedShare;
  return g > 0 ? g : 0.0;
}

double _share(int count, int total) => total > 0 ? count / total : 0.0;

/// Per-slug deficit (positive = under-represented vs. the balanced expected
/// share, zero = at-or-above target). Same arithmetic as the slug axis of
/// [_scoreAll], exposed so the generator's secondary sort key shares a single
/// notion of "sous-représenté" with [pickTarget].
///
/// Returned map covers every slug in [universe.allowedSlugs]; slugs with zero
/// gap are kept (caller can use `?? 0.0` interchangeably).
Map<String, double> slugDeficits(
  EquilibriumStats stats,
  TargetUniverse universe,
) {
  final total = stats.totalPuzzles;
  final nSlugs = universe.allowedSlugs.length;
  final totalSlugUses = stats.slugCounts.values.fold<int>(0, (a, b) => a + b);
  final avgSlugsPerPuzzle = total > 0 ? totalSlugUses / total : 0.0;
  final expSlug = nSlugs > 0 ? avgSlugsPerPuzzle / nSlugs : 0.0;
  final out = <String, double>{};
  for (final slug in universe.allowedSlugs) {
    final c = stats.slugCounts[slug] ?? 0;
    out[slug] = _gap(_share(c, total), expSlug);
  }
  return out;
}

List<_ScoredTarget> _scoreAll(EquilibriumStats stats, TargetUniverse universe) {
  final out = <_ScoredTarget>[];
  final total = stats.totalPuzzles;

  // --- Slug ---
  // Slug is the only axis where each puzzle contributes to *multiple* bins
  // (one per distinct slug it contains). The "balanced" fraction per slug is
  // therefore `avgK / nSlugs` where `avgK = totalSlugUses / totalPuzzles`,
  // not `1/nSlugs`. Using `1/nSlugs` made the slug axis effectively silent
  // (all gaps clamped to 0 once the corpus had any breadth) which biased the
  // picker toward ntypes/pair targets exclusively.
  final slugGaps = slugDeficits(stats, universe);
  for (final entry in slugGaps.entries) {
    out.add(_ScoredTarget(SlugTarget(entry.key), entry.value));
  }

  // --- N-types ---
  // Only the explicit profile keys (1..5) ever participate as targets.
  // The "6+" reliquat bucket has target share 0 → its gap is always ≤ 0,
  // so adding it would never change the picker's argmax. We omit it from
  // the ranking entirely.
  for (final n in kTargetNTypesProfile.keys) {
    final c = stats.ntypesCounts[n] ?? 0;
    out.add(
      _ScoredTarget(
        NTypesTarget(n),
        _gap(_share(c, total), targetShare(Axis.ntypes, n, 0)),
      ),
    );
  }

  // --- Pair (conditional on puzzles with exactly 2 types) ---
  final pairs = universe.allowedPairs;
  final nPairs = pairs.length;
  final expPair = targetShare(Axis.pair, '', nPairs);
  final totalPairs = stats.totalPairs;
  for (final (a, b) in pairs) {
    final c = stats.pairCounts[(a, b)] ?? 0;
    final share = _share(c, totalPairs);
    out.add(_ScoredTarget(PairTarget(a, b), _gap(share, expPair)));
  }

  // --- Size ---
  // Per-size target follows an asymmetric Gaussian on area (peak around
  // [kSizePeakArea]); see `sizeTargetShare`. The shape favors smalls over
  // larges, replacing the previous uniform `1/nSizes`.
  for (final (w, h) in universe.allowedSizes) {
    final c = stats.sizeCounts[(w, h)] ?? 0;
    final expSize = sizeTargetShare(w, h, universe);
    out.add(_ScoredTarget(SizeTarget(w, h), _gap(_share(c, total), expSize)));
  }

  // --- Profile (scenario) ---
  // Three categories with explicit targets in [kTargetProfile]. Existing
  // corpus puzzles are bucketed by [detectPuzzleProfile] (heuristic).
  for (final entry in kTargetProfile.entries) {
    final c = stats.profileCounts[entry.key] ?? 0;
    final share = _share(c, total);
    out.add(_ScoredTarget(ProfileTarget(entry.key), _gap(share, entry.value)));
  }

  return out;
}

// ---------------------------------------------------------------------------
// Warm-up
// ---------------------------------------------------------------------------

/// Concrete generator inputs derived for a single warm-up attempt.
class WarmupConfig {
  final int width;
  final int height;

  /// The candidate-pool restriction. Same set as [preferredSlugs] for warm-up
  /// (we want the puzzle to draw from these slugs and prefer them in the sort).
  final Set<String> allowedSlugs;

  /// Soft preference passed to the generator — these slugs bubble up in the
  /// candidate sort and trigger SH prefill if SH is among them. They are NOT
  /// strictly enforced: a warm-up attempt that ends up using only one of two
  /// chosen slugs still produces a valid 1-type puzzle (cross-axis recycling).
  final Set<String> preferredSlugs;

  const WarmupConfig({
    required this.width,
    required this.height,
    required this.allowedSlugs,
    required this.preferredSlugs,
  });
}

/// Pick a fast-warm-up generator config: small grid (clamped against
/// [kWarmupMaxWidth] / [kWarmupMaxHeight]) and few constraint types
/// (drawn from [kWarmupNTypesPool]).
///
/// `baseRequired` is included in the chosen pool so user-required slugs end
/// up prioritized in the candidate sort and trigger SH prefill if needed.
/// User-required slugs are NOT used to inflate the pool size beyond the
/// warm-up profile — strict enforcement happens later in `generateOne`
/// against `requiredRules`.
WarmupConfig pickWarmupConfig({
  required int minWidth,
  required int maxWidth,
  required int minHeight,
  required int maxHeight,
  required Iterable<String> baseAllowedSlugs,
  required Set<String> baseRequired,
  required Random rng,
}) {
  final wMax = _clampUpperBound(maxWidth, kWarmupMaxWidth, minWidth);
  final hMax = _clampUpperBound(maxHeight, kWarmupMaxHeight, minHeight);
  final w = minWidth + rng.nextInt(wMax - minWidth + 1);
  final h = minHeight + rng.nextInt(hMax - minHeight + 1);

  final allowedList = baseAllowedSlugs.toList()..shuffle(rng);
  final allowedSet = allowedList.toSet();
  final required = baseRequired.where(allowedSet.contains).toSet();

  int n = kWarmupNTypesPool[rng.nextInt(kWarmupNTypesPool.length)];
  if (n < required.length) n = required.length;
  if (n > allowedList.length) n = allowedList.length;

  final chosen = <String>{...required};
  for (final s in allowedList) {
    if (chosen.length >= n) break;
    chosen.add(s);
  }

  return WarmupConfig(
    width: w,
    height: h,
    allowedSlugs: chosen,
    preferredSlugs: chosen,
  );
}

/// Clamp `requested` to `hardCap`, but never below `floor` — when the caller's
/// floor exceeds the hard cap, fall back to the floor (the warm-up still
/// respects user-provided `min*` arguments even if it can't honor the cap).
int _clampUpperBound(int requested, int hardCap, int floor) {
  final capped = requested > hardCap ? hardCap : requested;
  return capped < floor ? floor : capped;
}
