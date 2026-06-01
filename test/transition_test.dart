import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
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
      expect(move.value, CellValue.white);
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
      expect(move.value, CellValue.black);
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
      expect(move.value, CellValue.white);
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
      expect(move.value, CellValue.black);
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
      // Row 0: [0, 1, 0], count=1
      // t=0 (no filled pair is both filled and different), fp=2,
      // t<count and t+fp>count and t+fp!=count → no deduction.
      // Neither endpoint is known → endpoint parity can't fire either.
      final p = makePuzzle('010\n222');
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
      final params = RowTransitionConstraint.generateAllParameters(
        4,
        4,
        defaultDomain,
        null,
      );
      expect(params.length, 4 * 4);
      expect(params.any((p) => p.endsWith('.0')), isTrue);
    });

    test('CT correct count for 4x4 grid', () {
      // 4 cols × 4 t values (0..3) = 16 (no color loop)
      final params = ColumnTransitionConstraint.generateAllParameters(
        4,
        4,
        defaultDomain,
        null,
      );
      expect(params.length, 4 * 4);
    });

    test('RT includes t=0', () {
      final params = RowTransitionConstraint.generateAllParameters(
        4,
        4,
        defaultDomain,
        null,
      );
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
      final p = Puzzle.empty(3, 1, defaultDomain);
      p.cells[0].setForSolver(CellValue.black);
      p.cells[0].readonly = true;
      p.addConstraint(RowCountConstraint('0.1.2'));
      p.addConstraint(RowTransitionConstraint('0.1'));
      p.solve();
      expect(p.complete, isTrue);
      // [1,1,2]: transitions=1 (pair 1→2), black cells=2
      expect(p.cellValues, [CellValue.black, CellValue.black, CellValue.white]);
    });
  });

  group('Zero transitions', () {
    test('RT:0.0 — one cell colored forces all others to same', () {
      // Row 0: RT with 0 transitions. One cell is 1 → all must be 1.
      final p = Puzzle.empty(4, 1, defaultDomain);
      p.cells[0].setForSolver(CellValue.black);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.0'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues.every((v) => v == CellValue.black), isTrue);
    });

    test('RT:0.0 — one cell value 2 forces all to 2', () {
      final p = Puzzle.empty(4, 1, defaultDomain);
      p.cells[0].setForSolver(CellValue.white);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.0'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues.every((v) => v == CellValue.white), isTrue);
    });
  });

  group('Maximum transitions', () {
    test('RT:0.3 on 4-wide forces strict alternation', () {
      // 4-wide row, max transitions=3 → each adjacent pair must differ
      final p = Puzzle.empty(4, 1, defaultDomain);
      p.cells[0].setForSolver(CellValue.black);
      p.cells[0].readonly = true;
      p.addConstraint(RowTransitionConstraint('0.3'));
      p.solve();
      expect(p.complete, isTrue);
      expect(p.cellValues, [
        CellValue.black,
        CellValue.white,
        CellValue.black,
        CellValue.white,
      ]);
    });
  });

  group('RowTransitionConstraint.apply — endpoint parity', () {
    test('last known, odd count → first is opposite', () {
      // Row 0: [0, 0, 0, 1], count=1
      // Last=1 (odd count) → first must differ → first=2
      final p = makePuzzle('0001\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 0);
      expect(move.value, CellValue.white);
    });

    test('last known, even count → first is same', () {
      // Row 0: [0, 0, 0, 1], count=2
      // Last=1 (even count) → first must match → first=1
      final p = makePuzzle('0001\n2222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 0);
      expect(move.value, CellValue.black);
    });

    test('first known, odd count → last is opposite', () {
      // Row 0: [2, 0, 0, 0], count=1
      // First=2 (odd count) → last must differ → last=1
      final p = makePuzzle('2000\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 3);
      expect(move.value, CellValue.black);
    });

    test('first known, even count → last is same', () {
      // Row 0: [2, 0, 0, 0], count=2
      // First=2 (even count) → last must match → last=2
      final p = makePuzzle('2000\n2222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 3);
      expect(move.value, CellValue.white);
    });

    test('two-cell row, odd count → last differs from first', () {
      // Row 0: [1, 0], count=1
      // First=1 (odd) → last must differ → last=2
      final p = makePuzzle('10\n22');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 1);
      expect(move.value, CellValue.white);
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
      expect(move.value, CellValue.white);
    });

    test('endpoint parity — column, last known, odd count', () {
      // Column 0: [0, 0, 1], count=1
      // Last=1 (odd) → first must differ → first=2
      final p = makePuzzle('0\n0\n1');
      final ct = ColumnTransitionConstraint('0.1');
      p.addConstraint(ct);
      final move = ct.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 0);
      expect(move.value, CellValue.white);
    });
  });

  group('verifyTransitionLine — endpoint parity', () {
    test('same ends, odd count → unreachable', () {
      // Row 0: [1, 0, 0, 1], count=1
      // Both ends=1 (same), count=1 (odd) → impossible
      final p = makePuzzle('1001\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
    });

    test('same ends, even count → reachable', () {
      // Row 0: [1, 0, 0, 1], count=2
      // Both ends=1 (same), count=2 (even) → reachable
      final p = makePuzzle('1001\n2222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });

    test('different ends, odd count → reachable', () {
      // Row 0: [1, 0, 0, 2], count=1
      // Ends differ (1≠2), count=1 (odd) → reachable
      final p = makePuzzle('1002\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });

    test('different ends, even count → unreachable', () {
      // Row 0: [1, 0, 0, 2], count=2
      // Ends differ (1≠2), count=2 (even) → impossible
      final p = makePuzzle('1002\n2222');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
    });

    test('one endpoint free → parity check skipped, reachable', () {
      // Row 0: [1, 0, 0, 0], count=1
      // Only first known, last free → parity not checked
      final p = makePuzzle('1000\n2222');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });
  });

  group('Transitions on a 3-colour domain', () {
    // Single-row puzzle on the full 3-colour domain so free cells keep three
    // options (black/white/purple) and removeOption deductions are meaningful.
    Puzzle makeRow3(String row) {
      final w = row.length;
      final p = Puzzle.empty(w, 1, fullDomain);
      for (int c = 0; c < w; c++) {
        final v = cellRepresentationToValue(row[c]);
        if (v != CellValue.free) p.cells[c].setForSolver(v);
      }
      return p;
    }

    test('full-need → removeOption neighbour colour (no forced value)', () {
      // [1, ., 2], count=2: t=0, fp=2, t+fp==count → every free pair must be a
      // transition. The middle cell must differ from both neighbours; we can
      // only prune one neighbour colour at a time (it cannot be forced to a
      // single value the way 2 colours would).
      final p = makeRow3('102');
      final rt = RowTransitionConstraint('0.2');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.value, isNull);
      expect(move.idx, 1);
      expect(move.removeOption, CellValue.black);
    });

    test('endpoint count==1 → removeOption the known end colour', () {
      // [1, ., ., .], count=1: exactly two runs ⇒ the far endpoint must differ
      // from the known one. Can't force a unique colour (two remain), only
      // prune the known colour.
      final p = makeRow3('1000');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 3);
      expect(move.removeOption, CellValue.black);
    });

    test('endpoint count==1 with equal coloured ends → impossible', () {
      // [1, ., 1], count=1: two runs would need different ends, but both ends
      // are colour 1 → unreachable.
      final p = makeRow3('101');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isFalse);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('lower-bound probing prunes a wedged third colour', () {
      // [1, ., 2], count=1: the middle cell taking a *third* colour (3) would
      // create two transitions (1→3, 3→2) and overshoot count=1. Neither
      // saturated nor full-need fires here; the probing fallback prunes 3.
      final p = makeRow3('102');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      final move = rt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 1);
      expect(move.removeOption, CellValue.purple);
      expect(move.complexity, 4);
    });

    test('count==1 with differing coloured ends stays reachable', () {
      // [1, ., 2], count=1: middle can still be 1 or 2 → reachable (guards
      // against the endpoint rule over-rejecting on 3 colours).
      final p = makeRow3('102');
      final rt = RowTransitionConstraint('0.1');
      p.addConstraint(rt);
      expect(rt.verify(p), isTrue);
    });
  });
}
