// Offline stats analysis for adapt-to-player.
//
// Reads every `.txt` under the given directory, deduplicates, filters out
// the cplx=100 legacy bucket, then:
//   1. Refits the duration model log(dur) = a + b·cplx + c·log(cells) + d·failures
//      via ordinary least squares and reports R² + MAPE.
//   2. Compares the three level-inference approaches discussed in the
//      adapt-to-player brainstorm:
//        A1 = proper inverse of the OLD formula (pre-714574d)
//        A2 = ratio·cplx (current code, post-714574d)
//        A3 = skill model: skill = cplx − inverseOfNewModel(dur)
//      and prints summary statistics + a few sample plays side-by-side.
//
// Usage: dart run bin/analyze_stats.dart stats/

import 'dart:io';
import 'dart:math' as math;

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class Play {
  final String timestamp;
  final int duration; // seconds
  final int failures;
  final int cplx;
  final int cells;
  final String puzzleLine;
  // Suffix-tagged fields appended over time. Default 0 for older lines.
  final int cellEdits;
  final int firstClickMs;
  final int longestGapMs;
  Play({
    required this.timestamp,
    required this.duration,
    required this.failures,
    required this.cplx,
    required this.cells,
    required this.puzzleLine,
    this.cellEdits = 0,
    this.firstClickMs = 0,
    this.longestGapMs = 0,
  });
}

int _suffixedValue(List<String> fields, String suffix) {
  for (final f in fields) {
    if (f.endsWith(suffix)) {
      return int.tryParse(f.substring(0, f.length - suffix.length)) ?? 0;
    }
  }
  return 0;
}

Play? parsePlay(String line) {
  final parts = line.split(' ');
  if (parts.length < 4) return null;
  final ts = parts[0];
  final dur = int.tryParse(parts[1].replaceAll('s', ''));
  final fails = int.tryParse(parts[2].replaceAll('f', ''));
  final puzLine = parts[3];
  if (dur == null || fails == null) return null;

  // puzzle line: v2_12_WxH_cells_constraints_solution_cplx
  final pp = puzLine.split('_');
  if (pp.length < 4) return null;
  final dim = pp[2].split('x');
  if (dim.length != 2) return null;
  final w = int.tryParse(dim[0]);
  final h = int.tryParse(dim[1]);
  final cplx = int.tryParse(pp.last);
  if (w == null || h == null || cplx == null) return null;

  return Play(
    timestamp: ts,
    duration: dur,
    failures: fails,
    cplx: cplx,
    cells: w * h,
    puzzleLine: puzLine,
    cellEdits: _suffixedValue(parts, 'e'),
    firstClickMs: _suffixedValue(parts, 'fc'),
    longestGapMs: _suffixedValue(parts, 'lg'),
  );
}

// ---------------------------------------------------------------------------
// Duration models (current and proposed reference)
// ---------------------------------------------------------------------------

double expectedNew(int cplx, int cells, int failures) {
  final c = cplx.clamp(0, 100) / 100.0;
  return cells * 1.25 * math.exp(c) * math.exp(c) * math.pow(1.65, failures);
}

double expectedOld(int cplx, int cells, int failures) {
  final c = cplx.clamp(0, 80);
  return 0.92 * cells * math.exp(c / 75.0) * math.pow(1.65, failures);
}

// ---------------------------------------------------------------------------
// Level inference approaches
// ---------------------------------------------------------------------------

// A1: proper algebraic inverse of the OLD model.
double levelA1(int dur, int cells, int failures) {
  return 75.0 * (math.log(dur) - math.log(cells) - 0.504 * failures + 0.086);
}

// A2: current code — ratio · cplx, with duration clamp at 10·expected.
double levelA2(int dur, int cells, int failures, int cplx) {
  final exp = expectedNew(cplx, cells, failures);
  final clampedDur = dur.clamp(1, (exp * 10).round());
  final ratio = exp / clampedDur.toDouble();
  return ratio * cplx;
}

// A3: skill model. Convention: when dur == expected, skill = cplx (so the
// scale aligns with the existing playerLevel display).
//   skill = 2·cplx − cplx_implicit_proper(NEW model)
double levelA3(int dur, int cells, int failures, int cplx) {
  // proper inverse of expectedNew: cplx_imp = 50·log(dur / (cells·1.25·1.65^f))
  final cplxImp =
      50.0 *
      (math.log(dur) -
          math.log(cells) -
          math.log(1.25) -
          failures * math.log(1.65));
  return 2.0 * cplx - cplxImp;
}

// ---------------------------------------------------------------------------
// OLS for log(dur) = a + b·cplx + c·log(cells) + d·failures
// ---------------------------------------------------------------------------

class FitResult {
  final List<double> beta; // [a, b, c, d]
  final double rSquared;
  final double mape;
  FitResult(this.beta, this.rSquared, this.mape);
}

FitResult fitLogLinear(List<Play> plays) {
  // Design matrix X (N×4), response y (N).
  final n = plays.length;
  final xs = List.generate(n, (i) {
    final p = plays[i];
    return [1.0, p.cplx.toDouble(), math.log(p.cells), p.failures.toDouble()];
  });
  final ys = plays.map((p) => math.log(p.duration)).toList();

  // Build X^T X (4×4) and X^T y (4).
  final xtx = List.generate(4, (_) => List.filled(4, 0.0));
  final xty = List.filled(4, 0.0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < 4; j++) {
      xty[j] += xs[i][j] * ys[i];
      for (var k = 0; k < 4; k++) {
        xtx[j][k] += xs[i][j] * xs[i][k];
      }
    }
  }
  final beta = solve4x4(xtx, xty);

  // R² and MAPE
  final yMean = ys.reduce((a, b) => a + b) / n;
  double ssTot = 0, ssRes = 0, mape = 0;
  for (var i = 0; i < n; i++) {
    final yhat =
        beta[0] + beta[1] * xs[i][1] + beta[2] * xs[i][2] + beta[3] * xs[i][3];
    ssTot += math.pow(ys[i] - yMean, 2).toDouble();
    ssRes += math.pow(ys[i] - yhat, 2).toDouble();
    final durHat = math.exp(yhat);
    mape += (plays[i].duration - durHat).abs() / plays[i].duration;
  }
  return FitResult(beta, 1 - ssRes / ssTot, 100 * mape / n);
}

List<double> solve4x4(List<List<double>> A, List<double> b) {
  // Augmented matrix
  final m = List.generate(4, (i) => [...A[i], b[i]]);
  for (var i = 0; i < 4; i++) {
    var maxRow = i;
    for (var k = i + 1; k < 4; k++) {
      if (m[k][i].abs() > m[maxRow][i].abs()) maxRow = k;
    }
    if (maxRow != i) {
      final t = m[maxRow];
      m[maxRow] = m[i];
      m[i] = t;
    }
    for (var k = i + 1; k < 4; k++) {
      final f = m[k][i] / m[i][i];
      for (var j = i; j <= 4; j++) {
        m[k][j] -= f * m[i][j];
      }
    }
  }
  final x = List.filled(4, 0.0);
  for (var i = 3; i >= 0; i--) {
    var s = m[i][4];
    for (var j = i + 1; j < 4; j++) {
      s -= m[i][j] * x[j];
    }
    x[i] = s / m[i][i];
  }
  return x;
}

// Compute R² for a fixed-form predictor f(p) -> predicted duration.
double rSquaredOf(List<Play> plays, double Function(Play) f) {
  final n = plays.length;
  final ys = plays.map((p) => math.log(p.duration)).toList();
  final yMean = ys.reduce((a, b) => a + b) / n;
  double ssTot = 0, ssRes = 0;
  for (var i = 0; i < n; i++) {
    final yhat = math.log(f(plays[i]));
    ssTot += math.pow(ys[i] - yMean, 2).toDouble();
    ssRes += math.pow(ys[i] - yhat, 2).toDouble();
  }
  return 1 - ssRes / ssTot;
}

double mapeOf(List<Play> plays, double Function(Play) f) {
  double s = 0;
  for (final p in plays) {
    s += (p.duration - f(p)).abs() / p.duration;
  }
  return 100 * s / plays.length;
}

// ---------------------------------------------------------------------------
// Distribution helpers
// ---------------------------------------------------------------------------

class Stats {
  final double min, p25, median, p75, max, mean, std;
  Stats(
    this.min,
    this.p25,
    this.median,
    this.p75,
    this.max,
    this.mean,
    this.std,
  );
  String fmt() =>
      'min=${min.toStringAsFixed(1)} p25=${p25.toStringAsFixed(1)} med=${median.toStringAsFixed(1)} p75=${p75.toStringAsFixed(1)} max=${max.toStringAsFixed(1)} mean=${mean.toStringAsFixed(1)} std=${std.toStringAsFixed(1)}';
}

Stats describe(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  double q(double p) => s[(p * (n - 1)).round()];
  final mean = s.reduce((a, b) => a + b) / n;
  final variance = s.fold(0.0, (a, x) => a + math.pow(x - mean, 2)) / n;
  return Stats(
    s.first,
    q(0.25),
    q(0.5),
    q(0.75),
    s.last,
    mean,
    math.sqrt(variance),
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main(List<String> args) {
  if (args.isEmpty) {
    print(
      'usage: dart run bin/analyze_stats.dart [--recompute-cplx] <stats_dir>',
    );
    exit(2);
  }
  final recomputeCplx = args.contains('--recompute-cplx');
  final dirArg = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  if (dirArg.isEmpty) {
    print(
      'usage: dart run bin/analyze_stats.dart [--recompute-cplx] <stats_dir>',
    );
    exit(2);
  }
  final dir = Directory(dirArg);
  final lines = <String>{};
  // Track which file each line came from for per-source diagnostics.
  final lineSource = <String, String>{};
  for (final f in dir.listSync()) {
    if (f is File && f.path.endsWith('.txt')) {
      final fname = f.uri.pathSegments.last;
      for (final l in f.readAsLinesSync()) {
        final t = l.trim();
        if (t.isEmpty) continue;
        if (lines.add(t)) lineSource[t] = fname;
      }
    }
  }

  var all = lines.map(parsePlay).whereType<Play>().toList();

  // Optional: rebuild every Play's cplx by running the current solver/complexity
  // formula on its puzzle line. Older stats may carry a cplx that was computed
  // by a now-obsolete formula, which makes mixing periods incoherent.
  if (recomputeCplx) {
    stderr.writeln('Recomputing cplx for ${all.length} plays...');
    final sw = Stopwatch()..start();
    final out = <Play>[];
    var ok = 0, fail = 0;
    for (var i = 0; i < all.length; i++) {
      final p = all[i];
      try {
        final puz = Puzzle(p.puzzleLine);
        puz.computeComplexity();
        final c = puz.cachedComplexity;
        if (c != null) {
          out.add(
            Play(
              timestamp: p.timestamp,
              duration: p.duration,
              failures: p.failures,
              cplx: c,
              cells: p.cells,
              puzzleLine: p.puzzleLine,
            ),
          );
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
      if ((i + 1) % 100 == 0) {
        stderr.write(
          '\r  $ok ok, $fail failed, ${i + 1}/${all.length} '
          '(${sw.elapsed.inSeconds}s)',
        );
      }
    }
    stderr.writeln(
      '\n  done: $ok recomputed, $fail failed in ${sw.elapsed.inSeconds}s',
    );
    all = out;
  }

  // Baseline filter: legacy cplx=100 bucket and obvious bad rows.
  final baseline = all
      .where((p) => p.cplx < 100 && p.duration > 0 && p.cells > 0)
      .toList();

  // Outlier filter:
  //   - dur < 2 s   → likely an accidental auto-complete or stale stat
  //   - dur > 1800 s → puzzle left open / AFK (the in-game clamp is 10·exp,
  //     but we don't trust the model here so we use an absolute cap).
  //   - dur > 10 · median(dur for same cplx-bucket × cells-bucket) → bucket
  //     median is robust enough to drop "ten times what's typical for this
  //     puzzle class" without referring to a model.
  bool tooLong(Play p, Map<String, double> bucketMedian) {
    final key = '${p.cplx ~/ 10}_${p.cells ~/ 5}';
    final m = bucketMedian[key];
    if (m == null) return false;
    return p.duration > 10 * m;
  }

  // First pass: compute robust per-bucket medians using baseline data.
  final durByBucket = <String, List<int>>{};
  for (final p in baseline) {
    final key = '${p.cplx ~/ 10}_${p.cells ~/ 5}';
    durByBucket.putIfAbsent(key, () => []).add(p.duration);
  }
  final bucketMedian = <String, double>{};
  for (final e in durByBucket.entries) {
    final s = [...e.value]..sort();
    bucketMedian[e.key] = s[s.length ~/ 2].toDouble();
  }

  final filtered = baseline
      .where(
        (p) =>
            p.duration >= 2 && p.duration <= 1800 && !tooLong(p, bucketMedian),
      )
      .toList();

  final droppedAfk = baseline
      .where((p) => p.duration > 1800 || tooLong(p, bucketMedian))
      .length;
  final droppedShort = baseline.where((p) => p.duration < 2).length;

  print('=== Data ===');
  print('  raw lines (deduped):  ${lines.length}');
  print('  parsed plays:         ${all.length}');
  print(
    '  after baseline:       ${baseline.length}  '
    '(dropped ${all.length - baseline.length}: cplx=100 or invalid)',
  );
  print(
    '  after outlier filter: ${filtered.length}  '
    '(dropped $droppedShort short + $droppedAfk afk/extreme)',
  );
  print('');

  // ---------- 1. Refit ----------
  final fit = fitLogLinear(filtered);
  final a = fit.beta[0], b = fit.beta[1], c = fit.beta[2], d = fit.beta[3];
  print(
    '=== OLS refit on log(dur) = a + b·cplx + c·log(cells) + d·failures ===',
  );
  print(
    '  a (intercept)   = ${a.toStringAsFixed(4)}    '
    '⇒ base coefficient exp(a) = ${math.exp(a).toStringAsFixed(3)}',
  );
  print(
    '  b (cplx slope)  = ${b.toStringAsFixed(5)}   '
    '⇒ scale = exp(cplx · ${b.toStringAsFixed(5)})  ≈ exp(cplx/${(1 / b).toStringAsFixed(1)})',
  );
  print(
    '  c (log-cells)   = ${c.toStringAsFixed(4)}    '
    '⇒ cells^${c.toStringAsFixed(3)}  (≈ linear if c≈1)',
  );
  print(
    '  d (failures)    = ${d.toStringAsFixed(4)}    '
    '⇒ multiplier per failure = exp(d) = ${math.exp(d).toStringAsFixed(3)}',
  );
  print(
    '  R² = ${fit.rSquared.toStringAsFixed(3)}    MAPE = ${fit.mape.toStringAsFixed(1)} %',
  );
  print('');

  // ---------- 2. Compare existing formulas ----------
  final r2New = rSquaredOf(
    filtered,
    (p) => expectedNew(p.cplx, p.cells, p.failures),
  );
  final r2Old = rSquaredOf(
    filtered,
    (p) => expectedOld(p.cplx, p.cells, p.failures),
  );
  final mNew = mapeOf(
    filtered,
    (p) => expectedNew(p.cplx, p.cells, p.failures),
  );
  final mOld = mapeOf(
    filtered,
    (p) => expectedOld(p.cplx, p.cells, p.failures),
  );
  // Per-source / per-date diagnostics: split the dataset by year-month and
  // by source file, refit on each chunk, and report R². If older data has
  // stale cplx values, the older chunks should refit poorly even on their
  // own — meaning their cplx column is no longer informative.
  print('=== Refit on time-window subsets ===');
  print(
    '  (each row refits log(dur) = a + b·cplx + c·log(cells) + d·failures '
    'on plays in that window only)',
  );
  final byMonth = <String, List<Play>>{};
  for (final p in filtered) {
    final ym = p.timestamp.length >= 7 ? p.timestamp.substring(0, 7) : '????';
    byMonth.putIfAbsent(ym, () => []).add(p);
  }
  final months = byMonth.keys.toList()..sort();
  for (final m in months) {
    final ps = byMonth[m]!;
    if (ps.length < 30) {
      print('  $m   n=${ps.length}  (skipped, <30 plays)');
      continue;
    }
    final f = fitLogLinear(ps);
    print(
      '  $m   n=${ps.length.toString().padLeft(4)}  '
      'R²=${f.rSquared.toStringAsFixed(3)}  '
      'cplx slope=1/${(1 / f.beta[1]).toStringAsFixed(0)}  '
      'cells exp=${f.beta[2].toStringAsFixed(2)}',
    );
  }
  print('');

  print('=== Existing formulas on this data ===');
  print(
    '  OLD (pre-714574d):  0.92·cells·exp(cplx/75)·1.65^f  '
    '→ R²=${r2Old.toStringAsFixed(3)}  MAPE=${mOld.toStringAsFixed(1)} %',
  );
  print(
    '  NEW (current):     1.25·cells·exp(cplx/50)·1.65^f  '
    '→ R²=${r2New.toStringAsFixed(3)}  MAPE=${mNew.toStringAsFixed(1)} %',
  );
  print(
    '  Refit (this run):                                    '
    '→ R²=${fit.rSquared.toStringAsFixed(3)}  MAPE=${fit.mape.toStringAsFixed(1)} %',
  );
  print('');

  // ---------- 3. Distribution of per-play level estimates ----------
  // Restrict to plays that actually pass the filters used in computePlayerLevel
  // (skipped is excluded by stats absence, played always true here).
  // Clip A2 to [0,100] like the production code.
  final a1 = filtered
      .map((p) => levelA1(p.duration, p.cells, p.failures).clamp(0.0, 100.0))
      .toList();
  final a2 = filtered
      .map(
        (p) =>
            levelA2(p.duration, p.cells, p.failures, p.cplx).clamp(0.0, 100.0),
      )
      .toList();
  final a3 = filtered
      .map(
        (p) =>
            levelA3(p.duration, p.cells, p.failures, p.cplx).clamp(0.0, 100.0),
      )
      .toList();

  print('=== Distribution of per-play level estimates (clamped to 0..100) ===');
  print('  A1 (old proper inverse):   ${describe(a1).fmt()}');
  print('  A2 (current ratio·cplx):    ${describe(a2).fmt()}');
  print('  A3 (skill: 2·cplx−cplxImp): ${describe(a3).fmt()}');
  print('');

  // Saturation count (how many plays hit the ceiling/floor).
  final satA2 = a2.where((x) => x == 0 || x == 100).length;
  final satA3 = a3.where((x) => x == 0 || x == 100).length;
  print(
    '  A2 plays saturated at 0 or 100: $satA2 / ${filtered.length} '
    '(${(100 * satA2 / filtered.length).toStringAsFixed(1)} %)',
  );
  print(
    '  A3 plays saturated at 0 or 100: $satA3 / ${filtered.length} '
    '(${(100 * satA3 / filtered.length).toStringAsFixed(1)} %)',
  );
  print('');

  // Coherence check: how stable is each approach across same-cplx plays?
  // Group by cplx bucket and compute std-dev of level_i within each bucket.
  // A small std means the approach gives consistent estimates for the same
  // puzzle difficulty (good signal); a large std means it depends heavily on
  // the actual duration noise.
  final byBucket = <int, List<int>>{};
  for (var i = 0; i < filtered.length; i++) {
    final b = (filtered[i].cplx ~/ 10) * 10;
    byBucket.putIfAbsent(b, () => []).add(i);
  }
  print('=== Within-bucket standard deviation of level estimates ===');
  print('  (smaller = more consistent across plays of similar difficulty)');
  print('  bucket   n   A1-σ   A2-σ   A3-σ');
  final sortedBuckets = byBucket.keys.toList()..sort();
  for (final b in sortedBuckets) {
    final ids = byBucket[b]!;
    if (ids.length < 5) continue;
    double std(List<double> all) {
      final xs = ids.map((i) => all[i]).toList();
      final m = xs.reduce((a, b) => a + b) / xs.length;
      return math.sqrt(
        xs.fold(0.0, (a, x) => a + math.pow(x - m, 2)) / xs.length,
      );
    }

    print(
      '  [${b.toString().padLeft(2)},${(b + 10).toString().padLeft(3)})  '
      '${ids.length.toString().padLeft(3)}   '
      '${std(a1).toStringAsFixed(1).padLeft(5)}  '
      '${std(a2).toStringAsFixed(1).padLeft(5)}  '
      '${std(a3).toStringAsFixed(1).padLeft(5)}',
    );
  }
  print('');

  // ---------- 4. A few sample plays side-by-side ----------
  print(
    '=== Sample plays (sorted by abs(dur − expectedNew), most surprising first) ===',
  );
  final indexed = List.generate(filtered.length, (i) => i);
  indexed.sort((i, j) {
    final pi = filtered[i], pj = filtered[j];
    final di = (pi.duration - expectedNew(pi.cplx, pi.cells, pi.failures))
        .abs();
    final dj = (pj.duration - expectedNew(pj.cplx, pj.cells, pj.failures))
        .abs();
    return dj.compareTo(di);
  });
  print('  cplx cells fail  dur  expN     A1    A2    A3');
  for (final i in indexed.take(8)) {
    final p = filtered[i];
    final eN = expectedNew(p.cplx, p.cells, p.failures);
    print(
      '  '
      '${p.cplx.toString().padLeft(4)} '
      '${p.cells.toString().padLeft(5)} '
      '${p.failures.toString().padLeft(4)} '
      '${p.duration.toString().padLeft(4)} '
      '${eN.toStringAsFixed(0).padLeft(5)}  '
      '${a1[i].toStringAsFixed(0).padLeft(4)}  '
      '${a2[i].toStringAsFixed(0).padLeft(4)}  '
      '${a3[i].toStringAsFixed(0).padLeft(4)}',
    );
  }
}
