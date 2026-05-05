// One-off analysis: per-constraint complexity distribution in 1-easy.txt.
//
// For every puzzle we replay `solveExplained` and tally, for each constraint
// slug:
//   - how many puzzles use it
//   - how many propagation steps it produces (total, by complexity tier 0-5)
//   - how many force steps occurred while it was the constraint pool
//
// Goal: choose the constraint(s) safest to introduce first to a brand-new
// player — i.e. those that mostly produce complexity-0 deductions.
//
// Usage:  dart run bin/onboarding_stats.dart [path]
// Default path: assets/1-easy.txt

import 'dart:io';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'assets/1-easy.txt';
  final lines = File(path)
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
      .toList();

  // slug -> tier -> count
  final stepsByTier = <String, Map<int, int>>{};
  // slug -> number of puzzles where it appears in the *catalog* (declared)
  final puzzlesWithSlug = <String, int>{};
  // slug -> number of puzzles where at least one propagation step uses it
  final puzzlesWithSlugUsed = <String, int>{};
  // slug -> number of puzzles where it is the *only* declared rule
  final puzzlesAlone = <String, int>{};
  // slug -> number of solo puzzles fully solvable with complexity ≤ N
  final puzzlesAloneCplx0 = <String, int>{};
  final puzzlesAloneCplx0or1 = <String, int>{};

  // Anchor -> partner -> count (puzzles where the declared rule set is
  // *exactly* {anchor, partner}, with anchor ∈ {FM, NC}).
  final duoCount = <String, Map<String, int>>{};
  // ... and how many of those duos have max-tier ≤ 0 / ≤ 1, no force step.
  final duoCplx0 = <String, Map<String, int>>{};
  final duoCplx0or1 = <String, Map<String, int>>{};
  // Tier histogram restricted to propagations attributed to the *partner*
  // slug (not to the anchor) when solving an exactly-{anchor,partner}
  // puzzle. Tells us what tier a player will face when meeting the
  // partner for the first time, anchor already mastered.
  final partnerTierHist = <String, Map<String, Map<int, int>>>{};

  int totalPuzzles = 0;
  int unsolvedPuzzles = 0;

  for (final line in lines) {
    totalPuzzles++;
    final puzzle = Puzzle(line);

    final declared = <String>{};
    for (final c in puzzle.constraints) {
      final slug = c.serialize().split(':').first;
      if (slug.isEmpty || slug == 'TX') continue;
      declared.add(slug);
    }
    for (final s in declared) {
      puzzlesWithSlug[s] = (puzzlesWithSlug[s] ?? 0) + 1;
    }
    final solo = declared.length == 1 ? declared.first : null;
    if (solo != null) {
      puzzlesAlone[solo] = (puzzlesAlone[solo] ?? 0) + 1;
    }

    final steps = puzzle.solveExplained(timeoutMs: 30000);
    if (steps.isEmpty) {
      unsolvedPuzzles++;
      continue;
    }

    final usedSlugsThisPuzzle = <String>{};
    int maxTierThisPuzzle = 0;
    bool sawForce = false;
    // Per-puzzle per-slug tier histogram, used for partnerTierHist below.
    final perSlugTier = <String, Map<int, int>>{};
    for (final s in steps) {
      if (s.method == SolveMethod.force) {
        sawForce = true;
        continue;
      }
      final slug = s.constraint.split(':').first;
      if (slug.isEmpty) continue;
      usedSlugsThisPuzzle.add(slug);
      stepsByTier
          .putIfAbsent(slug, () => <int, int>{})
          .update(s.complexity, (v) => v + 1, ifAbsent: () => 1);
      perSlugTier
          .putIfAbsent(slug, () => <int, int>{})
          .update(s.complexity, (v) => v + 1, ifAbsent: () => 1);
      if (s.complexity > maxTierThisPuzzle) maxTierThisPuzzle = s.complexity;
    }
    for (final s in usedSlugsThisPuzzle) {
      puzzlesWithSlugUsed[s] = (puzzlesWithSlugUsed[s] ?? 0) + 1;
    }
    if (solo != null && !sawForce) {
      if (maxTierThisPuzzle <= 0) {
        puzzlesAloneCplx0[solo] = (puzzlesAloneCplx0[solo] ?? 0) + 1;
      }
      if (maxTierThisPuzzle <= 1) {
        puzzlesAloneCplx0or1[solo] = (puzzlesAloneCplx0or1[solo] ?? 0) + 1;
      }
    }

    // Duo: exactly two declared slugs, one of which is FM or NC.
    if (declared.length == 2) {
      for (final anchor in const ['FM', 'NC']) {
        if (!declared.contains(anchor)) continue;
        final partner = declared.firstWhere((s) => s != anchor);
        duoCount
            .putIfAbsent(anchor, () => <String, int>{})
            .update(partner, (v) => v + 1, ifAbsent: () => 1);
        if (!sawForce) {
          if (maxTierThisPuzzle <= 0) {
            duoCplx0
                .putIfAbsent(anchor, () => <String, int>{})
                .update(partner, (v) => v + 1, ifAbsent: () => 1);
          }
          if (maxTierThisPuzzle <= 1) {
            duoCplx0or1
                .putIfAbsent(anchor, () => <String, int>{})
                .update(partner, (v) => v + 1, ifAbsent: () => 1);
          }
        }
        // Aggregate the partner's tier histogram for this puzzle.
        final partnerTiers = perSlugTier[partner];
        if (partnerTiers != null) {
          final dst = partnerTierHist
              .putIfAbsent(anchor, () => <String, Map<int, int>>{})
              .putIfAbsent(partner, () => <int, int>{});
          partnerTiers.forEach((tier, n) {
            dst.update(tier, (v) => v + n, ifAbsent: () => n);
          });
        }
      }
    }
  }

  final allSlugs = <String>{
    ...puzzlesWithSlug.keys,
    ...stepsByTier.keys,
    ...puzzlesAlone.keys,
  };
  final ordered = allSlugs.toList()
    ..sort((a, b) {
      final ca = puzzlesWithSlug[a] ?? 0;
      final cb = puzzlesWithSlug[b] ?? 0;
      return cb.compareTo(ca);
    });

  stdout.writeln('=== onboarding_stats: $path ===');
  stdout.writeln(
    'Total puzzles: $totalPuzzles  (unsolved by solveExplained: '
    '$unsolvedPuzzles)',
  );
  stdout.writeln('');

  stdout.writeln('Catalog presence (slug declared in puzzle):');
  stdout.writeln('  slug   #puz      %      solo   solo_cplx0  solo_cplx≤1');
  for (final slug in ordered) {
    final n = puzzlesWithSlug[slug] ?? 0;
    final pct = (n / totalPuzzles * 100).toStringAsFixed(1);
    final solo = puzzlesAlone[slug] ?? 0;
    final solo0 = puzzlesAloneCplx0[slug] ?? 0;
    final solo01 = puzzlesAloneCplx0or1[slug] ?? 0;
    stdout.writeln(
      '  ${slug.padRight(4)}   ${n.toString().padLeft(4)}  '
      '${pct.padLeft(5)}%   ${solo.toString().padLeft(4)}      '
      '${solo0.toString().padLeft(4)}        ${solo01.toString().padLeft(4)}',
    );
  }
  stdout.writeln('');

  stdout.writeln('Propagation steps by complexity tier (per slug):');
  stdout.writeln(
    '  slug   #puz_used  total   t0     t1     t2     t3     t4     t5    %t0',
  );
  final orderedByUse = allSlugs.toList()
    ..sort((a, b) {
      int sumA = 0, sumB = 0;
      stepsByTier[a]?.forEach((_, v) => sumA += v);
      stepsByTier[b]?.forEach((_, v) => sumB += v);
      return sumB.compareTo(sumA);
    });
  for (final slug in orderedByUse) {
    final tiers = stepsByTier[slug] ?? const <int, int>{};
    final used = puzzlesWithSlugUsed[slug] ?? 0;
    int total = 0;
    tiers.forEach((_, v) => total += v);
    if (total == 0) continue;
    final t0 = tiers[0] ?? 0;
    final t1 = tiers[1] ?? 0;
    final t2 = tiers[2] ?? 0;
    final t3 = tiers[3] ?? 0;
    final t4 = tiers[4] ?? 0;
    final t5 = tiers[5] ?? 0;
    final pct0 = total > 0 ? (t0 / total * 100).toStringAsFixed(1) : '0.0';
    stdout.writeln(
      '  ${slug.padRight(4)}   ${used.toString().padLeft(6)}    '
      '${total.toString().padLeft(5)}  '
      '${t0.toString().padLeft(5)}  '
      '${t1.toString().padLeft(5)}  '
      '${t2.toString().padLeft(5)}  '
      '${t3.toString().padLeft(5)}  '
      '${t4.toString().padLeft(5)}  '
      '${t5.toString().padLeft(5)}  '
      '${pct0.padLeft(5)}',
    );
  }

  // --- Phase coverage analysis ---
  // For each onboarding phase, count puzzles eligible by the phase
  // filter (declared rules ⊆ allowed) and split by whether they contain
  // the just-introduced slug. Implements §5 of docs/dev/onboarding.md.
  final phases = <({String name, Set<String> allowed, String? introducing})>[
    (name: 'P0  +FM     (FM only)', allowed: {'FM'}, introducing: 'FM'),
    (name: 'P1  +NC     ({FM,NC})', allowed: {'FM', 'NC'}, introducing: 'NC'),
    (
      name: 'P2  +PA     ({FM,PA,NC})',
      allowed: {'FM', 'PA', 'NC'},
      introducing: 'PA',
    ),
    (
      name: 'P3  +GS     ({FM,PA,GS,NC})',
      allowed: {'FM', 'PA', 'GS', 'NC'},
      introducing: 'GS',
    ),
    (
      name: 'P4  +DF     ({FM,PA,NC,DF})',
      allowed: {'FM', 'PA', 'NC', 'DF'},
      introducing: 'DF',
    ),
    (
      name: 'P5  +CC     ({FM,PA,NC,DF,CC})',
      allowed: {'FM', 'PA', 'NC', 'DF', 'CC'},
      introducing: 'CC',
    ),
  ];

  // Re-parse the catalog to extract declared slug sets per puzzle.
  final declaredPerPuzzle = <Set<String>>[];
  for (final line in lines) {
    final puzzle = Puzzle(line);
    final declared = <String>{};
    for (final c in puzzle.constraints) {
      final slug = c.serialize().split(':').first;
      if (slug.isEmpty || slug == 'TX') continue;
      declared.add(slug);
    }
    declaredPerPuzzle.add(declared);
  }

  stdout.writeln('');
  stdout.writeln('=== Phase coverage in $path ===');
  stdout.writeln(
    '  phase                          eligible  with_intro  refresh  '
    'avg_n_rules',
  );
  for (final phase in phases) {
    int eligible = 0;
    int withIntro = 0;
    int refresh = 0;
    int sumRules = 0;
    for (final declared in declaredPerPuzzle) {
      if (declared.isEmpty) continue;
      if (!declared.every(phase.allowed.contains)) continue;
      eligible++;
      sumRules += declared.length;
      if (phase.introducing != null && declared.contains(phase.introducing)) {
        withIntro++;
      } else {
        refresh++;
      }
    }
    final avgRules = eligible > 0
        ? (sumRules / eligible).toStringAsFixed(2)
        : '-';
    stdout.writeln(
      '  ${phase.name.padRight(30)}  '
      '${eligible.toString().padLeft(8)}  '
      '${withIntro.toString().padLeft(10)}  '
      '${refresh.toString().padLeft(7)}  '
      '${avgRules.toString().padLeft(10)}',
    );
  }
  stdout.writeln('  (with_intro = puzzles containing the slug being');
  stdout.writeln('   introduced; refresh = puzzles using only previously');
  stdout.writeln('   unlocked slugs. Target ratio in onboarding is 80/20.)');

  // --- Duo analysis ---
  for (final anchor in const ['FM', 'NC']) {
    final perPartner = duoCount[anchor] ?? const <String, int>{};
    if (perPartner.isEmpty) {
      stdout.writeln('');
      stdout.writeln('Duos with anchor=$anchor: none.');
      continue;
    }
    final partners = perPartner.keys.toList()
      ..sort((a, b) => (perPartner[b] ?? 0).compareTo(perPartner[a] ?? 0));

    stdout.writeln('');
    stdout.writeln(
      'Duos with anchor=$anchor (puzzles whose declared rules are exactly '
      '{$anchor, partner}):',
    );
    stdout.writeln(
      '  partner   #duo   cplx0  cplx≤1   partner_steps  t0   t1   t2   t3   t4   t5    %t0',
    );
    for (final partner in partners) {
      final n = perPartner[partner] ?? 0;
      final n0 = duoCplx0[anchor]?[partner] ?? 0;
      final n01 = duoCplx0or1[anchor]?[partner] ?? 0;
      final hist = partnerTierHist[anchor]?[partner] ?? const <int, int>{};
      int tot = 0;
      hist.forEach((_, v) => tot += v);
      final t0 = hist[0] ?? 0;
      final t1 = hist[1] ?? 0;
      final t2 = hist[2] ?? 0;
      final t3 = hist[3] ?? 0;
      final t4 = hist[4] ?? 0;
      final t5 = hist[5] ?? 0;
      final pct0 = tot > 0 ? (t0 / tot * 100).toStringAsFixed(1) : '0.0';
      stdout.writeln(
        '  ${partner.padRight(6)}  ${n.toString().padLeft(4)}  '
        '${n0.toString().padLeft(5)}  ${n01.toString().padLeft(5)}    '
        '${tot.toString().padLeft(8)}     '
        '${t0.toString().padLeft(3)}  '
        '${t1.toString().padLeft(3)}  '
        '${t2.toString().padLeft(3)}  '
        '${t3.toString().padLeft(3)}  '
        '${t4.toString().padLeft(3)}  '
        '${t5.toString().padLeft(3)}   '
        '${pct0.padLeft(5)}',
      );
    }
  }
}
