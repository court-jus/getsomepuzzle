import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
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
  group('ColumnCountConstraint.verify', () {
    test('complete puzzle with exact count → valid', () {
      // 3x3 grid, column 0 has values [1,2,1] → 2 cells of color 1
      final p = _make('12\n21\n12');
      expect(ColumnCountConstraint('0.1.2').verify(p), isTrue);
    });

    test('complete puzzle with wrong count → invalid', () {
      // column 0 has [1,2,1] → 2 cells of color 1, but constraint says 1
      final p = _make('12\n21\n12');
      expect(ColumnCountConstraint('0.1.1').verify(p), isFalse);
    });

    test('incomplete puzzle with count not exceeded → valid', () {
      // column 0 has [1,0,1] → 2 cells of color 1, constraint says 3 — still possible
      final p = _make('12\n02\n12');
      expect(ColumnCountConstraint('0.1.3').verify(p), isTrue);
    });

    test('incomplete puzzle with count already exceeded → invalid', () {
      // column 0 has [1,0,1] → 2 cells of color 1, but constraint says 1
      final p = _make('12\n02\n12');
      expect(ColumnCountConstraint('0.1.1').verify(p), isFalse);
    });

    test('checks the right column', () {
      // column 1 has [2,1,2] → 1 cell of color 1
      final p = _make('12\n21\n12');
      expect(ColumnCountConstraint('1.1.1').verify(p), isTrue);
      expect(ColumnCountConstraint('1.1.2').verify(p), isFalse);
    });
  });

  group('ColumnCountConstraint.apply', () {
    test('all color cells placed → fills remaining with opposite', () {
      // 3x2 grid, column 0: [1, 0, 0], CC says 1 cell of color 1
      // → free cells in column 0 should become 2
      final p = _make('12\n02\n02');
      final cc = ColumnCountConstraint('0.1.1');
      final move = cc.apply(p);
      expect(move, isNotNull);
      // cell at (1,0) = index 2 or (2,0) = index 4
      expect(move!.value, 2);
      expect(move.idx, anyOf(2, 4));
    });

    test('remaining free cells == remaining needed → fills with color', () {
      // 3x2 grid, column 0: [0, 0, 2], CC says 2 cells of color 1
      // → both free cells must be 1
      final p = _make('02\n02\n22');
      final cc = ColumnCountConstraint('0.1.2');
      final move = cc.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 1);
      expect(move.idx, anyOf(0, 2));
    });

    test('count exceeded → isImpossible', () {
      // column 0: [1, 1, 0], CC says only 1 cell of color 1 — already 2
      final p = _make('12\n12\n02');
      final cc = ColumnCountConstraint('0.1.1');
      final move = cc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('no deduction possible → null', () {
      // column 0: [1, 0, 0], CC says 2 cells of color 1
      // 1 placed, 2 free, need 1 more — can't decide which
      final p = _make('12\n02\n02');
      final cc = ColumnCountConstraint('0.1.2');
      final move = cc.apply(p);
      expect(move, isNull);
    });

    test('no free cells → null', () {
      final p = _make('12\n21\n12');
      final cc = ColumnCountConstraint('0.1.2');
      final move = cc.apply(p);
      expect(move, isNull);
    });
  });

  group('ColumnCountConstraint.serialize', () {
    test('round-trip', () {
      final cc = ColumnCountConstraint('2.1.3');
      expect(cc.serialize(), 'CC:2.1.3');
      expect(cc.columnIdx, 2);
      expect(cc.color, 1);
      expect(cc.count, 3);
    });
  });

  group('ColumnCountConstraint.generateAllParameters', () {
    test('generates correct number of parameters', () {
      // 4 columns × 2 colors × (height-1) counts = 4 × 2 × 4 = 32
      final params = ColumnCountConstraint.generateAllParameters(4, 5, [
        1,
        2,
      ], null);
      expect(params.length, 32);
    });

    test('all parameters are valid', () {
      final params = ColumnCountConstraint.generateAllParameters(3, 4, [
        1,
        2,
      ], null);
      for (final p in params) {
        // Should parse without error
        final cc = ColumnCountConstraint(p);
        expect(cc.columnIdx, lessThan(3));
        expect(cc.color, anyOf(1, 2));
        expect(cc.count, greaterThan(0));
        expect(cc.count, lessThan(4));
      }
    });
  });
}
