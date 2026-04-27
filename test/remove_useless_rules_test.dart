import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';

void main() {
  group('isDeductivelyUnique', () {
    test('returns true for a puzzle with a unique deductive solution', () {
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      expect(p.isDeductivelyUnique(), isTrue);
    });

    test('returns false for a 2x2 grid with no constraints', () {
      // No constraints at all → multiple valid colorings, deductive solver
      // can't pin a unique answer.
      final p = Puzzle.empty(2, 2, [1, 2]);
      expect(p.isDeductivelyUnique(), isFalse);
    });
  });

  group('removeUselessRules', () {
    test('preserves deductive uniqueness', () {
      // Whatever subset survives, the puzzle must still be deductively
      // unique — otherwise removeUselessRules would have stripped a load-
      // bearing constraint.
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      expect(p.isDeductivelyUnique(), isTrue);
      p.removeUselessRules();
      expect(p.isDeductivelyUnique(), isTrue);
    });

    test('strips a constraint that is provably redundant', () {
      // Start from a puzzle that's already deductively unique, then add a
      // redundant FM:22 (already satisfied by the solution) and verify
      // the result has at most the original count — the redundant one
      // (and any earlier-redundant rules) are dropped.
      final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_0');
      final originalLength = p.constraints.length;
      p.constraints.add(ForbiddenMotif('22'));
      expect(p.constraints.length, originalLength + 1);
      p.removeUselessRules();
      expect(p.constraints.length, lessThanOrEqualTo(originalLength));
      expect(p.isDeductivelyUnique(), isTrue);
    });
  });
}
