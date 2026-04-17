import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

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

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.startsWith('#')) {
      output.add(line);
      continue;
    }

    try {
      final puzzle = Puzzle(line);
      puzzle.computeComplexity();

      // Replace solution (field 5) and complexity (field 6) in the original
      // line, preserving everything else (including TX constraints).
      final fields = line.split('_');
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
  stderr.writeln(
    '\r$path: $processed puzzles in ${sw.elapsed.inSeconds}s -> $outPath',
  );
}
