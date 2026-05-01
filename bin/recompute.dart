import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run bin/recompute.dart <file1> [file2] ...');
    exit(1);
  }

  for (final path in args) {
    _processFile(path);
  }
}

void _processFile(String path) {
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

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith('#')) {
      output.add(line);
      continue;
    }

    try {
      // Drop exact-duplicate constraints (same slug + same params) and
      // sort them before recomputing. Some legacy lines have constraints
      // repeated verbatim (e.g. `SH:111.001.001;SH:111.001.001;...`);
      // keeping them inflates the constraint count and skews the
      // duration / complexity model downstream without changing the
      // puzzle's logic. Sorting matches the canonical ordering used by
      // the in-app stats matching, so two recompute outputs of
      // structurally equal puzzles share the same constraint section.
      final fields = line.split('_');
      final dedupedConstraintsField = dedupAndSortConstraints(fields[4]);
      final removed =
          fields[4].split(';').length -
          dedupedConstraintsField.split(';').length;
      if (removed > 0) {
        dedupedPuzzles++;
        dedupedConstraints += removed;
      }
      fields[4] = dedupedConstraintsField;
      final dedupedLine = fields.join('_');

      final puzzle = Puzzle(dedupedLine);
      puzzle.computeComplexity();

      // Replace solution (field 5) and complexity (field 6) in the deduped
      // line, preserving everything else (including TX constraints).
      final sol = puzzle.cachedSolution;
      fields[5] = sol != null ? '1:${sol.join('')}' : '0:0';
      fields[6] = '${puzzle.cachedComplexity}';
      output.add(fields.join('_'));

      processed++;
      if (processed % 100 == 0) {
        stderr.write('\r$path: $processed puzzles processed...');
      }
    } catch (e) {
      stderr.writeln('\nError on line ${i + 1}: $e');
      output.add(line);
    }
  }

  final outPath = '$path.new';
  File(outPath).writeAsStringSync('${output.join('\n')}\n');
  final dedupSummary = dedupedPuzzles > 0
      ? ' ($dedupedConstraints duplicate constraints removed across $dedupedPuzzles puzzles)'
      : '';
  stderr.writeln(
    '\r$path: $processed puzzles in ${sw.elapsed.inSeconds}s -> $outPath$dedupSummary',
  );
}
