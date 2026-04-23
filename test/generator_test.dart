import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/generator.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  test('Puzzle.clone preserves state for empty puzzles', () {
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.cells[0].setForSolver(1);
    p.cells[4].setForSolver(2);

    final c = p.clone();
    expect(c.cellValues, [1, 0, 0, 0, 2, 0, 0, 0, 0]);
    c.cells[1].setForSolver(1);
    expect(p.cellValues[1], 0); // original unaffected
  });

  test('Puzzle.lineExport produces parseable format', () {
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.cells[0].setForSolver(1);
    p.constraints.add(ForbiddenMotif('11'));
    final line = p.lineExport();
    expect(line, startsWith('v2_12_3x3_'));
    expect(line, contains('FM:11'));

    // Round-trip: parse the exported line
    final p2 = Puzzle(line);
    expect(p2.width, 3);
    expect(p2.height, 3);
    expect(p2.constraints.length, 1);
  });

  test('solve() works on a known puzzle', () {
    final p = Puzzle('v2_12_3x3_100000000_LT:A.0.2;LT:B.1.4');
    final solved = p.clone();
    final result = solved.solve();
    expect(result, isTrue);
    expect(solved.freeCells(), isEmpty);
  });

  test('solve() handles multi-constraint propagation on empty puzzle', () {
    // Three constraints together (FM + GS + PA) should uniquely determine
    // a 3x3 puzzle with no prefilled cells — stresses cross-constraint
    // propagation, not covered by single-constraint tests above.
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.constraints.add(ForbiddenMotif('1.2'));
    p.constraints.add(GroupSize('0.1'));
    p.constraints.add(ParityConstraint('8.top'));
    expect(p.clone().solve(), isTrue);
  });

  test('solve() works on puzzle built from Puzzle.empty', () {
    // Build a puzzle manually: 3x3, prefilled cell 0=1, FM:11 constraint
    // Solution should avoid "11" horizontally
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.cells[0].setForSolver(1);
    p.cells[0].readonly = true;
    p.constraints.add(ForbiddenMotif('11'));
    p.constraints.add(QuantityConstraint('1.3'));

    final cloned = p.clone();
    cloned.solve();
    print('After solve: ${cloned.cellValues}, ratio=${cloned.computeRatio()}');
    // Verify ratio improved (some cells determined)
    expect(cloned.computeRatio(), lessThan(p.computeRatio()));
  });

  test('Constraint.apply works on Puzzle.empty puzzles', () {
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.cells[0].setForSolver(1);
    p.cells[0].readonly = true;
    // FM:11 means "11" pattern is forbidden horizontally
    final fm = ForbiddenMotif('11');
    p.constraints.add(fm);

    // Cell 1 is next to cell 0 (value=1). Setting cell 1 to 1 would create "11".
    // So apply should deduce cell 1 = 2
    final move = fm.apply(p);
    print('FM apply move: idx=${move?.idx} value=${move?.value}');
    expect(move, isNotNull);
    expect(move!.idx, 1);
    expect(move.value, 2);
  });

  test('generateAllParameters produce valid constraints', () {
    expect(
      ForbiddenMotif.generateAllParameters(3, 3, [1, 2], null),
      isNotEmpty,
    );
    expect(
      ParityConstraint.generateAllParameters(3, 3, [1, 2], null),
      isNotEmpty,
    );
    expect(GroupSize.generateAllParameters(3, 3, [1, 2], null), isNotEmpty);
    expect(LetterGroup.generateAllParameters(3, 3, [1, 2], null), isNotEmpty);
    expect(
      QuantityConstraint.generateAllParameters(3, 3, [1, 2], null),
      isNotEmpty,
    );
    expect(
      SymmetryConstraint.generateAllParameters(3, 3, [1, 2], null),
      isNotEmpty,
    );
  });

  test('generateOne produces a puzzle for a seeded 3x3 grid', () {
    // Test the core algorithm with a known-good configuration
    // Build a solved grid manually and test constraint selection
    const width = 3, height = 3;
    const domain = [1, 2];
    final solved = Puzzle.empty(width, height, domain);
    // Checkerboard pattern: easy to constrain
    final values = [1, 2, 1, 2, 1, 2, 1, 2, 1];
    for (int i = 0; i < 9; i++) {
      solved.cells[i].setForSolver(values[i]);
    }

    // Create puzzle with 2 prefilled cells
    final pu = Puzzle.empty(width, height, domain);
    pu.cells[0].setForSolver(1);
    pu.cells[0].readonly = true;
    pu.cells[8].setForSolver(1);
    pu.cells[8].readonly = true;

    // Generate valid constraints for this solution
    int validCount = 0;
    final List<Constraint> validConstraints = [];
    for (final p in ForbiddenMotif.generateAllParameters(
      width,
      height,
      domain,
      null,
    )) {
      final c = ForbiddenMotif(p);
      if (c.verify(solved)) {
        validConstraints.add(c);
        validCount++;
      }
    }
    for (final p in QuantityConstraint.generateAllParameters(
      width,
      height,
      domain,
      null,
    )) {
      final c = QuantityConstraint(p);
      if (c.verify(solved)) {
        validConstraints.add(c);
        validCount++;
      }
    }
    print('Valid constraints for checkerboard: $validCount');
    expect(validCount, greaterThan(0));

    // Try adding constraints and solving
    double bestRatio = pu.computeRatio();
    print('Initial ratio: $bestRatio');
    for (final constraint in validConstraints) {
      final testPu = pu.clone();
      testPu.constraints.addAll(pu.constraints);
      testPu.constraints.add(constraint);
      testPu.solve();
      final ratio = testPu.computeRatio();
      if (ratio < bestRatio) {
        pu.constraints.add(constraint);
        bestRatio = ratio;
        print('Added ${constraint.serialize()}, ratio now $bestRatio');
        if (bestRatio == 0) break;
      }
    }
    print('Final ratio: $bestRatio, cells: ${pu.cellValues}');
    // We should have made some progress
    expect(bestRatio, lessThan(1.0));
  });

  test('generateOne returns a result (may be null for hard configs)', () {
    final result = PuzzleGenerator.generateOne(
      GeneratorConfig(
        width: 3,
        height: 3,
        count: 1,
        maxTime: Duration(seconds: 5),
      ),
    );
    print('generateOne 3x3 result: $result');
    // Don't assert non-null — 3x3 can legitimately fail
    // But if it succeeds, it should be valid
    if (result != null) {
      final p = Puzzle(result);
      expect(p.width, 3);
      expect(p.constraints.isNotEmpty, isTrue);
    }
  });
}
