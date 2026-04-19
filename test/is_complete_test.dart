import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

Puzzle _make(String grid) {
  final rows = grid
      .trim()
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  final h = rows.length;
  final w = rows.first.length;
  final p = Puzzle.empty(w, h, [1, 2]);
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      final v = int.parse(rows[r][c]);
      if (v != 0) {
        p.cells[r * w + c].setForSolver(v);
      }
    }
  }
  return p;
}

void main() {
  group('ParityConstraint.isCompleteFor', () {
    test('not complete when cells are empty', () {
      final p = _make('0\n1\n0');
      final c = ParityConstraint('0.bottom');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when all side cells are filled', () {
      final p = _make('0\n1\n2');
      final c = ParityConstraint('0.bottom');
      c.check(p);
      expect(c.isCompleteFor(p), isTrue);
    });

    test('not complete when constraint is invalid', () {
      final p = _make('0\n1\n1');
      final c = ParityConstraint('0.bottom');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });
  });

  group('GroupSize.isCompleteFor', () {
    test('not complete when group has free neighbors', () {
      final p = _make('1\n0');
      final c = GroupSize('0.1');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when group is bordered and has correct size', () {
      final p = _make('1\n2');
      final c = GroupSize('0.1');
      c.check(p);
      expect(c.isCompleteFor(p), isTrue);
    });

    test('not complete when group size is incorrect', () {
      final p = _make('1\n2');
      final c = GroupSize('0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });
  });

  group('LetterGroup.isCompleteFor', () {
    test('not complete when cells are empty', () {
      final p = _make('000\n000');
      final c = LetterGroup('A.0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });

    test('not complete when group has free neighbors', () {
      final p = _make('101\n111');
      final c = LetterGroup('A.0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when all filled with same color and group is bordered', () {
      final p = _make('121\n111');
      final c = LetterGroup('A.0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isTrue);
    });
  });

  group('SymmetryConstraint.isCompleteFor', () {
    test('not complete when group has free neighbors', () {
      final p = _make('1\n0');
      final c = SymmetryConstraint('0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when group is bordered', () {
      final p = _make('1\n2');
      final c = SymmetryConstraint('0.2');
      c.check(p);
      expect(c.isCompleteFor(p), isTrue);
    });
  });

  group('ForbiddenMotif.isCompleteFor', () {
    test('not complete when motif can still appear', () {
      final p = _make('00');
      final c = ForbiddenMotif('12');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when all placements are blocked', () {
      final p = _make('21\n01');
      final c = ForbiddenMotif('12');
      c.check(p);
      expect(c.isCompleteFor(p), isTrue);
    });

    test('not complete when constraint is invalid', () {
      final p = _make('12');
      final c = ForbiddenMotif('12');
      c.check(p);
      expect(c.isCompleteFor(p), isFalse);
    });
  });

  group('QuantityConstraint.isCompleteFor', () {
    test('not complete when count not reached', () {
      final p = _make('00');
      final c = QuantityConstraint('1.2');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when count reached', () {
      final p = _make('11');
      final c = QuantityConstraint('1.2');
      expect(c.isCompleteFor(p), isTrue);
    });

    test('complete if valid when puzzle is complete', () {
      final p = _make('12');
      final c = QuantityConstraint('1.1');
      expect(c.isCompleteFor(p), isTrue);
    });
  });

  group('GroupCountConstraint.isCompleteFor', () {
    test('not complete when count not reached', () {
      final p = _make('10');
      final c = GroupCountConstraint('1.2');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when count reached and no more groups possible', () {
      final p = _make('12\n02');
      final c = GroupCountConstraint('1.1');
      expect(c.isCompleteFor(p), isTrue);
    });

    test('not complete when more groups could be added', () {
      final p = _make('10\n00');
      final c = GroupCountConstraint('1.1');
      expect(c.isCompleteFor(p), isFalse);
    });
  });

  group('ColumnCountConstraint.isCompleteFor', () {
    test('not complete when column has empty cells', () {
      final p = _make('0\n0');
      final c = ColumnCountConstraint('0.1.1');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when column is full', () {
      final p = _make('1\n2');
      final c = ColumnCountConstraint('0.1.1');
      expect(c.isCompleteFor(p), isTrue);
    });
  });

  group('DifferentFromConstraint.isCompleteFor', () {
    test('not complete when cells are empty', () {
      final p = _make('00');
      final c = DifferentFromConstraint('0.right');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('not complete when one cell is empty', () {
      final p = _make('10');
      final c = DifferentFromConstraint('0.right');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when both cells are filled', () {
      final p = _make('12');
      final c = DifferentFromConstraint('0.right');
      expect(c.isCompleteFor(p), isTrue);
    });
  });
}
