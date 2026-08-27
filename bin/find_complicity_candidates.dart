// Find easy puzzles whose constraint set already contains the base slugs of a
// registered complicity (GS+FM, PA+LT, ...). These are the feedstock for
// "up-easing" (bin/up_ease.dart): removing the single constraint that currently
// pins a cell may force the solver to combine the surviving pair into a
// Complicity move, lifting a beginner/player puzzle into advanced/strong.
//
// The scan is a cheap static filter — it only reads slugs off the v2 line's
// constraint field (no solve, no full parse). It does NOT prove the complicity
// would actually fire; that is exactly what bin/up_ease.dart probes.
//
// Usage:
//   dart run bin/find_complicity_candidates.dart
//       [--input assets/1-easy-recycled.txt,assets/2-player-recycled.txt]
//       [--output assets/complicity-recycling-candidates.txt]
//       [--verbose]

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';

/// Base-slug pairs for every registered complicity (see
/// lib/getsomepuzzle/constraints/complicities/registry.dart). A pair of the
/// same slug twice needs two distinct instances of that slug.
const _pairs = <(String, String)>[
  ('FM', 'FM'), // FMFMComplicity  (tier 4 -> strong)
  ('GS', 'FM'), // GSAllComplicity (tier 3 or 4)
  ('GS', 'GS'), // GSGSComplicity  (tier 3 -> advanced)
  ('GS', 'QA'), // GSQAComplicity  (tier 3 -> advanced)
  ('LT', 'FM'), // LTFMComplicity  (tier 3 -> advanced)
  ('LT', 'GS'), // LTGSComplicity  (tier 4 -> strong)
  ('PA', 'FM'), // PABalancedSideComplicity (tier 3 -> advanced)
  ('PA', 'LT'), // PABalancedSideComplicity (tier 3 -> advanced)
  ('SH', 'GS'), // SHGSComplicity  (tier 3 -> advanced)
  ('SY', 'FM'), // SYFMComplicity  (tier 4 -> strong)
];

void main(List<String> args) {
  var input = 'assets/1-easy-recycled.txt,assets/2-player-recycled.txt';
  var output = 'assets/complicity-recycling-candidates.txt';
  var verbose = false;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--input':
        input = args[++i];
      case '--output':
        output = args[++i];
      case '-v':
      case '--verbose':
        verbose = true;
      case '-h':
      case '--help':
        stderr.writeln(_usage);
        exit(0);
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        stderr.writeln(_usage);
        exit(1);
    }
  }

  final inputs = input.split(',').map((s) => s.trim()).toList();
  final seen = <String>{};
  final matches = <String>[];
  final pairCounts = <String, int>{};

  for (final path in inputs) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('skip missing: $path');
      continue;
    }
    var total = 0;
    var matched = 0;
    for (final line in f.readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      total++;
      final counts = _slugCounts(line);
      final hits = _pairs.where((p) => _matches(counts, p)).toList();
      if (hits.isEmpty) continue;
      matched++;
      for (final p in hits) {
        final label = '${p.$1}+${p.$2}';
        pairCounts[label] = (pairCounts[label] ?? 0) + 1;
      }
      String key;
      try {
        key = canonicalPuzzleKey(line);
      } catch (_) {
        key = line.trim();
      }
      if (seen.add(key)) matches.add(line);
    }
    stderr.writeln('$path: $total puzzles, $matched with a complicity pair');
  }

  final out = File(output);
  out.writeAsStringSync('${matches.join('\n')}\n');
  stderr.writeln('');
  stderr.writeln('Wrote ${matches.length} candidates (deduped) to $output');
  stderr.writeln('Slug-pair hits (a puzzle can hit several):');
  final sorted = pairCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    stderr.writeln('  ${e.key.padRight(8)} ${e.value}');
  }
  if (verbose) {
    for (final line in matches.take(5)) {
      stderr.writeln('  sample: $line');
    }
  }
}

/// Slug -> occurrence count, read from the v2 line's constraint field.
/// Field layout: `v2_<domain>_<dim>_<prefill>_<constraints>_<solution>_<cplx>[_scenario:...]`.
Map<String, int> _slugCounts(String line) {
  final parts = line.trim().split('_');
  if (parts.length < 5) return const {};
  final counts = <String, int>{};
  for (final c in parts[4].split(';')) {
    if (c.isEmpty) continue;
    final colon = c.indexOf(':');
    final slug = colon < 0 ? c : c.substring(0, colon);
    counts[slug] = (counts[slug] ?? 0) + 1;
  }
  return counts;
}

bool _matches(Map<String, int> counts, (String, String) pair) {
  final (a, b) = pair;
  if (a == b) return (counts[a] ?? 0) >= 2;
  return (counts[a] ?? 0) >= 1 && (counts[b] ?? 0) >= 1;
}

const _usage = '''
Usage: dart run bin/find_complicity_candidates.dart [options]

Static filter: copy easy puzzles carrying a complicity base-slug pair into a
candidate file for bin/up_ease.dart. No solve is performed.

Options:
  --input LIST    Comma-separated input files
                  (default: assets/1-easy-recycled.txt,assets/2-player-recycled.txt)
  --output PATH   Candidate output (default: assets/complicity-recycling-candidates.txt)
  -v, --verbose   Print a few sample lines
  -h, --help      Show this help
''';
