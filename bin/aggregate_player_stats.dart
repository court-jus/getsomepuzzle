// Aggregate a player's stats files into a single chronological log.
//
// Given a directory of `.txt` stats files (the format players export from
// the app — one play per line, see `stats.dart` for the grammar), this
// script:
//
//   1. **Aggregates** every `.txt` under the directory (recursively).
//   2. **Deduplicates** plays. Two stats files often overlap (e.g. an
//      older export shipped alongside a newer cumulative one). We collapse
//      lines that share the same finished timestamp *and* the same
//      canonical puzzle key — that's the same play exported twice. Plays
//      of the same puzzle at different timestamps are kept (they are
//      genuinely different sessions).
//   3. **Recomputes complexity** with the latest algorithm. The `cplx`
//      stored in each stats line was produced by the generator at the
//      time of play; we run `Puzzle.computeComplexity` again so all plays
//      are scored on a single, current scale. The new value replaces
//      field 6 of the embedded puzzle line. The constraints field is
//      also dedup/sorted (same as `bin/recompute.dart`) so equivalent
//      puzzles share a key.
//   4. **Sorts** finished plays by timestamp (ascending). Any unfinished
//      lines are dropped — they have no chronological position.
//   5. **Appends `<n>lvl`** as a suffix-tagged field at the end of every
//      line. `level = duration + 30 * failures` — the same scoring used
//      by `PuzzleAggregatedStats.level` in the app. Pre-existing `*lvl`
//      tokens (from a re-run) are stripped first so the output stays
//      idempotent.
//
// Output is written to a single file passed as the second positional
// argument. The line grammar is preserved — downstream parsers
// (`StatEntry.parse`, `analyze_stats.dart`, …) keep working.
//
// Usage:
//   dart run bin/aggregate_player_stats.dart <stats_dir> <output_file>

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run bin/aggregate_player_stats.dart <stats_dir> <output_file>',
    );
    exit(1);
  }
  final dirPath = args[0];
  final outPath = args[1];

  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    stderr.writeln('Directory not found: $dirPath');
    exit(1);
  }

  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('No .txt files found under $dirPath');
    exit(1);
  }

  final seen = <String>{};
  final rows = <_Row>[];
  int total = 0, duplicates = 0, unparseable = 0, unfinished = 0;

  for (final f in files) {
    final lines = f.readAsLinesSync();
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      total++;
      final entry = StatEntry.parse(line);
      if (entry == null) {
        unparseable++;
        continue;
      }
      if (entry.finished == null) {
        unfinished++;
        continue;
      }
      final key = '${entry.finished}|${canonicalPuzzleKey(entry.puzzleLine)}';
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      rows.add(_Row(line: line, entry: entry, ts: entry.finished!));
    }
  }

  rows.sort((a, b) => a.ts.compareTo(b.ts));

  int recomputed = 0;
  int recomputeFailed = 0;
  final out = StringBuffer();

  for (final r in rows) {
    String puzzleLine = r.entry.puzzleLine;
    try {
      final pf = puzzleLine.split('_');
      // v2 grammar: v2_<domain>_<wxh>_<prefill>_<constraints>_<solution>_<cplx>[_p:...]
      if (pf.length >= 7) {
        // Dedup the constraint string then parse; the lex sort
        // `dedupAndSortConstraints` does is overwritten right after
        // by the in-memory trace-based sort.
        pf[4] = dedupAndSortConstraints(pf[4]);
        final puzzle = Puzzle(pf.join('_'));
        // Single trace for sort; `computeComplexity` re-solves
        // internally afterwards.
        final sortSteps = puzzle.solveExplained();
        puzzle.sortConstraintsByDifficulty(sortSteps);
        puzzle.computeComplexity();
        pf[4] = puzzle.constraints.map((c) => c.serialize()).join(';');
        pf[6] = '${puzzle.cachedComplexity}';
        if (puzzle.cachedSolution != null) {
          pf[5] = '1:${puzzle.cachedSolution!.join('')}';
        }
        puzzleLine = pf.join('_');
        recomputed++;
      }
    } catch (e) {
      recomputeFailed++;
    }

    final parts = r.line.split(' ');
    parts[3] = puzzleLine;
    parts.removeWhere((p) => p.endsWith('lvl'));
    final level = r.entry.duration + 30 * r.entry.failures;
    parts.add('${level}lvl');
    out.writeln(parts.join(' '));
  }

  File(outPath).writeAsStringSync(out.toString());

  stderr.writeln(
    '$dirPath: read $total lines from ${files.length} files '
    '($duplicates duplicates, $unparseable unparseable, '
    '$unfinished unfinished dropped) — kept ${rows.length}, '
    'cplx recomputed on $recomputed (failed on $recomputeFailed) -> $outPath',
  );
}

class _Row {
  final String line;
  final StatEntry entry;
  final String ts;
  _Row({required this.line, required this.entry, required this.ts});
}
