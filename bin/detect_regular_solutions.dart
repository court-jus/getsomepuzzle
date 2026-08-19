// Diagnostic: how many puzzles have a *globally regular* solution — a grid a
// human reads at a glance — yet the trace-based difficulty (the source
// collection) rates as hard?
//
// Motivation (see tmp/checkerboard_pattern.md): `classifyTrace` measures the
// depth of *local* deduction chains. It cannot see the global pattern a human
// uses as a shortcut. The `SH:11.11`/`SH:22.22` (2×2 square) family was the
// suspected offender — its 2×2-block "damier" solutions.
//
// EMPIRICAL FINDINGS (corpus run + designer review, 2026-06-10):
//  - Two patterns are designer-CONFIRMED human shortcuts:
//      * `checker`  — perfect 2×2 damier. Equals exactly the SH:11.11+SH:22.22
//        puzzles (validated 39/39). Only ~16 leak into 6-mad.
//      * `stripes`  — 1D colour bars (one grid axis fully constant, any bar
//        width). The MUCH bigger offender: 99 in 6-mad (mean cplx 82.3, 71 of
//        them ≥80), 123 across the hard tiers.
//  - METHODOLOGY: complexity is the SOLVER's rating — the very quantity that
//    is miscalibrated. A confirmed shortcut with HIGH complexity is the bug,
//    not a disqualifier. So "low mean complexity" is NOT a shortcut test
//    (an earlier draft wrongly used it and nearly rejected stripes).
//  - `periodic` (2D, non-stripes), `symmetric`, `rle_only` are NOT confirmed
//    shortcuts — reported for inspection (`--dump-grids`), excluded from the
//    easy-pattern flag. RLE alone is a low-ink artefact (59% false positives).
//  - Easy patterns are also REDUNDANT: many share one (constraints, solution)
//    and differ only by prefill — the same puzzle served many times.
//
// Diagnosis only — no difficulty / vector mutation. The assigned level is the
// source collection; the solution is read from the v2 line (no re-solve).
//
// Usage:
//   dart run bin/detect_regular_solutions.dart [--csv PATH] [--top N]
//   dart run bin/detect_regular_solutions.dart --dump-grids [--dump-limit N]

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

import '_solution_geometry.dart';

// Playable collections in cascade order. The file *is* the assigned level —
// that's exactly the (possibly inflated) classification we want to audit.
const _collections = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/1-easy-overfilled.txt',
  'assets/2-player-overfilled.txt',
  'assets/3-advanced-overfilled.txt',
  'assets/4-strong-overfilled.txt',
  'assets/5-expert-overfilled.txt',
  'assets/6-mad-overfilled.txt',
  'assets/overfilled.txt',
];

// Non-overfilled hard tiers — used to test which signals predict difficulty.
const _hardTiers = {'4-strong', '5-expert', '6-mad'};

// Categorization thresholds for the *reported* secondary signals. The report
// prints per-category complexity so these stay falsifiable.
bool _periodicAxis(int period, int span) => period * 2 <= span;
const double _rleRegularThreshold = 0.34;
const int _symRegularThreshold = 2;

// Signal categories, in priority order. `checker` and `stripes` are the
// designer-confirmed human shortcuts; the rest are reported for inspection.
const _signalChecker = 'checker';
const _signalStripes = 'stripes';
const _signalPeriodic = 'periodic';
const _signalSymmetric = 'symmetric';
const _signalRleOnly = 'rle_only';
const _signalNone = 'none';
const _signalOrder = [
  _signalChecker,
  _signalStripes,
  _signalPeriodic,
  _signalSymmetric,
  _signalRleOnly,
  _signalNone,
];

class Features {
  final int checkerK; // smallest k for a k×k-block checkerboard, 0 if none
  final int periodX;
  final int periodY;
  final int nSymmetries;
  final double rleRatio;

  Features(
    this.checkerK,
    this.periodX,
    this.periodY,
    this.nSymmetries,
    this.rleRatio,
  );
}

class Record {
  final String collection;
  final String canonicalKey;
  final int w;
  final int h;
  final int
  complexity; // cached cplx, unbounded (see complexity.md), -1 if absent
  final bool isSh2x2;
  final Features f;
  final List<CellValue> solution; // row-major solved grid
  // Identity *modulo prefill*: dims + domain + sorted constraints + solution.
  // Two puzzles sharing this are the same puzzle with different givens.
  final String identityKey;

  Record({
    required this.collection,
    required this.canonicalKey,
    required this.w,
    required this.h,
    required this.complexity,
    required this.isSh2x2,
    required this.f,
    required this.solution,
    required this.identityKey,
  });

  bool get evenDims => w.isEven && h.isEven;
  bool get isHardTier => _hardTiers.contains(collection);

  /// Perfect 2-colour 2×2 damier (⟺ SH:11.11 + SH:22.22, validated 39/39).
  bool get isCheckerboard => f.checkerK > 0;

  /// 1D "colour bars": one axis fully constant (any bar width). A confirmed
  /// human gestalt shortcut (designer-judged), distinct from 2D-periodic.
  bool get isStripes => f.periodX == 1 || f.periodY == 1;

  /// Patterns confirmed as "human reads it at a glance" → over-classified
  /// (a bug) whenever they land in a hard tier.
  bool get isEasyPattern => isCheckerboard || isStripes;

  /// Priority-cascaded signal label.
  String get signal {
    if (isCheckerboard) return _signalChecker;
    if (isStripes) return _signalStripes;
    if (_periodicAxis(f.periodX, w) || _periodicAxis(f.periodY, h)) {
      return _signalPeriodic;
    }
    if (f.nSymmetries >= _symRegularThreshold) return _signalSymmetric;
    if (f.rleRatio <= _rleRegularThreshold) return _signalRleOnly;
    return _signalNone;
  }
}

void main(List<String> args) {
  String? csvPath;
  int top = 25;
  bool dumpGrids = false;
  int dumpLimit = 50;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--csv':
        csvPath = args[++i];
      case '--top':
        top = int.parse(args[++i]);
      case '--dump-grids':
        dumpGrids = true;
      case '--dump-limit':
        dumpLimit = int.parse(args[++i]);
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/detect_regular_solutions.dart\n'
          '  [--csv PATH]        also dump per-puzzle feature rows\n'
          '  [--top N]           worst-offenders to print (default 25)\n'
          '  [--dump-grids]      print solved grids of non-checker SH-2×2\n'
          '                      puzzles, grouped by signal (for eyeballing\n'
          '                      near-damiers); suppresses the 4 reports\n'
          '  [--dump-limit N]    grids per signal group (default 50)',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  final records = <Record>[];
  int skippedNoSolution = 0;
  int skippedParse = 0;

  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  warn: $path not found, skipping');
      continue;
    }
    final collection = path.replaceAll('assets/', '').replaceAll('.txt', '');
    final seen = <String>{};
    int kept = 0;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;

      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        skippedParse++;
        continue;
      }
      if (!seen.add(key)) continue; // dedup within file

      Puzzle puzzle;
      try {
        puzzle = Puzzle(line);
      } catch (_) {
        skippedParse++;
        continue;
      }

      final sol = puzzle.cachedSolution;
      if (sol == null || sol.length != puzzle.width * puzzle.height) {
        skippedNoSolution++;
        continue;
      }

      // A 2×2 square shape = exactly 4 occupied cells inside a 2×2 box.
      // Colour-agnostic: catches both `SH:11.11` (black) and `SH:22.22`.
      final isSh2x2 = puzzle.constraints.any(
        (c) => c is ShapeConstraint && c.shapeSize == 4 && c.motifGridSize == 4,
      );

      // Identity modulo prefill: same dims + domain + constraints + solution
      // ⇒ same puzzle, only the givens differ.
      final constraintSig =
          (puzzle.constraints.map((c) => c.serialize()).toList()..sort()).join(
            ';',
          );
      final solStr = sol.map(cellValueToString).join();
      final identityKey =
          '${puzzle.width}x${puzzle.height}|${puzzle.domain.length}'
          '|$constraintSig|$solStr';

      records.add(
        Record(
          collection: collection,
          canonicalKey: key,
          w: puzzle.width,
          h: puzzle.height,
          complexity: puzzle.cachedComplexity ?? -1,
          isSh2x2: isSh2x2,
          f: _features(sol, puzzle.width, puzzle.height),
          solution: sol,
          identityKey: identityKey,
        ),
      );
      kept++;
    }
    stderr.writeln('  $path: $kept puzzles');
  }

  stderr.writeln(
    '  total: ${records.length} puzzles '
    '($skippedNoSolution without stored solution, $skippedParse unparseable)',
  );

  if (dumpGrids) {
    _dumpGrids(records, dumpLimit);
  } else {
    _reportSignalValidity(records);
    _reportEasyByCollection(records);
    _reportSh2x2(records);
    _reportRedundancy(records);
    _reportWorstOffenders(records, top);
  }
  if (csvPath != null) _writeCsv(records, csvPath);
}

// ---------------------------------------------------------------------------
// Feature extraction (all on the solved row-major grid).
// ---------------------------------------------------------------------------

Features _features(List<CellValue> g, int w, int h) {
  return Features(
    checkerBlockK(g, w, h),
    periodX(g, w, h),
    periodY(g, w, h),
    countSymmetries(g, w, h),
    rleRatio(g, w, h),
  );
}

// ---------------------------------------------------------------------------
// Reports.
// ---------------------------------------------------------------------------

/// Which regularity signal actually predicts "easy"? Mean complexity per
/// signal category, corpus-wide and on the hard tiers. The decisive table:
/// only `checker` should land below the base complexity.
void _reportSignalValidity(List<Record> records) {
  stdout.writeln(
    '\n=== 1. Solver complexity by signal (descriptive) ===\n'
    '  NB: cplx is the AUDITED quantity. A confirmed shortcut with HIGH cplx '
    'is over-classified — that is the bug, not a disqualifier.',
  );
  stdout.writeln(
    '  ${'signal'.padRight(11)}${'n'.padLeft(7)}${'cplx'.padLeft(8)}'
    '${'n(hard)'.padLeft(9)}${'cplx(hard)'.padLeft(12)}',
  );
  final hard = records.where((r) => r.isHardTier).toList();
  stdout.writeln(
    '  ${'BASE(all)'.padRight(11)}${records.length.toString().padLeft(7)}'
    '${_meanCplx(records).padLeft(8)}${hard.length.toString().padLeft(9)}'
    '${_meanCplx(hard).padLeft(12)}',
  );
  for (final sig in _signalOrder) {
    final rs = records.where((r) => r.signal == sig).toList();
    final rsHard = rs.where((r) => r.isHardTier).toList();
    stdout.writeln(
      '  ${sig.padRight(11)}${rs.length.toString().padLeft(7)}'
      '${_meanCplx(rs).padLeft(8)}${rsHard.length.toString().padLeft(9)}'
      '${_meanCplx(rsHard).padLeft(12)}',
    );
  }
}

/// The over-classification, by assigned level: how many easy patterns
/// (checker ∪ stripes) sit in each collection and at what complexity vs the
/// collection mean. The hard tiers are where the bug lives.
void _reportEasyByCollection(List<Record> records) {
  final byCol = <String, List<Record>>{};
  for (final r in records) {
    byCol.putIfAbsent(r.collection, () => []).add(r);
  }
  stdout.writeln(
    '\n=== 2. Easy patterns (checker ∪ stripes) by assigned level ===',
  );
  stdout.writeln(
    '  ${'collection'.padRight(22)}${'n_ck'.padLeft(6)}${'n_str'.padLeft(7)}'
    '${'%easy'.padLeft(8)}${'cplx(easy)'.padLeft(12)}${'cplx(col)'.padLeft(11)}',
  );
  for (final col in _collectionOrder()) {
    final rs = byCol[col];
    if (rs == null || rs.isEmpty) continue;
    final ck = rs.where((r) => r.isCheckerboard).length;
    final str = rs.where((r) => r.isStripes).length;
    final easy = rs.where((r) => r.isEasyPattern).toList();
    stdout.writeln(
      '  ${col.padRight(22)}${ck.toString().padLeft(6)}'
      '${str.toString().padLeft(7)}${_pct(easy.length, rs.length).padLeft(8)}'
      '${_meanCplx(easy).padLeft(12)}${_meanCplx(rs).padLeft(11)}',
    );
  }
}

/// SH-2×2 even-dims family: how it splits across the signal categories — most
/// are NOT checkerboards (SH:11.11 only constrains one colour).
void _reportSh2x2(List<Record> records) {
  final sh = records.where((r) => r.isSh2x2 && r.evenDims).toList();
  stdout.writeln('\n=== 3. SH 2×2 square, even dims: signal breakdown ===');
  stdout.writeln('  total SH-2×2 even-dims puzzles: ${sh.length}');
  for (final sig in _signalOrder) {
    final rs = sh.where((r) => r.signal == sig).toList();
    if (rs.isEmpty) continue;
    stdout.writeln(
      '  ${sig.padRight(11)} ${rs.length.toString().padLeft(4)}'
      '  (${_pct(rs.length, sh.length)})  mean cplx ${_meanCplx(rs)}',
    );
  }
  final easy = sh.where((r) => r.isEasyPattern).length;
  final easyHard = sh.where((r) => r.isEasyPattern && r.isHardTier).length;
  stdout.writeln(
    '  → $easy easy-pattern (checker/stripes); $easyHard in 4-strong/5-expert/6-mad',
  );
}

/// Near-duplicate inflation: easy-pattern puzzles sharing the same identity
/// (dims+domain+constraints+solution) differ ONLY in their prefill — the same
/// puzzle served many times. Quantifies how much the corpus is padded by them.
void _reportRedundancy(List<Record> records) {
  final easy = records.where((r) => r.isEasyPattern).toList();
  final byIdentity = <String, List<Record>>{};
  for (final r in easy) {
    byIdentity.putIfAbsent(r.identityKey, () => []).add(r);
  }
  final groups = byIdentity.values.toList();
  final dupGroups = groups.where((g) => g.length > 1).toList();
  final redundantCopies = dupGroups.fold<int>(0, (a, g) => a + g.length - 1);
  int maxCopies = 0;
  for (final g in groups) {
    if (g.length > maxCopies) maxCopies = g.length;
  }

  stdout.writeln(
    '\n=== 4. Easy-pattern redundancy (same solution, different prefill) ===',
  );
  stdout.writeln('  easy-pattern puzzles      : ${easy.length}');
  stdout.writeln('  distinct identities       : ${groups.length}');
  stdout.writeln('  identities with >1 copy   : ${dupGroups.length}');
  stdout.writeln('  redundant copies (sum−1)  : $redundantCopies');
  stdout.writeln('  largest single family     : $maxCopies copies');

  dupGroups.sort((a, b) => b.length.compareTo(a.length));
  stdout.writeln('  top families (copies × identity):');
  for (final g in dupGroups.take(10)) {
    final cplxs = g.map((r) => r.complexity).toList()..sort();
    stdout.writeln(
      '    ${g.length.toString().padLeft(3)}×  '
      'cplx ${cplxs.first}..${cplxs.last}  ${g.first.identityKey}',
    );
  }
}

/// Easy patterns rated hardest — the genuinely mis-classified ones a human
/// would breeze through.
void _reportWorstOffenders(List<Record> records, int top) {
  final offenders =
      records.where((r) => r.isEasyPattern && r.complexity >= 0).toList()
        ..sort((a, b) => b.complexity.compareTo(a.complexity));

  stdout.writeln('\n=== 5. Worst offenders (easy pattern, high cplx) ===');
  stdout.writeln(
    '  ${'cplx'.padLeft(5)} ${'lvl'.padRight(14)}'
    '${'dims'.padRight(7)}${'signal'.padRight(9)}  canonical_key',
  );
  for (final r in offenders.take(top)) {
    stdout.writeln(
      '  ${r.complexity.toString().padLeft(5)} '
      '${r.collection.padRight(14)}'
      '${'${r.w}x${r.h}'.padRight(7)}'
      '${r.signal.padRight(9)}  '
      '${r.canonicalKey}',
    );
  }
}

/// Visual inspection aid: print the solved grids of non-checker SH-2×2
/// even-dims puzzles, grouped by signal category. Lets a human judge whether
/// any *near*-damiers (regular lattices of 2×2 squares) hide outside the
/// strict checkerboard predicate — `periodic` is the likeliest home for them.
void _dumpGrids(List<Record> records, int limit) {
  final sh = records
      .where((r) => r.isSh2x2 && r.evenDims && !r.isEasyPattern)
      .toList();
  stdout.writeln(
    '\n=== SH-2×2 even-dims, undecided grids (excl. checker/stripes) '
    '(# black, . white, + purple) ===',
  );
  // periodic first — the most likely hiding place for "lattice of squares".
  for (final sig in [
    _signalPeriodic,
    _signalSymmetric,
    _signalRleOnly,
    _signalNone,
  ]) {
    final group = sh.where((r) => r.signal == sig).toList()
      ..sort((a, b) => b.complexity.compareTo(a.complexity));
    if (group.isEmpty) continue;
    final shown = group.length < limit ? group.length : limit;
    stdout.writeln(
      '\n----- signal: $sig  (${group.length} puzzles, showing $shown) -----',
    );
    for (final r in group.take(limit)) {
      stdout.writeln(
        '\n[cplx=${r.complexity}  ${r.collection}  ${r.w}x${r.h}'
        '  pX=${r.f.periodX} pY=${r.f.periodY} sym=${r.f.nSymmetries}]'
        '  ${r.canonicalKey}',
      );
      for (int row = 0; row < r.h; row++) {
        final sb = StringBuffer('  ');
        for (int col = 0; col < r.w; col++) {
          sb.write(_glyph(r.solution[row * r.w + col]));
        }
        stdout.writeln(sb);
      }
    }
  }
}

String _glyph(CellValue v) => switch (v) {
  CellValue.black => '#',
  CellValue.white => '.',
  CellValue.purple => '+',
  CellValue.free => ' ',
};

void _writeCsv(List<Record> records, String path) {
  final out = File(path).openWrite();
  out.writeln(
    'collection,canonical_key,width,height,complexity,is_sh2x2,'
    'checker_k,period_x,period_y,n_symmetries,rle_ratio,signal',
  );
  for (final r in records) {
    out.writeln(
      '${r.collection},${r.canonicalKey},${r.w},${r.h},${r.complexity},'
      '${r.isSh2x2 ? 1 : 0},${r.f.checkerK},${r.f.periodX},${r.f.periodY},'
      '${r.f.nSymmetries},${r.f.rleRatio.toStringAsFixed(4)},${r.signal}',
    );
  }
  out.flush().then((_) => out.close());
  stderr.writeln('Wrote $path');
}

List<String> _collectionOrder() => _collections
    .map((p) => p.replaceAll('assets/', '').replaceAll('.txt', ''))
    .toList();

String _pct(int num, int den) =>
    den == 0 ? '-' : '${(100 * num / den).toStringAsFixed(1)}%';

String _meanCplx(List<Record> rs) {
  final withCplx = rs.where((r) => r.complexity >= 0).toList();
  if (withCplx.isEmpty) return '-';
  final mean =
      withCplx.map((r) => r.complexity).reduce((a, b) => a + b) /
      withCplx.length;
  return mean.toStringAsFixed(1);
}
