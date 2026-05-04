import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';

/// Build a puzzle from a grid string (domain [1,2]).
/// Each digit is a cell value (0=empty, 1=black, 2=white), rows separated by newlines.
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
  group('RowCountConstraint.verify', () {
    test('complete puzzle with exact count → valid', () {
      // 3x3 grid, row 0 has values [1,2,1] → 2 cells of color 1
      final p = _make('121\n212\n121');
      expect(RowCountConstraint('0.1.2').verify(p), isTrue);
    });

    test('complete puzzle with wrong count → invalid', () {
      // row 0 has [1,2,1] → 2 cells of color 1, but constraint says 1
      final p = _make('121\n212\n121');
      expect(RowCountConstraint('0.1.1').verify(p), isFalse);
    });

    test('incomplete puzzle with count not exceeded → valid', () {
      // row 0 has [1,0,1] → 2 cells of color 1, constraint says 3 — still possible
      final p = _make('101\n212\n121');
      expect(RowCountConstraint('0.1.3').verify(p), isTrue);
    });

    test('incomplete puzzle with count already exceeded → invalid', () {
      // row 0 has [1,0,1] → 2 cells of color 1, but constraint says 1
      final p = _make('101\n212\n121');
      expect(RowCountConstraint('0.1.1').verify(p), isFalse);
    });

    test('incomplete puzzle with target unreachable → invalid', () {
      // row 0 = [1, 2, 2]: have=1 of color 1, 0 free cells in row.
      // Puzzle overall still incomplete (free cells elsewhere) but target
      // count=2 can never be reached for this row.
      final p = _make('122\n212\n000');
      expect(RowCountConstraint('0.1.2').verify(p), isFalse);
    });

    test('incomplete puzzle with target just reachable → valid', () {
      // row 0 = [1, 0, 0]: have=1, freeInRow=2, target=3 → reachable
      final p = _make('100\n212\n121');
      expect(RowCountConstraint('0.1.3').verify(p), isTrue);
    });
  });

  group('RowCountConstraint.apply', () {
    test('all color cells placed → fills remaining with opposite', () {
      // 2x3 grid, row 0: [1, 0, 0], RC says 1 cell of color 1
      // → free cells in row 0 should become 2
      final p = _make('100\n222');
      final rc = RowCountConstraint('0.1.1');
      final move = rc.apply(p);
      expect(move, isNotNull);
      // free cells in row 0: indices 1 and 2
      expect(move!.value, 2);
      expect(move.idx, anyOf(1, 2));
    });

    test('remaining free cells == remaining needed → fills with color', () {
      // 2x3 grid, row 0: [0, 0, 2], RC says 2 cells of color 1
      // → both free cells must be 1
      final p = _make('002\n222');
      final rc = RowCountConstraint('0.1.2');
      final move = rc.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 1);
      expect(move.idx, anyOf(0, 1));
    });

    test('count exceeded → isImpossible', () {
      // row 0: [1, 1, 0], RC says only 1 cell of color 1 — already 2
      final p = _make('110\n222');
      final rc = RowCountConstraint('0.1.1');
      final move = rc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('no deduction possible → null', () {
      // row 0: [1, 0, 0], RC says 2 cells of color 1
      // 1 placed, 2 free, need 1 more — can't decide which
      final p = _make('100\n222');
      final rc = RowCountConstraint('0.1.2');
      final move = rc.apply(p);
      expect(move, isNull);
    });

    test('no free cells → null', () {
      final p = _make('121\n212');
      final rc = RowCountConstraint('0.1.2');
      final move = rc.apply(p);
      expect(move, isNull);
    });
  });

  group('RowCountConstraint.serialize', () {
    test('round-trip', () {
      final rc = RowCountConstraint('2.1.3');
      expect(rc.serialize(), 'RC:2.1.3');
      expect(rc.rowIdx, 2);
      expect(rc.color, 1);
      expect(rc.count, 3);
    });
  });

  group('RowCountConstraint.generateAllParameters', () {
    test('generates correct number of parameters', () {
      // 3 rows × 2 colors × (width-1) counts = 3 × 2 × 3 = 18
      final params = RowCountConstraint.generateAllParameters(4, 3, [
        1,
        2,
      ], null);
      expect(params.length, 18);
    });

    test('all parameters are valid', () {
      final params = RowCountConstraint.generateAllParameters(3, 4, [
        1,
        2,
      ], null);
      for (final p in params) {
        // Should parse without error
        final rc = RowCountConstraint(p);
        expect(rc.rowIdx, lessThan(4));
        expect(rc.color, anyOf(1, 2));
        expect(rc.count, greaterThan(0));
        expect(rc.count, lessThan(3));
      }
    });
  });

  group('RowCountConstraint.isCompleteFor', () {
    test('row filled and verify true → true', () {
      final p = _make('121\n212\n121');
      final rc = RowCountConstraint('0.1.2');
      expect(rc.isCompleteFor(p), isTrue);
    });

    test('row not filled → false', () {
      final p = _make('101\n212\n121');
      final rc = RowCountConstraint('0.1.2');
      expect(rc.isCompleteFor(p), isFalse);
    });

    test('row filled but verify false → false', () {
      final p = _make('121\n212\n121');
      final rc = RowCountConstraint('0.1.1');
      expect(rc.isCompleteFor(p), isFalse);
    });
  });

  group('RC + CC interaction', () {
    test('RC and CC together force unique solution by propagation', () {
      // 2x2 grid puzzle where each row and column has exactly 1 black cell.
      // This is like a Latin square / nonogram mini-puzzle.
      // Constraints: RC:0, RC:1, CC:0, CC:1 all with count=1 for color 1.
      // Pre-filled: cell (0,1) = white (2), cell (1,0) = white (2)
      // Grid: [?, 2]
      //       [2, ?]
      // RC:0.1.1 → row 0 needs 1 black → cell (0,0) must be 1
      // CC:0.1.1 → column 0 needs 1 black → cell (0,0) must be 1 (already)
      // After applying: [1, 2]
      //                [2, ?]
      // RC:1.1.1 → row 1 needs 1 black → cell (1,1) must be 1
      // CC:1.1.1 → column 1 needs 1 black → cell (1,1) must be 1
      // Solution: [1, 2]
      //           [2, 1] — unique by propagation, no force needed

      final p = Puzzle.empty(2, 2, [1, 2]);
      // Pre-fill
      p.cells[1].setForSolver(2); // (0,1) = white
      p.cells[2].setForSolver(2); // (1,0) = white
      p.cells[1].readonly = true;
      p.cells[2].readonly = true;

      // Add RC and CC constraints for all rows and columns
      p.addConstraint(RowCountConstraint('0.1.1')); // row 0: 1 black
      p.addConstraint(RowCountConstraint('1.1.1')); // row 1: 1 black
      p.addConstraint(ColumnCountConstraint('0.1.1')); // column 0: 1 black
      p.addConstraint(ColumnCountConstraint('1.1.1')); // column 1: 1 black

      // Solve with propagation only (no backtracking)
      p.solve();

      // Verify unique solution found by propagation
      expect(p.complete, isTrue);
      expect(p.cells[0].value, 1); // (0,0) = black
      expect(p.cells[1].value, 2); // (0,1) = white (pre-filled)
      expect(p.cells[2].value, 2); // (1,0) = white (pre-filled)
      expect(p.cells[3].value, 1); // (1,1) = black

      // Verify no force rounds were needed (puzzle was solvable by propagation)
      final solvedPu = p.clone();
      solvedPu.solve();
      expect(solvedPu.computeRatio(), 0);
    });
  });
}
