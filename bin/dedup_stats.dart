// Normalize stats files: sort + dedup the constraints section inside
// each stat line's embedded v2 puzzle line.
//
// Two plays of the same puzzle can land in the file with constraints
// listed in different orders (different generators, different versions,
// or aggregated `LT:` constraints split into pairs in legacy files).
// That clutters the file when grepping or diffing, even though the
// runtime correctly matches them via `canonicalPuzzleKey`.
//
// We keep the line in v2 grammar (version prefix, domain, dimensions,
// prefill, constraints, solution, complexity, optional play-state) so
// tools that parse positional fields — `bin/analyze_stats.dart`, the
// `Puzzle()` constructor, etc. — keep working. Only the constraints
// section (field 4) is rewritten in canonical order.
//
// Every original line is kept (one play per line). Output is sorted
// lexicographically — the same convention as `Database.writeStats`.
import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

void main(List<String> args) {
  String? outputDir;
  final inputs = <String>[];
  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-o' || a == '--output-dir') {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing argument after $a');
        exit(1);
      }
      outputDir = args[++i];
    } else {
      inputs.add(a);
    }
  }
  if (inputs.isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/dedup_stats.dart [-o <dir>] <stats_file> [<stats_file>...]',
    );
    exit(1);
  }

  for (final path in inputs) {
    _processFile(path, outputDir);
  }
}

void _processFile(String path, String? outputDir) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  final lines = file.readAsLinesSync();
  final output = <String>[];
  final canonicalKeys = <String>{};
  int rewritten = 0;
  int skipped = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final entry = StatEntry.parse(line);
    if (entry == null) {
      // Unparseable line: keep verbatim rather than drop player data.
      output.add(line);
      skipped++;
      continue;
    }
    canonicalKeys.add(canonicalPuzzleKey(entry.puzzleLine));
    final normalized = normalizeV2Line(entry.puzzleLine);
    if (normalized == entry.puzzleLine) {
      output.add(line);
      continue;
    }
    // Replace only the 4th space-separated token (puzzleLine), keep the
    // rest of the line verbatim — timestamps, durations, S/L/D, every
    // suffix-tagged analytic.
    final fields = line.split(' ');
    fields[3] = normalized;
    output.add(fields.join(' '));
    rewritten++;
  }
  output.sort();

  final outPath = outputDir == null
      ? '$path.deduped'
      : '$outputDir/${file.uri.pathSegments.last}';
  File(outPath).writeAsStringSync('${output.join('\n')}\n');
  stderr.writeln(
    '$path: ${lines.length} lines, ${canonicalKeys.length} distinct '
    'canonical keys, $rewritten lines rewritten, $skipped unparseable '
    '-> $outPath',
  );
}
