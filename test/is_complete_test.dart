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

    test('not complete when count reached but free cells remain', () {
      // 1x2 grid, value=1 count=1: target reached but cell 1 is still free
      // and apply() will force it to 2 → constraint is still producing
      // deductions, must not gray out.
      final p = _make('10');
      final c = QuantityConstraint('1.1');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('complete when grid is full and valid', () {
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

    test('not complete when merge-cells still force deductions', () {
      // Diagonal alternation 101\n010\n101 + GC:1.5: count already = target,
      // no candidate cell exists, but every free cell borders multiple
      // color-1 groups → apply() would force them to white. Constraint is
      // still producing deductions, must not gray out.
      final p = _make('101\n010\n101');
      final c = GroupCountConstraint('1.5');
      expect(c.isCompleteFor(p), isFalse);
    });

    test('not complete when a future merge would drop the count', () {
      // 1x4 state 1001 + GC:1.2: current=target=2, no candidates, no
      // merge-cells NOW. But the two groups can still merge through the
      // empty gap (calculateMinGroups=1). If the user colours cell 1 with
      // black, a merge-cell appears at cell 2 and apply() fires. Must not
      // gray out in this state.
      final p = _make('1001');
      final c = GroupCountConstraint('1.2');
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

  group('Puzzle.clone constraint state isolation', () {
    test('findAMove on a clone must not mutate isComplete on the original', () {
      // Regression: findAMove clones the puzzle and calls setValue to probe
      // hypothetical moves. Before deep-cloning constraints, the clone and
      // the original shared Constraint objects, so updateConstraintStatus()
      // during probing could flip the original's `isComplete` to `true`
      // based on a hypothetical (not real) grid state, leaving the UI
      // incorrectly grayed.
      //
      // Here we take a state where the real grid leaves SY group open,
      // but where some probing state would make it bordered.
      final p = Puzzle('v2_12_4x4_1000000000000000_SY:5.1_0:0_0');
      final sy = p.constraints.whereType<SymmetryConstraint>().first;
      p.updateConstraintStatus();
      expect(sy.isComplete, isFalse);
      // Run findAMove — internally it clones and mutates cells via
      // setValue. Without deep-clone of constraints, this would flip
      // sy.isComplete on the original.
      p.findAMove();
      expect(
        sy.isComplete,
        isFalse,
        reason: 'findAMove on a clone must not mutate the original',
      );
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
