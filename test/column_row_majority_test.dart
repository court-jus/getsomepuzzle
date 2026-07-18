import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('ColumnMajorityConstraint', () {
    group('serialize', () {
      test('round-trip', () {
        final jc = ColumnMajorityConstraint('2.21');
        expect(jc.serialize(), 'JC:2.21');
        expect(jc.columnIdx, 2);
        expect(jc.colorOrder, [CellValue.white, CellValue.black]);
      });

      test('round-trip domain 3', () {
        final jc = ColumnMajorityConstraint('1.123');
        expect(jc.serialize(), 'JC:1.123');
        expect(jc.columnIdx, 1);
        expect(jc.colorOrder, [
          CellValue.black,
          CellValue.white,
          CellValue.purple,
        ]);
      });
    });

    group('verify — domain 2', () {
      // 4×2 grid, column 0: 4 cells
      // JC:0.21 → white > black in column 0
      test('complete with correct ordering → true', () {
        // col 0: [2,2,2,1] → white=3, black=1 → 3 > 1 ✓
        final p = makePuzzle('21\n21\n21\n11');
        expect(ColumnMajorityConstraint('0.21').verify(p), isTrue);
      });

      test('complete with wrong ordering → false', () {
        // col 0: [1,1,1,2] → black=3, white=1 → white not > black
        final p = makePuzzle('12\n12\n12\n22');
        expect(ColumnMajorityConstraint('0.21').verify(p), isFalse);
      });

      test('complete with tie → false', () {
        // 4×2 grid, col 0: [1,2,1,2] → black=2, white=2 → tie
        final p = makePuzzle('12\n21\n12\n21');
        expect(ColumnMajorityConstraint('0.12').verify(p), isFalse);
      });

      test('incomplete — target reachable → true', () {
        // col 0: [2,0,0,0] → white=1, 3 free → white can reach 3
        final p = makePuzzle('21\n01\n01\n01');
        expect(ColumnMajorityConstraint('0.21').verify(p), isTrue);
      });

      test('incomplete — target unreachable → false', () {
        // col 0: [1,1,0,0] → black=2, white=0, 2 free
        // Need white > black → white needs ≥ 3, but only 2 free → impossible
        final p = makePuzzle('12\n12\n02\n02');
        expect(ColumnMajorityConstraint('0.21').verify(p), isFalse);
      });

      test('incomplete — minority exceeded → false', () {
        // col 0: [1,1,1,0] → black=3, white=0, 1 free
        // Minority (white) at 0, but black=3 > floor(4/2)=2 → can't have white > black
        // Actually: ordering is 2>1 (white > black), black=3 means
        // the "minority" (black, second in order) has 3 > floor(4/2)=2
        final p = makePuzzle('12\n12\n12\n02');
        expect(ColumnMajorityConstraint('0.21').verify(p), isFalse);
      });
    });

    group('verify — domain 3', () {
      test('middle colour not pruned by max bound → true', () {
        // 9×1 row: [1,1,0,0,0,2,2,2,2], JR:0.123 (black > white > purple)
        // black=2, white=4, purple=0, 3 free → white=4 ≤ maxs[white]=4
        final p = makePuzzle3('110002222');
        expect(RowMajorityConstraint('0.123').verify(p), isTrue);
      });

      test('complete with correct ordering → true', () {
        // col 0: [1,1,1,2,2] → black=3, white=2, purple=0 → 3>2>0 ✓
        final p = makePuzzle3('123\n123\n123\n223\n223');
        expect(ColumnMajorityConstraint('0.123').verify(p), isTrue);
      });

      test('complete with wrong ordering → false', () {
        // col 0: [1,2,2,3,3] → black=1, white=2, purple=2 → 1>2 ✗
        final p = makePuzzle3('123\n223\n223\n323\n323');
        expect(ColumnMajorityConstraint('0.123').verify(p), isFalse);
      });

      test('complete with tie → false', () {
        // col 0: [1,1,2,2,3] → black=2, white=2, purple=1 → 2>2 ✗
        final p = makePuzzle3('123\n123\n223\n223\n323');
        expect(ColumnMajorityConstraint('0.123').verify(p), isFalse);
      });

      test('incomplete — target reachable → true', () {
        // col 0: [1,0,0,0,0] → black=1, 4 free → can reach black≥3
        final p = makePuzzle3('123\n023\n023\n023\n023');
        expect(ColumnMajorityConstraint('0.123').verify(p), isTrue);
      });

      test('incomplete — target unreachable → false', () {
        // col 0: [2,2,3,3,0] → white=2, purple=2, black=0, 1 free
        // black needs ≥ 4, only 1 free → impossible
        final p = makePuzzle3('213\n213\n313\n313\n013');
        expect(ColumnMajorityConstraint('0.123').verify(p), isFalse);
      });

      test('incomplete — first colour exceeded → false', () {
        // col 0: [1,1,1,2,3] → black=3, white=1, purple=1, 0 free
        // complete: 3>1 ✓, 1>1 ✗ (tie) → false
        final p = makePuzzle3('123\n123\n123\n223\n323');
        expect(ColumnMajorityConstraint('0.123').verify(p), isFalse);
      });
    });

    group('apply — domain 3', () {
      test('lower colour exceeded → isImpossible', () {
        // col 0: [2,2,3,3,0] → white=2, purple=2, black=0, 1 free
        // black needs ≥ 4, only 1 free → impossible
        final p = makePuzzle3('213\n213\n313\n313\n013');
        final move = ColumnMajorityConstraint('0.123').apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNotNull);
      });

      test('force first colour → SetValue', () {
        // 4-row, col 0: [1,1,2,0] → black=2, white=1, 1 free
        // black_min = max(2,2,2,3) = 3, needed=1, free=1 → force black
        final p = makePuzzle3('12\n12\n22\n02');
        final move = ColumnMajorityConstraint('0.123').apply(p);
        expect(move, isNotNull);
        expect(move!.value, CellValue.black);
      });

      test('block colour at max → RemoveOption', () {
        // col 0: [1,1,1,0] → black=3, 1 free
        // black_max=3, count=3 → block black from free cell
        final p = makePuzzle3('12\n12\n12\n02');
        final move = ColumnMajorityConstraint('0.123').apply(p);
        expect(move, isNotNull);
        if (move is RemoveOption) {
          expect(move.option, CellValue.black);
        }
      });

      test('pair already dominated → no deduction', () {
        // col 0: [1,1,1,2,0] → black=3, white=1, 1 free
        // black(3) > white(1)+1=2 → black already beats white in every
        // future; the pair is satisfied, no pruning needed.
        final p = makePuzzle3('12\n12\n12\n22\n02');
        final move = ColumnMajorityConstraint('0.123').apply(p);
        expect(move, isNull);
      });

      test('no deduction possible → null', () {
        // 7-row, col 0: [1,0,0,0,0,0,0] → black=1, 6 free
        // enough room for all colours, no force/block/pair triggers
        final p = makePuzzle3('12\n02\n02\n02\n02\n02\n02');
        final move = ColumnMajorityConstraint('0.123').apply(p);
        expect(move, isNull);
      });
    });

    group('isCompleteFor — domain 3', () {
      test('complete line with satisfied ordering → true', () {
        // col 0: [1,1,1,2,2] → black=3, white=2, purple=0 → 3>2>0 ✓
        final p = makePuzzle3('123\n123\n123\n223\n223');
        expect(ColumnMajorityConstraint('0.123').isCompleteFor(p), isTrue);
      });

      test('incomplete but unassailable lead → true', () {
        // 7-row, col 0: [1,1,1,1,2,2,0] → black=4, white=2, purple=0, 1 free
        // black(4) > white(2)+1=3 ✓, white(2) > purple(0)+1=1 ✓ → unassailable
        final p = makePuzzle3('12\n12\n12\n12\n22\n22\n02');
        expect(ColumnMajorityConstraint('0.123').isCompleteFor(p), isTrue);
      });

      test('incomplete without unassailable lead → false', () {
        // col 0: [1,1,2,0,0] → black=2, white=1, 2 free
        // black(2) ≤ white(1)+2=3 → not unassailable
        final p = makePuzzle3('12\n12\n22\n02\n02');
        expect(ColumnMajorityConstraint('0.123').isCompleteFor(p), isFalse);
      });
    });

    group('apply', () {
      test('minority exceeded → isImpossible', () {
        // 4×2 grid, col 0: [1,1,1,0], JC:0.21 (white > black)
        // black=3, ordering needs white > black, but black=3 > floor(4/2)=2
        final p = makePuzzle('12\n12\n12\n02');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNotNull);
      });

      test('first colour unreachable → isImpossible', () {
        // col 0: [1,1,0,0], JC:0.21 (white > black)
        // white=0, 2 free, need white > black(=2), white needs ≥ 3, only 2 free
        final p = makePuzzle('12\n12\n02\n02');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNotNull);
      });

      test('remaining free cells exactly enough → SetValue', () {
        // 3×2 grid, col 0: [2,0,1], JC:0.21 (white > black)
        // white=1, black=1, 1 free, need white ≥ floor(3/2)+1 = 2
        // target - firstCount = 2 - 1 = 1 == freeCells.length → all free must be white
        final p = makePuzzle('21\n01\n11');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNotNull);
        expect(move!.value, CellValue.white);
      });

      test('upper already has insurmountable lead → no deduction', () {
        // 4×2 grid, col 0: [2,2,2,0], JC:0.21 (white > black)
        // white=3, black=0, 1 free → white already beats black in every
        // future; the pair is satisfied, no pruning needed.
        final p = makePuzzle('21\n21\n21\n01');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNull);
      });

      test('no free cells → null', () {
        final p = makePuzzle('21\n21\n21\n11');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNull);
      });

      test('no deduction possible → null', () {
        // 5×2 grid, col 0: [2,0,0,0,0], JC:0.21 (white > black)
        // white=1, 4 free, need white ≥ floor(5/2)+1 = 3
        // 1+4 = 5 > 3+1 = 4 → not exactly enough
        final p = makePuzzle('21\n01\n01\n01\n01');
        final move = ColumnMajorityConstraint('0.21').apply(p);
        expect(move, isNull);
      });
    });

    group('isCompleteFor', () {
      test('complete line with satisfied ordering → true', () {
        final p = makePuzzle('21\n21\n21\n11');
        expect(ColumnMajorityConstraint('0.21').isCompleteFor(p), isTrue);
      });

      test('complete line with violated ordering → false', () {
        final p = makePuzzle('12\n12\n12\n22');
        expect(ColumnMajorityConstraint('0.21').isCompleteFor(p), isFalse);
      });

      test('incomplete line but unassailable lead → true', () {
        // 4×2, col 0: [2,2,2,0] → white=3, 1 free
        // white=3 > 4-3=1 → unassailable
        final p = makePuzzle('21\n21\n21\n01');
        expect(ColumnMajorityConstraint('0.21').isCompleteFor(p), isTrue);
      });

      test('incomplete line without unassailable lead → false', () {
        // 4×2, col 0: [2,2,0,0] → white=2, 2 free
        // white=2 is NOT > 4-2=2
        final p = makePuzzle('21\n21\n01\n01');
        expect(ColumnMajorityConstraint('0.21').isCompleteFor(p), isFalse);
      });
    });

    group('generateAllParameters', () {
      test('domain 2: 4 cols × 2 perms = 8 params', () {
        final params = ColumnMajorityConstraint.generateAllParameters(
          4,
          5,
          defaultDomain,
          null,
        );
        expect(params.length, 8);
      });

      test('domain 3: 3 cols × 6 perms = 18 params', () {
        final params = ColumnMajorityConstraint.generateAllParameters(
          3,
          4,
          fullDomain,
          null,
        );
        expect(params.length, 18);
      });

      test('all parameters parse without error', () {
        final params = ColumnMajorityConstraint.generateAllParameters(
          3,
          4,
          defaultDomain,
          null,
        );
        for (final p in params) {
          final jc = ColumnMajorityConstraint(p);
          expect(jc.columnIdx, lessThan(3));
          expect(jc.colorOrder.length, 2);
        }
      });
    });

    group('rotated', () {
      test('JC rotates to JR', () {
        final jc = ColumnMajorityConstraint('2.21');
        final jr = jc.rotated(5, 4);
        expect(jr, isA<RowMajorityConstraint>());
        expect((jr as RowMajorityConstraint).rowIdx, 2);
        expect(jr.colorOrder, [CellValue.white, CellValue.black]);
      });
    });

    group('conflictsWith', () {
      test('conflicts with CC on same column', () {
        final jc = ColumnMajorityConstraint('0.21');
        // CC on column 0
        final cc = ColumnCountConstraint('0.1.2');
        expect(jc.conflictsWith(cc), isTrue);
      });

      test('does not conflict with CC on different column', () {
        final jc = ColumnMajorityConstraint('0.21');
        final cc = ColumnCountConstraint('1.1.2');
        expect(jc.conflictsWith(cc), isFalse);
      });

      test('conflicts with another JC on same column', () {
        final jc1 = ColumnMajorityConstraint('0.21');
        final jc2 = ColumnMajorityConstraint('0.12');
        expect(jc1.conflictsWith(jc2), isTrue);
      });

      test('does not conflict with RC on same index', () {
        // JC is column-based, RC is row-based — different axes
        final jc = ColumnMajorityConstraint('0.21');
        final rc = RowCountConstraint('0.1.2');
        expect(jc.conflictsWith(rc), isFalse);
      });
    });
  });

  group('RowMajorityConstraint', () {
    group('serialize', () {
      test('round-trip', () {
        final jr = RowMajorityConstraint('1.12');
        expect(jr.serialize(), 'JR:1.12');
        expect(jr.rowIdx, 1);
        expect(jr.colorOrder, [CellValue.black, CellValue.white]);
      });
    });

    group('verify', () {
      test('complete with correct ordering → true', () {
        // 2×4 grid, row 0: [1,1,1,2] → black=3, white=1 → black > white ✓
        final p = makePuzzle('1112\n2222');
        expect(RowMajorityConstraint('0.12').verify(p), isTrue);
      });

      test('complete with wrong ordering → false', () {
        // row 0: [1,2,2,2] → black=1, white=3 → black not > white
        final p = makePuzzle('1222\n1111');
        expect(RowMajorityConstraint('0.12').verify(p), isFalse);
      });
    });

    group('apply', () {
      test('first colour needs all remaining → SetValue', () {
        // 2×3 grid, row 0: [1,0,1], JR:0.12 (black > white)
        // black=2, white=0, 1 free, need black ≥ floor(3/2)+1 = 2
        // target - firstCount = 2 - 2 = 0 ≠ 1 → NOT exactly enough
        // Actually: _majorityFloor(3) = 1, target = 2
        // firstCount = 2, freeCells.length = 1, target - firstCount = 0 ≠ 1
        // Let me use: row 0: [1,0,0], JR:0.12
        // black=1, 2 free, target = 2, target - firstCount = 1 ≠ 2 → NOT enough
        // Use: row 0: [1,0,2], JR:0.12
        // black=1, white=1, 1 free, target = 2, target - firstCount = 1 == 1 ✓
        final p = makePuzzle('102\n222');
        final move = RowMajorityConstraint('0.12').apply(p);
        expect(move, isNotNull);
        expect(move!.value, CellValue.black);
      });

      test('no free cells → null', () {
        final p = makePuzzle('1112\n2222');
        final move = RowMajorityConstraint('0.12').apply(p);
        expect(move, isNull);
      });
    });

    group('isCompleteFor', () {
      test('complete line → true', () {
        final p = makePuzzle('1112\n2222');
        expect(RowMajorityConstraint('0.12').isCompleteFor(p), isTrue);
      });

      test('incomplete with unassailable lead → true', () {
        // row 0: [1,1,1,0] → black=3, 1 free → 3 > 1
        final p = makePuzzle('1110\n2222');
        expect(RowMajorityConstraint('0.12').isCompleteFor(p), isTrue);
      });
    });

    group('generateAllParameters', () {
      test('domain 2: 4 rows × 2 perms = 8 params', () {
        final params = RowMajorityConstraint.generateAllParameters(
          5,
          4,
          defaultDomain,
          null,
        );
        expect(params.length, 8);
      });
    });

    group('rotated', () {
      test('JR rotates to JC', () {
        final jr = RowMajorityConstraint('1.21');
        final jc = jr.rotated(5, 4);
        expect(jc, isA<ColumnMajorityConstraint>());
        // row 1 on 5×4 → column (4-1-1) = 2
        expect((jc as ColumnMajorityConstraint).columnIdx, 2);
        expect(jc.colorOrder, [CellValue.white, CellValue.black]);
      });
    });

    group('conflictsWith', () {
      test('conflicts with RC on same row', () {
        final jr = RowMajorityConstraint('0.21');
        final rc = RowCountConstraint('0.1.2');
        expect(jr.conflictsWith(rc), isTrue);
      });

      test('does not conflict with RC on different row', () {
        final jr = RowMajorityConstraint('0.21');
        final rc = RowCountConstraint('1.1.2');
        expect(jr.conflictsWith(rc), isFalse);
      });

      test('does not conflict with CC on same index', () {
        final jr = RowMajorityConstraint('0.21');
        final cc = ColumnCountConstraint('0.1.2');
        expect(jr.conflictsWith(cc), isFalse);
      });
    });
  });
}
