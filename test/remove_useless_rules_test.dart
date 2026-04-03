import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';

void main() {
  group('countSolutions', () {
    test('returns 1 for a puzzle with a unique solution', () {
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      expect(p.countSolutions(), 1);
    });

    test('returns 2 for a puzzle with no constraints', () {
      // A 2x2 grid with no constraints has multiple valid colorings
      final p = Puzzle.empty(2, 2, [1, 2]);
      expect(p.countSolutions(), 2);
    });
  });

  group('removeUselessRules', () {
    test('keeps all constraints when each one is necessary', () {
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      expect(p.countSolutions(), 1);
      p.removeUselessRules();
      // All 3 constraints are needed for uniqueness — none removed
      expect(p.constraints.length, 3);
    });

    test('removes a redundant constraint', () {
      // Start with a puzzle that has a unique solution with 3 constraints
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      // Add a redundant FM that is already satisfied and doesn't help
      p.constraints.add(ForbiddenMotif('22'));
      expect(p.constraints.length, 4);
      p.removeUselessRules();
      // FM:22 should be removed since the puzzle already has a unique solution without it
      expect(p.constraints.length, 3);
    });
  });
}
