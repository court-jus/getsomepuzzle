import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/puzzle_display.dart';

/// Decode a puzzle share URL or v2 line and print a human-readable
/// description (domain, grid, constraints).
///
/// Usage:
/// ```bash
/// dart run bin/describe_puzzle.dart "<url_or_v2_line>"
/// dart run bin/describe_puzzle.dart path/to/puzzles.txt
/// ```
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/describe_puzzle.dart '
      '<puzzle_url_or_v2_line>',
    );
    exit(1);
  }

  final input = args.first;

  // If the argument points at an existing file, read all non-empty lines.
  final file = File(input);
  if (file.existsSync()) {
    final lines = file
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      if (lines.length > 1) {
        stdout.writeln('===== Puzzle ${i + 1}/${lines.length} =====');
      }
      _describe(lines[i]);
      if (i < lines.length - 1) stdout.writeln();
    }
    return;
  }

  _describe(input);
}

void _describe(String line) {
  final normalized = normalizeToV2Line(line);
  if (normalized == null) {
    stderr.writeln('Not a valid puzzle input: $line');
    return;
  }

  try {
    final p = Puzzle(normalized);
    stdout.write(describePuzzle(p));
  } catch (e) {
    stderr.writeln('Failed to parse puzzle: $e');
  }
}
