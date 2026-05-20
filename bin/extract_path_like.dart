import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Future<void> main(List<String> args) async {
  String? inPath;
  String? outPath;
  int minLetters = 2;
  int minAnchorDistance = 2;
  bool withTrace = false;
  double minLtShare = 0.5;
  int minLtInteresting = 1;
  int timeoutMs = 15000;
  bool verbose = false;
  int? sampleN;
  int sampleSeed = 42;

  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--in':
        inPath = args[++i];
      case '--out':
        outPath = args[++i];
      case '--min-letters':
        minLetters = int.parse(args[++i]);
      case '--min-anchor-distance':
        minAnchorDistance = int.parse(args[++i]);
      case '--with-trace':
        withTrace = true;
      case '--min-lt-share':
        minLtShare = double.parse(args[++i]);
      case '--min-lt-interesting':
        minLtInteresting = int.parse(args[++i]);
      case '--timeout-ms':
        timeoutMs = int.parse(args[++i]);
      case '--verbose':
        verbose = true;
      case '--sample':
        sampleN = int.parse(args[++i]);
      case '--sample-seed':
        sampleSeed = int.parse(args[++i]);
      case '-h':
      case '--help':
        stderr.writeln(
          'Usage: dart run bin/extract_path_like.dart \\\n'
          '         [--in FILE] [--out FILE] \\\n'
          '         [--sample N [--sample-seed S]] \\\n'
          '         [--min-letters N] \\\n'
          '         [--min-anchor-distance N] \\\n'
          '         [--with-trace [--min-lt-share F] \\\n'
          '                       [--min-lt-interesting N] \\\n'
          '                       [--timeout-ms MS]] \\\n'
          '         [--verbose]\n'
          '\n'
          'Extracts puzzles that look "path-like" from a v2 puzzle file.\n'
          '\n'
          'Topological filters (always applied, cheap):\n'
          '  --min-letters N           ≥ N distinct LT letters (default 2)\n'
          '  --min-anchor-distance N   for each LT, min pairwise Manhattan\n'
          '                            distance among its anchors ≥ N\n'
          '                            (default 2: no two anchors of the\n'
          '                            same letter are 4-adjacent). Anchors\n'
          '                            of DIFFERENT letters may freely be\n'
          '                            adjacent — that\'s a natural part\n'
          '                            of path-like puzzles.\n'
          '\n'
          'Trace filters (opt-in via --with-trace, runs the solver):\n'
          '  --min-lt-share F          ≥ F fraction of prop steps issued by\n'
          '                            an LT constraint (default 0.5)\n'
          '  --min-lt-interesting N    ≥ N LT prop steps with complexity ≥ 2\n'
          '                            (i.e. articulation points or\n'
          '                            inter-letter blocking; default 1)\n'
          '  --timeout-ms MS           per-puzzle solve budget (default 15000)\n'
          '\n'
          'Sampling (cheap when the per-puzzle solve is expensive):\n'
          '  --sample N         randomly pick N lines from the input before\n'
          '                     applying any filter (useful on large tiers)\n'
          '  --sample-seed S    PRNG seed for reproducibility (default 42)\n'
          '\n'
          'Output is sorted by LT share (descending) when --with-trace is set.\n',
        );
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        exit(1);
    }
  }

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

  if (sampleN != null && sampleN < lines.length) {
    final rng = Random(sampleSeed);
    final indices = List.generate(lines.length, (i) => i)..shuffle(rng);
    final picked = indices.take(sampleN).toList()..sort();
    lines = [for (final i in picked) lines[i]];
    stderr.writeln(
      'Sampled $sampleN / ${indices.length} lines (seed=$sampleSeed)',
    );
  }

  IOSink sink;
  bool closeSink = false;
  if (outPath != null) {
    sink = File(outPath).openWrite();
    closeSink = true;
  } else {
    sink = stdout;
  }

  int read = 0;
  int rejectedNoLT = 0;
  int rejectedFewLetters = 0;
  int rejectedAnchorDistance = 0;
  int rejectedParse = 0;
  int rejectedTrace = 0;
  int rejectedLtShare = 0;
  int rejectedLtInteresting = 0;
  final letterCountHist = <int, int>{};
  final sw = Stopwatch()..start();

  // For sorted output when --with-trace is set, we buffer.
  final kept = <_KeptPuzzle>[];

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    read++;

    final parsed = _parsePuzzle(line);
    if (parsed == null) {
      rejectedParse++;
      continue;
    }

    final ltList = parsed.lts;
    if (ltList.isEmpty) {
      rejectedNoLT++;
      continue;
    }

    if (ltList.length < minLetters) {
      rejectedFewLetters++;
      continue;
    }

    if (minAnchorDistance > 0) {
      bool allLettersWellSpaced = true;
      for (final lt in ltList) {
        if (_minPairwiseDistance(lt.indices, parsed.width) <
            minAnchorDistance) {
          allLettersWellSpaced = false;
          break;
        }
      }
      if (!allLettersWellSpaced) {
        rejectedAnchorDistance++;
        continue;
      }
    }

    double ltShare = 0.0;
    int ltInteresting = 0;
    int totalProp = 0;
    int ltProp = 0;

    if (withTrace) {
      try {
        final m = _traceMetrics(line, timeoutMs: timeoutMs);
        if (m == null) {
          rejectedTrace++;
          continue;
        }
        totalProp = m.totalProp;
        ltProp = m.ltProp;
        ltInteresting = m.ltInteresting;
        ltShare = m.totalProp > 0 ? m.ltProp / m.totalProp : 0.0;
      } catch (e) {
        rejectedTrace++;
        if (verbose) stderr.writeln('  TRACE ERROR: $e');
        continue;
      }

      if (ltShare < minLtShare) {
        rejectedLtShare++;
        continue;
      }
      if (ltInteresting < minLtInteresting) {
        rejectedLtInteresting++;
        continue;
      }
    }

    kept.add(
      _KeptPuzzle(
        line: line,
        letterCount: ltList.length,
        ltShare: ltShare,
        ltInteresting: ltInteresting,
        totalProp: totalProp,
        ltProp: ltProp,
      ),
    );
    letterCountHist[ltList.length] = (letterCountHist[ltList.length] ?? 0) + 1;

    if (read % 100 == 0) {
      stderr.write('\r  read=$read kept=${kept.length}    ');
    }
  }

  if (withTrace) {
    kept.sort((a, b) => b.ltShare.compareTo(a.ltShare));
  }

  for (final k in kept) {
    sink.writeln(k.line);
    if (verbose) {
      if (withTrace) {
        stderr.writeln(
          '  ${k.line.substring(0, k.line.length.clamp(0, 60))}…'
          '  L=${k.letterCount}'
          '  lt-share=${(k.ltShare * 100).toStringAsFixed(0)}%'
          '  lt-prop=${k.ltProp}/${k.totalProp}'
          '  lt-interesting=${k.ltInteresting}',
        );
      } else {
        stderr.writeln(
          '  ${k.line.substring(0, k.line.length.clamp(0, 60))}…'
          '  L=${k.letterCount}',
        );
      }
    }
  }

  if (closeSink) await sink.flush().then((_) => sink.close());

  stderr.writeln('');
  stderr.writeln('=== EXTRACT SUMMARY ===');
  stderr.writeln('  read                  $read');
  stderr.writeln(
    '  kept                  ${kept.length} (${_pct(kept.length, read)})',
  );
  stderr.writeln('  rejected (no LT)      $rejectedNoLT');
  stderr.writeln('  rejected (< $minLetters letters) $rejectedFewLetters');
  if (minAnchorDistance > 0) {
    stderr.writeln(
      '  rejected (anchor dist < $minAnchorDistance) $rejectedAnchorDistance',
    );
  }
  if (withTrace) {
    stderr.writeln('  rejected (trace fail) $rejectedTrace');
    stderr.writeln(
      '  rejected (lt-share < ${minLtShare.toStringAsFixed(2)}) $rejectedLtShare',
    );
    stderr.writeln(
      '  rejected (lt-interesting < $minLtInteresting) $rejectedLtInteresting',
    );
  }
  if (rejectedParse > 0) {
    stderr.writeln('  rejected (parse)      $rejectedParse');
  }
  if (letterCountHist.isNotEmpty) {
    final sorted = letterCountHist.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final hist = sorted.map((e) => '${e.key}L:${e.value}').join(', ');
    stderr.writeln('  letter counts kept    $hist');
  }
  stderr.writeln('  elapsed               ${sw.elapsed.inSeconds}s');
}

class _KeptPuzzle {
  final String line;
  final int letterCount;
  final double ltShare;
  final int ltInteresting;
  final int totalProp;
  final int ltProp;

  _KeptPuzzle({
    required this.line,
    required this.letterCount,
    required this.ltShare,
    required this.ltInteresting,
    required this.totalProp,
    required this.ltProp,
  });
}

class _ParsedPuzzle {
  final int width;
  final int height;
  final List<_Lt> lts;
  _ParsedPuzzle(this.width, this.height, this.lts);
}

class _Lt {
  final String letter;
  final List<int> indices;
  _Lt(this.letter, this.indices);
}

class _LtMetrics {
  final int totalProp;
  final int ltProp;
  final int ltInteresting;
  _LtMetrics(this.totalProp, this.ltProp, this.ltInteresting);
}

_ParsedPuzzle? _parsePuzzle(String line) {
  try {
    final parts = line.split('_');
    if (parts.length < 5) return null;
    final dimensions = parts[2].split('x');
    final width = int.parse(dimensions[0]);
    final height = int.parse(dimensions[1]);
    final constraintsStr = parts[4];
    final lts = <_Lt>[];
    for (final entry in constraintsStr.split(';')) {
      if (!entry.startsWith('LT:')) continue;
      final body = entry.substring(3);
      final tokens = body.split('.');
      if (tokens.length < 2) continue;
      final letter = tokens[0];
      final indices = <int>[];
      for (int i = 1; i < tokens.length; i++) {
        final v = int.tryParse(tokens[i]);
        if (v == null) return null;
        indices.add(v);
      }
      lts.add(_Lt(letter, indices));
    }
    return _ParsedPuzzle(width, height, lts);
  } catch (_) {
    return null;
  }
}

int _minPairwiseDistance(List<int> indices, int width) {
  if (indices.length < 2) return 1 << 30;
  int minDist = 1 << 30;
  for (int i = 0; i < indices.length; i++) {
    final xi = indices[i] % width;
    final yi = indices[i] ~/ width;
    for (int j = i + 1; j < indices.length; j++) {
      final xj = indices[j] % width;
      final yj = indices[j] ~/ width;
      final d = (xi - xj).abs() + (yi - yj).abs();
      if (d < minDist) minDist = d;
    }
  }
  return minDist;
}

// Runs the solver, returns LT-specific stats. Returns null if the puzzle
// needs backtracking (i.e. propagation+force can't close it) — we don't
// want such puzzles in the path-like playlist anyway.
_LtMetrics? _traceMetrics(String line, {required int timeoutMs}) {
  final puzzle = Puzzle(line);
  final probe = puzzle.clone();
  if (!probe.solve()) return null;

  final steps = puzzle.solveExplained(timeoutMs: timeoutMs);
  int totalProp = 0;
  int ltProp = 0;
  int ltInteresting = 0;
  for (final step in steps) {
    if (step.method != SolveMethod.propagation) continue;
    totalProp++;
    if (step.constraint.startsWith('LT:')) {
      ltProp++;
      if (step.complexity >= 2) ltInteresting++;
    }
  }
  return _LtMetrics(totalProp, ltProp, ltInteresting);
}

String _pct(int x, int total) {
  if (total == 0) return '0%';
  return '${(100.0 * x / total).toStringAsFixed(1)}%';
}
