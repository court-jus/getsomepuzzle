import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/path.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

/// Unit tests for `assignColors`, the colour-assignment logic of the
/// path-based pre-fill. As in `prefill_sy_test.dart`, the stochastic pipeline
/// (`preFillPath`) is not run end-to-end; only the deterministic colour logic
/// is, swept over seeds so every random branch is hit.
void main() {
  // The dominant LT constraint is colour-blind beyond its own colour, so a
  // domain-2 path puzzle must never leak a third colour — otherwise the
  // exported line would falsely claim domain 3. This locks that invariant for
  // L=2 and checks both Bernoulli sub-cases remain reachable.
  test('domain 2, L=2: palette stays black/white, both sub-cases occur', () {
    var sawSame = false;
    var sawDifferent = false;
    for (int seed = 0; seed < 100; seed++) {
      final c = assignColors(['A', 'B'], defaultDomain, 0.5, Random(seed));
      expect(c.values, everyElement(isIn(defaultDomain)));
      if (c['A'] == c['B']) {
        sawSame = true;
      } else {
        sawDifferent = true;
      }
    }
    // Same-colour (hard separation) and different-colour must both be
    // reachable; collapsing to one would silently kill the difficulty knob.
    expect(sawSame, isTrue);
    expect(sawDifferent, isTrue);
  });

  // With ≥3 letters in 2 colours the historical pigeonhole branch is reached
  // (exercised for the first time now that path-based varies L). The
  // regression we lock is purely chromatic: still no third colour.
  test('domain 2, L>=3: never emits a third colour', () {
    for (int seed = 0; seed < 100; seed++) {
      final c = assignColors(
        ['A', 'B', 'C', 'D'],
        defaultDomain,
        0.5,
        Random(seed),
      );
      expect(c.values, everyElement(isIn(defaultDomain)));
    }
  });

  // Core 3-colour guarantee: with L == |domain| every colour is owned by
  // exactly one letter, so the routed solution uses all three and
  // `autoShrinkDomain` cannot relabel it back to domain 2.
  test('domain 3, L=3: every colour is covered exactly once', () {
    for (int seed = 0; seed < 200; seed++) {
      final c = assignColors(['A', 'B', 'C'], fullDomain, 0.5, Random(seed));
      expect(c.values.toSet(), fullDomain.toSet());
    }
  });

  // "Shared colours": with L > |domain| every colour is still covered
  // (genuine 3-colour) AND exactly one colour is shared by two letters — the
  // hard same-colour separation case that gives the scenario its richness.
  test('domain 3, L=4: full coverage plus exactly one shared colour', () {
    for (int seed = 0; seed < 200; seed++) {
      final c = assignColors(
        ['A', 'B', 'C', 'D'],
        fullDomain,
        0.5,
        Random(seed),
      );
      expect(c.values.toSet(), fullDomain.toSet());
      // 4 letters across 3 distinct colours ⇒ exactly one colour used twice.
      expect(c.values.toSet(), hasLength(3));
      expect(c, hasLength(4));
    }
  });

  // The shuffle must not bias which colour gets doubled, otherwise one colour
  // would systematically carry the hard same-colour separation case.
  test('domain 3, L=4: any colour can be the shared one', () {
    final doubled = <CellValue>{};
    for (int seed = 0; seed < 200; seed++) {
      final c = assignColors(
        ['A', 'B', 'C', 'D'],
        fullDomain,
        0.5,
        Random(seed),
      );
      final counts = <CellValue, int>{};
      for (final v in c.values) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
      counts.forEach((color, n) {
        if (n == 2) doubled.add(color);
      });
    }
    expect(doubled, fullDomain.toSet());
  });

  // `dominantCause` drives the split of the catch-all `pathPrefillFailed`
  // reject into actionable reasons, so its tie/empty behaviour must be
  // deterministic. We seed `causeCounts` directly (public for this reason).
  group('PathPrefillStats.dominantCause', () {
    test('is null when no failure was recorded (e.g. first-try success)', () {
      expect(PathPrefillStats().dominantCause, isNull);
    });

    test('is the only recorded cause when one dominates', () {
      final s = PathPrefillStats();
      s.causeCounts[PathFailCause.routingTimeout] = 7;
      s.causeCounts[PathFailCause.placement] = 2;
      expect(s.dominantCause, PathFailCause.routingTimeout);
    });

    test('breaks ties toward the first cause that reached the max', () {
      // Equal counts: the earlier-inserted key wins (map insertion order),
      // making the classification reproducible across runs.
      final s = PathPrefillStats();
      s.causeCounts[PathFailCause.bipartite] = 3;
      s.causeCounts[PathFailCause.routingInfeasible] = 3;
      expect(s.dominantCause, PathFailCause.bipartite);
    });
  });
}
