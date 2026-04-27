/// Equilibrium: bias puzzle generation toward under-represented categories
/// across four independent axes (slug, number of types, pair of types, size).
///
/// All parameters are exposed as constants / pure functions at the top of the
/// file so the behavior can be retuned without touching the algorithm.
library;

// ---------------------------------------------------------------------------
// Tunable parameters
// ---------------------------------------------------------------------------

/// Target distribution for the "number of types per puzzle" axis.
/// Keys 1..6 are explicit; everything ≥ 7 shares [kTargetSevenPlusShare].
const Map<int, double> kTargetNTypesProfile = {
  1: 0.25,
  2: 0.30,
  3: 0.12,
  4: 0.12,
  5: 0.10,
  6: 0.09,
};
const double kTargetSevenPlusShare = 0.02;

/// Inclusive bounds for the "size" axis. Sizes outside the range are still
/// counted (legacy data) but never become a target.
const int kMinSide = 3;
const int kMaxSide = 10;

/// A target that fails this many times in a row is blacklisted for the
/// session — the algorithm stops trying to push it.
const int kBlacklistAfterFailures = 5;

/// Minimum number of puzzles that must already exist in the target corpus
/// before equilibrium kicks in. Below this threshold the distributions are
/// too sparse to drive meaningful targets — typically `pickTarget` would
/// chase impossible combinations and waste time blacklisting them. The CLI
/// falls back to the legacy slug-only bias until the corpus is warm.
const int kEquilibriumWarmupSize = 100;

/// Generated puzzles whose post-solve free ratio exceeds this threshold are
/// rejected. Mirrors the constant used by the generator.
const double kMaxAcceptableRatio = 0.25;

/// Returns the target share for [category] on [axis].
/// - `slug` / `pair` / `size` axes: uniform over [categoryCount].
/// - `ntypes` axis: lookup in [kTargetNTypesProfile] (and [kTargetSevenPlusShare]
///   for the 7+ bucket). [categoryCount] is ignored.
double targetShare(Axis axis, Object category, int categoryCount) {
  switch (axis) {
    case Axis.slug:
    case Axis.pair:
    case Axis.size:
      return categoryCount > 0 ? 1.0 / categoryCount : 0.0;
    case Axis.ntypes:
      final n = category as int;
      if (n >= 7) return kTargetSevenPlusShare;
      return kTargetNTypesProfile[n] ?? 0.0;
  }
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum Axis { slug, ntypes, pair, size }

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
  /// Use 7 to represent the "7+" bucket.
  final int n;
  const NTypesTarget(this.n);
  bool get isSevenPlus => n >= 7;
  @override
  Axis get axis => Axis.ntypes;
  @override
  String get key => 'ntypes:${isSevenPlus ? "7+" : n}';
  @override
  String get label => isSevenPlus ? 'ntypes=7+' : 'ntypes=$n';
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
  const SizeTarget(this.width, this.height);
  @override
  Axis get axis => Axis.size;
  @override
  String get key => 'size:${width}x$height';
  @override
  String get label => 'size=${width}x$height';
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
  final int totalPuzzles;

  const EquilibriumStats({
    required this.slugCounts,
    required this.ntypesCounts,
    required this.pairCounts,
    required this.sizeCounts,
    required this.totalPuzzles,
  });

  factory EquilibriumStats.empty() => const EquilibriumStats(
    slugCounts: {},
    ntypesCounts: {},
    pairCounts: {},
    sizeCounts: {},
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
      sizes[(w, h)] = (sizes[(w, h)] ?? 0) + 1;
      if (slugs.length == 2) {
        final sorted = slugs.toList()..sort();
        final pair = (sorted[0], sorted[1]);
        pairs[pair] = (pairs[pair] ?? 0) + 1;
      }
    }

    return EquilibriumStats(
      slugCounts: slug,
      ntypesCounts: ntypes,
      pairCounts: pairs,
      sizeCounts: sizes,
      totalPuzzles: total,
    );
  }

  /// Returns a copy with one more puzzle's slugs/size accounted for.
  EquilibriumStats withPuzzle({
    required Set<String> slugs,
    required int width,
    required int height,
  }) {
    final newSlug = Map<String, int>.from(slugCounts);
    final newNtypes = Map<int, int>.from(ntypesCounts);
    final newPairs = Map<(String, String), int>.from(pairCounts);
    final newSizes = Map<(int, int), int>.from(sizeCounts);

    for (final s in slugs) {
      newSlug[s] = (newSlug[s] ?? 0) + 1;
    }
    newNtypes[slugs.length] = (newNtypes[slugs.length] ?? 0) + 1;
    newSizes[(width, height)] = (newSizes[(width, height)] ?? 0) + 1;
    if (slugs.length == 2) {
      final sorted = slugs.toList()..sort();
      final pair = (sorted[0], sorted[1]);
      newPairs[pair] = (newPairs[pair] ?? 0) + 1;
    }

    return EquilibriumStats(
      slugCounts: newSlug,
      ntypesCounts: newNtypes,
      pairCounts: newPairs,
      sizeCounts: newSizes,
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

  /// (w, h) pairs eligible: in [minW..maxW] × [minH..maxH] intersected
  /// with [kMinSide..kMaxSide] on both dimensions.
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
    final sizes = <(int, int)>[];
    for (int w = w0; w <= w1; w++) {
      for (int h = h0; h <= h1; h++) {
        sizes.add((w, h));
      }
    }
    return TargetUniverse._(slugs, sizes);
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

List<_ScoredTarget> _scoreAll(EquilibriumStats stats, TargetUniverse universe) {
  final out = <_ScoredTarget>[];
  final total = stats.totalPuzzles;

  // --- Slug ---
  final nSlugs = universe.allowedSlugs.length;
  final expSlug = targetShare(Axis.slug, '', nSlugs);
  for (final slug in universe.allowedSlugs) {
    final c = stats.slugCounts[slug] ?? 0;
    out.add(_ScoredTarget(SlugTarget(slug), _gap(_share(c, total), expSlug)));
  }

  // --- N-types ---
  for (final n in kTargetNTypesProfile.keys) {
    final c = stats.ntypesCounts[n] ?? 0;
    out.add(
      _ScoredTarget(
        NTypesTarget(n),
        _gap(_share(c, total), targetShare(Axis.ntypes, n, 0)),
      ),
    );
  }
  // 7+ bucket aggregates everything ≥ 7.
  int sevenPlusCount = 0;
  for (final entry in stats.ntypesCounts.entries) {
    if (entry.key >= 7) sevenPlusCount += entry.value;
  }
  out.add(
    _ScoredTarget(
      NTypesTarget(7),
      _gap(_share(sevenPlusCount, total), kTargetSevenPlusShare),
    ),
  );

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
  final nSizes = universe.allowedSizes.length;
  final expSize = targetShare(Axis.size, '', nSizes);
  for (final (w, h) in universe.allowedSizes) {
    final c = stats.sizeCounts[(w, h)] ?? 0;
    out.add(_ScoredTarget(SizeTarget(w, h), _gap(_share(c, total), expSize)));
  }

  return out;
}
