import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';

import 'helpers/make_puzzle.dart';

/// Shorthand for `MajorityConstraint('r0.c0.r1.c1.color')`.
MajorityConstraint mj(String params) => MajorityConstraint(params);

void main() {
  group('MajorityConstraint.verify', () {
    // All tests below build a 3-row × 2-col puzzle via makePuzzle, so MJ:0.0.2.1.1
    // covers the entire 6-cell grid (zoneSize=6, target=4).
    test('complete puzzle with majority holds → true', () {
      // Cells [1,2,1,2,1,1]: color 1 = 4 (cells 0,2,4,5), color 2 = 2 (cells 1,3) → 4 >= 4
      final p = makePuzzle('12\n12\n11');
      expect(mj('0.0.2.1.1').verify(p), isTrue);
    });

    test('complete puzzle with tie (even zone) → false', () {
      // Cells [1,2,1,2,1,2]: color 1 = 3, color 2 = 3 → 3 < 4
      final p = makePuzzle('12\n12\n12');
      expect(mj('0.0.2.1.1').verify(p), isFalse);
    });

    test('complete puzzle with minority → false', () {
      // Cells [2,2,2,2,2,1]: color 1 = 1 (cell 5), color 2 = 5 → 1 < 4
      // (distinct from the tie case above: target is strictly minority, not equal).
      final p = makePuzzle('22\n22\n21');
      expect(mj('0.0.2.1.1').verify(p), isFalse);
    });

    test('incomplete with target still reachable → true', () {
      // Cells [1,0,0,2,1,0]: color 1 = 2 (cells 0,4), color 2 = 1 (cell 3), free = 3
      // 2+3 = 5 >= 4 reachable, opposite 1 <= 2 not blocking
      final p = makePuzzle('10\n02\n10');
      expect(mj('0.0.2.1.1').verify(p), isTrue);
    });

    test('incomplete with target unreachable → false', () {
      // Cells [1,2,0,2,2,2]: color 1 = 1, color 2 = 4, free = 1 (cell 2)
      // 1+1 = 2 < 4 → unreachable
      final p = makePuzzle('12\n02\n22');
      expect(mj('0.0.2.1.1').verify(p), isFalse);
    });

    test('incomplete with opposite already blocking → false', () {
      // Cells [1,2,1,2,0,2]: color 1 = 2 (cells 0,2), color 2 = 3 (cells 1,3,5), free = 1
      // oppositeCount = 3 > zoneSize - target = 2 → blocking
      final p = makePuzzle('12\n12\n02');
      expect(mj('0.0.2.1.1').verify(p), isFalse);
    });

    test('incomplete with zero target cells still reachable → true', () {
      // All free, no cells placed yet → reachable
      final p = makePuzzle('00\n00\n00');
      expect(mj('0.0.2.1.1').verify(p), isTrue);
    });
  });

  group('MajorityConstraint.apply', () {
    // Same 3-row × 2-col layout: zone covers the whole 6-cell grid (target=4).
    test('too much opposite → isImpossible', () {
      // Cells [1,2,1,2,0,2]: color 1 = 2, color 2 = 3, free = 1
      // oppositeCount = 3 > zoneSize - target = 2 → isImpossible
      final p = makePuzzle('12\n12\n02');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('not enough space to grow → isImpossible', () {
      // Cells [1,2,0,2,2,2]: color 1 = 1 (cell 0), color 2 = 4, free = 1 (cell 2)
      // currentCount + freeCount = 1+1 = 2 < 4 → isImpossible
      final p = makePuzzle('12\n02\n22');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('just enough space → force target color on first free cell', () {
      // Cells [1,0,0,2,0,2]: color 1 = 1 (cell 0), color 2 = 2 (cells 3,5), free = 3 (cells 1,2,4)
      // 1+3 = 4 == target → force first free (cell 1) to color 1
      final p = makePuzzle('10\n02\n02');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNotNull);
      final m = move!;
      expect(m.value, 1);
      expect(m.idx, 1);
      expect(m.complexity, 0);
    });

    test('more than enough space → no deduction', () {
      // Cells [1,0,0,0,0,0]: color 1 = 1, color 2 = 0, free = 5
      // 1+5 = 6 > 4, oppositeCount = 0 <= 2 → no constraint fires
      final p = makePuzzle('10\n00\n00');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNull);
    });

    test('no free cells → null', () {
      final p = makePuzzle('12\n12\n12');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNull);
    });

    test('intermediate state with slack on both sides → null', () {
      // Cells [1,2,1,0,0,0]: color 1 = 2 (cells 0,2), color 2 = 1 (cell 1), free = 3 (cells 3,4,5)
      // 2+3 = 5 > 4, oppositeCount = 1 <= 2 → neither condition fires
      final p = makePuzzle('12\n10\n00');
      final move = mj('0.0.2.1.1').apply(p);
      expect(move, isNull);
    });
  });

  group('MajorityConstraint.isCompleteFor', () {
    test('not complete when zone has empty cells', () {
      final p = makePuzzle('10\n10\n10');
      expect(mj('0.0.2.1.1').isCompleteFor(p), isFalse);
    });

    test('complete when zone is full and majority holds', () {
      final p = makePuzzle('11\n11\n11');
      expect(mj('0.0.2.1.1').isCompleteFor(p), isTrue);
    });

    test('not complete when zone is full but verify fails', () {
      // Tie → verify fails → isCompleteFor false
      final p = makePuzzle('12\n12\n12');
      expect(mj('0.0.2.1.1').isCompleteFor(p), isFalse);
    });

    test(
      'complete on target zone even if other cells outside zone are empty',
      () {
        // 3x3 grid, zone is first 2 columns. Column 2 (outside zone) is empty.
        // Zone itself is full with majority.
        final p = makePuzzle('110\n110\n110');
        expect(mj('0.0.2.1.1').isCompleteFor(p), isTrue);
      },
    );
  });

  group('MajorityConstraint.serialize', () {
    test('round-trip', () {
      final c = mj('0.0.2.1.1');
      expect(c.serialize(), 'MJ:0.0.2.1.1');
      expect(c.r0, 0);
      expect(c.c0, 0);
      expect(c.r1, 2);
      expect(c.c1, 1);
      expect(c.targetColor, 1);
    });

    test('odd-sized zone round-trip', () {
      // 3x3 zone (odd size), color 2
      final c = mj('0.0.2.2.2');
      expect(c.serialize(), 'MJ:0.0.2.2.2');
      expect(c.r0, 0);
      expect(c.r1, 2);
      expect(c.c0, 0);
      expect(c.c1, 2);
      expect(c.targetColor, 2);
      // 3x3 = 9 cells, target = 9~/2+1 = 5
      expect(c.target, 5);
    });
  });

  group('MajorityConstraint.rotated', () {
    test('90° CW rotation on 3x3 grid', () {
      // MJ:0.0.2.1.1 on 3x3 (rows 0-2, cols 0-1).
      // After 90° CW: rows become cols, cols become (height-1-row).
      // r0=0,c0=0 → new: r=c0=0, c=height-1-r0=2
      // r1=2,c1=1 → new: r=c1=1, c=height-1-r1=0
      // So: r0'=0, c0'=0, r1'=1, c1'=2 → MJ:0.0.1.2.1
      final c = mj('0.0.2.1.1');
      final rotated = c.rotated(3, 3) as MajorityConstraint;
      expect(rotated.serialize(), 'MJ:0.0.1.2.1');
      expect(rotated.targetColor, 1);
    });
  });

  group('MajorityConstraint.generateAllParameters', () {
    test('correct count for 3x3 grid', () {
      // 3x3 grid: only 2×2 zones survive.
      // Positions: 4 (top-left corners), × 2 colors = 8.
      // Single row/col zones (>3), 2×3/3×2 (>60%), and full grid are excluded.
      final params = MajorityConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      expect(params.length, 8);
    });

    test('correct count for 2x2 grid', () {
      // 2x2 grid: every rectangle is area < 3 or the full grid → 0
      final params = MajorityConstraint.generateAllParameters(2, 2, [
        1,
        2,
      ], null);
      expect(params.length, 0);
    });

    test('zones have at least 3 cells', () {
      final params = MajorityConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      for (final p in params) {
        final c = MajorityConstraint(p);
        expect(c.zoneSize, greaterThanOrEqualTo(3));
        expect(c.zoneSize, lessThan(9));
        expect(c.targetColor, anyOf(1, 2));
      }
    });

    test('full grid excluded', () {
      final params = MajorityConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      for (final p in params) {
        final c = MajorityConstraint(p);
        expect(c.zoneSize, lessThan(9));
      }
    });

    test('single row excluded', () {
      final params = MajorityConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      for (final p in params) {
        final c = MajorityConstraint(p);
        expect(c.r1 - c.r0 + 1, greaterThan(1));
      }
    });

    test('single column excluded', () {
      final params = MajorityConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      for (final p in params) {
        final c = MajorityConstraint(p);
        expect(c.c1 - c.c0 + 1, greaterThan(1));
      }
    });

    test('zones > 60% of grid excluded', () {
      // On a 4×4 grid, a 3×3 zone (9 cells) = 56% → kept.
      // A 3×4 zone (12 cells) = 75% → excluded.
      final params = MajorityConstraint.generateAllParameters(4, 4, [
        1,
        2,
      ], null);
      for (final p in params) {
        final c = MajorityConstraint(p);
        expect(c.zoneSize, lessThanOrEqualTo((16 * 0.6).floor()));
      }
    });

    test('sweet spots kept on 4x4 grid', () {
      // 4×4 grid: 2×2, 2×3, 3×2, 3×3 should all survive.
      final params = MajorityConstraint.generateAllParameters(4, 4, [
        1,
        2,
      ], null);
      final zoneSizes = params
          .map((p) => MajorityConstraint(p).zoneSize)
          .toSet();
      expect(zoneSizes, containsAll([4, 6, 9]));
    });
  });

  group('MajorityConstraint.target calculation', () {
    test('even-sized zone', () {
      // 2x2 = 4 cells, target = 4~/2+1 = 3
      final c = mj('0.0.1.1.1');
      expect(c.zoneSize, 4);
      expect(c.target, 3);
    });

    test('odd-sized zone', () {
      // 3x3 = 9 cells, target = 9~/2+1 = 5
      final c = mj('0.0.2.2.1');
      expect(c.zoneSize, 9);
      expect(c.target, 5);
    });

    test('single column', () {
      // 3x1 = 3 cells, target = 3~/2+1 = 2
      final c = mj('0.0.2.0.1');
      expect(c.zoneSize, 3);
      expect(c.target, 2);
    });
  });
}
