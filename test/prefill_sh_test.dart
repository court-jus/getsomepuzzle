import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sh.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  group('preFillSh domain-3 colour distribution', () {
    test('at least one seed produces all 3 colours on a 4×4 grid', () {
      // With domain [black, white, purple] and ~12 background cells, the
      // probability that both non-motif colours appear is ~1 − 2×0.5¹².
      // Over 100 seeds, at least one should succeed.
      bool found = false;
      for (int seed = 0; seed < 100; seed++) {
        final solved = preFillSh(4, 4, fullDomain, Random(seed));
        final used = solved.cells.map((c) => c.value).toSet();
        used.remove(CellValue.free);
        if (used.length >= 3) {
          found = true;
          break;
        }
      }
      expect(
        found,
        isTrue,
        reason: 'no seed out of 100 produced a solved grid with all 3 colours',
      );
    });
  });

  group('findAdditionalPositions with mixed background', () {
    test('accepts a bounding box containing both non-motif colours', () {
      // 3×3 puzzle with domain [black, white, purple].
      // Grid:  B B W        L-shape (11.10) at (0,0)
      //        B P W        cell (1,1) = purple (not the first non-motif
      //        f f f        colour, so the old binary check would reject).
      final p = Puzzle.empty(3, 3, fullDomain);
      p.cells[0].setForSolver(CellValue.black); // (0,0)
      p.cells[1].setForSolver(CellValue.black); // (0,1)
      p.cells[3].setForSolver(CellValue.black); // (1,0)
      p.cells[4].setForSolver(CellValue.purple); // (1,1) — purple, not white
      p.cells[2].setForSolver(CellValue.white); // (0,2)
      p.cells[5].setForSolver(CellValue.white); // (1,2)
      // row 2 = all free

      p.addConstraint(ShapeConstraint("11.10"));
      final positions = ShapeConstraint.findAdditionalPositions(p);
      // The variant [[free, black], [black, black]] should be found at (1,1):
      // bounding-box cells (1,1)=P, (1,2)=W, (2,1)=free, (2,2)=free are all
      // either free or a non-motif colour.
      expect(positions, isNotEmpty);
      expect(
        positions.any((pos) => pos.$1 == (1, 1)),
        isTrue,
        reason:
            'expected position (1,1) with variant [[free,B],[B,B]], '
            'but it was rejected because cell (1,1) is purple',
      );
    });
  });

  group('domain-2 non-regression', () {
    test(
      'findAdditionalPositions behaves identically to the old binary check',
      () {
        // Exact same case as the existing test in shape_utils_test.dart.
        final p = Puzzle.empty(3, 3, defaultDomain);
        p.cells[0].setForSolver(CellValue.black);
        p.cells[1].setForSolver(CellValue.black);
        p.cells[3].setForSolver(CellValue.black);
        p.cells[4].setForSolver(CellValue.white);
        p.addConstraint(ShapeConstraint("11.10"));
        final positions = ShapeConstraint.findAdditionalPositions(p);
        expect(positions.length, 1);
        expect(positions.first.$1, (1, 1));
        expect(positions.first.$2, [
          [CellValue.free, CellValue.black],
          [CellValue.black, CellValue.black],
        ]);
      },
    );
  });
}
