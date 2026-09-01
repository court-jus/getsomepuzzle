import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/mirror.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('MirrorConstraint.serialize', () {
    test('serializes and parses through the registry', () {
      expect(MirrorConstraint('1.H').serialize(), 'MI:1.H');
      final c = createConstraint('MI', '2.V');
      final mc = c! as MirrorConstraint;
      expect(mc.color, CellValue.white);
      expect(mc.direction, 'V');
      expect(mc.serialize(), 'MI:2.V');
    });

    test('parses a single mirror from a v2 line', () {
      final p = Puzzle('v2_12_2x4_00000000_MI:1.H_0:0_0');
      expect(p.constraints, hasLength(1));
      final c = p.constraints.single as MirrorConstraint;
      expect(c.color, CellValue.black);
      expect(c.direction, 'H');
    });

    test('coexisting mirrors parse independently', () {
      final p = Puzzle('v2_12_2x4_00000000_MI:1.H;MI:1.V_0:0_0');
      expect(p.constraints, hasLength(2));
      expect(p.constraints.whereType<MirrorConstraint>(), hasLength(2));
    });
  });

  group('MirrorConstraint.generateAllParameters', () {
    test('both directions on an even×even grid', () {
      expect(
        MirrorConstraint.generateAllParameters(
          4,
          6,
          defaultDomain,
          null,
        ).toSet(),
        {'1.H', '2.H', '1.V', '2.V'},
      );
    });

    test('H only when the height is even', () {
      expect(
        MirrorConstraint.generateAllParameters(5, 4, defaultDomain, null),
        {'1.H', '2.H'},
      );
    });

    test('V only when the width is even', () {
      expect(
        MirrorConstraint.generateAllParameters(4, 5, defaultDomain, null),
        {'1.V', '2.V'},
      );
    });

    test('empty on an odd×odd grid', () {
      expect(
        MirrorConstraint.generateAllParameters(5, 5, defaultDomain, null),
        isEmpty,
      );
    });

    test('cardinality scales with the domain', () {
      expect(
        MirrorConstraint.generateAllParameters(4, 4, fullDomain, null),
        hasLength(6),
      );
    });
  });

  group('MirrorConstraint.verify', () {
    test('undecided while a live cell remains, even with unequal counts', () {
      final p = makePuzzle('1100\n2211');
      expect(MirrorConstraint('1.H').verify(p), isTrue);
    });

    test("false if one half cannot reach the other one's count", () {
      final p = makePuzzle('1112\n1022');
      expect(MirrorConstraint('1.H').verify(p), isFalse);
    });

    test('true when both halves are decided and balanced', () {
      final p = makePuzzle('1122\n2211');
      expect(MirrorConstraint('1.H').verify(p), isTrue);
    });

    test('false when both halves are decided and unbalanced', () {
      final p = makePuzzle('1112\n2211');
      expect(MirrorConstraint('1.H').verify(p), isFalse);
    });

    test('a free cell with the colour pruned counts as decided', () {
      final p = makePuzzle3('1101\n1131');
      p.cells[2].removeOption(CellValue.black);
      expect(MirrorConstraint('1.H').verify(p), isTrue);
    });
  });

  group('MirrorConstraint.apply', () {
    test('generalized saturation: deficit == live count forces them all', () {
      final p = makePuzzle('1000\n1111');
      final m = MirrorConstraint('1.H').apply(p);
      expect(m, isA<SetValue>());
      expect(m!.idx, 1);
      expect(m.value, CellValue.black);
      expect(m.removeOption, isNull);
      // The propagation loop re-runs: each apply forces the next live cell.
      final seen = <int>[];
      var puzzle = p;
      while (true) {
        final move = MirrorConstraint('1.H').apply(puzzle);
        if (move is! SetValue) break;
        seen.add(move.idx);
        puzzle.setValue(move.idx, move.value);
      }
      expect(seen, [1, 2, 3]);
      expect(
        puzzle.cells.where((c) => c.value == CellValue.black),
        hasLength(8),
      );
    });

    test('single live cell with deficit 1', () {
      final p = makePuzzle('1210\n1112');
      final m = MirrorConstraint('1.H').apply(p);
      expect(m, isA<SetValue>());
      expect(m!.idx, 3);
      expect(m.value, CellValue.black);
    });

    test('prunes the colour when counts are equal and one half is closed', () {
      final p = makePuzzle('1110\n1112');
      final m = MirrorConstraint('1.H').apply(p);
      expect(m, isA<RemoveOption>());
      expect(m!.idx, 3);
      expect(m.removeOption, CellValue.black);
    });

    test('vertical mirror: deficit 1 == 1 live in the left half', () {
      final p = makePuzzle('01\n11');
      final m = MirrorConstraint('1.V').apply(p);
      expect(m, isA<SetValue>());
      expect(m!.idx, 0);
      expect(m.value, CellValue.black);
    });

    test('null when both halves are live and equal', () {
      final p = makePuzzle('10\n01');
      expect(MirrorConstraint('1.H').apply(p), isNull);
    });

    test('null when the deficit does not match the live count', () {
      final p = makePuzzle('1100\n1112');
      expect(MirrorConstraint('1.H').apply(p), isNull);
    });

    test('null on a fully decided unbalanced grid', () {
      final p = makePuzzle('1112\n2211');
      expect(MirrorConstraint('1.H').apply(p), isNull);
    });
  });

  group('MirrorConstraint.isCompleteFor', () {
    test('true when balanced and no live cell remains', () {
      final p = makePuzzle('1122\n2211');
      expect(MirrorConstraint('1.H').isCompleteFor(p), isTrue);
    });

    test('false while a live cell remains', () {
      final p = makePuzzle('1110\n1112');
      expect(MirrorConstraint('1.H').isCompleteFor(p), isFalse);
    });

    test('false when verify fails', () {
      final p = makePuzzle('1112\n2211');
      expect(MirrorConstraint('1.H').isCompleteFor(p), isFalse);
    });
  });

  group('MirrorConstraint coexistence', () {
    test('H and V mirrors of the same colour verify together', () {
      final p = makePuzzle('1212\n2121');
      expect(MirrorConstraint('1.H').verify(p), isTrue);
      expect(MirrorConstraint('1.V').verify(p), isTrue);
    });

    test('mirrors of different colours verify together', () {
      final p = makePuzzle('1212\n2121');
      expect(MirrorConstraint('1.H').verify(p), isTrue);
      expect(MirrorConstraint('2.H').verify(p), isTrue);
    });
  });

  group('MirrorConstraint.rotated', () {
    test('flips the axis', () {
      expect(MirrorConstraint('1.H').rotated(4, 6).serialize(), 'MI:1.V');
      expect(MirrorConstraint('1.V').rotated(4, 6).serialize(), 'MI:1.H');
    });

    test('identity over four turns', () {
      const w = 4, h = 6;
      final c = MirrorConstraint('1.H');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });
  });

  group('MirrorConstraint solver smoke', () {
    test('prune-to-white solves', () {
      final p = Puzzle('v2_12_2x4_11101112_MI:1.H_0:0_0');
      expect(p.solve(), isTrue);
    });

    test('saturation loop solves', () {
      final p = Puzzle('v2_12_2x4_10001111_MI:1.H_0:0_0');
      expect(p.solve(), isTrue);
    });
  });
}
