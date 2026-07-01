import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sy.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

/// Unit tests for `pickIslandColors`, the colour-assignment logic of the
/// SY-based pre-fill. Per project convention the stochastic pipeline
/// itself (`preFillSy`) is not run end-to-end in tests; only its
/// deterministic colour logic is — over a sweep of seeds so every random
/// branch (bg choice, per-island draw, diversity recolouring) is hit.
void main() {
  test('2-colour domain: islands take the single non-bg colour', () {
    for (int seed = 0; seed < 50; seed++) {
      final r = pickIslandColors(2, defaultDomain, Random(seed));
      expect(defaultDomain, contains(r.bg));
      // With one fg choice only, every island is the opposite of bg —
      // the classic bicolour bg/fg dichotomy must be preserved.
      final fg = defaultDomain.firstWhere((c) => c != r.bg);
      expect(r.islandColors, everyElement(fg));
    }
  });

  test('3-colour domain: islands avoid bg and span >= 2 colours', () {
    for (int seed = 0; seed < 200; seed++) {
      final r = pickIslandColors(2, fullDomain, Random(seed));
      expect(fullDomain, contains(r.bg));
      // No island may take the background colour (it would vanish).
      expect(r.islandColors, isNot(contains(r.bg)));
      // Diversity guarantee: with >= 2 islands the puzzle must use two
      // distinct island colours, otherwise it is functionally 2-colour
      // and would be auto-shrunk at export (wasted domain-3 attempt).
      expect(
        r.islandColors.toSet().length,
        greaterThanOrEqualTo(2),
        reason: 'seed $seed produced monochrome islands',
      );
    }
  });

  test('3-colour domain, single island: no diversity to enforce', () {
    // The guarantee only applies from 2 islands up; a lone island just
    // needs a valid non-bg colour.
    for (int seed = 0; seed < 50; seed++) {
      final r = pickIslandColors(1, fullDomain, Random(seed));
      expect(r.islandColors, hasLength(1));
      expect(fullDomain, contains(r.islandColors.single));
      expect(r.islandColors.single, isNot(r.bg));
    }
  });

  test('3-colour domain: every colour can be the background', () {
    // bg is drawn uniformly over the whole domain — purple included.
    // A regression here (e.g. bg restricted to black/white) would pass
    // the other tests silently.
    final seen = <CellValue>{};
    for (int seed = 0; seed < 100; seed++) {
      seen.add(pickIslandColors(2, fullDomain, Random(seed)).bg);
    }
    expect(seen, fullDomain.toSet());
  });
}
