import 'package:flutter_test/flutter_test.dart';

import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/rectangular_groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('RectangularGroupsConstraint.verify', () {
    test('rectangular group passes', () {
      final p = makePuzzle('111\n111\n222');
      expect(RectangularGroupsConstraint('0').verify(p), isTrue);
    });

    test('non-rectangular group fails (white hole in bounding box)', () {
      final p = makePuzzle('111\n121\n222');
      expect(RectangularGroupsConstraint('0').verify(p), isFalse);
    });

    test('incomplete, box fillable → true', () {
      final p = makePuzzle('110\n010\n000');
      expect(RectangularGroupsConstraint('0').verify(p), isTrue);
    });

    test('incomplete, box cell colour-pruned → false', () {
      final p = makePuzzle3('110\n010\n000');
      p.cells[3].removeOptionForSolver(CellValue.black);
      expect(RectangularGroupsConstraint('0').verify(p), isFalse);
    });

    test('free anchor on incomplete puzzle → true', () {
      final p = makePuzzle('000\n000');
      expect(RectangularGroupsConstraint('5').verify(p), isTrue);
    });

    test('square group fails (complete)', () {
      final p = makePuzzle('112\n112\n222');
      expect(RectangularGroupsConstraint('0').verify(p), isFalse);
    });

    test('square box spanning the whole grid fails (incomplete)', () {
      final p = makePuzzle('11\n10');
      expect(RectangularGroupsConstraint('0').verify(p), isFalse);
    });

    test('closed full square fails (incomplete)', () {
      final p = makePuzzle3('112\n112\n200');
      p.cells[7].removeOptionForSolver(CellValue.black);
      expect(RectangularGroupsConstraint('0').verify(p), isFalse);
    });
  });

  group('RectangularGroupsConstraint.apply', () {
    test('box-fill: free box cell takes the group colour', () {
      final p = makePuzzle('110\n010\n000');
      final move = RectangularGroupsConstraint('0').apply(p)!;
      expect(move.idx, 3);
      expect(move.value, CellValue.black);
    });

    test('contradiction: wrong-colour cell inside the bounding box', () {
      final p = makePuzzle('110\n210\n000');
      final move = RectangularGroupsConstraint('0').apply(p)!;
      expect(move.isImpossible, isNotNull);
    });

    test('prune: colouring a neighbour would overhang a white cell', () {
      final p = makePuzzle('110\n020\n000');
      final move = RectangularGroupsConstraint('0').apply(p)!;
      expect(move.idx, 3);
      expect(move.removeOption, CellValue.black);
    });

    test('no prune when the expansion is fillable', () {
      final p = makePuzzle('110\n000\n000');
      final move = RectangularGroupsConstraint('0').apply(p);
      // The 1×2 box is already full; every expansion overhangs only free,
      // black-capable cells, so nothing is pruned and nothing is forced.
      expect(move is RemoveOption, isFalse);
    });

    test('free anchor → null', () {
      final p = makePuzzle('000\n000');
      expect(RectangularGroupsConstraint('5').apply(p), isNull);
    });

    test('Impossible when a full square box cannot grow', () {
      final p = makePuzzle3('112\n112\n200');
      p.cells[7].removeOptionForSolver(CellValue.black);
      final move = RectangularGroupsConstraint('0').apply(p)!;
      expect(move.isImpossible, isNotNull);
    });

    test('prune growth that would leave a stuck square', () {
      final p = makePuzzle('111\n111\n000');
      final move = RectangularGroupsConstraint('0').apply(p)!;
      expect(move.removeOption, CellValue.black);
      expect({6, 7, 8}.contains(move.idx), isTrue);
    });

    test('square full box with growable neighbour → nothing forced', () {
      final p = makePuzzle('112\n112\n000');
      expect(RectangularGroupsConstraint('0').apply(p), isNull);
    });
  });

  group('RectangularGroupsConstraint.isCompleteFor', () {
    test('rectangular and closed → true', () {
      final p = makePuzzle('112\n222\n222');
      expect(RectangularGroupsConstraint('0').isCompleteFor(p), isTrue);
    });

    test('open neighbour still holding the colour → false', () {
      final p = makePuzzle('110\n000');
      expect(RectangularGroupsConstraint('0').isCompleteFor(p), isFalse);
    });

    test('box not fully coloured → false', () {
      final p = makePuzzle('110\n010\n000');
      expect(RectangularGroupsConstraint('0').isCompleteFor(p), isFalse);
    });

    test('invalid (non-rectangular) → false', () {
      final p = makePuzzle('111\n121\n222');
      expect(RectangularGroupsConstraint('0').isCompleteFor(p), isFalse);
    });

    test('square group → false (even when it could grow)', () {
      final p = makePuzzle('112\n112\n000');
      expect(RectangularGroupsConstraint('0').isCompleteFor(p), isFalse);
    });
  });

  group('RectangularGroupsConstraint serialization & generation', () {
    test('serialize round-trips a bare index', () {
      expect(RectangularGroupsConstraint('5').serialize(), 'RE:5');
    });

    test('createConstraint parses RE and re-serializes', () {
      final c = createConstraint('RE', '5') as RectangularGroupsConstraint;
      expect(c.indices, [5]);
      expect(c.serialize(), 'RE:5');
    });

    test('generateAllParameters emits one param per cell', () {
      expect(
        RectangularGroupsConstraint.generateAllParameters(
          3,
          2,
          defaultDomain,
          null,
        ),
        ['0', '1', '2', '3', '4', '5'],
      );
    });

    test('rotated remaps the anchor index 90° CW', () {
      final c = RectangularGroupsConstraint('0');
      expect(c.rotated(2, 3).serialize(), 'RE:${rotateIdx90CW(0, 2, 3)}');
    });
  });
}
