import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/islands.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('IslandsConstraint.verify', () {
    test('reachable-incomplete: multi-island clean grid → true', () {
      // Black cells {0,1} form a single group; no corner contact anywhere.
      final p = makePuzzle('11\n22');
      expect(IslandsConstraint('1').verify(p), isTrue);
    });

    test('reachable-incomplete: single snaking group → true', () {
      // Black {0,1,2,5,8} is one 4-connected snake; no second group exists.
      final p = makePuzzle('111\n001\n001');
      expect(IslandsConstraint('1').verify(p), isTrue);
    });

    test('reachable-incomplete: wrong-colour diagonal contact ignored', () {
      // White groups {2,5,8} and {6,7} corner-touch (cell 5 ↔ cell 7), but
      // IS:1 reasons about black only: black {0,1,3,4} is a single
      // 4-adjacent group → valid.
      final p = makePuzzle('112\n112\n222');
      expect(IslandsConstraint('1').verify(p), isTrue);
      // Symmetric mirror: black groups corner-touch, ignored by IS:2.
      final p2 = makePuzzle('221\n221\n111');
      expect(IslandsConstraint('2').verify(p2), isTrue);
    });

    test('violated: two islands touching at a corner → false', () {
      // Black islands {0} and {3} share the corner at the grid centre.
      final p = makePuzzle('12\n21');
      expect(IslandsConstraint('1').verify(p), isFalse);
    });

    test('violated: white islands touching at a corner → false', () {
      final p = makePuzzle('21\n12');
      expect(IslandsConstraint('2').verify(p), isFalse);
    });

    test('growable contact is not a violation (mergeable groups)', () {
      // Two black islands corner-touch, but the free cells let them grow
      // together — colouring cell 0 merges everything into one group.
      final p = makePuzzle('010\n100');
      expect(IslandsConstraint('1').verify(p), isTrue);
    });

    test('permanent contact with free cells left is still a violation',
        () {
      // Black islands {0} and {4} corner-touch; cells {2, 5} are free but
      // unreachable from island {0} (walled in by whites 1 and 3), so no
      // future move can merge the groups → violated despite open cells.
      final p = makePuzzle('120\n210\n222');
      expect(IslandsConstraint('1').verify(p), isFalse);
    });
  });

  group('IslandsConstraint.apply', () {
    test('impossible on existing diagonal contact', () {
      final p = makePuzzle('12\n21');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      expect(c.apply(p)?.isImpossible, same(c));
    });

    test('no prune when the touched groups are still mergeable', () {
      // Black islands {0} and {8}; colouring centre cell 4 black would
      // corner-touch both, but the whole grid is one capable component —
      // every island can still grow together through the free cells →
      // legal, no prune.
      final p = makePuzzle('100\n000\n001');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      expect(c.apply(p), isNull);
    });

    test('no prune when growth stays mergeable (former bridged case)', () {
      // Colouring cell 3 black grows island {0} into {0,3}, which
      // corner-contacts island {7} — but they can still merge through the
      // free cells below → legal.
      final p = makePuzzle('100\n000\n010');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      expect(c.apply(p), isNull);
    });

    test('prunes across a wall: growth would permanently corner-contact',
        () {
      // Islands {0,1} and {8}; free cell 5 shares its capable component
      // with 8 but is walled off from {0,1} by whites. Colouring 5 black
      // grows island {5,8}, which corner-contacts island {0,1} at cells
      // 1/5 with no merge path → permanent → prune black from 5.
      final p = makePuzzle('112\n220\n221');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      final move = c.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 5);
      expect(move.removeOption, CellValue.black);
    });

    test('forces the unique merge cell between diagonally-connected islands',
        () {
      // Black islands {3} and {7} corner-touch; whites seal every other
      // route, so the only capable path between them runs through cell 6.
      // The merge is mandatory → cell 6 must be black. Cells 5 and 8 are
      // not on every path and stay free.
      final p = makePuzzle('222\n120\n010');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      final move = c.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 6);
      expect(move.value, CellValue.black);
    });

    test('no forced merge when two disjoint routes exist', () {
      // Islands {0} and {3} corner-touch; they can merge through cell 1 OR
      // through cells 4→5... no single cell is on every path → no SetValue.
      final p = makePuzzle('100\n010\n000');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      expect(c.apply(p), isNull);
    });

    test('null on safe free cells', () {
      // Single 2x2 black island surrounded by a white sea; the two free
      // cells are two rows/columns away, so colouring either black can
      // never corner-contact anything → no prune, apply returns null.
      final p = makePuzzle('22222\n21122\n21122\n22220\n20222');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      expect(c.apply(p), isNull);
    });

    test('no-op guard: already-pruned colour is not re-emitted', () {
      // 3-colour livelock regression: cell 4 is the only prune target, but
      // black is already absent from its options — apply must return null
      // instead of re-emitting the same no-op RemoveOption forever.
      final p = makePuzzle3('100\n000\n001');
      final c = IslandsConstraint('1');
      p.addConstraint(c);
      p.cells[4].removeOptionForSolver(CellValue.black);
      expect(c.apply(p), isNull);
    });
  });

  group('IslandsConstraint.isCompleteFor', () {
    test('free corners keep the constraint lit (conservative grayout)',
        () {
      // 6x6: single black island in the middle, white sea, only the four
      // corners are still free. Even though no placement could ever
      // violate the rule, grayout is conservative (SH convention): any
      // free cell still holding the colour keeps IS active, because the
      // capable-component partition can refine later.
      final p = makePuzzle('022220\n222222\n221122\n221122\n222222\n022220');
      final c = IslandsConstraint('1');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('empty grid stays lit', () {
      // Free cells still hold the colour → not complete.
      final p = makePuzzle('000\n000\n000');
      final c = IslandsConstraint('1');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('two free diagonal cells without a capable bridge → not complete',
        () {
      // Free capable cells remain → not complete under the conservative
      // criterion.
      final p = makePuzzle('2220\n2102\n2222\n2222');
      final c = IslandsConstraint('1');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('all free cells stripped of colour → complete', () {
      // With black pruned from every free cell the capable set is empty:
      // conditions 2 and 3 are vacuous and verify holds → complete.
      final p = makePuzzle3('100\n000\n000');
      for (var i = 0; i < p.cells.length; i++) {
        if (p.cellValues[i] == CellValue.free) {
          p.cells[i].removeOptionForSolver(CellValue.black);
        }
      }
      final c = IslandsConstraint('1');
      expect(c.isCompleteFor(p), isTrue);
    });
  });

  group('IslandsConstraint.serialize', () {
    test('round-trips through the registry', () {
      for (final v in fullDomain) {
        final c = IslandsConstraint(cellValueToString(v));
        expect(c.serialize(), 'IS:${cellValueToString(v)}');
        final parsed = createConstraint('IS', cellValueToString(v));
        expect(parsed, isA<IslandsConstraint>());
        expect(parsed!.serialize(), c.serialize());
      }
    });
  });

  group('IslandsConstraint.generateAllParameters', () {
    test('cardinality equals the domain length', () {
      expect(
        IslandsConstraint.generateAllParameters(4, 4, defaultDomain, null),
        [for (final v in defaultDomain) cellValueToString(v)],
      );
      expect(
        IslandsConstraint.generateAllParameters(6, 6, fullDomain, null),
        [for (final v in fullDomain) cellValueToString(v)],
      );
    });
  });

  group('IslandsConstraint.rotated', () {
    test('identity over four turns (non-square dimensions)', () {
      const w = 4, h = 3;
      final c = IslandsConstraint('2');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });
  });
}
