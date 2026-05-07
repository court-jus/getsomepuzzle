// Classify puzzles into 6 difficulty buckets based on the structure of
// their solveExplained() trace, and report counts on a stratified
// random sample of the asset files.
//
// Buckets (cascading, mutually exclusive):
//   - Fou furieux : >=2 force moves OR a single force with depth > 5
//   - Balaise     : no force, >=1 complicity step with complexity >= 4
//   - Avance      : no force, >=1 complicity step (max complexity <= 3)
//   - Expert      : exactly 1 force move with depth <= 5
//   - Joueur      : no force, no complicity, max prop complexity >= 3
//   - Debutant    : no force, no complicity, max prop complexity <= 2
//   - Indetermine : trace stopped before completing the puzzle (timeout
//                   or contradiction). Reported separately.
//
// Usage:
//   dart run bin/classify_difficulty.dart \
//     --files assets/default.txt,assets/collection2.txt,assets/collection3.txt,assets/tutorial.txt \
//     --pct 10 [--seed 42] [--sample-out /tmp/classify_sample.tsv]
//
// All flags are optional. Defaults: pct=10, seed=42, no sample-out.

import 'dart:io';
import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

const _categories = [
  'Debutant',
  'Joueur',
  'Avance',
  'Balaise',
  'Expert',
  'Fou furieux',
  'Pre-rempli',
  'Indetermine',
];

class _Verdict {
  final String category;
  final int forceMoves;
  final int maxForceDepth;
  final int maxPropCx;
  final int maxComplCx;
  final double prefillRatio;
  _Verdict(
    this.category,
    this.forceMoves,
    this.maxForceDepth,
    this.maxPropCx,
    this.maxComplCx,
    this.prefillRatio,
  );
}

_Verdict _classify(Puzzle puzzle, {required double maxPrefill}) {
  final prefill =
      puzzle.cells.where((c) => c.readonly).length / puzzle.cells.length;
  if (prefill > maxPrefill) {
    return _Verdict('Pre-rempli', 0, 0, 0, 0, prefill);
  }
  // solveExplained works on a clone so the original puzzle is untouched.
  final steps = puzzle.solveExplained(timeoutMs: 30000);

  // Replay on a clone to know whether the puzzle was actually solved.
  final replay = puzzle.clone();
  for (final s in steps) {
    if (s.value != null) {
      replay.setValue(s.cellIdx, s.value!);
    } else if (s.removeOption != null) {
      replay.removeOption(s.cellIdx, s.removeOption!);
    }
  }
  final solved = replay.complete && replay.check(saveResult: false).isEmpty;

  final force = steps.where((s) => s.method == SolveMethod.force).toList();
  int forceMoves = force.length;
  int maxForceDepth = 0;
  for (final s in force) {
    if (s.forceDepth > maxForceDepth) maxForceDepth = s.forceDepth;
  }

  int maxPropCx = 0;
  int maxComplCx = 0;
  for (final s in steps) {
    if (s.method != SolveMethod.propagation) continue;
    if (s.isComplicity) {
      if (s.complexity > maxComplCx) maxComplCx = s.complexity;
    } else {
      if (s.complexity > maxPropCx) maxPropCx = s.complexity;
    }
  }

  if (!solved) {
    return _Verdict(
      'Indetermine',
      forceMoves,
      maxForceDepth,
      maxPropCx,
      maxComplCx,
      prefill,
    );
  }

  String cat;
  if (forceMoves >= 2 || (forceMoves == 1 && maxForceDepth > 5)) {
    cat = 'Fou furieux';
  } else if (forceMoves == 0 && maxComplCx >= 4) {
    cat = 'Balaise';
  } else if (forceMoves == 0 && maxComplCx > 0) {
    cat = 'Avance';
  } else if (forceMoves == 1) {
    // Depth ≤ 5 here, since the Fou furieux branch already captured the
    // single-force / depth > 5 case.
    cat = 'Expert';
  } else if (maxPropCx >= 3) {
    // No force, no complicity, but the propagation phase needed at least
    // one complexity-≥3 deduction (3, 4, or 5).
    cat = 'Joueur';
  } else {
    cat = 'Debutant';
  }
  return _Verdict(
    cat,
    forceMoves,
    maxForceDepth,
    maxPropCx,
    maxComplCx,
    prefill,
  );
}

List<String> _readLines(String path) {
  final lines = File(path).readAsLinesSync();
  return lines.map((l) => l.trim()).where((l) => l.startsWith('v2_')).toList();
}

void _printTable(Map<String, Map<String, int>> table, List<String> fileLabels) {
  final colWidth = max(
    14,
    fileLabels.map((l) => l.length).fold<int>(0, max) + 2,
  );
  final header = StringBuffer();
  header.write('category'.padRight(14));
  for (final l in fileLabels) {
    header.write(l.padLeft(colWidth));
  }
  header.write('total'.padLeft(8));
  header.write('pct'.padLeft(8));
  stdout.writeln(header);
  stdout.writeln('-' * header.length);

  // Compute totals per file
  final totalsPerFile = <String, int>{for (final l in fileLabels) l: 0};
  int grandTotal = 0;
  for (final cat in _categories) {
    for (final l in fileLabels) {
      final n = table[cat]?[l] ?? 0;
      totalsPerFile[l] = totalsPerFile[l]! + n;
      grandTotal += n;
    }
  }

  for (final cat in _categories) {
    int rowTotal = 0;
    final row = StringBuffer();
    row.write(cat.padRight(14));
    for (final l in fileLabels) {
      final n = table[cat]?[l] ?? 0;
      rowTotal += n;
      row.write(n.toString().padLeft(colWidth));
    }
    row.write(rowTotal.toString().padLeft(8));
    final pct = grandTotal == 0 ? 0.0 : 100.0 * rowTotal / grandTotal;
    row.write('${pct.toStringAsFixed(1).padLeft(7)}%');
    stdout.writeln(row);
  }
  stdout.writeln('-' * header.length);
  final totalRow = StringBuffer();
  totalRow.write('total'.padRight(14));
  for (final l in fileLabels) {
    totalRow.write(totalsPerFile[l].toString().padLeft(colWidth));
  }
  totalRow.write(grandTotal.toString().padLeft(8));
  totalRow.write('100.0%'.padLeft(8));
  stdout.writeln(totalRow);
}

void main(List<String> args) {
  List<String> files = [
    'assets/default.txt',
    'assets/collection2.txt',
    'assets/collection3.txt',
    'assets/tutorial.txt',
  ];
  int pct = 10;
  int seed = 42;
  String? sampleOut;
  int sampleN = 5;
  String? splitOut;
  // Default: 0.30. Slightly more permissive than the current
  // generator contract (`ratio` ∈ [0.75, 1.0] in generator.dart:103,
  // i.e. prefill ≤ 0.25) to keep more legacy puzzles in the corpus
  // while still expurging the heavily pre-filled tail. Any puzzle
  // with prefill > maxPrefill is bucketed in "Pre-rempli" / written
  // to `overfilled.txt` when --split-out is set.
  double maxPrefill = 0.30;

  for (int i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--files') {
      files = args[++i].split(',');
    } else if (a == '--pct') {
      pct = int.parse(args[++i]);
    } else if (a == '--seed') {
      seed = int.parse(args[++i]);
    } else if (a == '--sample-out') {
      sampleOut = args[++i];
    } else if (a == '--sample-n') {
      sampleN = int.parse(args[++i]);
    } else if (a == '--max-prefill') {
      maxPrefill = double.parse(args[++i]);
    } else if (a == '--split-out') {
      splitOut = args[++i];
    } else if (a == '-h' || a == '--help') {
      stderr.writeln(
        'Usage: dart run bin/classify_difficulty.dart '
        '[--files A,B,...] [--pct N] [--seed N] '
        '[--sample-out PATH] [--sample-n N] [--max-prefill F] '
        '[--split-out DIR]',
      );
      exit(0);
    } else {
      stderr.writeln('Unknown argument: $a');
      exit(1);
    }
  }

  // Bucketed table[category][fileLabel] = count
  final table = <String, Map<String, int>>{
    for (final cat in _categories)
      cat: {for (final f in files) f.split('/').last: 0},
  };

  // For sample TSV: per-category list of (verdict, fileLabel, idx, line)
  final samples = <String, List<List<String>>>{
    for (final cat in _categories) cat: [],
  };

  // Per-category puzzle lines, only filled when --split-out is set.
  // Mapping mirrors the playlist filenames requested in docs/dev/levels.md.
  const splitFilenames = <String, String>{
    'Debutant': '1-easy.txt',
    'Joueur': '2-player.txt',
    'Avance': '3-advanced.txt',
    'Balaise': '4-strong.txt',
    'Expert': '5-expert.txt',
    'Fou furieux': '6-mad.txt',
    'Pre-rempli': 'overfilled.txt',
    'Indetermine': 'undetermined.txt',
  };
  final splitLines = <String, List<String>>{
    for (final cat in _categories) cat: [],
  };

  final rng = Random(seed);

  for (final path in files) {
    final label = path.split('/').last;
    final List<String> lines;
    try {
      lines = _readLines(path);
    } catch (e) {
      stderr.writeln('Skipping $path: $e');
      continue;
    }
    final n = lines.length;
    final keep = (n * pct / 100).ceil();
    // Shuffle indices deterministically.
    final indices = List<int>.generate(n, (i) => i);
    indices.shuffle(rng);
    final sampleIdx = indices.take(keep).toList()..sort();

    stdout.writeln(
      'Sampling $label: $keep / $n lines (${(100 * keep / max(1, n)).toStringAsFixed(2)}%)',
    );

    int done = 0;
    for (final idx in sampleIdx) {
      final line = lines[idx];
      _Verdict v;
      try {
        final puzzle = Puzzle(line);
        v = _classify(puzzle, maxPrefill: maxPrefill);
      } catch (e) {
        v = _Verdict('Indetermine', 0, 0, 0, 0, 0.0);
      }
      table[v.category]![label] = (table[v.category]![label] ?? 0) + 1;

      if (samples[v.category]!.length < sampleN) {
        samples[v.category]!.add([
          v.category,
          label,
          idx.toString(),
          v.forceMoves.toString(),
          v.maxForceDepth.toString(),
          v.maxPropCx.toString(),
          v.maxComplCx.toString(),
          v.prefillRatio.toStringAsFixed(3),
          line,
        ]);
      }
      if (splitOut != null) {
        splitLines[v.category]!.add(line);
      }
      done++;
      if (done % 100 == 0) {
        stderr.writeln('  $label: $done / $keep');
      }
    }
  }

  stdout.writeln('');
  if (maxPrefill < 1.0) {
    stdout.writeln(
      'Filter: puzzles with prefill ratio > ${maxPrefill.toStringAsFixed(2)} '
      'are bucketed in "Pre-rempli" instead of being classified.',
    );
    stdout.writeln('');
  }
  _printTable(table, [for (final f in files) f.split('/').last]);

  if (sampleOut != null) {
    final sb = StringBuffer();
    sb.writeln(
      'category\tfile\tindex\tforceMoves\tmaxForceDepth\tmaxPropCx\tmaxComplCx\tprefill\tline',
    );
    for (final cat in _categories) {
      for (final row in samples[cat]!) {
        sb.writeln(row.join('\t'));
      }
    }
    File(sampleOut).writeAsStringSync(sb.toString());
    stdout.writeln('');
    stdout.writeln('Sample TSV written to $sampleOut');
  }

  if (splitOut != null) {
    final dir = Directory(splitOut);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    stdout.writeln('');
    stdout.writeln('Splitting puzzles into $splitOut/');
    for (final cat in _categories) {
      final fname = splitFilenames[cat];
      if (fname == null) continue;
      final outPath = '$splitOut/$fname';
      final lines = splitLines[cat]!;
      File(
        outPath,
      ).writeAsStringSync(lines.join('\n') + (lines.isEmpty ? '' : '\n'));
      stdout.writeln('  $fname  (${lines.length} puzzles)');
    }
  }
}
