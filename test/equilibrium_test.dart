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

    test('ntypes profile reads from kTargetNTypesProfile', () {
      expect(targetShare(Axis.ntypes, 1, 0), 0.25);
      expect(targetShare(Axis.ntypes, 2, 0), 0.30);
      expect(targetShare(Axis.ntypes, 6, 0), 0.09);
      // 7+ bucket
      expect(targetShare(Axis.ntypes, 7, 0), kTargetSevenPlusShare);
      expect(targetShare(Axis.ntypes, 99, 0), kTargetSevenPlusShare);
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
}
