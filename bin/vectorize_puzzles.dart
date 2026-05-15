// Vectorize every puzzle from the playable collections into a CSV row.
//
// The vector captures what makes two puzzles *feel* similar to a player:
// the mix of constraint families used by the trace, weighted by their
// per-move complexity tier (so a puzzle solved by trivial-FM is a
// different vector from one solved by 2×2-FM, even though both share
// the slug `FM`).
//
// Identity / static block (cheap, from the line):
//   file, canonical_key, width, height, cells, domain_size,
//   prefill_ratio, n_constraints, n_distinct_types
//
// Cached metadata block (cheap):
//   complexity (cached cplx 0-100), level (0..7 from classifyTrace)
//
// Trace summary block (one solveExplained() per puzzle, ~20-50ms):
//   n_prop_moves, n_force_rounds, max_force_depth, n_total_steps,
//   distinct_constraints_used, max_cascade, avg_move_complexity
//
// Trace shares block — the heart of the "feeling" signal:
//   share_<slug>_t<tier> for slug in {FM,PA,GS,LT,QA,SY,DF,SH,CC,GC,NC,EY,CX}
//   and tier in {0..5}. Cells = #prop_moves attributed to (slug, tier)
//   divided by #total_prop_moves. CX = complicity (multi-constraint
//   deduction). Most cells are 0 — vector is wide but sparse.
//
// Usage:
//   dart run bin/vectorize_puzzles.dart [--output PATH] [--sample N]
//                                        [--timeout-ms MS] [--verbose]
//
// Default output path: `puzzle_vectors.csv` at repo root.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

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

// Stable, alphabetical slug list — defines the CSV column order so two
// runs of the script produce diff-able files. `CX` is the synthetic
// slug used for complicity moves (multi-constraint deductions).
const _slugs = [
  'CC',
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

// Move complexity tiers (`Move.complexity`, 0..5). See
// docs/dev/complexity.md for the per-tier semantics. We allocate one
// share column per (slug, tier) pair.
const _tiers = [0, 1, 2, 3, 4, 5];

// Ordinal index of each PuzzleLevel — used as a numeric `level` feature
// in the vector. Out-of-cascade buckets are placed past `mad` so they
// don't get clustered with mid-tier puzzles by accident.
const Map<PuzzleLevel, int> _levelOrdinal = {
  PuzzleLevel.beginner: 0,
  PuzzleLevel.player: 1,
  PuzzleLevel.advanced: 2,
  PuzzleLevel.strong: 3,
  PuzzleLevel.expert: 4,
  PuzzleLevel.mad: 5,
  PuzzleLevel.overfilledEasy: 6,
  PuzzleLevel.overfilled: 7,
  PuzzleLevel.undetermined: 8,
};

void main(List<String> args) {
  String outputPath = 'puzzle_vectors.csv';
  int? sample;
  int timeoutMs = 15000;
  bool verbose = false;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--output':
      case '-o':
        outputPath = args[++i];
      case '--sample':
        sample = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '-v':
      case '--verbose':
        verbose = true;
      case '-h':
      case '--help':
        stderr.writeln('''
Usage: dart run bin/vectorize_puzzles.dart [options]

Options:
  -o, --output PATH    Output CSV path (default: puzzle_vectors.csv)
  --sample N           Process only first N puzzles (dev aid)
  --timeout-ms MS      Solver timeout per puzzle (default: 15000)
  -v, --verbose        Per-puzzle progress lines on failure
  -h, --help           Show this help
''');
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  // Collect (file, line) pairs across all collections, dedup by
  // canonical key. We want one vector per *puzzle identity*, not per
  // copy — a same canonical puzzle living in two files would otherwise
  // produce two rows and skew clustering distance.
  stderr.writeln('Loading collections...');
  final entries = <_Entry>[];
  final seen = <String>{};
  for (final path in _collections) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  warn: $path not found, skipping');
      continue;
    }
    int kept = 0;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        continue;
      }
      if (!seen.add(key)) continue;
      entries.add(_Entry(path, key, line));
      kept++;
    }
    stderr.writeln('  $path: $kept unique puzzles');
  }
  stderr.writeln('  total: ${entries.length} unique puzzles');

  if (sample != null && sample < entries.length) {
    entries.length = sample;
    stderr.writeln('Sampling first $sample puzzles');
  }

  // Open the output file and write the header row first so a Ctrl-C
  // mid-run still produces a valid (truncated) CSV.
  final out = File(outputPath).openWrite();
  out.writeln(_csvHeader());

  int processed = 0;
  int errors = 0;
  int unsolved = 0;
  final sw = Stopwatch()..start();

  for (final entry in entries) {
    try {
      final vec = _vectorize(entry, timeoutMs: timeoutMs);
      if (vec == null) {
        unsolved++;
        if (verbose) stderr.writeln('  unsolved: ${entry.canonicalKey}');
      } else {
        out.writeln(_csvRow(vec));
      }
    } catch (e) {
      errors++;
      if (verbose) stderr.writeln('  error on ${entry.canonicalKey}: $e');
    }
    processed++;
    if (processed % 200 == 0) {
      final pct = (processed / entries.length * 100).toStringAsFixed(1);
      stderr.write(
        '\r  $processed/${entries.length} ($pct%) — '
        '$errors errors, $unsolved unsolved   ',
      );
    }
  }
  stderr.writeln(
    '\r  done in ${sw.elapsed.inSeconds}s: '
    '$processed processed, $errors errors, $unsolved unsolved      ',
  );

  out.flush().then((_) => out.close());
  stderr.writeln('Wrote $outputPath');
}

class _Entry {
  final String file;
  final String canonicalKey;
  final String line;
  _Entry(this.file, this.canonicalKey, this.line);
}

class _Vector {
  final _Entry entry;
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
  // (slug, tier) -> share. Stored as a flat map so the CSV writer can
  // iterate `_slugs × _tiers` in fixed column order.
  final Map<String, double> shares;

  _Vector({
    required this.entry,
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
    required this.shares,
  });
}

/// Build a [_Vector] for one puzzle, or null if the puzzle can't be
/// solved by propagation+force (it needs backtracking — out of scope).
_Vector? _vectorize(_Entry entry, {required int timeoutMs}) {
  final puzzle = Puzzle(entry.line);

  // Static fields.
  final width = puzzle.width;
  final height = puzzle.height;
  final domainSize = puzzle.domain.length;
  final readonly = puzzle.cells.where((c) => c.readonly).length;
  final prefillRatio = puzzle.cells.isEmpty
      ? 0.0
      : readonly / puzzle.cells.length;
  final nConstraints = puzzle.constraints.length;
  final distinctTypes = <Type>{};
  for (final c in puzzle.constraints) {
    distinctTypes.add(c.runtimeType);
  }
  // The Puzzle constructor loads `cachedComplexity` from the v2 line's
  // field [6], so reading the cache is enough — no need to re-solve.
  final storedCplx = puzzle.cachedComplexity ?? -1;

  // Trace.
  final steps = puzzle.solveExplained(timeoutMs: timeoutMs);

  // Tally per-(slug, tier) counts. Use the synthetic `CX` slug for
  // complicity steps — the `step.constraint` they carry is the slug of
  // the *first* constraint in the complicity, which would otherwise
  // double-count under e.g. `FM`. Force steps don't get a slug share
  // (they're surfaced through `nForceRounds` / `maxForceDepth`).
  final counts = <String, Map<int, int>>{};
  for (final s in _slugs) {
    counts[s] = {for (final t in _tiers) t: 0};
  }
  int nProp = 0;
  int nForce = 0;
  int maxForceDepth = 0;
  int maxCascade = 0;
  int cascade = 0;
  String? prev;
  int complexitySum = 0;
  final distinctInTrace = <String>{};

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
    final tier = step.complexity.clamp(0, _tiers.last);
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

  // Replay the trace to confirm the puzzle is actually solved by it —
  // matches the discipline in `classifyPuzzle`. An unsolved trace means
  // the solver gave up (timeout or backtracking-only puzzle), and we'd
  // be vectorizing partial information.
  final replay = puzzle.clone();
  for (final s in steps) {
    replay.setValue(s.cellIdx, s.value);
  }
  final solved = replay.complete && replay.check(saveResult: false).isEmpty;
  if (!solved) return null;

  final level = classifyTrace(
    steps: steps,
    prefillRatio: prefillRatio,
    solved: true,
  );

  // Convert counts to shares. Guard nProp == 0 (a pre-solved puzzle
  // would have an empty trace, vector dominated by 0s — still emit so
  // downstream tools see it).
  final shares = <String, double>{};
  for (final s in _slugs) {
    for (final t in _tiers) {
      final c = counts[s]?[t] ?? 0;
      shares['${s}_t$t'] = nProp > 0 ? c / nProp : 0.0;
    }
  }

  return _Vector(
    entry: entry,
    width: width,
    height: height,
    domainSize: domainSize,
    prefillRatio: prefillRatio,
    nConstraints: nConstraints,
    nDistinctTypes: distinctTypes.length,
    complexity: storedCplx,
    level: _levelOrdinal[level] ?? 8,
    nPropMoves: nProp,
    nForceRounds: nForce,
    maxForceDepth: maxForceDepth,
    nTotalSteps: nProp + nForce,
    distinctConstraintsUsed: distinctInTrace.length,
    maxCascade: maxCascade,
    avgMoveComplexity: nProp > 0 ? complexitySum / nProp : 0.0,
    shares: shares,
  );
}

/// Extract the slug prefix of a constraint serialization, e.g.
/// `"FM:11"` → `"FM"`. Returns `"??"` for unparseable strings so we
/// don't silently lose them; that bucket can be tracked in QA later.
String _slugOf(String serialized) {
  final i = serialized.indexOf(':');
  if (i < 0) return serialized.isEmpty ? '??' : serialized;
  return serialized.substring(0, i);
}

String _csvHeader() {
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
  ];
  for (final s in _slugs) {
    for (final t in _tiers) {
      cols.add('share_${s}_t$t');
    }
  }
  return cols.join(',');
}

String _csvRow(_Vector v) {
  final cells = v.width * v.height;
  final cols = <String>[
    _csvField(v.entry.file),
    _csvField(v.entry.canonicalKey),
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
  ];
  for (final s in _slugs) {
    for (final t in _tiers) {
      cols.add(v.shares['${s}_t$t']!.toStringAsFixed(4));
    }
  }
  return cols.join(',');
}

/// Minimal CSV escaper: quote when the field contains `,`, `"`, or
/// newline; double up internal quotes. Canonical keys don't carry
/// commas (their separators are `_` and `;`) but the file path or any
/// future identity-key tweak might, so escape defensively.
String _csvField(String s) {
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
