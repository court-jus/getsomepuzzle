// Filters a stream of puzzle lines by their trace score.
//
// Reads puzzle lines (from --in or stdin), scores each using
// `scorePuzzle()` from trace_score.dart, and emits only those whose
// score is at least the threshold. Reports rejection stats on stderr.
//
// Usage:
//   dart run bin/filter_score.dart [--in FILE] [--out FILE]
//                                  [--threshold N] [--limit N]
//                                  [--timeout-ms MS]

import 'dart:io';

import 'trace_score.dart' show TraceMetrics, scorePuzzle;

void main(List<String> args) async {
  String? inPath;
  String? outPath;
  double threshold = 40.0;
  int? limit;
  int timeoutMs = 15000;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        inPath = args[++i];
      case '--out':
        outPath = args[++i];
      case '--threshold':
        threshold = double.parse(args[++i]);
      case '--limit':
        limit = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/filter_score.dart '
          '[--in FILE] [--out FILE] [--threshold N] [--limit N] '
          '[--timeout-ms MS]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

  // Source.
  List<String> lines;
  if (inPath != null) {
    final f = File(inPath);
    if (!f.existsSync()) {
      stderr.writeln('File not found: $inPath');
      exit(1);
    }
    lines = f.readAsLinesSync();
  } else {
    lines = <String>[];
    String? raw;
    while ((raw = stdin.readLineSync()) != null) {
      lines.add(raw!);
    }
  }

  // Sink.
  IOSink sink;
  bool closeSink = false;
  if (outPath != null) {
    sink = File(outPath).openWrite();
    closeSink = true;
  } else {
    sink = stdout;
  }

  int read = 0;
  int kept = 0;
  int rejectedScore = 0;
  int rejectedBacktrack = 0;
  int rejectedParse = 0;
  double sumIn = 0.0;
  double sumKept = 0.0;
  // Slug -> count among rejected (excluding parse errors).
  final rejectedSlugs = <String, int>{};
  final sw = Stopwatch()..start();

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    read++;

    TraceMetrics m;
    try {
      m = scorePuzzle(line, timeoutMs: timeoutMs);
    } catch (e) {
      rejectedParse++;
      stderr.writeln('  PARSE ERROR: $e');
      continue;
    }

    if (!m.needsBacktrack) sumIn += m.score;

    if (m.needsBacktrack) {
      rejectedBacktrack++;
      _bumpSlugs(rejectedSlugs, line);
      continue;
    }
    if (m.score < threshold) {
      rejectedScore++;
      _bumpSlugs(rejectedSlugs, line);
      continue;
    }

    sink.writeln(line);
    kept++;
    sumKept += m.score;

    if (limit != null && kept >= limit) break;

    if (read % 50 == 0) {
      stderr.write(
        '\r  read=$read kept=$kept '
        'rej=${rejectedScore + rejectedBacktrack + rejectedParse}        ',
      );
    }
  }

  if (closeSink) await sink.flush().then((_) => sink.close());

  stderr.writeln('');
  stderr.writeln('=== FILTER SUMMARY (threshold=$threshold) ===');
  stderr.writeln('  read              $read');
  stderr.writeln(
    '  kept              $kept '
    '(${_pct(kept, read)})',
  );
  stderr.writeln(
    '  rejected (score)  $rejectedScore '
    '(${_pct(rejectedScore, read)})',
  );
  stderr.writeln(
    '  rejected (BT)     $rejectedBacktrack '
    '(${_pct(rejectedBacktrack, read)})',
  );
  if (rejectedParse > 0) {
    stderr.writeln(
      '  rejected (parse)  $rejectedParse '
      '(${_pct(rejectedParse, read)})',
    );
  }
  final scorable = read - rejectedBacktrack - rejectedParse;
  if (scorable > 0) {
    stderr.writeln(
      '  mean score in     ${(sumIn / scorable).toStringAsFixed(1)}',
    );
  }
  if (kept > 0) {
    stderr.writeln(
      '  mean score kept   ${(sumKept / kept).toStringAsFixed(1)}',
    );
  }
  if (rejectedSlugs.isNotEmpty) {
    final sorted = rejectedSlugs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).map((e) => '${e.key}×${e.value}').join(', ');
    stderr.writeln('  top slugs in rej  $top');
  }
  stderr.writeln('  elapsed           ${sw.elapsed.inSeconds}s');
}

void _bumpSlugs(Map<String, int> tally, String line) {
  // Puzzle line format: v2_<dom>_<dims>_<cells>_<slug:params>;<slug:params>...
  final parts = line.split('_');
  if (parts.length < 5) return;
  for (final c in parts[4].split(';')) {
    final slug = c.split(':').first;
    if (slug.isEmpty) continue;
    tally[slug] = (tally[slug] ?? 0) + 1;
  }
}

String _pct(int n, int total) {
  if (total == 0) return '0%';
  return '${(n / total * 100).toStringAsFixed(1)}%';
}
