// Identify the Top-K most-similar puzzle pairs in the corpus, based on
// the CSV produced by `bin/vectorize_puzzles.dart`. Goal: surface
// redundant puzzles so the cleanup can drop one of each near-duplicate
// pair (instead of generating new ones via equilibrium).
//
// Recycle mode (--mode recycle): instead of ε-clustering, prune each
// over-full collection down to a target count via farthest-point
// sampling — keep the `--target-count` most-diverse puzzles in place and
// MOVE the excess to `<file>-recycled.txt` (e.g. assets/6-mad-recycled.txt,
// the default feed of bin/recycle_mad.dart). No ε threshold needed, so it
// works uniformly on the easy tier AND on 6-mad.
//
// Distance model:
//   - All numeric features are z-scored across the pool, std capped
//     against zero, z-score clipped to ±5 so rare-slug outliers don't
//     dominate the bulk.
//   - Distance = Euclidean on the z-scored vector.
//   - Bucketed by (domain_size, dominant_slug-in-trace): two puzzles
//     where the highest-share slug differs are very unlikely to feel
//     similar; bucketing avoids the O(N²) global scan.
//
// Output: one line per pair, sorted by distance ascending. Each line
// shows the two source files + the truncated v2 lines, plus the top-3
// dims that brought them together and the top-3 that still separate
// them.
//
// Usage:
//   dart run bin/cluster_puzzles.dart [--input PATH] [--top-k N]
//                                      [--include-size]
//                                      [--include-level]
//                                      [--include-prefill]
//                                      [--per-bucket-limit M]
//                                      [--output PATH]
//                                      [--verbose]

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';

import '_csv.dart';

const _collections = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/1-easy-overfilled.txt',
  'assets/overfilled.txt',
  'assets/2-player-overfilled.txt',
  'assets/3-advanced-overfilled.txt',
  'assets/4-strong-overfilled.txt',
  'assets/5-expert-overfilled.txt',
  'assets/6-mad-overfilled.txt',
];

/// The six playable level files — default targets of recycle mode
/// (`--mode recycle`). The overfilled buckets stay out of scope.
const _playableLevels = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
];

const _slugs = [
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
  'SH',
  'SY',
];
const _tiers = [0, 1, 2, 3, 4, 5];

void main(List<String> args) {
  String inputPath = 'puzzle_vectors.csv';
  String? outputPath;
  int topK = 100;
  int perBucketLimit = 5000;
  bool includeSize = true;
  bool includeLevel = false;
  // prefill_ratio matters for the *starting* feel of a puzzle even when
  // the trace looks identical — two puzzles with 25 % vs 5 % readonly
  // cells are different exercises. Default on; --no-include-prefill
  // restores the original trace-only behaviour.
  bool includePrefill = true;
  bool verbose = false;
  // Apply-mode args. When `apply == true` we ignore --top-k and collect
  // every pair with distance ≤ maxDistance, union them into clusters,
  // and keep `keepPerCluster` representatives via farthest-point
  // sampling. The rest are written out as removal candidates.
  bool apply = false;
  double maxDistance = 0.15;
  int keepPerCluster = 1;
  String? protectFromPath;

  // Recycle-mode (FPS prune-to-count) args. `--mode` selects the algorithm
  // used by --apply: `cluster` (ε-threshold) or `recycle` (prune-to-count).
  String mode = 'cluster';
  int targetCount = 20000;
  List<String> collections = List.of(_playableLevels);
  int? sample;
  // Track which args were explicitly passed, to warn when a flag does not
  // apply to the selected mode (defaults are silently ignored).
  bool maxDistanceSet = false;
  bool keepPerClusterSet = false;
  bool topKSet = false;
  bool targetCountSet = false;
  bool collectionsSet = false;
  bool sampleSet = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        inputPath = args[++i];
      case '--output':
        outputPath = args[++i];
      case '--top-k':
        topK = int.parse(args[++i]);
        topKSet = true;
      case '--per-bucket-limit':
        perBucketLimit = int.parse(args[++i]);
      case '--include-size':
        includeSize = true;
      case '--no-include-size':
        includeSize = false;
      case '--include-level':
        includeLevel = true;
      case '--include-prefill':
        includePrefill = true;
      case '--no-include-prefill':
        includePrefill = false;
      case '--mode':
        mode = args[++i];
        if (mode != 'cluster' && mode != 'recycle') {
          stderr.writeln('--mode accepts "cluster" or "recycle" (got "$mode")');
          _printUsage();
          exit(1);
        }
      case '--target-count':
        targetCount = int.parse(args[++i]);
        targetCountSet = true;
      case '--collections':
        collections = args[++i].split(',').map((s) => s.trim()).toList();
        collectionsSet = true;
      case '--sample':
        sample = int.parse(args[++i]);
        sampleSet = true;
      case '--apply':
        apply = true;
      case '--max-distance':
        maxDistance = double.parse(args[++i]);
        maxDistanceSet = true;
      case '--keep-per-cluster':
        keepPerCluster = int.parse(args[++i]);
        keepPerClusterSet = true;
      case '--protect-from':
        protectFromPath = args[++i];
      case '-v':
      case '--verbose':
        verbose = true;
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        _printUsage();
        exit(1);
    }
  }

  // Warn about flags that don't apply to the selected mode (they are
  // ignored rather than an error, so existing cluster invocations are
  // untouched and recycle invocations are forgiving).
  if (mode == 'recycle') {
    final ignored = <String>[
      if (maxDistanceSet) '--max-distance',
      if (keepPerClusterSet) '--keep-per-cluster',
      if (topKSet) '--top-k',
    ];
    if (ignored.isNotEmpty) {
      stderr.writeln('warn: ${ignored.join(', ')} ignored in recycle mode');
    }
  } else {
    final ignored = <String>[
      if (targetCountSet) '--target-count',
      if (collectionsSet) '--collections',
      if (sampleSet) '--sample',
    ];
    if (ignored.isNotEmpty) {
      stderr.writeln('warn: ${ignored.join(', ')} ignored in cluster mode');
    }
  }

  // --- 1. Read CSV ---
  stderr.writeln('Reading $inputPath...');
  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $inputPath');
    exit(1);
  }
  final lines = file.readAsLinesSync();
  if (lines.isEmpty) {
    stderr.writeln('Empty CSV');
    exit(1);
  }

  final header = parseCsvLine(lines.first);
  final colIdx = <String, int>{};
  for (int i = 0; i < header.length; i++) {
    colIdx[header[i]] = i;
  }

  // Required identity columns.
  final iFile = _need(colIdx, 'file');
  final iKey = _need(colIdx, 'canonical_key');
  final iDom = _need(colIdx, 'domain_size');
  final iWidth = _need(colIdx, 'width');
  final iHeight = _need(colIdx, 'height');

  // Build the list of feature columns we'll use for distance.
  final featureCols = <int>[];
  final featureNames = <String>[];
  void addFeature(String name) {
    final idx = colIdx[name];
    if (idx == null) {
      stderr.writeln('Missing column in CSV: $name');
      exit(1);
    }
    featureCols.add(idx);
    featureNames.add(name);
  }

  // Trace shares are the heart of the signal.
  for (final s in _slugs) {
    for (final t in _tiers) {
      addFeature('share_${s}_t$t');
    }
  }
  // Difficulty signals.
  addFeature('complexity');
  addFeature('n_force_rounds');
  addFeature('max_force_depth');
  addFeature('avg_move_complexity');
  addFeature('distinct_constraints_used');
  addFeature('n_constraints');
  // Constraint-mix extras: dead declared slugs (presence vs usage) and mix
  // evenness — separate puzzles that use the same slug *set* with very
  // different balance, or that only differ by constraints that never fire.
  addFeature('unused_slugs');
  addFeature('trace_slug_entropy');
  // Solution-geometry power-spectrum signals (translation- and colour-swap-
  // invariant) — let the clusterer separate globally-regular solutions
  // (damier, colour bars) that the trace shares alone cannot distinguish.
  addFeature('spec_peak_frac');
  addFeature('spec_xbars_frac');
  addFeature('spec_ybars_frac');
  addFeature('spec_checker_frac');
  addFeature('spec_concentration');
  // Solution-geometry autocorrelation signals (parity-robust companions to the
  // spectrum) — detect a 2×2 damier on odd block counts (4×6, 6×6) and generic
  // shifted-motif repetition the fixed spectral bins miss.
  addFeature('auto_band');
  addFeature('auto_checker');
  addFeature('auto_tile');
  // Solution-geometry interpretable scalars — the designer-confirmed predicates
  // (period 1 = colour bars, checker_block_k > 0 = damier) plus dihedral
  // symmetry and run density. Sharpen the grouping of regular-solution families.
  addFeature('period_x');
  addFeature('period_y');
  addFeature('checker_block_k');
  addFeature('n_symmetries');
  addFeature('rle_ratio');
  // Optional features.
  if (includeSize) addFeature('cells');
  if (includeLevel) addFeature('level');
  if (includePrefill) addFeature('prefill_ratio');

  stderr.writeln('  ${featureNames.length} features in distance vector');

  // In apply mode the CSV can be a superset of the live corpus: the
  // maintenance pipeline builds the vector first, then removes puzzles
  // (dedup / cleanup) before clustering. Restrict to puzzles still present in
  // the collections so a stale row can never be picked as a cluster
  // representative — that would delete the whole family from the files.
  Set<String>? liveKeys;
  if (apply) {
    liveKeys = _loadLiveKeys();
    stderr.writeln('  ${liveKeys.length} live canonical keys in collections');
  }

  // --- 2. Load rows ---
  // idx must stay a contiguous 0..n-1 range (the Union-Find indexes on it), so
  // stale rows are skipped here rather than filtered out after construction.
  final rows = <_Row>[];
  int staleSkipped = 0;
  for (int li = 1; li < lines.length; li++) {
    final raw = lines[li];
    if (raw.trim().isEmpty) continue;
    final fields = parseCsvLine(raw);
    if (fields.length < header.length) continue;
    if (liveKeys != null && !liveKeys.contains(fields[iKey])) {
      staleSkipped++;
      continue;
    }
    final vec = Float64List(featureCols.length);
    for (int k = 0; k < featureCols.length; k++) {
      vec[k] = double.tryParse(fields[featureCols[k]]) ?? 0.0;
    }
    rows.add(
      _Row(
        idx: rows.length,
        file: fields[iFile],
        canonicalKey: fields[iKey],
        domainSize: int.tryParse(fields[iDom]) ?? 2,
        width: int.tryParse(fields[iWidth]) ?? 0,
        height: int.tryParse(fields[iHeight]) ?? 0,
        rawVec: vec,
      ),
    );
  }
  stderr.writeln('  ${rows.length} rows loaded');
  if (staleSkipped > 0) {
    stderr.writeln('  $staleSkipped stale rows skipped (not in collections)');
  }
  if (rows.length < 2) {
    stderr.writeln('Not enough rows to cluster.');
    exit(0);
  }

  // --- Branch: recycle mode short-circuits before the global z-score and
  // bucketing, which are cluster/report concerns. Recycle mode normalizes
  // per collection (inside _runRecycleMode), so the global pass is skipped.
  if (mode == 'recycle') {
    _runRecycleMode(
      rows: rows,
      targetCount: targetCount,
      collections: collections,
      sample: sample,
      protectFromPath: protectFromPath,
      outputPath: outputPath,
      apply: apply,
      verbose: verbose,
    );
    return;
  }

  // --- 3. Z-score normalize each feature column ---
  // Per-feature mean and std over the pool. Std=0 columns (constant)
  // get zeroed out — they contribute nothing to distance. z-scores are
  // clipped to ±5 so rare-slug outliers can't dominate the metric.
  _zscoreNormalize(rows);

  // --- 4. Bucket by (domain_size, dominant_slug-in-trace) ---
  // dominant_slug = argmax of summed shares over tiers for each slug.
  final shareColIdxBySlug = <String, List<int>>{};
  for (final s in _slugs) {
    shareColIdxBySlug[s] = [
      for (final t in _tiers) featureNames.indexOf('share_${s}_t$t'),
    ];
  }
  final buckets = <String, List<_Row>>{};
  for (final r in rows) {
    String topSlug = _slugs.first;
    double topShare = -1;
    for (final s in _slugs) {
      double sum = 0;
      for (final ci in shareColIdxBySlug[s]!) {
        if (ci >= 0) sum += r.rawVec[ci];
      }
      if (sum > topShare) {
        topShare = sum;
        topSlug = s;
      }
    }
    final key = '${r.domainSize}/$topSlug';
    buckets.putIfAbsent(key, () => []).add(r);
  }
  stderr.writeln('  ${buckets.length} buckets');
  if (verbose) {
    final sorted = buckets.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in sorted) {
      stderr.writeln('    ${e.key}: ${e.value.length}');
    }
  }

  // --- Branch: apply mode short-circuits the top-K reporting path ---
  if (apply) {
    _runApplyMode(
      rows: rows,
      buckets: buckets,
      maxDistance: maxDistance,
      keepPerCluster: keepPerCluster,
      protectFromPath: protectFromPath,
      perBucketLimit: perBucketLimit,
      outputPath: outputPath,
      verbose: verbose,
    );
    return;
  }

  // --- 5. Top-K pairs via max-heap of size K ---
  // We keep squared distances inside the loop (monotonic in actual
  // distance, no sqrt cost). sqrt is applied once at report time.
  final heap = _MaxHeap(topK);
  int pairsTested = 0;
  final sw = Stopwatch()..start();

  for (final entry in buckets.entries) {
    final pool = entry.value;
    if (pool.length < 2) continue;

    // Per-bucket sample cap: if a bucket is huge, sub-sample pairs by
    // taking only the first `perBucketLimit` elements. Defensive — at
    // 26k puzzles and ~12 buckets we expect ~2k/bucket so usually no
    // cap kicks in. Verbose logs the truncation.
    final n = pool.length > perBucketLimit ? perBucketLimit : pool.length;
    if (verbose && pool.length > perBucketLimit) {
      stderr.writeln(
        '    ${entry.key}: capped ${pool.length}→$n (per-bucket-limit)',
      );
    }
    for (int i = 0; i < n; i++) {
      final a = pool[i].normVec;
      for (int j = i + 1; j < n; j++) {
        final b = pool[j].normVec;
        double dSq = 0;
        for (int k = 0; k < a.length; k++) {
          final diff = a[k] - b[k];
          dSq += diff * diff;
          // Early-out: once we exceed the heap's worst already, abort.
          // Saves the tail of the vector on far-apart pairs.
          if (heap.isFull && dSq >= heap.topDistanceSq) break;
        }
        pairsTested++;
        if (!heap.isFull || dSq < heap.topDistanceSq) {
          heap.pushIfBetter(_Pair(dSq, pool[i], pool[j]));
        }
      }
      if (i % 200 == 0 && i > 0) {
        stderr.write('\r  bucket ${entry.key}: $i/$n     ');
      }
    }
    if (verbose) {
      stderr.writeln(
        '\r  bucket ${entry.key}: done, $pairsTested total pairs tested   ',
      );
    }
  }
  stderr.writeln(
    '\r  done in ${sw.elapsed.inSeconds}s, $pairsTested pairs tested,'
    ' ${heap.size} kept                                  ',
  );

  // --- 6. Load original lines for the kept pairs ---
  // Build the canonical_key → first-occurrence v2 line index lazily,
  // only after the heap is settled — saves a full second of disk I/O
  // we'd otherwise burn parsing all 26k lines.
  final neededKeys = <String>{};
  final sorted = heap.toSortedList();
  for (final p in sorted) {
    neededKeys.add(p.a.canonicalKey);
    neededKeys.add(p.b.canonicalKey);
  }
  final byKey = _loadLinesByCanonicalKey(neededKeys);

  // --- 7. Emit report ---
  // Keep stdout untouched if no output file is provided. Only the
  // file path opens an IOSink we'll explicitly close.
  if (outputPath == null) {
    _writeReport(stdout, sorted, featureNames, byKey);
  } else {
    final fileSink = File(outputPath).openWrite();
    _writeReport(fileSink, sorted, featureNames, byKey);
    fileSink.flush().then((_) => fileSink.close());
    stderr.writeln('Wrote $outputPath');
  }
}

void _printUsage() {
  stderr.writeln('''
Usage: dart run bin/cluster_puzzles.dart [options]

Three modes:
  - REPORT (default):          emit the Top-K closest pairs
  - CLUSTER (--apply):         collect pairs ≤ --max-distance, cluster them,
                               keep --keep-per-cluster representatives via
                               farthest-point sampling (with --protect-from
                               puzzles as forced seeds), write the rest to
                               <file>.cleanup for the user to mv into place.
  - RECYCLE (--mode recycle):  per-collection FPS prune-to-count. Any
                               collection with more than --target-count
                               puzzles keeps the N most-diverse (farthest-
                               point sampling, --protect-from keys as forced
                               seeds) and MOVES the excess to
                               <file>-recycled.txt (e.g. assets/6-mad-
                               recycled.txt, the default feed of
                               bin/recycle_mad.dart). --apply writes the
                               moves; without it, a dry-run report.

Common options:
  --input PATH            CSV from vectorize_puzzles.dart
                          (default: puzzle_vectors.csv)
  --output PATH           Report file (default: stdout)
  --per-bucket-limit M    Cap puzzles per bucket (default: 5000; cluster)
  --include-size          Include cells in distance (default: on)
  --no-include-size       Exclude cells from distance
  --include-level         Include `level` ordinal in distance
  --include-prefill       Include `prefill_ratio` in distance (default: on)
  -v, --verbose           Per-bucket / per-move progress lines
  -h, --help              Show this help

Mode selector:
  --mode cluster|recycle  Algorithm for --apply (default: cluster).
                          Recycle mode ignores --max-distance /
                          --keep-per-cluster / --top-k; cluster mode
                          ignores --target-count / --collections / --sample.

Report-mode options:
  --top-k N               Pairs to report (default: 100)

Cluster apply-mode options:
  --apply                 Enable apply mode (rewrites <file>.cleanup)
  --max-distance X        Distance threshold for "redundant" (default: 0.15)
  --keep-per-cluster N    Representatives kept per cluster (default: 1)
  --protect-from PATH     File of v2 lines that must never be removed/moved
                          (e.g. assets/1-easy_onboarding.txt)

Recycle-mode options:
  --apply                 Enable apply mode (rewrites collections in place,
                          appends excess to <file>-recycled.txt)
  --target-count N        Keep N most-diverse puzzles per collection
                          (default: 20000)
  --collections LIST      Comma-separated collection files to prune
                          (default: the six playable level files)
  --sample N              Process at most N vectorized rows per collection
                          (dev aid)
  --protect-from PATH     File of v2 lines kept as forced FPS seeds
''');
}

int _need(Map<String, int> idx, String col) {
  final v = idx[col];
  if (v == null) {
    stderr.writeln('Missing required column: $col');
    exit(1);
  }
  return v;
}

class _Row {
  /// Global row index, used by the Union-Find structure in --apply mode.
  final int idx;
  final String file;
  final String canonicalKey;
  final int domainSize;
  final int width;
  final int height;
  final Float64List rawVec;
  late Float64List normVec;

  _Row({
    required this.idx,
    required this.file,
    required this.canonicalKey,
    required this.domainSize,
    required this.width,
    required this.height,
    required this.rawVec,
  });
}

class _Pair {
  /// Squared distance — sqrt applied at report time only.
  final double distanceSq;
  final _Row a;
  final _Row b;
  _Pair(this.distanceSq, this.a, this.b);
}

/// Path-compressed Union-Find on row indices. Used in --apply mode to
/// turn the set of (a, b) pairs under the distance threshold into
/// connected components without materialising the adjacency graph.
class _UnionFind {
  final List<int> parent;
  _UnionFind(int n) : parent = List.generate(n, (i) => i);
  int find(int x) {
    int root = x;
    while (parent[root] != root) {
      root = parent[root];
    }
    while (parent[x] != root) {
      final next = parent[x];
      parent[x] = root;
      x = next;
    }
    return root;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }
}

double _sqDist(Float64List a, Float64List b) {
  double s = 0;
  for (int k = 0; k < a.length; k++) {
    final d = a[k] - b[k];
    s += d * d;
  }
  return s;
}

/// Per-feature z-score normalization over [rows] (mean 0, std 1), z-scores
/// clipped to ±5 so rare-slug outliers don't single-handedly dominate the
/// distance metric. Std=0 columns (constant across the pool) are zeroed —
/// they contribute nothing to distance. Writes each row's `normVec`.
void _zscoreNormalize(List<_Row> rows) {
  final dim = rows.first.rawVec.length;
  final means = Float64List(dim);
  final stds = Float64List(dim);
  for (int k = 0; k < dim; k++) {
    double sum = 0;
    for (final r in rows) {
      sum += r.rawVec[k];
    }
    means[k] = sum / rows.length;
    double sumSq = 0;
    for (final r in rows) {
      final d = r.rawVec[k] - means[k];
      sumSq += d * d;
    }
    stds[k] = sqrt(sumSq / rows.length);
  }
  const zClip = 5.0;
  for (final r in rows) {
    r.normVec = Float64List(dim);
    for (int k = 0; k < dim; k++) {
      if (stds[k] < 1e-12) {
        r.normVec[k] = 0;
      } else {
        var z = (r.rawVec[k] - means[k]) / stds[k];
        if (z > zClip) z = zClip;
        if (z < -zClip) z = -zClip;
        r.normVec[k] = z;
      }
    }
  }
}

/// Greedy max-min sampling, identical in spirit to the one in
/// `bin/extract_onboarding.dart` but with an optional set of [seeds]
/// that are forcibly kept (used here to honour `--protect-from`:
/// onboarding puzzles in a redundancy cluster are kept as seeds, then
/// FPS fills the remaining quota from the rest of the cluster).
List<_Row> _farthestPointSampleWithSeeds(
  List<_Row> cluster,
  Set<_Row> seeds,
  int n,
) {
  if (cluster.isEmpty || n <= 0) return const [];

  final selected = <_Row>[...seeds];
  if (selected.length >= n) return selected.take(n).toList();

  final pool = cluster.where((r) => !seeds.contains(r)).toList();
  if (pool.isEmpty) return selected;

  final minDist = List<double>.filled(pool.length, double.infinity);

  if (selected.isNotEmpty) {
    // Pre-fill minDist from the seed set.
    for (int i = 0; i < pool.length; i++) {
      for (final s in selected) {
        final d = _sqDist(pool[i].normVec, s.normVec);
        if (d < minDist[i]) minDist[i] = d;
      }
    }
  } else {
    // No seed: bootstrap with the puzzle farthest from the cluster
    // centroid (deterministic, no RNG).
    final dim = pool.first.normVec.length;
    final centroid = Float64List(dim);
    for (final r in pool) {
      for (int k = 0; k < dim; k++) {
        centroid[k] += r.normVec[k];
      }
    }
    for (int k = 0; k < dim; k++) {
      centroid[k] /= pool.length;
    }
    int firstIdx = 0;
    double firstDist = -1;
    for (int i = 0; i < pool.length; i++) {
      final d = _sqDist(pool[i].normVec, centroid);
      if (d > firstDist) {
        firstDist = d;
        firstIdx = i;
      }
    }
    selected.add(pool[firstIdx]);
    for (int i = 0; i < pool.length; i++) {
      if (i == firstIdx) {
        minDist[i] = -1;
        continue;
      }
      minDist[i] = _sqDist(pool[i].normVec, pool[firstIdx].normVec);
    }
  }

  while (selected.length < n) {
    int bestIdx = -1;
    double bestDist = -1;
    for (int i = 0; i < pool.length; i++) {
      if (minDist[i] < 0) continue;
      if (minDist[i] > bestDist) {
        bestDist = minDist[i];
        bestIdx = i;
      }
    }
    if (bestIdx < 0) break;
    selected.add(pool[bestIdx]);
    final newVec = pool[bestIdx].normVec;
    minDist[bestIdx] = -1;
    for (int i = 0; i < pool.length; i++) {
      if (minDist[i] < 0) continue;
      final d = _sqDist(pool[i].normVec, newVec);
      if (d < minDist[i]) minDist[i] = d;
    }
  }

  return selected;
}

/// --apply implementation: scan pairs ≤ maxDistance, build clusters,
/// run farthest-point sampling per cluster (with protected puzzles as
/// seeds), then rewrite each affected `assets/*.txt` minus the
/// non-kept puzzles to `<file>.cleanup`.
void _runApplyMode({
  required List<_Row> rows,
  required Map<String, List<_Row>> buckets,
  required double maxDistance,
  required int keepPerCluster,
  required String? protectFromPath,
  required int perBucketLimit,
  required String? outputPath,
  required bool verbose,
}) {
  final maxDistSq = maxDistance * maxDistance;

  // 1. Load protected canonical keys.
  final protectedKeys = <String>{};
  if (protectFromPath != null) {
    final file = File(protectFromPath);
    if (!file.existsSync()) {
      stderr.writeln('Protect-from file not found: $protectFromPath');
      exit(1);
    }
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      try {
        protectedKeys.add(canonicalPuzzleKey(line));
      } catch (_) {
        // Skip unparseable lines silently — the protect file is
        // user-controlled and may carry stray comments.
      }
    }
    stderr.writeln('  ${protectedKeys.length} puzzles protected from removal');
  }

  // 2. Scan buckets, union pairs ≤ maxDistance.
  final uf = _UnionFind(rows.length);
  int pairsFound = 0;
  final sw = Stopwatch()..start();

  for (final entry in buckets.entries) {
    final pool = entry.value;
    if (pool.length < 2) continue;
    final n = pool.length > perBucketLimit ? perBucketLimit : pool.length;
    int bucketPairs = 0;
    for (int i = 0; i < n; i++) {
      final a = pool[i].normVec;
      for (int j = i + 1; j < n; j++) {
        final b = pool[j].normVec;
        double dSq = 0;
        for (int k = 0; k < a.length; k++) {
          final diff = a[k] - b[k];
          dSq += diff * diff;
          if (dSq > maxDistSq) break;
        }
        if (dSq <= maxDistSq) {
          uf.union(pool[i].idx, pool[j].idx);
          bucketPairs++;
          pairsFound++;
        }
      }
    }
    if (verbose) {
      stderr.writeln('    ${entry.key}: $bucketPairs pairs ≤ $maxDistance');
    }
  }
  stderr.writeln(
    '  ${sw.elapsed.inSeconds}s, $pairsFound pairs ≤ $maxDistance found',
  );

  // 3. Group rows by Union-Find root → list of clusters.
  final clustersByRoot = <int, List<_Row>>{};
  for (final r in rows) {
    final root = uf.find(r.idx);
    clustersByRoot.putIfAbsent(root, () => []).add(r);
  }
  final clusters = clustersByRoot.values.where((c) => c.length >= 2).toList();
  stderr.writeln('  ${clusters.length} non-trivial clusters');
  if (verbose) {
    final hist = <int, int>{};
    for (final c in clusters) {
      hist[c.length] = (hist[c.length] ?? 0) + 1;
    }
    final sizes = hist.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final sz in sizes.take(10)) {
      stderr.writeln('    size $sz: ${hist[sz]} clusters');
    }
  }

  // 4. Per cluster: keep N representatives via FPS (with protected
  //    puzzles as seeds), mark the rest for removal.
  final toRemove = <String>{};
  final perFileRemoval = <String, int>{};
  int protectedSkips = 0;
  for (final cluster in clusters) {
    final seeds = cluster
        .where((r) => protectedKeys.contains(r.canonicalKey))
        .toSet();
    final picked = _farthestPointSampleWithSeeds(
      cluster,
      seeds,
      keepPerCluster,
    );
    final pickedSet = picked.toSet();
    for (final r in cluster) {
      if (pickedSet.contains(r)) continue;
      if (protectedKeys.contains(r.canonicalKey)) {
        protectedSkips++;
        continue;
      }
      toRemove.add(r.canonicalKey);
      perFileRemoval.update(r.file, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  stderr.writeln('');
  stderr.writeln('  ${toRemove.length} puzzles flagged for removal');
  if (protectedKeys.isNotEmpty) {
    stderr.writeln(
      '  $protectedSkips protected puzzles in clusters kept regardless',
    );
  }
  final files = perFileRemoval.keys.toList()..sort();
  for (final f in files) {
    stderr.writeln('    $f: ${perFileRemoval[f]}');
  }

  // 5. Emit cluster report.
  if (outputPath == null) {
    _writeApplyReport(stdout, clusters, toRemove);
  } else {
    final sink = File(outputPath).openWrite();
    _writeApplyReport(sink, clusters, toRemove);
    sink.flush().then((_) => sink.close());
    stderr.writeln('  Wrote $outputPath');
  }

  // 6. Rewrite each affected collection to <file>.cleanup.
  if (toRemove.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln('Writing .cleanup files...');
    _rewriteCollections(perFileRemoval.keys.toSet(), toRemove);
  }
}

/// Per-collection result of recycle mode.
typedef _RecycleOutcome = ({
  String path,
  int total,
  int kept,
  List<String> movedKeys,
});

/// `--mode recycle` implementation: per-collection FPS prune-to-count.
///
/// For each collection in [collections]: vectorized rows are filtered to
/// live puzzles, z-scored *within that collection* (the population being
/// pruned), and the `targetCount` most-diverse puzzles are selected by
/// farthest-point sampling (`--protect-from` keys as forced seeds). The
/// selected keepers stay in the collection file; the excess (`count −
/// targetCount`) is appended to `&lt;file&gt;-recycled.txt` (deduped by
/// canonical key), e.g. `assets/6-mad-recycled.txt` — the default feed of
/// `bin/recycle_mad.dart`. `--apply` writes; without it this is a dry run.
void _runRecycleMode({
  required List<_Row> rows,
  required int targetCount,
  required List<String> collections,
  required int? sample,
  required String? protectFromPath,
  required String? outputPath,
  required bool apply,
  required bool verbose,
}) {
  // 1. Load protected canonical keys (forced FPS seeds).
  final protectedKeys = <String>{};
  if (protectFromPath != null) {
    final file = File(protectFromPath);
    if (!file.existsSync()) {
      stderr.writeln('Protect-from file not found: $protectFromPath');
      exit(1);
    }
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      try {
        protectedKeys.add(canonicalPuzzleKey(line));
      } catch (_) {
        // Skip unparseable lines silently.
      }
    }
    stderr.writeln('  ${protectedKeys.length} puzzles protected from moving');
  }

  // 2. Live keys: only puzzles currently in the collections are eligible —
  // a puzzle already moved to a `-recycled.txt` feed is not re-picked.
  final liveKeys = _loadLiveKeys();
  stderr.writeln('  ${liveKeys.length} live canonical keys in collections');

  // 3. Group rows by source collection file.
  final byFile = <String, List<_Row>>{};
  for (final r in rows) {
    if (!liveKeys.contains(r.canonicalKey)) continue;
    byFile.putIfAbsent(r.file, () => []).add(r);
  }

  // 4. Prune each requested collection.
  final outcomes = <_RecycleOutcome>[];
  final sw = Stopwatch()..start();
  for (final path in collections) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  warn: $path not found, skipping');
      continue;
    }
    final all = byFile[path] ?? const <_Row>[];
    var pool = all;
    if (sample != null && pool.length > sample) {
      pool = pool.take(sample).toList();
      stderr.writeln('  $path: sampled ${all.length} → $sample rows (dev aid)');
    }
    if (pool.isEmpty) {
      stderr.writeln(
        '  $path: 0 vectorized rows — run bin/vectorize_puzzles.dart first',
      );
      continue;
    }

    // Per-collection normalization: the collection is the population whose
    // mutual distance FPS maximizes.
    _zscoreNormalize(pool);

    if (pool.length <= targetCount) {
      stderr.writeln(
        '  $path: ${pool.length} ≤ $targetCount — in range, nothing to move',
      );
      outcomes.add((
        path: path,
        total: pool.length,
        kept: pool.length,
        movedKeys: const [],
      ));
      continue;
    }

    final seeds = pool
        .where((r) => protectedKeys.contains(r.canonicalKey))
        .toSet();
    final keepers = _farthestPointSampleWithSeeds(pool, seeds, targetCount);
    final keeperKeys = keepers.map((r) => r.canonicalKey).toSet();
    final movedKeys = [
      for (final r in pool)
        if (!keeperKeys.contains(r.canonicalKey)) r.canonicalKey,
    ];

    stderr.writeln(
      '  $path: ${pool.length} → keep ${keepers.length}, move ${movedKeys.length}',
    );
    if (verbose) {
      for (final key in movedKeys) {
        stderr.writeln('    MOVE  $key');
      }
    }
    outcomes.add((
      path: path,
      total: pool.length,
      kept: keepers.length,
      movedKeys: movedKeys,
    ));

    if (apply) {
      // Rewrite the collection keeping only the FPS-selected puzzles and
      // append the moved lines to `<file>-recycled.txt`.
      final movedLines = _rewriteKeeping(path, keeperKeys);
      _appendRecycled(path, movedLines);
    }
  }
  stderr.writeln(
    '  done in ${sw.elapsed.inSeconds}s (${apply ? 'applied' : 'dry-run'})',
  );

  // 5. Emit report.
  if (outputPath == null) {
    _writeRecycleReport(stdout, outcomes, targetCount, apply);
  } else {
    final sink = File(outputPath).openWrite();
    _writeRecycleReport(sink, outcomes, targetCount, apply);
    sink.flush().then((_) => sink.close());
    stderr.writeln('  Wrote $outputPath');
  }

  if (!apply) {
    stderr.writeln(
      '(dry-run — pass --apply to move the excess into <file>-recycled.txt)',
    );
  }
}

/// Stream [path] keeping only lines whose canonical key is in [keeperKeys]
/// (comments and blanks pass through verbatim), writing in-place via a
/// `<file>.recycle` staging file renamed over the original. Returns the
/// moved (non-kept) v2 lines in file order.
List<String> _rewriteKeeping(String path, Set<String> keeperKeys) {
  final kept = <String>[];
  final movedLines = <String>[];
  int keptPuzzles = 0;
  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) {
      kept.add(line);
      continue;
    }
    String key;
    try {
      key = canonicalPuzzleKey(line);
    } catch (_) {
      kept.add(line); // Unparseable — keep verbatim.
      continue;
    }
    if (keeperKeys.contains(key)) {
      kept.add(line);
      keptPuzzles++;
    } else {
      movedLines.add(line);
    }
  }
  final tmpPath = '$path.recycle';
  File(tmpPath).writeAsStringSync('${kept.join('\n')}\n');
  File(tmpPath).renameSync(path);
  stderr.writeln(
    '    $path: rewrote keeping $keptPuzzles (${movedLines.length} moved out)',
  );
  return movedLines;
}

/// Append [movedLines] to `<path>-recycled.txt` (e.g. `assets/6-mad.txt`
/// → `assets/6-mad-recycled.txt`), deduped by canonical key against the
/// existing content. Append + dedup keeps the feed idempotent across runs:
/// re-pruning after a partial `recycle_mad` consumption never loses or
/// duplicates lines.
void _appendRecycled(String path, List<String> movedLines) {
  final recycledPath = path.replaceFirst(RegExp(r'\.txt$'), '-recycled.txt');
  final existing = File(recycledPath).existsSync()
      ? File(recycledPath).readAsLinesSync()
      : <String>[];
  final existingKeys = <String>{};
  for (final l in existing) {
    if (l.trim().isEmpty || l.startsWith('#')) continue;
    try {
      existingKeys.add(canonicalPuzzleKey(l));
    } catch (_) {}
  }
  final added = <String>[];
  for (final l in movedLines) {
    try {
      if (existingKeys.add(canonicalPuzzleKey(l))) added.add(l);
    } catch (_) {}
  }
  if (added.isEmpty) {
    stderr.writeln('    $recycledPath: nothing new (all already present)');
    return;
  }
  File(
    recycledPath,
  ).writeAsStringSync('${[...existing, ...added].join('\n')}\n');
  stderr.writeln(
    '    $recycledPath: +${added.length} '
    '(${existing.length} → ${existing.length + added.length})',
  );
}

/// Write the recycle-mode report: one section per collection with the
/// kept/moved counts and the canonical keys of the moved puzzles.
void _writeRecycleReport(
  StringSink sink,
  List<_RecycleOutcome> outcomes,
  int targetCount,
  bool apply,
) {
  sink.writeln('# Recycle-mode report (FPS prune-to-count)');
  sink.writeln(
    '# target per collection: $targetCount (${apply ? 'applied' : 'dry-run'})',
  );
  sink.writeln('');
  for (final o in outcomes) {
    sink.writeln(
      '## ${o.path}  ${o.total} → keep ${o.kept}, move ${o.movedKeys.length}',
    );
    for (final key in o.movedKeys) {
      sink.writeln('  MOVE  $key');
    }
    sink.writeln('');
  }
}

/// Write the human-readable cluster report. Shows the 20 largest
/// clusters with KEEP/DROP markers per row.
void _writeApplyReport(
  StringSink sink,
  List<List<_Row>> clusters,
  Set<String> toRemove,
) {
  sink.writeln('# Apply-mode cluster report');
  sink.writeln(
    '# ${clusters.length} non-trivial clusters, '
    '${toRemove.length} puzzles to remove',
  );
  sink.writeln('');
  final sorted = List<List<_Row>>.from(clusters)
    ..sort((a, b) => b.length.compareTo(a.length));
  int n = 0;
  for (final c in sorted.take(20)) {
    n++;
    sink.writeln('## Cluster $n  size=${c.length}');
    for (final r in c) {
      final mark = toRemove.contains(r.canonicalKey) ? 'DROP' : 'KEEP';
      sink.writeln(
        '  $mark  ${r.file}  ${r.width}x${r.height}  ${r.canonicalKey}',
      );
    }
    sink.writeln('');
  }
}

/// Canonical keys of every puzzle currently present in the playable
/// collections. Used in apply mode to drop stale CSV rows — puzzles removed by
/// an earlier pipeline step (dedup / cleanup) after the vector was built — so
/// they can't be picked as a cluster representative and wipe out the family.
Set<String> _loadLiveKeys() {
  final keys = <String>{};
  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      try {
        keys.add(canonicalPuzzleKey(line));
      } catch (_) {
        // Unparseable line — skip, matching the protect-file loader.
      }
    }
  }
  return keys;
}

/// Stream each affected collection through the toRemove filter and
/// overwrite it in-place (via a `<file>.cleanup` staging file that is
/// immediately renamed). Comments and blank lines pass through verbatim.
void _rewriteCollections(Set<String> affectedFiles, Set<String> toRemove) {
  for (final path in affectedFiles) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  warn: $path not found, skip');
      continue;
    }
    final kept = <String>[];
    int dropped = 0;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) {
        kept.add(line);
        continue;
      }
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        kept.add(line);
        continue;
      }
      if (toRemove.contains(key)) {
        dropped++;
        continue;
      }
      kept.add(line);
    }
    final tmpPath = '$path.cleanup';
    File(tmpPath).writeAsStringSync('${kept.join('\n')}\n');
    File(tmpPath).renameSync(path);
    stderr.writeln('  $path: $dropped dropped, ${kept.length} kept (in-place)');
  }
}

/// Max-heap of fixed capacity: keeps the K *smallest* distances seen.
/// `topDistanceSq` is the current threshold (largest among the keepers);
/// any pair with `distanceSq < topDistanceSq` is a strict improvement.
class _MaxHeap {
  final int capacity;
  final List<_Pair> _data = [];
  _MaxHeap(this.capacity);

  int get size => _data.length;
  bool get isFull => size >= capacity;
  double get topDistanceSq => _data[0].distanceSq;

  void pushIfBetter(_Pair p) {
    if (size < capacity) {
      _data.add(p);
      _siftUp(size - 1);
    } else if (p.distanceSq < _data[0].distanceSq) {
      _data[0] = p;
      _siftDown(0);
    }
  }

  List<_Pair> toSortedList() {
    final out = List<_Pair>.from(_data);
    out.sort((a, b) => a.distanceSq.compareTo(b.distanceSq));
    return out;
  }

  void _siftUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_data[i].distanceSq > _data[parent].distanceSq) {
        final tmp = _data[i];
        _data[i] = _data[parent];
        _data[parent] = tmp;
        i = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int i) {
    final n = _data.length;
    while (true) {
      final l = 2 * i + 1;
      final r = 2 * i + 2;
      int largest = i;
      if (l < n && _data[l].distanceSq > _data[largest].distanceSq) largest = l;
      if (r < n && _data[r].distanceSq > _data[largest].distanceSq) largest = r;
      if (largest == i) break;
      final tmp = _data[i];
      _data[i] = _data[largest];
      _data[largest] = tmp;
      i = largest;
    }
  }
}

/// Pull the first-occurrence v2 line for each requested canonical key
/// by streaming the asset collections once. Keys not found end up
/// with a placeholder string in the report.
Map<String, String> _loadLinesByCanonicalKey(Set<String> keys) {
  final out = <String, String>{};
  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        continue;
      }
      if (keys.contains(key) && !out.containsKey(key)) {
        out[key] = line;
      }
    }
  }
  return out;
}

/// Write the human-readable report: ranked pairs with per-feature
/// contribution breakdown. Each pair gets:
///   - rank, distance, both file/canonical-key tags
///   - both v2 lines truncated
///   - top-3 features pulling the puzzles together (smallest |Δz|)
///     and top-3 pulling them apart (largest |Δz|)
void _writeReport(
  StringSink sink,
  List<_Pair> pairs,
  List<String> featureNames,
  Map<String, String> byKey,
) {
  sink.writeln('# Top ${pairs.length} closest puzzle pairs');
  sink.writeln('# Distance: Euclidean on z-scored feature vector (clipped ±5)');
  sink.writeln('');
  for (int i = 0; i < pairs.length; i++) {
    final p = pairs[i];
    final dist = sqrt(p.distanceSq);
    sink.writeln('## #${i + 1}  distance=${dist.toStringAsFixed(3)}');
    sink.writeln('  A  ${p.a.file}  ${p.a.width}x${p.a.height}');
    sink.writeln(
      '     ${_preview(byKey[p.a.canonicalKey] ?? p.a.canonicalKey)}',
    );
    sink.writeln('  B  ${p.b.file}  ${p.b.width}x${p.b.height}');
    sink.writeln(
      '     ${_preview(byKey[p.b.canonicalKey] ?? p.b.canonicalKey)}',
    );

    // Per-feature delta breakdown. Each entry: (name, |Δz|).
    final deltas = <(String, double)>[];
    for (int k = 0; k < featureNames.length; k++) {
      final d = (p.a.normVec[k] - p.b.normVec[k]).abs();
      if (d > 0) deltas.add((featureNames[k], d));
    }
    deltas.sort((x, y) => y.$2.compareTo(x.$2));
    final top3Apart = deltas.take(3).toList();
    final top3Together = deltas.reversed.take(3).toList();
    if (top3Apart.isNotEmpty) {
      sink.writeln(
        '  diverging: ${top3Apart.map((e) => "${e.$1}(${e.$2.toStringAsFixed(2)})").join(", ")}',
      );
    }
    if (top3Together.isNotEmpty) {
      sink.writeln(
        '  shared   : ${top3Together.map((e) => "${e.$1}(${e.$2.toStringAsFixed(2)})").join(", ")}',
      );
    }
    sink.writeln('');
  }
}

String _preview(String line) =>
    line.length > 110 ? '${line.substring(0, 107)}...' : line;
