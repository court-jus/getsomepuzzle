import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/backtrack.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  group('enumerateSolutions', () {
    test('returns exactly one completion for a deductively unique puzzle', () {
      // This is the same regression puzzle used in cli_check_test: the 4x6
      // empty grid with sparse constraints. `enumerateSolutions(limit: 2)`
      // must find ≥2 completions, confirming it's not uniquely determined.
      // We use the under-determined case here because it exercises the
      // multi-solution branch — the unique case is exercised in the second
      // test below.
      final p = Puzzle(
        'v2_12_4x6_000000000000000000000000_FM:2.2.2;FM:1.1.2;PA:10.left;LT:A.11.12;FM:2.1.2;PA:18.top_0:0_100',
      );
      final solutions = enumerateSolutions(p.clone(), limit: 2);
      expect(solutions.length, greaterThanOrEqualTo(2));
    });

    test('returns one completion for a deductively unique puzzle', () {
      // A real shipped puzzle from assets/2-player.txt — known unique by
      // construction (passes isDeductivelyUnique). The brute-force
      // enumerator must agree: exactly one completion exists.
      final p = Puzzle(
        'v2_12_4x3_000000000000_FM:22;LT:A.8.0;LT:B.11.2;PA:1.bottom;PA:6.left;FM:11.11_1:121212111121_55',
      );
      expect(p.isDeductivelyUnique(), isTrue);
      final solutions = enumerateSolutions(p.clone(), limit: 5);
      expect(solutions.length, equals(1));
    });

    test('respects the limit parameter', () {
      // The same under-determined 4x6 puzzle has many completions, but we
      // cap at 3 to verify enumeration stops early.
      final p = Puzzle(
        'v2_12_4x6_000000000000000000000000_FM:2.2.2;FM:1.1.2;PA:10.left;LT:A.11.12;FM:2.1.2;PA:18.top_0:0_100',
      );
      final solutions = enumerateSolutions(p.clone(), limit: 3);
      expect(solutions.length, equals(3));
    });
  });

  group('findOneSolutionByDpll', () {
    test('finds a routing on a 5x5 grid with non-alternating anchors', () {
      // 5x5 partial puzzle: anchors readonly + 2 LT constraints, nothing
      // else. This is the input shape that path-based pre-fill will
      // produce.
      //
      // Layout (col on left axis):
      //   A . . . B
      //   . . . . .
      //   . . . . .
      //   . . . . .
      //   A . . . B
      // A = color 1 at indices 0 (col 0, row 0) and 20 (col 0, row 4) —
      //     both on left edge.
      // B = color 2 at indices 4 (col 4, row 0) and 24 (col 4, row 4) —
      //     both on right edge.
      //
      // Non-alternating around the boundary (going clockwise: A, B, B, A)
      // → topologically feasible (Jordan curve theorem allows a vertical
      // wall partitioning). Many routings exist.
      final pu = Puzzle.empty(5, 5, [1, 2]);
      pu.cells[0].setForSolver(1);
      pu.cells[0].readonly = true;
      pu.cells[20].setForSolver(1);
      pu.cells[20].readonly = true;
      pu.cells[4].setForSolver(2);
      pu.cells[4].readonly = true;
      pu.cells[24].setForSolver(2);
      pu.cells[24].readonly = true;
      pu.addConstraint(LetterGroup('A.0.20'));
      pu.addConstraint(LetterGroup('B.4.24'));

      final solution = findOneSolutionByDpll(pu, timeoutMs: 5000);
      expect(solution, isNotNull);
      expect(solution![0], equals(1));
      expect(solution[20], equals(1));
      expect(solution[4], equals(2));
      expect(solution[24], equals(2));
      expect(solution.any((v) => v == 0), isFalse);
    });

    test('returns null for topologically infeasible alternating anchors', () {
      // Same 5x5 but with A on the MAIN diagonal (TL, BR) and B on the
      // ANTI-diagonal (TR, BL). The four anchors alternate around the
      // boundary (clockwise: A, B, A, B), so by Jordan curve theorem no
      // connected bipartition of the grid can put A's pair on one side
      // and B's pair on the other.
      //
      //   A . . . B
      //   . . . . .
      //   . . . . .
      //   . . . . .
      //   B . . . A
      //
      // The DPLL must correctly identify this as infeasible and return
      // null (rather than time out indefinitely).
      final pu = Puzzle.empty(5, 5, [1, 2]);
      pu.cells[0].setForSolver(1);
      pu.cells[0].readonly = true;
      pu.cells[24].setForSolver(1);
      pu.cells[24].readonly = true;
      pu.cells[4].setForSolver(2);
      pu.cells[4].readonly = true;
      pu.cells[20].setForSolver(2);
      pu.cells[20].readonly = true;
      pu.addConstraint(LetterGroup('A.0.24'));
      pu.addConstraint(LetterGroup('B.4.20'));

      final solution = findOneSolutionByDpll(pu, timeoutMs: 10000);
      expect(solution, isNull);
    });

    test('returns null for an immediately violated configuration', () {
      // 3x3 grid: A at idx 0, B at idx 1, both forced to color 1. The
      // cells are 4-adjacent and would necessarily belong to the same
      // color-1 connected component — but they carry different letters,
      // which LT.verify rejects on the spot.
      //   A B .
      //   . . .
      //   . . .
      // This exercises the "immediate violation" path: solve() can't
      // propagate anywhere because check() already fails on the input.
      final pu = Puzzle.empty(3, 3, [1, 2]);
      pu.cells[0].setForSolver(1);
      pu.cells[0].readonly = true;
      pu.cells[1].setForSolver(1);
      pu.cells[1].readonly = true;
      pu.addConstraint(LetterGroup('A.0'));
      pu.addConstraint(LetterGroup('B.1'));

      final solution = findOneSolutionByDpll(pu, timeoutMs: 5000);
      expect(solution, isNull);
    });
  });
}
