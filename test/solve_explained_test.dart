import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main() {
  test('solveExplained returns all steps for a propagation-only puzzle', () {
    // 6x7 puzzle with many prefilled cells — fully solvable by propagation
    final p = Puzzle('v2_12_6x7_002000210001022011020210200200100010202211_FM:12;FM:1.1.2;PA:17.top_0:0_0');
    final freeCount = p.cellValues.where((v) => v == 0).length;
    final steps = p.solveExplained();

    // Should determine all free cells
    expect(steps.length, freeCount);
    // All steps should be propagation
    expect(steps.every((s) => s.method == SolveMethod.propagation), isTrue);
    // Each step should reference a constraint
    expect(steps.every((s) => s.constraint.isNotEmpty), isTrue);
    // The puzzle should not be modified
    expect(p.cellValues.where((v) => v == 0).length, freeCount);
  });

  test('solveExplained includes force steps when needed', () {
    // This puzzle requires force (no prefilled cells, must reason by contradiction)
    final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_2');
    final steps = p.solveExplained();

    // Should determine all 9 cells
    expect(steps.length, 9);
    // Should have at least one force step
    expect(steps.any((s) => s.method == SolveMethod.force), isTrue);
    // Force steps have no constraint name
    for (final s in steps.where((s) => s.method == SolveMethod.force)) {
      expect(s.constraint, isEmpty);
    }
  });

  test('solveExplained does not modify the original puzzle', () {
    final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_2');
    final before = List<int>.from(p.cellValues);
    p.solveExplained();
    expect(p.cellValues, before);
  });
}
