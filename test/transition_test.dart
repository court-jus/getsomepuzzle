import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('RowTransitionConstraint.verify', () {
    test('complete — correct count', () {
      // Row 0: [1, 1, 2, 2, 1]
      // Transitions: (1,2) at idx 1→2, (2,1) at idx 3→4 → 2 transitions
      final p = makePuzzle('11221\n22222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });

    test('complete — wrong count', () {
      final p = makePuzzle('11221\n22222');
      final rt = RowTransitionConstraint('0.3');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
    });

    test('partial — reachable', () {
      // Row 0: [1, 0, 2, 0, 1]
      // t=0 (no adjacent filled pairs), freePairs=4, count=2 → reachable
      final p = makePuzzle('10201\n22222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });

    test('partial — unreachable (t + freePairs < count)', () {
      // Row 0: [1, 2, 0, 0, 0]
      // t=1 (pair 0→1: 1≠2), freePairs=3, t+fp=4 < count=5 → unreachable
      final p = makePuzzle('12000\n22222');
      final rt = RowTransitionConstraint('0.5');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
    });

    test('partial — already exceeded', () {
      // Row 0: [1, 2, 1]
      // t=2 (1→2, 2→1), count=1 already exceeded
      final p = makePuzzle('121\n222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
    });
  });

  group('ColumnTransitionConstraint.verify', () {
    test('complete — correct count', () {
      // Column 0: [1, 2, 1]
      // t=2 (1→2, 2→1)
      final p = makePuzzle('1\n2\n1');
      final ct = ColumnTransitionConstraint('0.2');
      p.addConstraint(ct);
      expect(ct.verify(p), isTrue);
    });

    test('complete — wrong count', () {
      final p = makePuzzle('1\n2\n1');
      final ct = ColumnTransitionConstraint('0.0');
      p.addConstraint(ct);
      expect(ct.verify(p), isFalse);
    });
  });

  group('RowTransitionConstraint.apply', () {
    test('saturated — free cell forced to match neighbor', () {
      // Row 0: [1, 2, 0], count=1
      // t=1 (pair 0→1), fp=1, saturated
      // Cell 2 free, neighbor=2 → forced to 2
      final p = makePuzzle('120\n222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, 2);
    });

    test('saturated — free cell forced (right side)', () {
      // Row 0: [0, 1, 2], count=1
      // t=1 (pair 1→2), fp=1, saturated
      // Cell 0 free, neighbor=1 → forced to 1
      final p = makePuzzle('012\n222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, 1);
    });

    test('saturated — conflicting neighbours leads to impossible', () {
      // Row 0: [1, 2, 0, 1], count=1
      // t=1 (pair 0→1), fp=2, saturated
      // Cell 2: left=2 → forced to 2; right=1 → forced to 1. CONFLICT → impossible
      final p = makePuzzle('1201\n2222\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('full need — free cell forced to differ from neighbor', () {
      // Row 0: [1, 0], count=1
      // t=0, fp=1, t+fp=1 == count → full need
      // Cell 1 free, neighbor=1 → forced to 2 (must differ)
      final p = makePuzzle('10\n22');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, 2);
    });

    test('full need — free cell forced to differ in other direction', () {
      // Row 0: [2, 0], count=1
      // t=0, fp=1, full need
      // Cell 1 free, neighbor=2 → forced to 1 (must differ)
      final p = makePuzzle('20\n22');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, 1);
    });

    test('impossible — t > count', () {
      final p = makePuzzle('121\n222');
      final rt = RowTransitionConstraint('0.0');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('impossible — t + freePairs < count', () {
      final p = makePuzzle('100\n222');
      final rt = RowTransitionConstraint('0.5');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('no deduction — intermediate state', () {
      // Row 0: [1, 0, 0], count=1
      // t=0, fp=2, t<count and t+fp>count and t+fp!=count → no deduction
      final p = makePuzzle('100\n222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.apply(p), isNull);
    });
  });

  group('isCompleteFor', () {
    test('fully filled line with correct count → true', () {
      // Row 0 [1,2,1] fully filled, 2 transitions → complete
      final p = makePuzzle('121\n222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      expect(rt.isCompleteFor(p), isTrue);
    });

    test('line with free cell → false', () {
      // Row 0 [1,2,0] has a free cell → incomplete
      final p = makePuzzle('120\n222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.isCompleteFor(p), isFalse);
    });
  });

  group('serialize / deserialize', () {
    test('RT round-trip', () {
      final rt = RowTransitionConstraint('2.3');
      expect(rt.serialize(), 'RT:2.3');
    });

    test('CT round-trip', () {
      final ct = ColumnTransitionConstraint('0.0');
      expect(ct.serialize(), 'CT:0.0');
    });
  });

  group('generateAllParameters', () {
    test('RT correct count for 4x4 grid', () {
      // 4 rows × 4 t values (0..3) = 16 (no color loop)
      final params = RowTransitionConstraint.generateAllParameters(4, 4, [
        1,
        2,
      ], null);
      expect(params.length, 4 * 4);
      expect(params.any((p) => p.endsWith('.0')), isTrue);
    });

    test('CT correct count for 4x4 grid', () {
      // 4 cols × 4 t values (0..3) = 16 (no color loop)
      final params = ColumnTransitionConstraint.generateAllParameters(4, 4, [
        1,
        2,
      ], null);
      expect(params.length, 4 * 4);
    });

    test('RT includes t=0', () {
      final params = RowTransitionConstraint.generateAllParameters(4, 4, [
        1,
        2,
      ], null);
      expect(params.where((p) => p.endsWith('.0')).length, 4);
    });
  });

  group('conflictsWith', () {
    test('RT with RC on same row → true', () {
      final rt = RowTransitionConstraint('0.2');
      final rc = RowCountConstraint('0.1.2');
      expect(rt.conflictsWith(rc), isTrue);
    });

    test('RC with RT on same row → true (symmetric)', () {
      final rt = RowTransitionConstraint('0.2');
      final rc = RowCountConstraint('0.1.2');
      expect(rc.conflictsWith(rt), isTrue);
    });

    test('CT with CC on same column → true', () {
      final ct = ColumnTransitionConstraint('0.2');
      final cc = ColumnCountConstraint('0.1.2');
      expect(ct.conflictsWith(cc), isTrue);
    });

    test('CC with CT on same column → true (symmetric)', () {
      final ct = ColumnTransitionConstraint('0.2');
      final cc = ColumnCountConstraint('0.1.2');
      expect(cc.conflictsWith(ct), isTrue);
    });

    test('different indices → false', () {
      final rt = RowTransitionConstraint('0.2');
      final rc = RowCountConstraint('1.1.2');
      expect(rt.conflictsWith(rc), isFalse);
    });

    test('cross-axis (RT with CC) → false', () {
      final rt = RowTransitionConstraint('0.2');
      final cc = ColumnCountConstraint('0.1.2');
      expect(rt.conflictsWith(cc), isFalse);
    });
  });

  group('RT + RC interaction', () {
    test('synthetic puzzle solvable by propagation with combined RT+RC', () {
      // 3-wide row: RC says 2 black cells, RT says 1 transition
      // 2 black cells with 1 transition → contiguous block [1 1 2]
      final p = Puzzle.empty(3, 1, [1, 2]);
      p.cells[0].setForSolver(1);
      p.cells[0].readonly = true;
      p.addConstraint(RowCountConstraint('0.1.2'));
      p.addConstraint(RowTransitionConstraint('0.1'));
      p.solve();
      expect(p.complete, isTrue);
      // [1,1,2]: transitions=1 (pair 1→2), black cells=2
      expect(p.cellValues, [1, 1, 2]);
    });
  });

  group('Zero transitions', () {
    test('RT:0.0 — one cell colored forces all others to same', () {
      // Row 0: RT with 0 transitions. One cell is 1 → all must be 1.
      final p = Puzzle.empty(4, 1, [1, 2]);
      p.cells[0].setForSolver(1);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.0'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues.every((v) => v == 1), isTrue);
    });

    test('RT:0.0 — one cell value 2 forces all to 2', () {
      final p = Puzzle.empty(4, 1, [1, 2]);
      p.cells[0].setForSolver(2);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.0'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues.every((v) => v == 2), isTrue);
    });
  });

  group('Maximum transitions', () {
    test('RT:0.3 on 4-wide forces strict alternation', () {
      // 4-wide row, max transitions=3 → each adjacent pair must differ
      final p = Puzzle.empty(4, 1, [1, 2]);
      p.cells[0].setForSolver(1);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.3'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues, [1, 2, 1, 2]);
    });
  });

  group('ColumnTransitionConstraint.apply', () {
    test('saturated deduction on column', () {
      // Column 0: [1, 2, 0], count=1
      // t=1 (pair 0→1), fp=1, saturated
      // Cell 2 free, neighbor=2 → forced to 2
      final p = makePuzzle('1\n2\n0');
      final ct = ColumnTransitionConstraint('0.1');
      p.addConstraint(ct);
      final move = ct.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, 2);
    });
  });
}
