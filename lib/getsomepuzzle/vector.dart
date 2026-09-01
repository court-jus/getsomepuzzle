// Shared per-puzzle feature vector for similarity pruning and clustering.
//
// Single source of truth for the vector that `bin/vectorize_puzzles.dart`
// writes to `puzzle_vectors.csv` and that the generator emits inline per
// accepted puzzle (so the recycle/orchestrator loop never needs a full
// re-vectorize to see fresh puzzles).
//
// The vector captures what makes two puzzles *feel* similar to a player:
// the mix of constraint families used by the trace, weighted by their
// per-move complexity tier, plus the translation/colour-swap-invariant
// geometry of the solved grid. Full column list in [vectorCsvColumns].
//
// The two production drivers are:
//   * `bin/vectorize_puzzles.dart` — batch pass over the whole corpus,
//     reading `solve_traces.tsv` for cache hits (post-sort traces).
//   * `PuzzleGenerator._finalize` — inline per-puzzle emission during
//     generation, using the post-sort trace (see
//     `docs/dev/collection_management.md` "Vector freshness via inline
//     emission").

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/solution_geometry.dart';

/// Stable, alphabetical slug list — defines the CSV column order so two
/// runs produce diff-able files. `CX` is the synthetic slug used for
/// complicity moves (multi-constraint deductions).
const List<String> puzzleSlugs = [
  'CC',
  'CH',
  'CX',
  'DF',
  'EY',
  'FM',
  'GC',
  'GS',
  'LT',
  'NC',
  'PA',
  'QA',
  'RE',
  'SH',
  'SZ',
  'SY',
];

/// Move complexity tiers (`Move.complexity`, 0..5). We allocate one share
/// column per (slug, tier) pair.
const List<int> puzzleTiers = [0, 1, 2, 3, 4, 5];

/// Ordinal index of each [PuzzleLevel] — used as the numeric `level`
/// feature in the vector. Out-of-cascade buckets are placed past `mad` so
/// they don't get clustered with mid-tier puzzles by accident.
const Map<PuzzleLevel, int> vectorLevelOrdinal = {
  PuzzleLevel.beginner: 0,
  PuzzleLevel.player: 1,
  PuzzleLevel.advanced: 2,
  PuzzleLevel.strong: 3,
  PuzzleLevel.expert: 4,
  PuzzleLevel.mad: 5,
  PuzzleLevel.overfilledEasy: 6,
  PuzzleLevel.overfilledPlayer: 7,
  PuzzleLevel.overfilledAdvanced: 8,
  PuzzleLevel.overfilledStrong: 9,
  PuzzleLevel.overfilledExpert: 10,
  PuzzleLevel.overfilledMad: 11,
  PuzzleLevel.overfilled: 12,
  PuzzleLevel.undetermined: 13,
};

/// The per-puzzle feature vector, mirroring one `puzzle_vectors.csv` row
/// (minus the `file` / `canonical_key` identity columns, which the driver
/// fills from its own routing context).
class PuzzleVector {
  final int width;
  final int height;
  final int domainSize;
  final double prefillRatio;
  final int nConstraints;
  final int nDistinctTypes;
  final int complexity;
  final int level;
  final int nPropMoves;
  final int nForceRounds;
  final int maxForceDepth;
  final int nTotalSteps;
  final int distinctConstraintsUsed;
  final int maxCascade;
  final double avgMoveComplexity;

  /// Declared constraint slugs (post-sort puzzle) that never fired in the
  /// solving trace. A present-but-unused constraint still shows its icon and
  /// can mislead the player, so two puzzles with identical traces but
  /// different dead constraints are *not* interchangeable.
  final int unusedSlugs;

  /// Normalized Shannon entropy of the trace slug distribution
  /// (1.0 = every used slug fires equally often, near 0 = one slug
  /// dominates). Summarizes mix *evenness* that [distinctConstraintsUsed]
  /// ignores and the per-slug share block only encodes redundantly.
  final double traceSlugEntropy;

  // (slug, tier) -> share. Keyed `FM_t0`, `CX_t2`, … in fixed column order.
  final Map<String, double> shares;
  // Solution-geometry (power-spectrum) descriptors.
  final double specPeakFrac;
  final double specXbarsFrac;
  final double specYbarsFrac;
  final double specCheckerFrac;
  final double specConcentration;
  // Solution-geometry (autocorrelation) descriptors.
  final double autoBand;
  final double autoChecker;
  final double autoTile;
  // Solution-geometry (interpretable scalars).
  final int periodX;
  final int periodY;
  final int checkerBlockK;
  final int nSymmetries;
  final double rleRatio;

  const PuzzleVector({
    required this.width,
    required this.height,
    required this.domainSize,
    required this.prefillRatio,
    required this.nConstraints,
    required this.nDistinctTypes,
    required this.complexity,
    required this.level,
    required this.nPropMoves,
    required this.nForceRounds,
    required this.maxForceDepth,
    required this.nTotalSteps,
    required this.distinctConstraintsUsed,
    required this.maxCascade,
    required this.avgMoveComplexity,
    required this.unusedSlugs,
    required this.traceSlugEntropy,
    required this.shares,
    required this.specPeakFrac,
    required this.specXbarsFrac,
    required this.specYbarsFrac,
    required this.specCheckerFrac,
    required this.specConcentration,
    required this.autoBand,
    required this.autoChecker,
    required this.autoTile,
    required this.periodX,
    required this.periodY,
    required this.checkerBlockK,
    required this.nSymmetries,
    required this.rleRatio,
  });
}

/// Compute the feature vector for a puzzle.
///
/// [pu] is the (already post-sort / post-shrink) puzzle being exported;
/// [steps] is its solving trace — the caller is responsible for passing the
/// *post-sort* trace so the result is consistent with `bin/vectorize_puzzles.dart`
/// (which works on post-sort collections). [replay] is a clone of [pu] that
/// has been replayed through [steps] and verified complete — its `cellValues`
/// give the solved grid used for the geometry columns.
PuzzleVector computePuzzleVector({
  required Puzzle pu,
  required List<SolveStep> steps,
  required Puzzle replay,
}) {
  final width = pu.width;
  final height = pu.height;
  final domainSize = pu.domain.length;
  final readonly = pu.cells.where((c) => c.readonly).length;
  final prefillRatio = pu.cells.isEmpty ? 0.0 : readonly / pu.cells.length;
  final nConstraints = pu.constraints.length;
  final distinctTypes = <Type>{};
  for (final c in pu.constraints) {
    distinctTypes.add(c.runtimeType);
  }
  // The Puzzle constructor loads `cachedComplexity` from the v2 line's field
  // [6]; the generator sets it via `computeComplexityFromSteps` before export.
  final storedCplx = pu.cachedComplexity ?? -1;

  // Tally per-(slug, tier) counts. Use the synthetic `CX` slug for complicity
  // steps — the `step.constraint` they carry is the slug of the *first*
  // constraint in the complicity, which would otherwise double-count under
  // e.g. `FM`. Force steps don't get a slug share (they're surfaced through
  // `nForceRounds` / `maxForceDepth`).
  final counts = <String, Map<int, int>>{};
  for (final s in puzzleSlugs) {
    counts[s] = {for (final t in puzzleTiers) t: 0};
  }
  int nProp = 0;
  int nForce = 0;
  int maxForceDepth = 0;
  int maxCascade = 0;
  int cascade = 0;
  String? prev;
  int complexitySum = 0;
  final distinctInTrace = <String>{};
  final slugCounts = <String, int>{};

  for (final step in steps) {
    if (step.method == SolveMethod.force) {
      nForce++;
      if (step.forceDepth > maxForceDepth) maxForceDepth = step.forceDepth;
      prev = null;
      cascade = 0;
      continue;
    }
    nProp++;
    complexitySum += step.complexity;
    distinctInTrace.add(step.constraint);

    final slug = step.isComplicity ? 'CX' : _slugOf(step.constraint);
    slugCounts.update(slug, (n) => n + 1, ifAbsent: () => 1);
    final tier = step.complexity.clamp(0, puzzleTiers.last);
    final bySlug = counts[slug];
    if (bySlug != null) {
      bySlug[tier] = (bySlug[tier] ?? 0) + 1;
    }

    if (step.constraint == prev) {
      cascade++;
    } else {
      cascade = 1;
    }
    if (cascade > maxCascade) maxCascade = cascade;
    prev = step.constraint;
  }

  // Solution geometry from the verified solved grid (read `replay` directly,
  // not the line's cached `1:` field, so it always reflects the current solve).
  final solGrid = replay.cellValues;
  final spec = spectralFeatures(solGrid, width, height);
  final auto = autocorrelationFeatures(solGrid, width, height);

  final level = classifyTrace(
    steps: steps,
    prefillRatio: prefillRatio,
    solved: true,
  );

  // Convert counts to shares. Guard nProp == 0 (a pre-solved puzzle would
  // have an empty trace, vector dominated by 0s).
  final shares = <String, double>{};
  for (final s in puzzleSlugs) {
    for (final t in puzzleTiers) {
      final c = counts[s]?[t] ?? 0;
      shares['${s}_t$t'] = nProp > 0 ? c / nProp : 0.0;
    }
  }
  // Constraint-mix extras: dead declared slugs and mix evenness. Declared
  // slugs are read off the post-sort constraint list; anything that doesn't
  // map to a known puzzle slug (e.g. synthetic complicity serializations)
  // is ignored.
  final declaredSlugs = <String>{
    for (final c in pu.constraints) _slugOf(c.serialize()),
  }..retainWhere(puzzleSlugs.contains);
  final usedSlugs = slugCounts.keys.toSet();
  final unusedSlugs = declaredSlugs.difference(usedSlugs).length;
  // Normalized Shannon entropy over the used-slug distribution; k > 1
  // implies nProp >= 2, so the division is safe.
  final k = usedSlugs.length;
  var traceSlugEntropy = 0.0;
  if (k > 1) {
    var h = 0.0;
    for (final n in slugCounts.values) {
      final p = n / nProp;
      h -= p * log(p);
    }
    traceSlugEntropy = h / log(k);
  }

  return PuzzleVector(
    width: width,
    height: height,
    domainSize: domainSize,
    prefillRatio: prefillRatio,
    nConstraints: nConstraints,
    nDistinctTypes: distinctTypes.length,
    complexity: storedCplx,
    level: vectorLevelOrdinal[level] ?? 8,
    nPropMoves: nProp,
    nForceRounds: nForce,
    maxForceDepth: maxForceDepth,
    nTotalSteps: nProp + nForce,
    distinctConstraintsUsed: distinctInTrace.length,
    maxCascade: maxCascade,
    avgMoveComplexity: nProp > 0 ? complexitySum / nProp : 0.0,
    shares: shares,
    unusedSlugs: unusedSlugs,
    traceSlugEntropy: traceSlugEntropy,
    specPeakFrac: spec.peak,
    specXbarsFrac: spec.xbars,
    specYbarsFrac: spec.ybars,
    specCheckerFrac: spec.checker,
    specConcentration: spec.concentration,
    autoBand: auto.band,
    autoChecker: auto.checker,
    autoTile: auto.tile,
    periodX: periodX(solGrid, width, height),
    periodY: periodY(solGrid, width, height),
    checkerBlockK: checkerBlockK(solGrid, width, height),
    nSymmetries: countSymmetries(solGrid, width, height),
    rleRatio: rleRatio(solGrid, width, height),
  );
}

/// Extract the slug prefix of a constraint serialization, e.g.
/// `"FM:11"` → `"FM"`. Returns `"??"` for unparseable strings so we don't
/// silently lose them.
String _slugOf(String serialized) {
  final i = serialized.indexOf(':');
  if (i < 0) return serialized.isEmpty ? '??' : serialized;
  return serialized.substring(0, i);
}

/// Full column list for `puzzle_vectors.csv`, in fixed order (including the
/// `file` / `canonical_key` identity columns, which the driver fills).
List<String> vectorCsvColumns() {
  final cols = <String>[
    'file',
    'canonical_key',
    'width',
    'height',
    'cells',
    'domain_size',
    'prefill_ratio',
    'n_constraints',
    'n_distinct_types',
    'complexity',
    'level',
    'n_prop_moves',
    'n_force_rounds',
    'max_force_depth',
    'n_total_steps',
    'distinct_constraints_used',
    'max_cascade',
    'avg_move_complexity',
    'unused_slugs',
    'trace_slug_entropy',
  ];
  for (final s in puzzleSlugs) {
    for (final t in puzzleTiers) {
      cols.add('share_${s}_t$t');
    }
  }
  // Solution-geometry block, appended last so existing column indices are
  // stable for any positional reader (consumers select by name).
  cols.addAll([
    'spec_peak_frac',
    'spec_xbars_frac',
    'spec_ybars_frac',
    'spec_checker_frac',
    'spec_concentration',
    'auto_band',
    'auto_checker',
    'auto_tile',
    'period_x',
    'period_y',
    'checker_block_k',
    'n_symmetries',
    'rle_ratio',
  ]);
  return cols;
}

/// CSV header line for `puzzle_vectors.csv`.
String vectorCsvHeader() => vectorCsvColumns().join(',');

/// The CSV field values for [v] for every column **except** the leading
/// `file` and `canonical_key` identity columns (the driver supplies those).
/// A driver writing a full row prepends them:
/// `[vectorCsvField(file), vectorCsvField(key), ...vectorCsvFields(v)]`.
List<String> vectorCsvFields(PuzzleVector v) {
  final cells = v.width * v.height;
  final cols = <String>[
    '${v.width}',
    '${v.height}',
    '$cells',
    '${v.domainSize}',
    v.prefillRatio.toStringAsFixed(4),
    '${v.nConstraints}',
    '${v.nDistinctTypes}',
    '${v.complexity}',
    '${v.level}',
    '${v.nPropMoves}',
    '${v.nForceRounds}',
    '${v.maxForceDepth}',
    '${v.nTotalSteps}',
    '${v.distinctConstraintsUsed}',
    '${v.maxCascade}',
    v.avgMoveComplexity.toStringAsFixed(4),
    '${v.unusedSlugs}',
    v.traceSlugEntropy.toStringAsFixed(4),
  ];
  for (final s in puzzleSlugs) {
    for (final t in puzzleTiers) {
      cols.add(v.shares['${s}_t$t']!.toStringAsFixed(4));
    }
  }
  cols.add(v.specPeakFrac.toStringAsFixed(4));
  cols.add(v.specXbarsFrac.toStringAsFixed(4));
  cols.add(v.specYbarsFrac.toStringAsFixed(4));
  cols.add(v.specCheckerFrac.toStringAsFixed(4));
  cols.add(v.specConcentration.toStringAsFixed(4));
  cols.add(v.autoBand.toStringAsFixed(4));
  cols.add(v.autoChecker.toStringAsFixed(4));
  cols.add(v.autoTile.toStringAsFixed(4));
  cols.add('${v.periodX}');
  cols.add('${v.periodY}');
  cols.add('${v.checkerBlockK}');
  cols.add('${v.nSymmetries}');
  cols.add(v.rleRatio.toStringAsFixed(4));
  return cols;
}

/// Minimal CSV escaper: quote when the field contains `,`, `"`, or newline;
/// double up internal quotes. Canonical keys don't carry commas but the file
/// path or any future identity-key tweak might, so escape defensively.
String vectorCsvField(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
