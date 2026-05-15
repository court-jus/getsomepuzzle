// Deduplicate a puzzle file using the canonical (identity-only) key.
//
// Two puzzle lines are considered duplicates when they share the same
// `canonicalPuzzleKey` — i.e. same domain, dimensions, prefill, and
// constraint set (ignoring order, exact-string duplicates, version
// prefix, and the trailing solution / complexity / play-state fields).
//
// On collision we keep the first occurrence and drop the rest. The
// kept line is re-solved and re-scored before being written, so the
// output file's solution cache and complexity field reflect the current
// algorithm — same role as `bin/recompute.dart`, combined here with
// dedup so a single pass migrates a file fully.
//
// Comments and blank lines are preserved verbatim (cf. `recompute.dart`).
import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

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
      // Dedup the constraints string (TX strip + exact duplicates),
      // parse, then reorder by real-trace cplx before emitting. The
      // intermediate lex order from `dedupAndSortConstraints` is
      // harmless: it gets overwritten by the in-memory sort below.
      final fields = line.split('_');
      fields[4] = dedupAndSortConstraints(fields[4]);
      final puzzle = Puzzle(fields.join('_'));
      // Single trace fed to the sort; `computeComplexity` does its
      // own internal solve, so the total cost here is two solves
      // per puzzle — acceptable for a one-shot maintenance tool.
      final sortSteps = puzzle.solveExplained();
      puzzle.sortConstraintsByDifficulty(sortSteps);
      puzzle.computeComplexity();
      final sol = puzzle.cachedSolution;
      // Re-emit field 4 from the in-memory sorted constraint list;
      // replace fields 5/6 from the fresh complexity computation.
      fields[4] = puzzle.constraints.map((c) => c.serialize()).join(';');
      fields[5] = sol != null ? '1:${sol.join('')}' : '0:0';
      fields[6] = '${puzzle.cachedComplexity}';
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

  final outPath = outputPath ?? '$path.deduped';
  File(outPath).writeAsStringSync('${output.join('\n')}\n');
  stderr.writeln(
    '\r$path: ${lines.length} lines in, $kept kept, $dropped duplicates '
    'dropped, $errors errors, ${sw.elapsed.inSeconds}s -> $outPath',
  );
}
