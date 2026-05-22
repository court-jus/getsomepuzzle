import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('ChainConstraint.verify', () {
    test('complete grid with a left-right path → valid', () {
      final p = makePuzzle('111\n222\n111');
      // CH:1.left.right — color-1 strips on the top and bottom rows both
      // connect left to right; either one alone satisfies the constraint.
      expect(ChainConstraint('1.left.right').verify(p), isTrue);
    });

    test('complete grid with no path → invalid', () {
      // Full grid, but color-1 cells are isolated from the right side.
      // v2_12_3x3_122212221 is the final state.
      final p = makePuzzle('122\n212\n221');
      expect(ChainConstraint('1.left.right').verify(p), isFalse);
    });

    test('incomplete grid with free corridor → valid', () {
      // 3×3, a free (0) path from left to right could still form
      final p = makePuzzle('000\n101\n020');
      // There's a color-1 cell at idx 4 (1,1) and free cells around
      expect(ChainConstraint('1.left.right').verify(p), isTrue);
    });

    test('incomplete grid, opposite-colour barrier → invalid', () {
      // 3×3: all right-side cells are opposite (2), and a solid colour-2
      // wall separates the left side from the right. No free cell bridges it.
      final p = makePuzzle('222\n202\n002');
      expect(ChainConstraint('1.left.right').verify(p), isFalse);
    });

    test('top-bottom path on complete grid → valid', () {
      final p = makePuzzle('121\n121\n121');
      expect(ChainConstraint('1.top.bottom').verify(p), isTrue);
    });

    test('top-bottom path via a single column → valid', () {
      // Color-1 column 0 forms a vertical chain top→bottom.
      final p = makePuzzle('100\n100\n100');
      expect(ChainConstraint('1.top.bottom').verify(p), isTrue);
    });

    test('left-right path blocked on complete grid → invalid', () {
      // Full colour-2 barrier with all right-side cells opposite.
      final p = makePuzzle('222\n222\n222');
      expect(ChainConstraint('1.left.right').verify(p), isFalse);
    });
  });

  group('ChainConstraint.apply - impossible states', () {
    test('isImpossible when opposite-colour barrier exists', () {
      // All right-side cells are opposite, and a solid colour-2 wall blocks
      // any path from left to right.
      final p = makePuzzle('222\n202\n002');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('isImpossible when source side is all opposite', () {
      // Top side = {0,1,2}, all colour 2.
      final p = makePuzzle('222\n100\n001');
      final ch = ChainConstraint('1.top.bottom');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('isImpossible when target side is all opposite', () {
      // Bottom side = {6,7,8}, all colour 2.
      final p = makePuzzle('100\n001\n222');
      final ch = ChainConstraint('1.top.bottom');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });
  });

  group('ChainConstraint.apply - forced bridge', () {
    test(
      'single free cell that bridges two segments must be target colour',
      () {
        // 3×3:
        //   1 0 2
        //   1 ? 1
        //   2 0 2
        // CH:1.left.right. Color-1 components: {0,3} on left, {5} on right.
        // Cell 4 is the only bridge. If 4=2 (opposite), flood can't reach
        // the right side → forced to 1.
        final p = makePuzzle('102\n101\n202');
        final ch = ChainConstraint('1.left.right');
        p.addConstraint(ch);
        final move = ch.apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNull);
        expect(move.idx, 4);
        expect(move.value, 1);
        expect(move.complexity, 2);
      },
    );

    test('forced bridge on top-bottom chain', () {
      // 3×3:
      //   1 0 2
      //   0 ? 0
      //   2 1 2
      // CH:1.top.bottom. Top component {0}, bottom component {7}.
      // Cell 4 is the only bridge. If 4=2, flood from top can't reach
      // the bottom side → forced to 1.
      final p = makePuzzle('102\n000\n212');
      final ch = ChainConstraint('1.top.bottom');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 4);
      expect(move.value, 1);
    });
  });

  group('ChainConstraint.apply - border saturation', () {
    test('only free cell on source side must be target colour', () {
      // 3×3, left-right:
      //   2 0 2
      //   ? 0 1
      //   2 0 2
      // Left cells: {0=2, 3=?, 6=2}. Only cell 3 is free, rest opposite.
      // Border saturation: cell 3 must be 1.
      final p = makePuzzle('202\n001\n202');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 3);
      expect(move.value, 1);
      expect(move.complexity, 1);
    });

    test('only free cell on target side must be target colour', () {
      // 4×4, top-bottom:
      //   1 0 0 2
      //   0 0 0 2
      //   0 0 0 0
      //   2 2 2 ?
      // Bottom cells: {12=2, 13=2, 14=2, 15=?}. Only cell 15 is free, rest
      // opposite. Cell 15 is reachable from top through free cells via the
      // corridor 2→6→10→11→15, and is the only possible endpoint → forced.
      final p = makePuzzle('1002\n0002\n0000\n2220');
      final ch = ChainConstraint('1.top.bottom');
      p.addConstraint(ch);
      final move = ch.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 15);
      expect(move.value, 1);
    });
  });

  group('ChainConstraint.apply - no deduction', () {
    test('intermediate state with slack → null', () {
      // 3×3, mostly empty: no certainty yet.
      final p = makePuzzle('000\n000\n000');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      expect(ch.apply(p), isNull);
    });

    test('partial path with multiple possible routes → null', () {
      // Several free cells could form the path; no single cell is forced.
      final p = makePuzzle('100\n000\n001');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      expect(ch.apply(p), isNull);
    });
  });

  group('ChainConstraint.isCompleteFor', () {
    test('full grid with valid path → complete', () {
      final p = makePuzzle('111\n222\n111');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      expect(ch.isCompleteFor(p), isTrue);
    });

    test('full grid without path → not complete (verify false)', () {
      final p = makePuzzle('122\n212\n221');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      expect(ch.isCompleteFor(p), isFalse);
    });

    test('incomplete grid → not complete', () {
      final p = makePuzzle('100\n000\n001');
      final ch = ChainConstraint('1.left.right');
      p.addConstraint(ch);
      expect(ch.isCompleteFor(p), isFalse);
    });
  });

  group('ChainConstraint serialization', () {
    test('serialize round-trip', () {
      final ch = ChainConstraint('1.left.right');
      expect(ch.serialize(), 'CH:1.left.right');
      final ch2 = ChainConstraint('2.top.bottom');
      expect(ch2.serialize(), 'CH:2.top.bottom');
    });

    test('fromParams and serialize match', () {
      final serialized = 'CH:1.left.right';
      final slug = 'CH';
      final params = '1.left.right';
      final ch = ChainConstraint(params);
      expect(ch.slug, slug);
      expect(ch.serialize(), serialized);
    });
  });

  group('ChainConstraint.generateAllParameters', () {
    test('generates only opposite-side pairs without mirror duplicates', () {
      // 2 opposite pairs × 2 colours = 4 parameters.
      final params = ChainConstraint.generateAllParameters(3, 3, [1, 2], null);
      expect(params.length, 4);
      expect(params, contains('1.left.right'));
      expect(params, contains('2.left.right'));
      expect(params, contains('1.top.bottom'));
      expect(params, contains('2.top.bottom'));
    });

    test('no self-pair (from==to)', () {
      final params = ChainConstraint.generateAllParameters(3, 3, [1, 2], null);
      expect(params, isNot(contains('1.left.left')));
      expect(params, isNot(contains('2.right.right')));
    });
  });

  group('ChainConstraint.toHuman', () {
    test('describes path between two sides', () {
      final p = Puzzle.empty(4, 4, [1, 2]);
      expect(
        ChainConstraint('1.left.right').toHuman(p),
        'Path from left to right in color 1',
      );
    });
  });

  group('ChainConstraint.rotated', () {
    test('left-right rotates to top-bottom in a square grid', () {
      // 90° clockwise: left→top, right→bottom.
      // CH:1.left.right → CH:1.top.bottom
      final rotated = ChainConstraint('1.left.right').rotated(3, 3);
      expect(rotated.serialize(), 'CH:1.top.bottom');
    });

    test('top-bottom rotates to canonical left-right form', () {
      // Raw 90° CW: top→right, bottom→left. Canonicalization swaps
      // the (right, left) pair to (left, right) so rotated outputs
      // match the forms produced by generateAllParameters.
      final rotated = ChainConstraint('1.top.bottom').rotated(3, 3);
      expect(rotated.serialize(), 'CH:1.left.right');
    });
  });
}
