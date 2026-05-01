// Classify puzzles into 6 difficulty buckets based on the structure of
// their solveExplained() trace, and report counts on a stratified
// random sample of the asset files.
//
// Buckets (cascading, mutually exclusive):
//   - Fou furieux : >=2 force moves OR a single force with depth > 5
//   - Expert      : exactly 1 force move with depth <= 5
//   - Balaise     : no force, >=1 complicity step with complexity >= 4
//   - Avance      : no force, >=1 complicity step (max complexity <= 3)
//   - Joueur      : no force, no complicity, max prop complexity >= 4
//   - Debutant    : no force, no complicity, max prop complexity <= 3
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
  'Indetermine',
];

class _Verdict {
  final String category;
  final int forceMoves;
  final int maxForceDepth;
  final int maxPropCx;
  final int maxComplCx;
  _Verdict(
    this.category,
    this.forceMoves,
    this.maxForceDepth,
    this.maxPropCx,
    this.maxComplCx,
  );
}

_Verdict _classify(Puzzle puzzle) {
  // solveExplained works on a clone so the original puzzle is untouched.
  final steps = puzzle.solveExplained(timeoutMs: 30000);

  // Replay on a clone to know whether the puzzle was actually solved.
  final replay = puzzle.clone();
  for (final s in steps) {
    replay.setValue(s.cellIdx, s.value);
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
    );
  }

  String cat;
  if (forceMoves >= 2 || (forceMoves == 1 && maxForceDepth > 5)) {
    cat = 'Fou furieux';
  } else if (forceMoves == 1) {
    cat = 'Expert';
  } else if (maxComplCx >= 4) {
    cat = 'Balaise';
  } else if (maxComplCx > 0) {
    cat = 'Avance';
  } else if (maxPropCx >= 4) {
    cat = 'Joueur';
  } else {
    cat = 'Debutant';
  }
  return _Verdict(cat, forceMoves, maxForceDepth, maxPropCx, maxComplCx);
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
    } else if (a == '-h' || a == '--help') {
      stderr.writeln(
        'Usage: dart run bin/classify_difficulty.dart '
        '[--files A,B,...] [--pct N] [--seed N] '
        '[--sample-out PATH] [--sample-n N]',
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
        v = _classify(puzzle);
      } catch (e) {
        v = _Verdict('Indetermine', 0, 0, 0, 0);
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
          line,
        ]);
      }
      done++;
      if (done % 100 == 0) {
        stderr.writeln('  $label: $done / $keep');
      }
    }
  }

  stdout.writeln('');
  _printTable(table, [for (final f in files) f.split('/').last]);

  if (sampleOut != null) {
    final sb = StringBuffer();
    sb.writeln(
      'category\tfile\tindex\tforceMoves\tmaxForceDepth\tmaxPropCx\tmaxComplCx\tline',
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
}
