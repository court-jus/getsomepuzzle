import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  final positional = <String>[];
  int? sample;
  bool dryRun = false;
  bool verbose = false;
  bool route = false;
  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--sample') {
      sample = int.parse(args[++i]);
    } else if (a == '--dry-run') {
      dryRun = true;
    } else if (a == '-v' || a == '--verbose') {
      verbose = true;
    } else if (a == '--route') {
      route = true;
    } else if (a == '-h' || a == '--help') {
      _printUsage();
      exit(0);
    } else {
      positional.add(a);
    }
  }

  if (route) {
    // --route operates on the full set of playable-level files by
    // default: redistribute every puzzle into the file matching its
    // post-sort classification. Positional args are unsupported here
    // — partial input sets would either lose puzzles (source not
    // covered) or grow destinations unboundedly across reruns.
    if (positional.isNotEmpty) {
      stderr.writeln(
        '--route ignores positional args; it operates on the six '
        'playable-level files: ${_playableLevelPaths.join(', ')}',
      );
    }
    _routeFiles(dryRun: dryRun, sample: sample, verbose: verbose);
    return;
  }

  if (positional.isEmpty) {
    _printUsage();
    exit(1);
  }

  for (final path in positional) {
    _processFile(path, sample: sample, dryRun: dryRun, verbose: verbose);
  }
}

const _playableLevelPaths = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
];

void _printUsage() {
  stderr.writeln('''
Usage: dart run bin/recompute.dart [options] <file1> [file2] ...

For each puzzle line: dedup constraints, re-parse, sort constraints
by real-trace min cplx (`Puzzle.sortConstraintsByDifficulty`),
re-compute the complexity score, and emit the result.

Options:
  --sample N    Process only the first N non-empty puzzles per file.
                Useful for diagnostic runs over large corpora.
  --dry-run     Do not write any output file; just report stats.
                Combined with --sample, gives a fast read on whether
                the sort / recent code changes shift cplx or
                classified level.
  --route       Redistribute every puzzle from the six playable-level
                files (assets/1-easy.txt … assets/6-mad.txt) into the
                file matching its post-sort classification. Out-of-
                cascade puzzles (overfilled, undetermined) go to their
                dedicated files. Writes to `<dest>.tmp` (append mode);
                **never modifies the source `.txt` files**. The user
                migrates manually with `mv <dest>.tmp <dest>` when
                satisfied. Re-runs are idempotent: puzzles already
                emitted to a `.tmp` (by `canonicalPuzzleKey`) are
                skipped, so an interrupted `--route` can be resumed
                by simply re-launching the command. Positional args
                are ignored in this mode.
  -v, --verbose Emit a per-puzzle diff line whenever the stored cplx,
                the pre-sort level, or the post-sort level changes.
  -h, --help    Show this help.

The summary always reports:
  - stored cplx vs recomputed cplx (count up / down / equal)
  - pre-sort level vs post-sort level (count flipped + transitions)
  - both level distributions
  - duplicate constraints removed
''');
}

void _processFile(
  String path, {
  int? sample,
  required bool dryRun,
  required bool verbose,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  final lines = file.readAsLinesSync();
  final output = <String>[];
  final sw = Stopwatch()..start();

  int processed = 0;
  int dedupedPuzzles = 0;
  int dedupedConstraints = 0;
  int cplxEqual = 0;
  int cplxUp = 0;
  int cplxDown = 0;
  int sumStoredCplx = 0;
  int sumRecomputedCplx = 0;
  int levelFlipped = 0;
  final transitions = <String, int>{};
  final preSortHist = <PuzzleLevel, int>{};
  final postSortHist = <PuzzleLevel, int>{};

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith('#')) {
      output.add(line);
      continue;
    }
    if (sample != null && processed >= sample) {
      // Keep remaining lines verbatim so the .new file (if written)
      // stays a faithful tail of the original.
      output.add(line);
      continue;
    }

    try {
      final fields = line.split('_');
      // v2 grammar guard: domain, dims, prefill, constraints,
      // solution, cplx (and optionally _p:<state>).
      if (fields.length < 7) {
        output.add(line);
        continue;
      }
      // Field 6 is the previously-stored cplx; we'll compare against
      // it after re-computing on the sorted constraint list.
      final storedCplx = int.tryParse(fields[6]) ?? -1;

      // Step 1 — dedup the constraint string. The lex sort the helper
      // does as a side effect is harmless intermediate state (the
      // in-memory sort below overwrites it).
      final dedupedConstraintsField = dedupAndSortConstraints(fields[4]);
      final removed =
          fields[4].split(';').length -
          dedupedConstraintsField.split(';').length;
      if (removed > 0) {
        dedupedPuzzles++;
        dedupedConstraints += removed;
      }
      fields[4] = dedupedConstraintsField;
      final puzzle = Puzzle(fields.join('_'));

      // Step 2 — pre-sort trace. We classify it now so we can later
      // attribute level changes specifically to the sort (vs to any
      // other codebase shift, which would already show up here vs the
      // file's expected level).
      final preSortSteps = puzzle.solveExplained();
      final prefillRatio =
          puzzle.cells.where((c) => c.readonly).length / puzzle.cells.length;
      final preSortLevel = classifyTrace(
        steps: preSortSteps,
        prefillRatio: prefillRatio,
        solved: true,
      );

      // Step 3 — sort (reusing the pre-sort trace as the signal) and
      // re-classify on the post-sort trace.
      puzzle.sortConstraintsByDifficulty(preSortSteps);
      final postSortSteps = puzzle.solveExplained();
      final postSortLevel = classifyTrace(
        steps: postSortSteps,
        prefillRatio: prefillRatio,
        solved: true,
      );

      // Step 4 — recompute the cplx score. Single internal solve.
      // `force: true` bypasses the cached value the Puzzle constructor
      // loaded from the line's field [6] — recompute's entire purpose
      // is to re-derive that value from scratch.
      puzzle.computeComplexity(force: true);
      final newCplx = puzzle.cachedComplexity ?? -1;

      processed++;
      preSortHist.update(preSortLevel, (v) => v + 1, ifAbsent: () => 1);
      postSortHist.update(postSortLevel, (v) => v + 1, ifAbsent: () => 1);
      sumStoredCplx += storedCplx;
      sumRecomputedCplx += newCplx;
      if (newCplx == storedCplx) {
        cplxEqual++;
      } else if (newCplx > storedCplx) {
        cplxUp++;
      } else {
        cplxDown++;
      }
      if (postSortLevel != preSortLevel) {
        levelFlipped++;
        final key = '${preSortLevel.name}→${postSortLevel.name}';
        transitions.update(key, (v) => v + 1, ifAbsent: () => 1);
      }

      if (verbose && (newCplx != storedCplx || postSortLevel != preSortLevel)) {
        stderr.writeln(
          '  line ${i + 1}: cplx $storedCplx→$newCplx, '
          'level ${preSortLevel.name}→${postSortLevel.name}',
        );
      }

      // Re-emit field 4 from the in-memory sorted list; refresh
      // fields 5/6 from the post-sort computation.
      fields[4] = puzzle.constraints.map((c) => c.serialize()).join(';');
      final sol = puzzle.cachedSolution;
      fields[5] = sol != null ? '1:${sol.join('')}' : '0:0';
      fields[6] = '$newCplx';
      output.add(fields.join('_'));

      if (processed % 100 == 0) {
        stderr.write('\r$path: $processed puzzles processed...');
      }
    } catch (e) {
      stderr.writeln('\nError on line ${i + 1}: $e');
      output.add(line);
    }
  }

  if (!dryRun) {
    final outPath = '$path.new';
    File(outPath).writeAsStringSync('${output.join('\n')}\n');
    stderr.writeln(
      '\r$path: $processed puzzles in ${sw.elapsed.inSeconds}s -> $outPath',
    );
  } else {
    stderr.writeln(
      '\r$path: $processed puzzles in ${sw.elapsed.inSeconds}s (dry-run)',
    );
  }

  if (processed > 0) {
    final avgStored = (sumStoredCplx / processed).toStringAsFixed(1);
    final avgNew = (sumRecomputedCplx / processed).toStringAsFixed(1);
    stderr.writeln(
      '  cplx: $cplxEqual unchanged, $cplxUp up, $cplxDown down '
      '(avg stored=$avgStored, recomputed=$avgNew)',
    );
    stderr.writeln('  pre-sort level: ${_fmtHistogram(preSortHist)}');
    stderr.writeln('  post-sort level: ${_fmtHistogram(postSortHist)}');
    if (levelFlipped > 0) {
      final transitionsStr =
          (transitions.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .map((e) => '${e.key} (${e.value})')
              .join(', ');
      stderr.writeln(
        '  level flipped by sort: $levelFlipped — $transitionsStr',
      );
    }
    if (dedupedPuzzles > 0) {
      stderr.writeln(
        '  dedup: $dedupedConstraints duplicate constraints across $dedupedPuzzles puzzles',
      );
    }
  }
}

String _fmtHistogram(Map<PuzzleLevel, int> hist) {
  if (hist.isEmpty) return '{}';
  // Print in cascade order (easiest → hardest, then out-of-cascade).
  const order = [
    PuzzleLevel.beginner,
    PuzzleLevel.player,
    PuzzleLevel.advanced,
    PuzzleLevel.strong,
    PuzzleLevel.expert,
    PuzzleLevel.mad,
    PuzzleLevel.overfilledEasy,
    PuzzleLevel.overfilled,
    PuzzleLevel.undetermined,
  ];
  final parts = <String>[];
  for (final l in order) {
    final c = hist[l];
    if (c != null && c > 0) parts.add('${l.name}=$c');
  }
  return '{${parts.join(', ')}}';
}

/// Route puzzles from the six playable-level files into the file
/// matching their post-sort classification. Off-cascade puzzles land
/// in their dedicated `overfilled*` / `undetermined` files.
///
/// Algorithm:
///   1. Read every line of every input file.
///   2. For each line: if it's blank/comment/parse-failure, keep it
///      *in the source file* (bucket `keepInPlace`); otherwise parse,
///      sort, classify, and bucket the re-emitted line under the
///      destination level.
///   3. After scanning all inputs, write each output path with
///      `keepInPlace[path] + routedHere[path]`. Source files where
///      every puzzle moved away end up containing just their original
///      comments/blanks.
///   4. Destinations not in [_playableLevelPaths] (overfilled, etc.)
///      get created from scratch — they have no `keepInPlace`.
///
/// Idempotency: a second `--route` run on the post-routing files
/// shouldn't move anything (modulo small numeric drift from the
/// classification cascade).
void _routeFiles({required bool dryRun, int? sample, required bool verbose}) {
  final sw = Stopwatch()..start();

  // ─── Pre-load: read all existing `.tmp` to build idempotence sets ──
  //
  // We treat the `.tmp` files as the single source of truth for
  // "already done". A puzzle whose `canonicalPuzzleKey` is already in
  // the loaded set is skipped — its sort + classify + recompute
  // happened on a previous run. Non-puzzle lines (blanks, comments,
  // parse-failures) are deduped by exact string content so we don't
  // re-append them on every rerun.
  //
  // Sources are NEVER read or modified here; only the `.tmp` files
  // are inspected.
  final existingCanonical = <String>{};
  final existingVerbatim = <String>{};
  int preloadedPuzzles = 0;
  int preloadedVerbatim = 0;
  for (final tmpPath in _allPossibleTmpPaths()) {
    final f = File(tmpPath);
    if (!f.existsSync()) continue;
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) {
        if (existingVerbatim.add(line)) preloadedVerbatim++;
        continue;
      }
      try {
        if (existingCanonical.add(canonicalPuzzleKey(line))) {
          preloadedPuzzles++;
        }
      } catch (_) {
        // Couldn't compute the key (malformed line). Treat as
        // verbatim so we don't re-add it next time.
        if (existingVerbatim.add(line)) preloadedVerbatim++;
      }
    }
  }
  if (preloadedPuzzles + preloadedVerbatim > 0) {
    stderr.writeln(
      'Loaded $preloadedPuzzles puzzles + $preloadedVerbatim verbatim '
      'lines from existing .tmp files. Resume mode active.',
    );
  }

  // ─── Sinks (append mode) ────────────────────────────────────────────
  //
  // Append so multiple runs accumulate without truncating prior work.
  // No commit / rename / cleanup at the end — the `.tmp` files stay
  // in place for the user to verify and migrate manually.
  final destFiles = <String, RandomAccessFile>{};
  final destStats = <String, _DestStats>{};
  final perFileStats = <String, _RouteStats>{};

  RandomAccessFile sinkFor(String destPath) {
    return destFiles.putIfAbsent(destPath, () {
      final tmp = File('$destPath.tmp');
      final dir = tmp.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      destStats[destPath] = _DestStats();
      return tmp.openSync(mode: FileMode.append);
    });
  }

  void emit(String destPath, String line, _DestStatsKind kind) {
    if (dryRun) {
      // Track stats but never touch disk in dry-run.
      destStats.putIfAbsent(destPath, _DestStats.new);
    } else {
      final raf = sinkFor(destPath);
      raf.writeStringSync('$line\n');
    }
    final s = destStats[destPath]!;
    switch (kind) {
      case _DestStatsKind.verbatim:
        s.verbatim++;
      case _DestStatsKind.stayed:
        s.stayed++;
      case _DestStatsKind.newcomer:
        s.newcomers++;
    }
  }

  int alreadyProcessed = 0;
  int newlyProcessed = 0;

  for (final srcPath in _playableLevelPaths) {
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) {
      stderr.writeln('warn: $srcPath not found, skipping');
      continue;
    }
    final fileSw = Stopwatch()..start();
    final stats = perFileStats.putIfAbsent(srcPath, _RouteStats.new);
    int processedThisFile = 0;

    for (final line in srcFile.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) {
        if (existingVerbatim.add(line)) {
          emit(srcPath, line, _DestStatsKind.verbatim);
        }
        continue;
      }
      if (sample != null && processedThisFile >= sample) {
        // Sample-bypass: skip entirely. We don't treat these as
        // "verbatim" (they're real puzzles we chose not to process);
        // they'll be picked up by a subsequent non-sample run via the
        // canonical-key idempotence check.
        continue;
      }

      // Idempotence check before any heavy work: compute the
      // canonical key on the *source* line and skip if already
      // present in a `.tmp`.
      String sourceKey;
      try {
        sourceKey = canonicalPuzzleKey(line);
      } catch (_) {
        sourceKey = '';
      }
      if (sourceKey.isNotEmpty && existingCanonical.contains(sourceKey)) {
        alreadyProcessed++;
        processedThisFile++;
        continue;
      }

      try {
        final fields = line.split('_');
        if (fields.length < 7) {
          if (existingVerbatim.add(line)) {
            emit(srcPath, line, _DestStatsKind.verbatim);
          }
          continue;
        }

        fields[4] = dedupAndSortConstraints(fields[4]);
        final puzzle = Puzzle(fields.join('_'));

        final preSortSteps = puzzle.solveExplained();
        final prefillRatio =
            puzzle.cells.where((c) => c.readonly).length / puzzle.cells.length;
        final preSortLevel = classifyTrace(
          steps: preSortSteps,
          prefillRatio: prefillRatio,
          solved: true,
        );

        puzzle.sortConstraintsByDifficulty(preSortSteps);
        final postSortSteps = puzzle.solveExplained();
        final postSortLevel = classifyTrace(
          steps: postSortSteps,
          prefillRatio: prefillRatio,
          solved: true,
        );

        puzzle.computeComplexity(force: true);

        fields[4] = puzzle.constraints.map((c) => c.serialize()).join(';');
        final sol = puzzle.cachedSolution;
        fields[5] = sol != null ? '1:${sol.join('')}' : '0:0';
        fields[6] = '${puzzle.cachedComplexity}';
        final outLine = fields.join('_');

        final destFilename = levelFilenames[postSortLevel];
        final destPath = destFilename != null
            ? 'assets/$destFilename'
            : srcPath;

        // Second check: in case sort + recompute produced a line
        // whose canonical key is now in the set (extremely rare but
        // safer than emitting a duplicate). We add the OUT key
        // unconditionally so any subsequent run sees this puzzle as
        // processed.
        try {
          existingCanonical.add(canonicalPuzzleKey(outLine));
        } catch (_) {}
        if (sourceKey.isNotEmpty) existingCanonical.add(sourceKey);

        if (destPath == srcPath) {
          emit(destPath, outLine, _DestStatsKind.stayed);
          stats.kept++;
        } else {
          emit(destPath, outLine, _DestStatsKind.newcomer);
          stats.moved++;
          final key = '$srcPath -> $destPath';
          stats.moves.update(key, (v) => v + 1, ifAbsent: () => 1);
          if (verbose) {
            stderr.writeln(
              '  ${preSortLevel.name}→${postSortLevel.name}: '
              '$srcPath -> $destPath',
            );
          }
        }

        processedThisFile++;
        stats.processed++;
        newlyProcessed++;
        if (stats.processed % 100 == 0) {
          stderr.write('\r$srcPath: ${stats.processed} new processed...');
        }
      } catch (e) {
        if (existingVerbatim.add(line)) {
          emit(srcPath, line, _DestStatsKind.verbatim);
        }
      }
    }

    stderr.writeln(
      '\r$srcPath: ${stats.processed} new in '
      '${fileSw.elapsed.inSeconds}s '
      '(${stats.kept} stayed, ${stats.moved} moved out)',
    );
  }

  // Close handles. No rename, no delete — the `.tmp` files remain
  // on disk for the user to inspect.
  for (final raf in destFiles.values) {
    raf.closeSync();
  }

  stderr.writeln('');
  final action = dryRun ? '(dry-run, no files written)' : 'appended';
  for (final destPath in destStats.keys.toList()..sort()) {
    final s = destStats[destPath]!;
    final total = s.verbatim + s.stayed + s.newcomers;
    if (total == 0) continue;
    stderr.writeln(
      '$destPath.tmp: $total lines $action — '
      '${s.verbatim} verbatim, '
      '${s.stayed} recomputed-and-stayed, '
      '${s.newcomers} recomputed-and-arrived',
    );
  }

  stderr.writeln('');
  stderr.writeln('--route summary in ${sw.elapsed.inSeconds}s:');
  stderr.writeln(
    '  Already processed (matched in prior .tmp): $alreadyProcessed',
  );
  stderr.writeln(
    '  Newly processed this run:                  $newlyProcessed',
  );
  if (newlyProcessed == 0 && alreadyProcessed > 0) {
    stderr.writeln('');
    stderr.writeln(
      'All source puzzles are present in the .tmp files. '
      'You can review them, then migrate with:',
    );
    for (final p in _playableLevelPaths) {
      stderr.writeln('  mv $p.tmp $p');
    }
  }
  stderr.writeln('');
  for (final srcPath in _playableLevelPaths) {
    final s = perFileStats[srcPath];
    if (s == null) continue;
    stderr.writeln(
      '  $srcPath: ${s.processed} newly processed, '
      '${s.kept} kept here, ${s.moved} moved out',
    );
    final moveEntries =
        (s.moves.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(5);
    for (final m in moveEntries) {
      stderr.writeln('    ${m.value}× ${m.key}');
    }
  }
}

/// Enumerate the candidate `.tmp` paths the pre-load step should
/// scan. Includes the 6 playable destinations + the 3 off-cascade
/// (`overfilledEasy`, `overfilled`, `undetermined`). Returning the
/// candidate set (even files that don't exist) keeps the caller
/// simple — it just `existsSync()`-checks each.
List<String> _allPossibleTmpPaths() {
  final paths = <String>[..._playableLevelPaths];
  // Off-cascade destinations from `levelFilenames`.
  for (final lvl in [
    PuzzleLevel.overfilledEasy,
    PuzzleLevel.overfilled,
    PuzzleLevel.undetermined,
  ]) {
    final name = levelFilenames[lvl];
    if (name != null) paths.add('assets/$name');
  }
  return paths.map((p) => '$p.tmp').toList();
}

class _RouteStats {
  int processed = 0;
  int kept = 0;
  int moved = 0;
  // Source→dest path strings → count, for the per-file move breakdown.
  final Map<String, int> moves = {};
}

/// Categorisation of a single emitted line, used for the per-
/// destination summary printed at the end of `--route`.
enum _DestStatsKind { verbatim, stayed, newcomer }

class _DestStats {
  int verbatim = 0;
  int stayed = 0;
  int newcomers = 0;
}
