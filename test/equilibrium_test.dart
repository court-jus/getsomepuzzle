import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/equilibrium.dart';

void main() {
  group('EquilibriumStats.fromLines', () {
    // Real-format line with 2 types (FM and PA): exercises the pair path.
    const twoTypeLine =
        'v2_12_4x4_2210000010000000_FM:11;PA:0.left_1:1212121212121212_2';
    // 3-type line: should NOT contribute to pairCounts (we don't expand 3 → C(3,2)).
    const threeTypeLine =
        'v2_12_4x5_22100000100000002221_FM:11;PA:0.left;GS:1.2_1:11221122112211221122_3';
    // Comment and empty are skipped.
    const skipped = ['# a comment', '', '   '];

    test('counts slugs once per puzzle and tracks size + ntypes', () {
      final stats = EquilibriumStats.fromLines([
        twoTypeLine,
        threeTypeLine,
        ...skipped,
      ]);
      expect(stats.totalPuzzles, 2);
      // Both puzzles use FM and PA → each appears in 2 puzzles.
      expect(stats.slugCounts['FM'], 2);
      expect(stats.slugCounts['PA'], 2);
      expect(stats.slugCounts['GS'], 1);
      // ntypes: one 2-type, one 3-type.
      expect(stats.ntypesCounts[2], 1);
      expect(stats.ntypesCounts[3], 1);
      // sizes are recorded per puzzle.
      expect(stats.sizeCounts[(4, 4)], 1);
      expect(stats.sizeCounts[(4, 5)], 1);
    });

    test('pair counts only include puzzles with exactly 2 types', () {
      final stats = EquilibriumStats.fromLines([twoTypeLine, threeTypeLine]);
      expect(stats.pairCounts.length, 1);
      // Pair is sorted lexicographically.
      expect(stats.pairCounts[('FM', 'PA')], 1);
      expect(stats.totalPairs, 1);
    });

    test('skips malformed lines silently', () {
      final stats = EquilibriumStats.fromLines([
        'not_a_puzzle', // only 1 field
        'v2_12_invalid_xxx_FM:11', // dims do not parse as WxH
        'v2_12_4xZ_xxx_FM:11', // height is non-numeric
        'v2_12_4x4_xxxx_', // empty constraint field
      ]);
      expect(stats.totalPuzzles, 0);
    });
  });

  group('EquilibriumStats.withPuzzle', () {
    test('increments slug, ntypes, size and pair counts', () {
      var stats = EquilibriumStats.empty();
      stats = stats.withPuzzle(slugs: {'FM', 'PA'}, width: 4, height: 4);
      expect(stats.totalPuzzles, 1);
      expect(stats.slugCounts['FM'], 1);
      expect(stats.ntypesCounts[2], 1);
      expect(stats.sizeCounts[(4, 4)], 1);
      // Two types → contributes to the pair axis.
      expect(stats.pairCounts[('FM', 'PA')], 1);

      stats = stats.withPuzzle(slugs: {'GS'}, width: 4, height: 4);
      expect(stats.totalPuzzles, 2);
      expect(stats.ntypesCounts[1], 1);
      // Single-type puzzle does NOT add to pair counts.
      expect(stats.totalPairs, 1);
    });
  });

  group('targetShare', () {
    test('uniform axes divide 1 by category count', () {
      expect(targetShare(Axis.slug, '', 4), closeTo(0.25, 1e-9));
      expect(targetShare(Axis.size, '', 10), closeTo(0.10, 1e-9));
      expect(targetShare(Axis.pair, '', 0), 0.0); // no candidates → 0
    });

    test('ntypes profile reads from kTargetNTypesProfile (1..5 only)', () {
      expect(targetShare(Axis.ntypes, 1, 0), 0.25);
      expect(targetShare(Axis.ntypes, 2, 0), 0.30);
      expect(targetShare(Axis.ntypes, 5, 0), 0.10);
      // 6+ reliquat bucket has share 0 — never pushed.
      expect(targetShare(Axis.ntypes, 6, 0), 0.0);
      expect(targetShare(Axis.ntypes, 99, 0), 0.0);
    });
  });

  group('TargetUniverse', () {
    test('clamps size range to [kMinSide, kMaxSide]', () {
      final u = TargetUniverse(
        allowedSlugs: ['FM', 'SH'],
        minWidth: 1, // should be clamped up to kMinSide
        maxWidth: 12, // should be clamped down to kMaxSide
        minHeight: 4,
        maxHeight: 5,
      );
      expect(u.allowedSlugs, ['FM', 'SH']);
      // Width: 3..10 = 8 values; height: 4..5 = 2 values; total = 16.
      expect(u.allowedSizes.length, 8 * 2);
      expect(u.allowedSizes.contains((kMinSide, 4)), isTrue);
      expect(u.allowedSizes.contains((kMaxSide, 5)), isTrue);
    });

    test('allowedPairs are sorted and unordered (a<b only)', () {
      final u = TargetUniverse(
        allowedSlugs: ['PA', 'FM', 'GS'],
        minWidth: 4,
        maxWidth: 4,
        minHeight: 4,
        maxHeight: 4,
      );
      // 3 slugs → C(3,2) = 3 pairs, all sorted lexicographically.
      expect(u.allowedPairs, [('FM', 'GS'), ('FM', 'PA'), ('GS', 'PA')]);
    });
  });

  group('pickTarget', () {
    // 6 slugs (gap each ≤ 1/6 ≈ 0.167 < 0.30) and 9 sizes (3x3..5x5,
    // gap each ≤ 1/9 ≈ 0.111 < 0.30) so ntypes=2 (target 0.30) is the
    // dominant gap on an empty corpus.
    final universe = TargetUniverse(
      allowedSlugs: ['FM', 'PA', 'GS', 'SY', 'QA', 'CC'],
      minWidth: 3,
      maxWidth: 5,
      minHeight: 3,
      maxHeight: 5,
    );

    test('on an empty corpus, picks the bin with highest expected share', () {
      // total=0 → observed=0 → gap = expected. With this universe,
      // ntypes=2 (target 0.30) is the maximum.
      final t = pickTarget(EquilibriumStats.empty(), universe);
      expect(t, isA<NTypesTarget>());
      expect((t as NTypesTarget).n, 2);
    });

    test('over-represented categories are ignored (gap clamped to 0)', () {
      // 100 single-FM 3x3 puzzles. Now FM is 100% over, ntypes=1 is 100% over,
      // 3x3 is 100% over. Most under-represented should still come from one
      // of the untouched slugs / sizes / ntypes bins.
      var stats = EquilibriumStats.empty();
      for (int i = 0; i < 100; i++) {
        stats = stats.withPuzzle(slugs: {'FM'}, width: 3, height: 3);
      }
      final t = pickTarget(stats, universe)!;
      // Expected absolute leader: ntypes=2 (gap 0.30, no other category beats
      // it given uniform 1/6 ≈ 0.167 on slug, 1/9 ≈ 0.111 on size).
      expect(t, isA<NTypesTarget>());
      expect((t as NTypesTarget).n, 2);
    });

    test('pair axis bootstraps when no 2-type puzzle exists yet', () {
      // No 2-type puzzles → pair gaps = uniform expected.
      // Need a universe where the pair uniform expected dominates ntypes=2 (0.30):
      // C(3, 2) = 3 pairs → 1/3 ≈ 0.333. Use a 3-slug sub-universe.
      final small = TargetUniverse(
        allowedSlugs: ['FM', 'PA', 'GS'],
        minWidth: 4,
        maxWidth: 4,
        minHeight: 4,
        maxHeight: 4,
      );
      var stats = EquilibriumStats.empty();
      stats = stats.withPuzzle(slugs: {'FM'}, width: 4, height: 4);
      stats = stats.withPuzzle(slugs: {'PA'}, width: 4, height: 4);
      stats = stats.withPuzzle(slugs: {'GS'}, width: 4, height: 4);
      // After 3 single-type puzzles: slugs balanced, size balanced, but the
      // pair axis is still completely empty → 1/3 gap on each pair, beating
      // ntypes=2 (0.30) by a hair.
      final ranked = rankTargets(stats, small);
      expect(ranked.first.target, isA<PairTarget>());
    });

    test('blacklist filters out the requested target', () {
      final stats = EquilibriumStats.empty();
      // Without blacklist: top is ntypes=2.
      final top = pickTarget(stats, universe)!;
      expect(top, isA<NTypesTarget>());
      expect((top as NTypesTarget).n, 2);
      // Blacklist ntypes=2 → a different target wins.
      final next = pickTarget(
        stats,
        universe,
        blacklistedKeys: {const NTypesTarget(2).key},
      );
      expect(next!.key, isNot(equals(top.key)));
    });

    test('returns null when every gap is zero', () {
      // Build a fictional stats where every axis matches its profile.
      // Easiest: use a totalPuzzles count whose distribution exactly matches
      // ntypes profile and uniform on slug/size, with 0 on pair (we can't
      // make pair gap 0 from observation alone since target is 1/3 each).
      // Instead: blacklist every key — pickTarget should return null.
      final stats = EquilibriumStats.empty();
      final blackAll = <String>{};
      for (final r in rankTargets(stats, universe)) {
        blackAll.add(r.target.key);
      }
      expect(pickTarget(stats, universe, blacklistedKeys: blackAll), isNull);
    });
  });

  group('sizeTargetShare', () {
    final universe = TargetUniverse(
      allowedSlugs: ['FM', 'PA'],
      minWidth: 4,
      maxWidth: 7,
      minHeight: 4,
      maxHeight: 8,
    );

    test('sums to 1.0 across the universe', () {
      double total = 0.0;
      for (final (w, h) in universe.allowedSizes) {
        total += sizeTargetShare(w, h, universe);
      }
      expect(total, closeTo(1.0, 1e-9));
    });

    test('peaks near area=20 and decreases on both sides', () {
      // (4,5) and (5,4) both have area 20 → identical share, and that share
      // should dominate the rest in this universe.
      final sharePeak = sizeTargetShare(4, 5, universe);
      expect(sharePeak, closeTo(sizeTargetShare(5, 4, universe), 1e-9));
      // Move further from the peak in either direction → share shrinks.
      expect(sizeTargetShare(4, 4, universe), lessThan(sharePeak)); // area 16
      expect(sizeTargetShare(7, 7, universe), lessThan(sharePeak)); // area 49
      // Right tail (σ_R=15) is wider than left (σ_L=8) so far-right values
      // shouldn't collapse to 0 too fast — but should still be less than
      // a same-distance left value.
      expect(sizeTargetShare(7, 8, universe), greaterThan(0)); // area 56
    });

    test(
      'aggregated bucket shares favor small/medium over large (per Option B)',
      () {
        double small = 0.0, medium = 0.0, large = 0.0;
        for (final (w, h) in universe.allowedSizes) {
          final s = sizeTargetShare(w, h, universe);
          final area = w * h;
          if (area <= 20) {
            small += s;
          } else if (area <= 40) {
            medium += s;
          } else {
            large += s;
          }
        }
        // Skew check: smalls + medium should clearly dominate larges.
        expect(small + medium, greaterThan(large * 5));
        // And smalls should outweigh larges (the whole point of Option B).
        expect(small, greaterThan(large));
      },
    );
  });

  group('pickWeightedSize', () {
    final universe = TargetUniverse(
      allowedSlugs: ['FM', 'PA'],
      minWidth: 3,
      maxWidth: 4,
      minHeight: 3,
      maxHeight: 4,
    );

    test('returns null when no size has a positive gap', () {
      // Single-size universe → target share = 1.0 for that size. One puzzle
      // saturates the bin exactly → gap = 0 everywhere → null.
      final solo = TargetUniverse(
        allowedSlugs: ['FM'],
        minWidth: 4,
        maxWidth: 4,
        minHeight: 4,
        maxHeight: 4,
      );
      var stats = EquilibriumStats.empty();
      stats = stats.withPuzzle(slugs: {'FM'}, width: 4, height: 4);
      expect(pickWeightedSize(stats, solo, Random(0)), isNull);
    });

    test('biased toward positive-gap bins on a sample of 1000 draws', () {
      // 100 puzzles all on (3,3): that bin is heavily over-represented; the
      // other three each have a positive gap (their target share is
      // unobserved). With Option B's asymmetric Gaussian on area, (4,4)
      // (area 16, closest to peak 20) carries the largest gap, so it gets
      // the most picks — but all three still get sampled at least once.
      var stats = EquilibriumStats.empty();
      for (int i = 0; i < 100; i++) {
        stats = stats.withPuzzle(slugs: {'FM'}, width: 3, height: 3);
      }
      final rng = Random(42);
      final counts = <(int, int), int>{};
      for (int i = 0; i < 1000; i++) {
        final picked = pickWeightedSize(stats, universe, rng);
        if (picked != null) counts[picked] = (counts[picked] ?? 0) + 1;
      }
      // (3,3) is saturated → never returned.
      expect(counts[(3, 3)] ?? 0, 0);
      // The other three have positive gaps, all eligible.
      expect(counts[(3, 4)] ?? 0, greaterThan(0));
      expect(counts[(4, 3)] ?? 0, greaterThan(0));
      expect(counts[(4, 4)] ?? 0, greaterThan(0));
      // (4,4) has the biggest gap → most-picked.
      final cMax = counts[(4, 4)] ?? 0;
      expect(cMax, greaterThan(counts[(3, 4)] ?? 0));
      expect(cMax, greaterThan(counts[(4, 3)] ?? 0));
    });
  });

  group('pickWeightedSlugs', () {
    final universe = TargetUniverse(
      allowedSlugs: ['FM', 'PA', 'GS', 'SY'],
      minWidth: 4,
      maxWidth: 4,
      minHeight: 4,
      maxHeight: 4,
    );

    test('always returns exactly n slugs (clamped to nSlugs)', () {
      // No corpus → every slug has gap 0. The function must still return
      // n slugs by filling with random uniform picks.
      final stats = EquilibriumStats.empty();
      for (final n in [0, 1, 2, 4, 99]) {
        final picked = pickWeightedSlugs(stats, universe, n, Random(n));
        final expected = n > 4 ? 4 : n;
        expect(picked.length, expected);
        expect(picked.every((s) => universe.allowedSlugs.contains(s)), isTrue);
      }
    });

    test('biases toward under-represented slugs', () {
      // Saturate FM and PA; GS and SY have positive gaps. Asking for 1
      // slug should produce GS or SY almost every time.
      var stats = EquilibriumStats.empty();
      for (int i = 0; i < 100; i++) {
        stats = stats.withPuzzle(slugs: {'FM', 'PA'}, width: 4, height: 4);
      }
      final rng = Random(7);
      int undersampled = 0;
      for (int i = 0; i < 200; i++) {
        final picked = pickWeightedSlugs(stats, universe, 1, rng);
        if (picked.contains('GS') || picked.contains('SY')) undersampled++;
      }
      // Heuristic: at least 95% of draws should hit the under-represented set.
      // (FM/PA gaps are ≤ 0 → never picked by the weighted phase, and the
      // random fill phase only kicks in when fewer than n positive-gap
      // candidates exist.)
      expect(undersampled, greaterThan(190));
    });
  });

  group('pickWarmupConfig', () {
    final allowed = const ['FM', 'PA', 'GS', 'SY', 'QA'];

    test('clamps grid sides to kWarmupMaxWidth/Height', () {
      final rng = Random(0);
      // User asks for 3..10 / 3..10 — warm-up clamps the upper end.
      for (int i = 0; i < 50; i++) {
        final wc = pickWarmupConfig(
          minWidth: 3,
          maxWidth: 10,
          minHeight: 3,
          maxHeight: 10,
          baseAllowedSlugs: allowed,
          baseRequired: const {},
          rng: rng,
        );
        expect(wc.width, inInclusiveRange(3, kWarmupMaxWidth));
        expect(wc.height, inInclusiveRange(3, kWarmupMaxHeight));
      }
    });

    test(
      'falls back to user min when it exceeds the cap (still respects --min-width)',
      () {
        // User explicitly asked for ≥7 wide grids — we can't honor the warm-up
        // cap, so the floor wins (8 in this case is locked).
        final rng = Random(1);
        final wc = pickWarmupConfig(
          minWidth: 8,
          maxWidth: 8,
          minHeight: 8,
          maxHeight: 8,
          baseAllowedSlugs: allowed,
          baseRequired: const {},
          rng: rng,
        );
        expect(wc.width, 8);
        expect(wc.height, 8);
      },
    );

    test(
      'pool size is drawn from kWarmupNTypesPool when baseRequired is empty',
      () {
        final rng = Random(2);
        final seen = <int>{};
        for (int i = 0; i < 200; i++) {
          final wc = pickWarmupConfig(
            minWidth: 3,
            maxWidth: 5,
            minHeight: 3,
            maxHeight: 5,
            baseAllowedSlugs: allowed,
            baseRequired: const {},
            rng: rng,
          );
          // Pool is [1, 1, 2, 2] → only 1 or 2 ever appear in the chosen set.
          expect(kWarmupNTypesPool, contains(wc.allowedSlugs.length));
          // Warm-up makes preferredSlugs == allowedSlugs (both = chosen set).
          expect(wc.preferredSlugs, equals(wc.allowedSlugs));
          seen.add(wc.allowedSlugs.length);
        }
        // Both 1 and 2 should appear with random seed across 200 draws.
        expect(seen, containsAll([1, 2]));
      },
    );

    test('respects baseRequired even when it exceeds the warm-up pool', () {
      // Three required slugs — pool max is 2 — must still include all 3 in
      // the chosen set so SH prefill / sort priority work as expected.
      final rng = Random(3);
      final wc = pickWarmupConfig(
        minWidth: 3,
        maxWidth: 5,
        minHeight: 3,
        maxHeight: 5,
        baseAllowedSlugs: allowed,
        baseRequired: const {'FM', 'PA', 'GS'},
        rng: rng,
      );
      expect(wc.allowedSlugs.length, 3);
      expect(wc.allowedSlugs.containsAll({'FM', 'PA', 'GS'}), isTrue);
      expect(wc.preferredSlugs, equals(wc.allowedSlugs));
    });

    test('drops baseRequired entries that conflict with the allowed set', () {
      // 'XX' is not in the allowed list — it must NOT inflate the pool size.
      final rng = Random(4);
      final wc = pickWarmupConfig(
        minWidth: 3,
        maxWidth: 5,
        minHeight: 3,
        maxHeight: 5,
        baseAllowedSlugs: allowed,
        baseRequired: const {'XX', 'YY'},
        rng: rng,
      );
      // baseRequired reduces to empty after intersection — pool decides size.
      expect(kWarmupNTypesPool, contains(wc.allowedSlugs.length));
      expect(wc.allowedSlugs.contains('XX'), isFalse);
      expect(wc.allowedSlugs.contains('YY'), isFalse);
    });
  });
}
