// Find puzzles whose first N propagation moves are all produced by a
// Complicity (not by an individual Constraint).
//
// A "propagation move" is what `Puzzle.apply()` returns (constraints first,
// then complicities). Force / backtracking is never triggered — if the
// solver gets stuck before N moves, the puzzle is skipped.
//
// Usage:
//   dart run bin/find_complicity_openers.dart [--min 3] [--examples 10] \
//       [--assets assets/1-easy.txt,assets/2-player.txt] [--verbose]
//
//   --min N       : minimum number of leading complicity moves (default 3)
//   --examples K  : how many example puzzles to print per file (default 10)
//   --assets LIST : comma-separated list of asset files to scan
//                   (default: all 8 level files)
//   --verbose     : also print puzzle lines for examples
//
// The script only uses propagation (no force, no backtracking). If the puzzle
// cannot produce N moves by propagation alone it is not counted.

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

const _defaultAssets = [
  'assets/1-easy.txt',
  'assets/2-player.txt',
  'assets/3-advanced.txt',
  'assets/4-strong.txt',
  'assets/5-expert.txt',
  'assets/6-mad.txt',
  'assets/overfilled.txt',
  'assets/overfilled-easy.txt',
];

void main(List<String> args) {
  int minComplicity = 3;
  int maxExamples = 10;
  bool verbose = false;
  List<String> assetFiles = List.of(_defaultAssets);

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--min' && i + 1 < args.length) {
      minComplicity = int.tryParse(args[i + 1]) ?? minComplicity;
      i++;
    } else if (args[i] == '--examples' && i + 1 < args.length) {
      maxExamples = int.tryParse(args[i + 1]) ?? maxExamples;
      i++;
    } else if (args[i] == '--assets' && i + 1 < args.length) {
      assetFiles = args[i + 1].split(',').map((s) => s.trim()).toList();
      i++;
    } else if (args[i] == '--verbose') {
      verbose = true;
    }
  }

  stderr.writeln(
    'Scanning for puzzles with >= $minComplicity leading complicity moves '
    '(propagation only, no force)',
  );
  stderr.writeln('Files: ${assetFiles.join(', ')}');
  stderr.writeln('');

  // Global counters across all files, for summary.
  int grandTotal = 0;
  int grandMatch3 = 0;
  int grandMatch4 = 0;

  for (final path in assetFiles) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('  [SKIP] $path — file not found');
      continue;
    }

    final lines = file
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
        .toList();

    int total = lines.length;
    int match3 = 0;
    int match4 = 0;

    // Collect examples for printing after counting.
    // Each entry: (line, leadingSlugPairs) where leadingSlugPairs is the list
    // of (slugA, slugB) from Complicity.slugs for the first minComplicity moves.
    final List<({String puzzleLine, List<String> slugSeq})> examples3 = [];
    final List<({String puzzleLine, List<String> slugSeq})> examples4 = [];

    for (final line in lines) {
      final result = _analyzeLeadingMoves(line, maxN: 4);
      if (result == null) continue; // parse failure

      final seq = result;
      // seq[i] is either 'complicity(<slugA>+<slugB>)' or 'constraint'

      // Count leading complicity moves.
      int leadingComplicity = 0;
      for (final tag in seq) {
        if (tag.startsWith('complicity:')) {
          leadingComplicity++;
        } else {
          break;
        }
      }

      if (leadingComplicity >= 3) {
        match3++;
        if (examples3.length < maxExamples) {
          examples3.add((puzzleLine: line, slugSeq: seq.take(4).toList()));
        }
      }
      if (leadingComplicity >= 4) {
        match4++;
        if (examples4.length < maxExamples) {
          examples4.add((puzzleLine: line, slugSeq: seq.take(4).toList()));
        }
      }
    }

    grandTotal += total;
    grandMatch3 += match3;
    grandMatch4 += match4;

    // Print per-file summary.
    final name = path.split('/').last;
    print(
      '$name: $total puzzles — ≥3 leading complicities: $match3'
      ' | ≥4: $match4',
    );

    // Print examples for ≥3 (or ≥4 if there are more).
    final examplesSource = examples4.isNotEmpty ? examples4 : examples3;
    if (examplesSource.isEmpty) {
      print('  (no examples)');
    } else {
      final label = examples4.isNotEmpty ? '≥4' : '≥3';
      print('  Examples ($label):');
      for (final ex in examplesSource) {
        final slugLine = ex.slugSeq
            .map((s) => s.startsWith('complicity:') ? s.substring(11) : '[C]')
            .join(' → ');
        if (verbose) {
          print('    ${ex.puzzleLine}');
          print('    Sequence: $slugLine');
        } else {
          // Print a short puzzle ID (domain + dimensions + first 8 cells).
          final id = _shortId(ex.puzzleLine);
          print('    $id  |  $slugLine');
        }
      }
    }
    print('');
  }

  print('─────────────────────────────────────');
  print('TOTAL: $grandTotal puzzles scanned');
  print('  ≥3 leading complicity moves: $grandMatch3');
  print('  ≥4 leading complicity moves: $grandMatch4');
}

/// Returns the leading move sequence as a list of tags.
/// Each tag is either:
///   'complicity:slugA+slugB'  — produced by a Complicity
///   'constraint'              — produced by a plain Constraint
///
/// Returns null if parsing fails.
/// Returns an empty list if propagation produces 0 moves.
/// Stops after [maxN] moves.
List<String>? _analyzeLeadingMoves(String line, {required int maxN}) {
  Puzzle p;
  try {
    p = Puzzle(line);
  } catch (_) {
    return null;
  }

  final tags = <String>[];
  for (int step = 0; step < maxN; step++) {
    Move? move;
    try {
      move = p.apply();
    } catch (_) {
      break;
    }
    if (move == null) break;
    if (move.isImpossible != null) break;

    final givenBy = move.givenBy;
    if (givenBy is Complicity) {
      final (a, b) = givenBy.slugs;
      tags.add('complicity:$a+$b');
    } else {
      tags.add('constraint');
    }
    if (move.value != null) {
      try {
        p.setValue(move.idx, move.value!);
      } catch (_) {
        break;
      }
    } else if (move.removeOption != null) {
      try {
        p.removeOption(move.idx, move.removeOption!);
      } catch (_) {
        break;
      }
    }
    if (p.complete) break;
  }

  return tags;
}

/// Returns a short human-readable identifier for a puzzle line.
String _shortId(String line) {
  final parts = line.split('_');
  if (parts.length < 5) return line.substring(0, line.length.clamp(0, 60));
  final domain = parts[1];
  final dim = parts[2];
  final cells = parts[3];
  final shortCells = cells.length > 10 ? '${cells.substring(0, 10)}…' : cells;
  final slugs = parts[4]
      .split(';')
      .map((s) {
        final colon = s.indexOf(':');
        return colon < 0 ? s : s.substring(0, colon);
      })
      .toSet()
      .join(',');
  return 'dom=$domain dim=$dim cells=$shortCells constraints=[$slugs]';
}
