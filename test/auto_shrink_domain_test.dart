import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  group('PuzzleGenerator.autoShrinkDomain', () {
    // Build a 3-colour puzzle carrying [constraintField] and a [solution]
    // (one CellValue per cell) to stand in for the validated `replay`.
    (Puzzle pu, Puzzle replay) setup(
      String constraintField,
      List<CellValue> solution,
    ) {
      final pu = Puzzle('v2_123_2x2_0000_${constraintField}_0:0_0');
      final replay = pu.clone();
      for (int i = 0; i < solution.length; i++) {
        replay.cells[i].setForSolver(solution[i]);
      }
      return (pu, replay);
    }

    test('drops a colour absent from the solution and unreferenced by any '
        'constraint', () {
      // DF references no colour, and the solution is black/white only →
      // purple is unjustified and must be dropped, promoting the puzzle
      // back to a 2-colour domain.
      final (pu, replay) = setup('DF:0.right', const [
        CellValue.black,
        CellValue.white,
        CellValue.white,
        CellValue.black,
      ]);
      expect(pu.domain, hasLength(3));

      PuzzleGenerator.autoShrinkDomain(pu, replay);

      expect(pu.domain, [CellValue.black, CellValue.white]);
      // The per-cell domains are rewritten too, not just the puzzle's.
      expect(pu.cells.first.domain, [CellValue.black, CellValue.white]);
    });

    test('keeps a colour the solution uses', () {
      // Same setup but the solution paints one cell purple → purple is
      // justified by use and the domain stays at three colours.
      final (pu, replay) = setup('DF:0.right', const [
        CellValue.black,
        CellValue.white,
        CellValue.purple,
        CellValue.black,
      ]);

      PuzzleGenerator.autoShrinkDomain(pu, replay);

      expect(pu.domain, hasLength(3));
    });

    test('keeps a colour a constraint references even if the solution omits '
        'it', () {
      // QA:3.2 caps purple at 2; the solution is purple-free but dropping
      // purple would orphan the constraint, so it must be kept. Contrast
      // with the DF case above, where the identical solution does shrink.
      final (pu, replay) = setup('QA:3.2', const [
        CellValue.black,
        CellValue.white,
        CellValue.white,
        CellValue.black,
      ]);

      PuzzleGenerator.autoShrinkDomain(pu, replay);

      expect(pu.domain, contains(CellValue.purple));
    });

    test('is a no-op when every declared colour is already justified', () {
      // Solution uses all three colours → nothing to drop, domain unchanged.
      final (pu, replay) = setup('DF:0.right', const [
        CellValue.black,
        CellValue.white,
        CellValue.purple,
        CellValue.purple,
      ]);
      final before = List.of(pu.domain);

      PuzzleGenerator.autoShrinkDomain(pu, replay);

      expect(pu.domain, before);
    });
  });
}
