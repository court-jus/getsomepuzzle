/// One-pass corpus assimilation: validate + route + vectorize with a
/// SINGLE `solveExplained()` per puzzle.
///
/// Replaces the three-pass pipeline (`generate --check` → 1 solve,
/// `recompute` → 2 solves, `vectorize_puzzles` → 1 cached-or-real solve)
/// with one solve whose trace feeds every consumer:
///
///   * validity   — no conflicting constraints + the trace replays to a
///                  complete, constraint-consistent grid (same criterion
///                  as `isDeductivelyUnique`, since `solveExplained` uses
///                  propagation+force only, never backtracking);
///   * routing    — `classifyTrace` on that trace → `levelFilenames`,
///                  including the off-cascade `overfilled*` buckets
///                  (prefill > 30 %) and `undetermined`;
///   * metadata   — `computeComplexityFromSteps` refreshes the cached
///                  `_1:` solution and `_cplx` field on the emitted line;
///   * vector     — `computePuzzleVector` on the same trace + solved grid,
///                  written to a `puzzle_vectors.csv` compatible with
///                  `cluster_puzzles.dart`;
///   * cache      — when the stored constraint order is already
///                  difficulty-sorted (the corpus convention), the trace
///                  is stored in `solve_traces.tsv` under the post-sort
///                  hash, so later `recompute`/`vectorize` runs on these
///                  lines are pure cache hits.
///
/// Caveats vs the two-solve `recompute` path:
///   * classification/vector use the *stored-order* trace. For lines
///     already difficulty-sorted this IS the post-sort trace. Lines whose
///     stored order differs from what `sortConstraintsByDifficulty` would
///     produce are counted as "order drift" and listed in
///     `<out-dir>/order-drift.txt`; their metadata keeps the stored order
///     (honest) but a later `recompute` pass may re-classify them.
///   * NEEDS-BACKTRACK vs UNSOLVABLE vs NON-UNIQUE are not distinguished —
///     that needs exhaustive backtracking (`--check-detailed`). Everything
///     not solved deductively lands in `invalid.txt`.
///
/// Nothing is ever written into `assets/`: routed lines go to
/// `<out-dir>/<collection>.txt` (same filenames), ready to be appended to
/// the live corpus once the generator has finished its run.
library;

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/vector.dart';

import '_trace_cache.dart';

Future<void> main(List<String> args) async {
  final inputs = <String>[];
  var outDir = 'assimilated';
  var vectorsOut = '';
  int? sample;
  var timeoutMs = 15000;
  var dryRun = false;
  var useCache = true;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      case '--in':
        inputs.add(args[++i]);
      case '--out-dir':
        outDir = args[++i];
      case '--vectors-out':
        vectorsOut = args[++i];
      case '--sample':
        sample = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '--no-cache':
        // Don't read or write solve_traces.tsv.
        useCache = false;
      case '--dry-run':
        dryRun = true;
      default:
        stderr.writeln('Error: unknown option $a (use --help).');
        exit(2);
    }
  }
  if (inputs.isEmpty) {
    stderr.writeln('Error: at least one --in PATH is required.');
    exit(2);
  }
  if (vectorsOut.isEmpty) vectorsOut = '$outDir/puzzle_vectors.csv';

  final files = <String>[];
  for (final p in inputs) {
    final entity = FileSystemEntity.typeSync(p);
    if (entity == FileSystemEntityType.directory) {
      files.addAll(
        Directory(p)
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((f) => f.endsWith('.txt')),
      );
    } else if (entity == FileSystemEntityType.file) {
      files.add(p);
    } else {
      stderr.writeln('warn: $p not found, skipping');
    }
  }
  files.sort();

  final cache = useCache ? TraceCache.load(kTraceCachePath) : null;
  final outDirHandle = Directory(outDir);
  if (!dryRun && !outDirHandle.existsSync()) {
    outDirHandle.createSync(recursive: true);
  }

  // ─── Idempotence: preload canonical keys already sitting in out-dir ──
  final seenKeys = <String>{};
  for (final f in Directory(outDir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.txt')) continue;
    if (f.path.endsWith('order-drift.txt')) continue;
    // invalid.txt counts too: rejected puzzles must not be re-solved on
    // every restart. Its `# INVALID (reason)` comment lines are filtered
    // by the startsWith('#') check below.
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      try {
        seenKeys.add(canonicalPuzzleKey(t));
      } catch (_) {}
    }
  }

  // ─── Sinks ───────────────────────────────────────────────────────────
  final sinks = <String, IOSink>{};
  IOSink sinkFor(String path) => sinks.putIfAbsent(path, () {
    final f = File(path);
    final isNew = !f.existsSync() || f.lengthSync() == 0;
    final s = f.openWrite(mode: FileMode.append);
    if (isNew && path.endsWith('puzzle_vectors.csv')) {
      s.writeln(vectorCsvHeader());
    }
    return s;
  });

  // ─── Stats ───────────────────────────────────────────────────────────
  final destCounts = <String, int>{};
  final invalidReasons = <String, int>{};
  var validCount = 0;
  var invalidCount = 0;
  var cacheHits = 0;
  var orderDrift = 0;
  var skippedKnown = 0;
  var processed = 0;
  final sw = Stopwatch()..start();

  void countInvalid(String reason, String line) {
    invalidCount++;
    invalidReasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
    if (!dryRun) {
      sinkFor('$outDir/invalid.txt').writeln('# INVALID ($reason)\n$line');
    }
  }

  for (final path in files) {
    var doneInFile = 0;
    for (final raw in File(path).readAsLinesSync()) {
      if (sample != null && doneInFile >= sample) break;
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      String sourceKey;
      try {
        sourceKey = canonicalPuzzleKey(line);
      } catch (_) {
        sourceKey = '';
      }
      if (sourceKey.isNotEmpty && seenKeys.contains(sourceKey)) {
        skippedKnown++;
        continue;
      }

      processed++;
      doneInFile++;
      try {
        final fields = line.split('_');
        if (fields.length < 7) {
          countInvalid('malformed', line);
          continue;
        }
        fields[4] = _dedupKeepOrder(fields[4]);
        final pu = Puzzle(fields.join('_'));

        // Conflict pre-check, same as `generate --check`.
        var conflicted = false;
        for (var ai = 0; ai < pu.constraints.length && !conflicted; ai++) {
          for (
            var bi = ai + 1;
            bi < pu.constraints.length && !conflicted;
            bi++
          ) {
            if (pu.constraints[ai].conflictsWith(pu.constraints[bi]) ||
                pu.constraints[bi].conflictsWith(pu.constraints[ai])) {
              conflicted = true;
            }
          }
        }
        if (conflicted) {
          countInvalid('conflict', line);
          continue;
        }

        // ── THE single solve ──
        // The stored order is presumed difficulty-sorted (corpus
        // convention), so a hash lookup under that presumption matches
        // what recompute would do with the same line.
        final preSortHash = traceKeyFromPuzzle(pu);
        var steps = cache?.lookup(preSortHash);
        if (steps != null) cacheHits++;
        steps ??= pu.solveExplained(timeoutMs: timeoutMs);

        // Replay to validate + get the solved grid.
        final replay = pu.clone();
        for (final s in steps) {
          if (s.value != null) {
            replay.setValue(s.cellIdx, s.value!);
          } else if (s.removeOption != null) {
            replay.removeOption(s.cellIdx, s.removeOption!);
          }
        }
        final solved =
            replay.complete && replay.check(saveResult: false).isEmpty;
        if (!solved) {
          countInvalid('notDeductivelySolvable', line);
          continue;
        }

        // Order-drift probe: would sortConstraintsByDifficulty change
        // the stored order?
        final before = pu.constraints.map((c) => c.serialize()).join(';');
        pu.sortConstraintsByDifficulty(steps);
        final after = pu.constraints.map((c) => c.serialize()).join(';');
        if (before != after) {
          orderDrift++;
          if (!dryRun) {
            sinkFor('$outDir/order-drift.txt').writeln('# $path\n$line');
          }
        } else {
          // Stored order confirmed difficulty-sorted: this trace IS the
          // post-sort trace — publish it so recompute/vectorize hit.
          cache?.update(preSortHash, sourceKey, steps);
        }

        // Refresh metadata from the one trace.
        pu.computeComplexityFromSteps(steps);
        final sol = pu.cachedSolution;
        fields[5] = sol != null
            ? '1:${sol.map(cellValueToString).join('')}'
            : '0:0';
        fields[6] = '${pu.cachedComplexity}';
        final outLine = fields.join('_');
        try {
          seenKeys.add(canonicalPuzzleKey(outLine));
        } catch (_) {}
        if (sourceKey.isNotEmpty) seenKeys.add(sourceKey);

        // Route by today's cascade (overfilled buckets included).
        final prefillRatio =
            pu.cells.where((c) => c.readonly).length / pu.cells.length;
        final level = classifyTrace(
          steps: steps,
          prefillRatio: prefillRatio,
          solved: true,
        );
        final destName = levelFilenames[level];
        if (destName == null) {
          countInvalid('noDestination:${level.name}', line);
          continue;
        }
        destCounts.update(destName, (n) => n + 1, ifAbsent: () => 1);
        validCount++;

        // Vectorize from the same trace + solved grid.
        final vec = computePuzzleVector(pu: pu, steps: steps, replay: replay);
        if (!dryRun) {
          sinkFor('$outDir/$destName').writeln(outLine);
          sinkFor(vectorsOut).writeln(
            [
              'assets/$destName',
              vectorCsvField(sourceKey),
              ...vectorCsvFields(vec),
            ].join(','),
          );
        }
      } catch (e) {
        countInvalid('error:$e', line);
      }
      if (processed % 500 == 0) {
        stderr.writeln(
          '[${sw.elapsed}] $processed processed '
          '(valid $validCount, invalid $invalidCount, '
          'cache hits $cacheHits, drift $orderDrift)',
        );
      }
      // Periodic checkpoint: bound the work an interrupt can lose to one
      // window. Flushing makes the canonical-key resume set cover every
      // puzzle solved so far; saving the trace cache makes the solves
      // themselves reusable even for lines not yet emitted.
      if (!dryRun && processed % 5000 == 0) {
        await Future.wait(sinks.values.map((s) => s.flush()));
        cache?.save(kTraceCachePath);
      }
    }
  }

  await Future.wait(sinks.values.map((s) => s.flush()));
  for (final s in sinks.values) {
    await s.close();
  }
  cache?.save(kTraceCachePath);

  // ─── Report ──────────────────────────────────────────────────────────
  stderr.writeln('');
  stderr.writeln('== Assimilation summary (${sw.elapsed}) ==');
  stderr.writeln('Input files: ${files.length}');
  stderr.writeln(
    'Processed: $processed — valid $validCount, invalid $invalidCount',
  );
  stderr.writeln('Skipped (already in out-dir): $skippedKnown');
  stderr.writeln('Trace-cache hits: $cacheHits');
  stderr.writeln(
    'Constraint-order drift: $orderDrift '
    '(listed in $outDir/order-drift.txt)',
  );
  if (invalidReasons.isNotEmpty) {
    stderr.writeln('Invalid breakdown:');
    final entries = invalidReasons.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries) {
      stderr.writeln('  ${e.value}\t${e.key}');
    }
  }
  stderr.writeln('Routing:');
  final dests = destCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in dests) {
    stderr.writeln('  ${e.value.toString().padLeft(7)}  ${e.key}');
  }
  stderr.writeln('Output dir: $outDir');
  stderr.writeln('Vectors: $vectorsOut');
}

/// Order-preserving dedup of the constraints field: drops exact
/// duplicates and TX markers but keeps the stored order, which the
/// corpus convention keeps difficulty-sorted (easier-first). Unlike
/// [dedupAndSortConstraints] — whose lexicographic sort scrambles that
/// order and would make every line look order-drifted — this lets the
/// drift probe measure the *stored* order against the current sort.
String _dedupKeepOrder(String field) {
  final seen = <String>{};
  final kept = <String>[];
  for (final c in field.split(';')) {
    if (c.startsWith('TX:') || c == 'TX') continue;
    if (seen.add(c)) kept.add(c);
  }
  return kept.join(';');
}

void _printUsage() {
  stderr.writeln('''
Usage: dart run bin/assimilate.dart --in PATH [--in PATH …] [options]

One solve per puzzle: validates (deductive propagation+force), routes
into the collection matching classifyTrace (overfilled* included),
refreshes cached solution/cplx, emits the feature-vector CSV row, and
publishes the trace to solve_traces.tsv when the stored constraint
order is confirmed difficulty-sorted.

Inputs may be files or directories (.txt files inside are used).
Nothing is written to assets/ — outputs land in --out-dir using the
standard collection filenames, ready to be merged later.

Options:
  --in PATH         Input file or directory. Repeatable.
  --out-dir DIR     Output directory (default: assimilated)
  --vectors-out P   Vector CSV path (default: <out-dir>/puzzle_vectors.csv)
  --sample N        Process only the first N puzzles per input file,
                    counting only puzzles that pass the
                    already-assimilated filter (re-runs continue where
                    the previous run stopped rather than re-verifying).
  --timeout-ms MS   Solver timeout per puzzle (default: 15000).
  --no-cache        Don't read or write solve_traces.tsv.
  --dry-run         Compute everything, write nothing (cache still saved
                    unless --no-cache).
  -h, --help        This message.
''');
}
