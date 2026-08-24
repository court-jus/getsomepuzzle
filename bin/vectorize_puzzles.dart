// Vectorize every puzzle from the playable collections into a CSV row.
//
// Thin batch driver over the shared vector logic in
// `lib/getsomepuzzle/vector.dart`: it loads the corpus, resolves each
// puzzle's (post-sort) solving trace (via the `solve_traces.tsv` cache or a
// fresh solve), verifies it completes deductively, and writes one row per
// puzzle to `puzzle_vectors.csv`.
//
// The same `computePuzzleVector` is used by the generator for inline
// emission during generation, so batch vectors and freshly-generated vectors
// are produced by exactly the same code (see
// `docs/dev/collection_management.md`).
//
// Identity / static block (cheap, from the line):
//   file, canonical_key, width, height, cells, domain_size,
//   prefill_ratio, n_constraints, n_distinct_types
//
// Cached metadata block (cheap):
//   complexity (cached cplx, unbounded — see docs/dev/complexity.md),
//   level (0..7 from classifyTrace)
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
// Solution geometry block — translation- and colour-swap-invariant
// descriptors of the solved grid (the black mask, ±1). See
// `lib/getsomepuzzle/solution_geometry.dart`.
//
// Usage:
//   dart run bin/vectorize_puzzles.dart [--output PATH] [--sample N]
//                                        [--timeout-ms MS] [--verbose]
//
// Default output path: `puzzle_vectors.csv` at repo root.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/vector.dart';

import '_trace_cache.dart';

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

  // Collect (file, line) pairs across all collections, dedup by canonical
  // key. One vector per *puzzle identity*, not per copy — a same canonical
  // puzzle living in two files would otherwise produce two rows and skew
  // clustering distance.
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

  // Open the output file and write the header row first so a Ctrl-C mid-run
  // still produces a valid (truncated) CSV.
  final out = File(outputPath).openWrite();
  out.writeln(vectorCsvHeader());

  final cache = TraceCache.load(kTraceCachePath);
  if (cache.isEmpty) {
    stderr.writeln(
      '  warn: no solve_traces.tsv found — run bin/recompute.dart first '
      'to populate the cache and speed up vectorization.',
    );
  } else {
    stderr.writeln('  Trace cache loaded: ${cache.size} entries');
  }

  int processed = 0;
  int errors = 0;
  int unsolved = 0;
  int cacheHits = 0;
  final sw = Stopwatch()..start();

  for (final entry in entries) {
    try {
      final traceKey = traceKeyFromLine(entry.line);
      final cachedSteps = cache.lookup(traceKey);
      if (cachedSteps != null) cacheHits++;
      final vec = _vectorize(
        entry,
        timeoutMs: timeoutMs,
        cachedSteps: cachedSteps,
      );
      if (vec == null) {
        unsolved++;
        if (verbose) stderr.writeln('  unsolved: ${entry.canonicalKey}');
      } else {
        // Full row = [file, canonical_key] + the vector's remaining fields.
        final row = [
          vectorCsvField(entry.file),
          vectorCsvField(entry.canonicalKey),
          ...vectorCsvFields(vec),
        ].join(',');
        out.writeln(row);
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
    '$processed processed, $cacheHits cache hits, $errors errors, $unsolved unsolved      ',
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

/// Build the vector for one puzzle, or null if the puzzle can't be solved by
/// propagation+force (it needs backtracking — out of scope).
///
/// [cachedSteps] — pre-computed trace from [TraceCache]. When non-null,
/// `puzzle.solveExplained()` is skipped entirely. The solved grid is derived
/// by replaying the (post-sort) trace and verifying completeness, exactly as
/// the generator's `_finalize` does.
PuzzleVector? _vectorize(
  _Entry entry, {
  required int timeoutMs,
  List<SolveStep>? cachedSteps,
}) {
  final puzzle = Puzzle(entry.line);

  // Trace — use cached steps when available.
  final steps = cachedSteps ?? puzzle.solveExplained(timeoutMs: timeoutMs);

  // Replay the trace to confirm the puzzle is actually solved by it —
  // matches the discipline in `classifyPuzzle`. An unsolved trace means the
  // solver gave up (timeout or backtracking-only puzzle), and we'd be
  // vectorizing partial information.
  final replay = puzzle.clone();
  for (final s in steps) {
    if (s.value != null) {
      replay.setValue(s.cellIdx, s.value!);
    } else if (s.removeOption != null) {
      replay.removeOption(s.cellIdx, s.removeOption!);
    }
  }
  final solved = replay.complete && replay.check(saveResult: false).isEmpty;
  if (!solved) return null;

  return computePuzzleVector(pu: puzzle, steps: steps, replay: replay);
}
