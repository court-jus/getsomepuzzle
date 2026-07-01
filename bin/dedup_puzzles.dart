// Deduplicate a puzzle file using the canonical (identity-only) key.
//
// Two puzzle lines are considered duplicates when they share the same
// `canonicalPuzzleKey` — i.e. same domain, dimensions, prefill, and
// constraint set (ignoring order, exact-string duplicates, version
// prefix, and the trailing solution / complexity / play-state fields).
//
// On collision we keep the first occurrence and drop the rest.
//
// This tool assumes `bin/recompute.dart` has already been run: it does
// not re-solve, re-sort, or re-score kept lines. It only removes
// within-constraint-field duplicates via `dedupAndSortConstraints`
// (a cheap string operation). If `solve_traces.tsv` is absent a warning
// is emitted, but the tool proceeds — the output will lack re-sorting.
//
// Comments and blank lines are preserved verbatim (cf. `recompute.dart`).
import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';

import '_trace_cache.dart';

void main(List<String> args) {
  String? outputPath;
  final inputs = <String>[];
  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-o' || a == '--output') {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing argument after $a');
        exit(1);
      }
      outputPath = args[++i];
    } else {
      inputs.add(a);
    }
  }
  if (inputs.length != 1) {
    stderr.writeln(
      'Usage: dart run bin/dedup_puzzles.dart [-o <output>] <puzzle_file>',
    );
    exit(1);
  }
  _processFile(inputs.single, outputPath);
}

void _processFile(String path, String? outputPath) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  final cache = TraceCache.load(kTraceCachePath);
  if (cache.isEmpty) {
    stderr.writeln(
      'warn: no solve_traces.tsv found — run bin/recompute.dart first. '
      'Lines will not be re-sorted or re-scored.',
    );
  }

  final lines = file.readAsLinesSync();
  final output = <String>[];
  final sw = Stopwatch()..start();
  final seenKeys = <String>{};
  int kept = 0;
  int dropped = 0;
  int errors = 0;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith('#')) {
      output.add(line);
      continue;
    }
    final key = canonicalPuzzleKey(line);
    if (!seenKeys.add(key)) {
      dropped++;
      stderr.writeln('Line ${i + 1}: duplicate of an earlier puzzle, dropped');
      continue;
    }
    try {
      // Remove duplicate constraint entries within the constraint field —
      // cheap string operation, no solve needed.
      final fields = line.split('_');
      fields[4] = dedupAndSortConstraints(fields[4]);
      output.add(fields.join('_'));
      kept++;
      if (kept % 100 == 0) {
        stderr.write('\r$path: $kept puzzles processed...');
      }
    } catch (e) {
      stderr.writeln('\nLine ${i + 1}: error: $e — kept verbatim');
      output.add(line);
      errors++;
    }
  }

  if (outputPath != null) {
    File(outputPath).writeAsStringSync('${output.join('\n')}\n');
    stderr.writeln(
      '\r$path: ${lines.length} lines in, $kept kept, $dropped duplicates '
      'dropped, $errors errors, ${sw.elapsed.inSeconds}s -> $outputPath',
    );
  } else {
    final tmpPath = '$path.deduped';
    File(tmpPath).writeAsStringSync('${output.join('\n')}\n');
    File(tmpPath).renameSync(path);
    stderr.writeln(
      '\r$path: ${lines.length} lines in, $kept kept, $dropped duplicates '
      'dropped, $errors errors, ${sw.elapsed.inSeconds}s (in-place)',
    );
  }
}
