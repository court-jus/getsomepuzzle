// One-off check: phase coverage on the augmented onboarding catalog
// (1-easy.txt ∪ filtered overfilled.txt). Useful to verify that the
// onboarding source is large enough after a generation run. Runs
// without Flutter — parses the v2 lines directly so it can be invoked
// from the plain `dart` CLI.
//
// Usage:  dart run bin/check_phase_coverage.dart
//         (override the prefill cap with: --max-prefill 40)

import 'dart:io';

const _phases = [
  ('P0 +FM', {'FM'}, 'FM'),
  ('P1 +NC', {'FM', 'NC'}, 'NC'),
  ('P2 +PA', {'FM', 'PA', 'NC'}, 'PA'),
  ('P3 +GS', {'FM', 'PA', 'GS', 'NC'}, 'GS'),
  ('P4 +DF', {'FM', 'PA', 'NC', 'DF'}, 'DF'),
  ('P5 +CC', {'FM', 'PA', 'NC', 'DF', 'CC'}, 'CC'),
];

class _Puz {
  final Set<String> rules;
  final int prefillPercent;
  _Puz(this.rules, this.prefillPercent);

  static _Puz? parse(String line) {
    final parts = line.split('_');
    if (parts.length < 5) return null;
    final cells = parts[3]
        .split('')
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (cells.isEmpty) return null;
    final filled = cells.where((c) => c > 0).length / cells.length * 100;
    final rules = <String>{};
    for (final c in parts[4].split(';')) {
      final colon = c.indexOf(':');
      final slug = colon < 0 ? c : c.substring(0, colon);
      if (slug.isEmpty || slug == 'TX') continue;
      rules.add(slug);
    }
    return _Puz(rules, filled.toInt());
  }
}

void main(List<String> args) {
  int maxPrefill = 35;
  bool perLevel = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--max-prefill' && i + 1 < args.length) {
      maxPrefill = int.tryParse(args[i + 1]) ?? maxPrefill;
    } else if (args[i] == '--per-level') {
      perLevel = true;
    } else if (args[i] == '--soft') {
      _runSoftFilter();
      return;
    }
  }

  final levelFiles = const [
    '1-easy',
    '2-player',
    '3-advanced',
    '4-strong',
    '5-expert',
    '6-mad',
    'overfilled',
  ];
  final byLevel = {for (final n in levelFiles) n: _load('assets/$n.txt')};

  if (perLevel) {
    print('Phase-4-eligible (DF) and Phase-5-eligible (CC) per level:');
    for (final ((label, allowed, intro), _) in [
      (_phases[4], null),
      (_phases[5], null),
    ]) {
      print('  --- $label ---');
      for (final n in levelFiles) {
        int total = 0;
        for (final p in byLevel[n]!) {
          if (p.rules.every(allowed.contains) && p.rules.contains(intro)) {
            total++;
          }
        }
        print('    $n: $total');
      }
    }
    return;
  }

  final easy = byLevel['1-easy']!;
  final overfilled = byLevel['overfilled']!;
  final overfilledFiltered = overfilled
      .where((p) => p.prefillPercent <= maxPrefill)
      .toList();

  print('1-easy: ${easy.length} puzzles');
  print(
    'overfilled (<=$maxPrefill% prefill): ${overfilledFiltered.length} '
    '(out of ${overfilled.length} in the bucket)',
  );
  print('');
  print('Phase coverage on (1-easy U overfilled<=$maxPrefill%):');
  print(
    '  phase     eligible  with_intro  refresh   from_easy  from_overfilled',
  );
  for (final (name, allowed, intro) in _phases) {
    int el = 0, wi = 0, rf = 0, fe = 0, fo = 0;
    for (final p in easy) {
      if (!p.rules.every(allowed.contains)) continue;
      el++;
      fe++;
      if (p.rules.contains(intro)) {
        wi++;
      } else {
        rf++;
      }
    }
    for (final p in overfilledFiltered) {
      if (!p.rules.every(allowed.contains)) continue;
      el++;
      fo++;
      if (p.rules.contains(intro)) {
        wi++;
      } else {
        rf++;
      }
    }
    print(
      '  ${name.padRight(8)}  ${el.toString().padLeft(8)}  '
      '${wi.toString().padLeft(10)}  ${rf.toString().padLeft(7)}   '
      '${fe.toString().padLeft(9)}  ${fo.toString().padLeft(15)}',
    );
  }
}

List<_Puz> _load(String path) {
  return File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .map(_Puz.parse)
      .whereType<_Puz>()
      .toList();
}

/// Counts how many puzzles satisfy the "soft filter" of the post-strict
/// onboarding mode: at most one constraint slug outside the player's
/// already-seen set, simulating each possible state of the player as
/// they traverse the strict phases.
void _runSoftFilter() {
  final levelFiles = const [
    '1-easy',
    '2-player',
    '3-advanced',
    '4-strong',
    '5-expert',
    '6-mad',
  ];
  final byLevel = {for (final n in levelFiles) n: _load('assets/$n.txt')};

  // States named after the strict phase that just ended. After phase 3
  // (the proposed last strict phase) the player has seen
  // {FM, PA, NC, GS}; soft mode then opens the rest of the corpus.
  final scenarios = <(String label, Set<String> seen)>[
    ('After P1 ({FM, NC})', {'FM', 'NC'}),
    ('After P2 ({FM, NC, PA})', {'FM', 'NC', 'PA'}),
    ('After P3 ({FM, NC, PA, GS})', {'FM', 'NC', 'PA', 'GS'}),
  ];

  print('Soft filter coverage: ≤1 unseen slug per puzzle.');
  print('');
  for (final (label, seen) in scenarios) {
    print(label);
    print(
      '  level         eligible    %    avg_unseen_in_eligible  '
      'distinct_unseen_introduced',
    );
    int totalEligible = 0;
    int totalAll = 0;
    final introducedAcross = <String>{};
    for (final n in levelFiles) {
      final puzzles = byLevel[n]!;
      int eligible = 0;
      int sumUnseen = 0;
      final introducedHere = <String>{};
      for (final p in puzzles) {
        final unseen = p.rules.difference(seen);
        if (unseen.length <= 1) {
          eligible++;
          if (unseen.isNotEmpty) {
            sumUnseen += unseen.length;
            introducedHere.addAll(unseen);
          }
        }
      }
      totalEligible += eligible;
      totalAll += puzzles.length;
      introducedAcross.addAll(introducedHere);
      final pct = puzzles.isEmpty
          ? '-'
          : (eligible / puzzles.length * 100).toStringAsFixed(1);
      final avgU = eligible > 0
          ? (sumUnseen / eligible).toStringAsFixed(2)
          : '-';
      print(
        '  ${n.padRight(11)}   ${eligible.toString().padLeft(8)}'
        '  ${pct.padLeft(5)}              '
        '${avgU.padLeft(5)}  '
        '${introducedHere.toList().join(",")}',
      );
    }
    final pctAll = (totalEligible / totalAll * 100).toStringAsFixed(1);
    print(
      '  TOTAL         ${totalEligible.toString().padLeft(8)}'
      '  ${pctAll.padLeft(5)}',
    );
    print(
      '  Slugs the soft filter can introduce: '
      '${introducedAcross.toList()..sort()}',
    );
    print('');
  }
}
