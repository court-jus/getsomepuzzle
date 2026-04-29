// Offline stats analysis for adapt-to-player.
//
// Reads every `.txt` under the given directory, deduplicates, filters out
// the cplx=100 legacy bucket, then:
//   1. Refits log(dur) = a + b·cplx + c·log(cells) + d·failures (4 vars)
//      and the v1.6.1+ form that adds e·n_constraints (5 vars). Reports
//      coefficients + R² + MAPE for each.
//   2. Replays the production skill inversion (`expectedProd` /
//      `levelProd`, mirrors of `Database._expectedDuration` /
//      `Database._impliedCplx`) on every play and reports the per-play
//      level distribution, saturation rate, and within-bucket spread.
//   3. Lists the eight plays the production model fits worst — useful
//      for spotting a missing variable or a stale calibration.
//
// Usage: dart run bin/analyze_stats.dart [--recompute-cplx] <stats_dir>

import 'dart:io';
import 'dart:math' as math;

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class Play {
  final String timestamp;
  final int duration; // seconds
  final int failures;
  final int cplx;
  final int cells;
  final int nConstraints; // count of `;`-separated entries in the constraints
  // section. Folded into the duration model in v1.6.1.
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
    required this.nConstraints,
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
  // Constraints section sits at index 4 in the v2 layout. We just count
  // the `;`-separated entries; semantic validation is not our concern.
  final nCons = pp.length > 4
      ? pp[4].split(';').where((s) => s.isNotEmpty).length
      : 0;

  return Play(
    timestamp: ts,
    duration: dur,
    failures: fails,
    cplx: cplx,
    cells: w * h,
    nConstraints: nCons,
    puzzleLine: puzLine,
    cellEdits: _suffixedValue(parts, 'e'),
    firstClickMs: _suffixedValue(parts, 'fc'),
    longestGapMs: _suffixedValue(parts, 'lg'),
  );
}

// ---------------------------------------------------------------------------
// Production duration model + skill inversion
// ---------------------------------------------------------------------------

// Must mirror `Database._expectedDuration` in
// `lib/getsomepuzzle/model/database.dart`. Anchored so the calibration
// cohort's mean `level_i` lands at 50.
double expectedProd(int cplx, int cells, int failures, int nConstraints) {
  return 8.62 *
      math.pow(cells, 0.442) *
      math.exp(cplx / 27.3) *
      math.pow(1.145, failures) *
      math.pow(1.085, nConstraints);
}

// Mirror of `Database._impliedCplx`: the algebraic inverse of
// `expectedProd`. Same constants as the production code.
double impliedCplxProd(int dur, int cells, int failures, int nConstraints) {
  return 27.3 *
      (math.log(dur) -
          math.log(8.62) -
          0.442 * math.log(cells) -
          failures * math.log(1.145) -
          nConstraints * math.log(1.085));
}

// Mirror of `Database.computePlayerLevel`'s per-play inversion: when a
// play's duration matches the expected for its puzzle, level == cplx.
// Faster ⇒ above; slower ⇒ below. The intercept anchor in `expectedProd`
// shifts cohort plays up so their average lands at 50.
double levelProd(int dur, int cells, int failures, int cplx, int nCons) {
  return 2.0 * cplx - impliedCplxProd(dur, cells, failures, nCons);
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
  return _fitOLS(
    plays,
    (p) => [1.0, p.cplx.toDouble(), math.log(p.cells), p.failures.toDouble()],
  );
}

/// Same as `fitLogLinear` but with a 5th regressor: the puzzle's constraint
/// count. Used to verify the v1.6.1+ production model and to refit on new
/// data.
FitResult fitLogLinearWithConstraints(List<Play> plays) {
  return _fitOLS(
    plays,
    (p) => [
      1.0,
      p.cplx.toDouble(),
      math.log(p.cells),
      p.failures.toDouble(),
      p.nConstraints.toDouble(),
    ],
  );
}

FitResult _fitOLS(List<Play> plays, List<double> Function(Play) features) {
  final n = plays.length;
  final xs = plays.map(features).toList();
  final ys = plays.map((p) => math.log(p.duration)).toList();
  final p = xs[0].length;

  // Build X^T X (p×p) and X^T y (p).
  final xtx = List.generate(p, (_) => List.filled(p, 0.0));
  final xty = List.filled(p, 0.0);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < p; j++) {
      xty[j] += xs[i][j] * ys[i];
      for (var k = 0; k < p; k++) {
        xtx[j][k] += xs[i][j] * xs[i][k];
      }
    }
  }
  final beta = _solveLinear(xtx, xty);

  // R² and MAPE
  final yMean = ys.reduce((a, b) => a + b) / n;
  double ssTot = 0, ssRes = 0, mape = 0;
  for (var i = 0; i < n; i++) {
    double yhat = 0;
    for (var j = 0; j < p; j++) {
      yhat += beta[j] * xs[i][j];
    }
    ssTot += math.pow(ys[i] - yMean, 2).toDouble();
    ssRes += math.pow(ys[i] - yhat, 2).toDouble();
    final durHat = math.exp(yhat);
    mape += (plays[i].duration - durHat).abs() / plays[i].duration;
  }
  return FitResult(beta, 1 - ssRes / ssTot, 100 * mape / n);
}

// Gauss-Jordan elimination on an augmented matrix [A | b] of any size.
List<double> _solveLinear(List<List<double>> A, List<double> b) {
  final p = A.length;
  final m = List.generate(p, (i) => [...A[i], b[i]]);
  for (var i = 0; i < p; i++) {
    var maxRow = i;
    for (var k = i + 1; k < p; k++) {
      if (m[k][i].abs() > m[maxRow][i].abs()) maxRow = k;
    }
    if (maxRow != i) {
      final t = m[maxRow];
      m[maxRow] = m[i];
      m[i] = t;
    }
    for (var k = i + 1; k < p; k++) {
      final f = m[k][i] / m[i][i];
      for (var j = i; j <= p; j++) {
        m[k][j] -= f * m[i][j];
      }
    }
  }
  final x = List.filled(p, 0.0);
  for (var i = p - 1; i >= 0; i--) {
    var s = m[i][p];
    for (var j = i + 1; j < p; j++) {
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
              nConstraints: p.nConstraints,
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

  // ---------- 1b. Refit including n_constraints (the v1.6.1+ form) ----------
  final fitC = fitLogLinearWithConstraints(filtered);
  final ac = fitC.beta[0],
      bc = fitC.beta[1],
      cc = fitC.beta[2],
      dc = fitC.beta[3],
      ec = fitC.beta[4];
  print(
    '=== OLS refit on log(dur) = a + b·cplx + c·log(cells) + d·failures '
    '+ e·n_constraints ===',
  );
  print(
    '  a = ${ac.toStringAsFixed(4)}  '
    'b (cplx) = ${bc.toStringAsFixed(5)} (1/${(1 / bc).toStringAsFixed(1)})  '
    'c (cells) = ${cc.toStringAsFixed(4)}  '
    'd (fails) = ${dc.toStringAsFixed(4)}  '
    'e (n_cons) = ${ec.toStringAsFixed(4)}',
  );
  print(
    '  R² = ${fitC.rSquared.toStringAsFixed(3)}    MAPE = ${fitC.mape.toStringAsFixed(1)} %',
  );
  print('');

  // ---------- 2. Per-month subset refits ----------
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

  // ---------- 3. Distribution of per-play level estimates ----------
  // Mirrors the production code path: same constants, same skill inversion.
  // Saturation rows tell us how often the formula hits the [0, 100] floor
  // or ceiling on this dataset — the signal we'd lose to clamping.
  final levels = filtered
      .map(
        (p) =>
            levelProd(p.duration, p.cells, p.failures, p.cplx, p.nConstraints),
      )
      .toList();
  final clamped = levels.map((x) => x.clamp(0.0, 100.0)).toList();
  print('=== Per-play level (production formula, n_cons-aware) ===');
  print('  raw:           ${describe(levels).fmt()}');
  print('  clamped 0–100: ${describe(clamped).fmt()}');
  final sat = clamped.where((x) => x == 0 || x == 100).length;
  print(
    '  saturated at 0 or 100: $sat / ${filtered.length} '
    '(${(100 * sat / filtered.length).toStringAsFixed(1)} %)',
  );
  print('');

  // Coherence check: how stable is the level estimate across plays of
  // similar difficulty? A small bucket std means estimates don't depend
  // heavily on per-play duration noise.
  final byBucket = <int, List<int>>{};
  for (var i = 0; i < filtered.length; i++) {
    final b = (filtered[i].cplx ~/ 10) * 10;
    byBucket.putIfAbsent(b, () => []).add(i);
  }
  print('=== Within-cplx-bucket level standard deviation ===');
  print('  bucket   n    σ');
  final sortedBuckets = byBucket.keys.toList()..sort();
  for (final b in sortedBuckets) {
    final ids = byBucket[b]!;
    if (ids.length < 5) continue;
    final xs = ids.map((i) => clamped[i]).toList();
    final m = xs.reduce((a, b) => a + b) / xs.length;
    final std = math.sqrt(
      xs.fold(0.0, (a, x) => a + math.pow(x - m, 2)) / xs.length,
    );
    print(
      '  [${b.toString().padLeft(2)},${(b + 10).toString().padLeft(3)})  '
      '${ids.length.toString().padLeft(3)}   '
      '${std.toStringAsFixed(1).padLeft(4)}',
    );
  }
  print('');

  // ---------- 4. A few sample plays side-by-side ----------
  // Sorted by largest deviation from the production model — these are the
  // plays the model fits worst, which are usually the most informative
  // for spotting a missing variable or a stale calibration.
  print(
    '=== Sample plays (sorted by abs(dur − expectedProd), most surprising first) ===',
  );
  final indexed = List.generate(filtered.length, (i) => i);
  indexed.sort((i, j) {
    final pi = filtered[i], pj = filtered[j];
    final di =
        (pi.duration -
                expectedProd(pi.cplx, pi.cells, pi.failures, pi.nConstraints))
            .abs();
    final dj =
        (pj.duration -
                expectedProd(pj.cplx, pj.cells, pj.failures, pj.nConstraints))
            .abs();
    return dj.compareTo(di);
  });
  print('  cplx cells fail n_cons  dur  expected  level');
  for (final i in indexed.take(8)) {
    final p = filtered[i];
    final exp = expectedProd(p.cplx, p.cells, p.failures, p.nConstraints);
    print(
      '  '
      '${p.cplx.toString().padLeft(4)} '
      '${p.cells.toString().padLeft(5)} '
      '${p.failures.toString().padLeft(4)} '
      '${p.nConstraints.toString().padLeft(6)} '
      '${p.duration.toString().padLeft(4)} '
      '${exp.toStringAsFixed(0).padLeft(8)}  '
      '${clamped[i].toStringAsFixed(0).padLeft(5)}',
    );
  }
}
