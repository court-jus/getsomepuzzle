// Identify the Top-K most-similar puzzle pairs in the corpus, based on
// the CSV produced by `bin/vectorize_puzzles.dart`. Goal: surface
// redundant puzzles so the cleanup can drop one of each near-duplicate
// pair (instead of generating new ones via equilibrium).
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

const _collections = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/overfilled-easy.txt',
  'assets/overfilled.txt',
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

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        inputPath = args[++i];
      case '--output':
        outputPath = args[++i];
      case '--top-k':
        topK = int.parse(args[++i]);
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
      case '--apply':
        apply = true;
      case '--max-distance':
        maxDistance = double.parse(args[++i]);
      case '--keep-per-cluster':
        keepPerCluster = int.parse(args[++i]);
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

  final header = _parseCsvLine(lines.first);
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
  // Optional features.
  if (includeSize) addFeature('cells');
  if (includeLevel) addFeature('level');
  if (includePrefill) addFeature('prefill_ratio');

  stderr.writeln('  ${featureNames.length} features in distance vector');

  // --- 2. Load rows ---
  final rows = <_Row>[];
  for (int li = 1; li < lines.length; li++) {
    final raw = lines[li];
    if (raw.trim().isEmpty) continue;
    final fields = _parseCsvLine(raw);
    if (fields.length < header.length) continue;
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
  if (rows.length < 2) {
    stderr.writeln('Not enough rows to cluster.');
    exit(0);
  }

  // --- 3. Z-score normalize each feature column ---
  // Per-feature mean and std over the pool. Std=0 columns (constant)
  // get zeroed out — they contribute nothing to distance.
  final means = Float64List(featureCols.length);
  final stds = Float64List(featureCols.length);
  for (int k = 0; k < featureCols.length; k++) {
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
  // Clip z-scores to ±_zClip to keep rare-slug outliers from
  // single-handedly dominating the distance metric.
  const zClip = 5.0;
  for (final r in rows) {
    r.normVec = Float64List(featureCols.length);
    for (int k = 0; k < featureCols.length; k++) {
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

Two modes:
  - REPORT (default): emit the Top-K closest pairs
  - APPLY (--apply):  collect pairs ≤ --max-distance, cluster them,
                      keep --keep-per-cluster representatives via
                      farthest-point sampling (with --protect-from
                      puzzles as forced seeds), write the rest to
                      <file>.cleanup for the user to mv into place.

Common options:
  --input PATH            CSV from vectorize_puzzles.dart
                          (default: puzzle_vectors.csv)
  --output PATH           Report file (default: stdout)
  --per-bucket-limit M    Cap puzzles per bucket (default: 5000)
  --include-size          Include cells in distance (default: on)
  --no-include-size       Exclude cells from distance
  --include-level         Include `level` ordinal in distance
  --include-prefill       Include `prefill_ratio` in distance (default: on)
  --no-include-prefill    Exclude prefill_ratio from distance
  -v, --verbose           Per-bucket progress lines
  -h, --help              Show this help

Report-mode options:
  --top-k N               Pairs to report (default: 100)

Apply-mode options:
  --apply                 Enable apply mode (rewrites <file>.cleanup)
  --max-distance X        Distance threshold for "redundant" (default: 0.15)
  --keep-per-cluster N    Representatives kept per cluster (default: 1)
  --protect-from PATH     File of v2 lines that must never be removed
                          (e.g. assets/1-easy_onboarding.txt)
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

/// Stream each affected collection through the toRemove filter, write
/// the survivors to `<file>.cleanup`. Comments and blank lines pass
/// through verbatim so the .cleanup file stays diff-able with the
/// original.
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
    final outPath = '$path.cleanup';
    File(outPath).writeAsStringSync('${kept.join('\n')}\n');
    stderr.writeln('  $outPath: $dropped dropped, ${kept.length} kept');
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

/// Minimal CSV parser: handles double-quoted fields with embedded
/// quotes ("") and commas. Trailing whitespace stripped.
List<String> _parseCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else {
      if (ch == ',') {
        out.add(buf.toString());
        buf.clear();
      } else if (ch == '"' && buf.isEmpty) {
        inQuotes = true;
      } else {
        buf.write(ch);
      }
    }
  }
  out.add(buf.toString());
  return out;
}
