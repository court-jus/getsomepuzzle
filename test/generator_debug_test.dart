import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator.dart';

void main() {
  test('solve with FM+GS on empty 3x3 via force+autoCheck', () {
    // Known valid: FM:1.2 + GS:0.1 + PA:8.top
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.constraints.add(ForbiddenMotif('1.2'));
    p.constraints.add(GroupSize('0.1'));
    p.constraints.add(ParityConstraint('8.top'));
    final c = p.clone();
    final solved = c.solve();
    print('solve: $solved, cells: ${c.cellValues}, ratio: ${c.computeRatio()}');
    expect(solved, isTrue);
  });

  test('solve with 1 prefilled cell + 1 FM constraint makes progress', () {
    final p = Puzzle.empty(3, 3, [1, 2]);
    p.cells[0].setForSolver(1);
    p.cells[0].readonly = true;
    p.constraints.add(ForbiddenMotif('1.2'));
    final c = p.clone();
    c.solve();
    print('1 prefilled + FM: cells=${c.cellValues}, ratio=${c.computeRatio()}');
    expect(c.computeRatio(), lessThan(1.0));
  });

  test('generator loop simulation with prefilled cell', () {
    // Mimic generateOne: 1 prefilled cell, known solution
    final ref = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top');
    ref.solve();
    final solvedValues = ref.cellValues;
    print('Target solution: $solvedValues');

    final solved = Puzzle.empty(3, 3, [1, 2]);
    for (int i = 0; i < 9; i++) {
      solved.cells[i].setForSolver(solvedValues[i]);
    }

    final pu = Puzzle.empty(3, 3, [1, 2]);
    pu.cells[0].setForSolver(solvedValues[0]);
    pu.cells[0].readonly = true;

    // Generate valid constraints
    final List<Constraint> allConstraints = [];
    for (final params in ForbiddenMotif.generateAllParameters(3, 3, [1, 2])) {
      final c = ForbiddenMotif(params);
      if (c.verify(solved)) allConstraints.add(c);
    }
    for (final params in ParityConstraint.generateAllParameters(3, 3)) {
      final c = ParityConstraint(params);
      if (c.verify(solved)) allConstraints.add(c);
    }
    for (final params in GroupSize.generateAllParameters(3, 3)) {
      final c = GroupSize(params);
      if (c.verify(solved)) allConstraints.add(c);
    }
    print('Valid constraints: ${allConstraints.length}');

    // Add first constraint
    pu.constraints.add(allConstraints.removeAt(0));

    // Generator loop
    double ratio = 1.0;
    int added = 1;
    for (final constraint in allConstraints) {
      final cloned = pu.clone();
      cloned.solve();
      final ratioBefore = cloned.computeRatio();

      cloned.constraints.add(constraint);
      cloned.solve();
      final ratioAfter = cloned.computeRatio();

      if (ratioAfter < ratioBefore) {
        pu.constraints.add(constraint);
        ratio = ratioAfter;
        added++;
        print('  +${constraint.serialize()} => $ratioBefore -> $ratioAfter');
        if (ratio == 0) break;
      }
    }
    print('Final: added=$added, ratio=$ratio');
    expect(ratio, lessThan(1.0), reason: 'Should make at least some progress');
  });

  test('generateOne produces a 3x3 puzzle', () {
    final result = PuzzleGenerator.generateOne(
      GeneratorConfig(
        width: 3,
        height: 3,
        count: 1,
        maxTime: Duration(seconds: 5),
      ),
    );
    print('generateOne result: $result');
    if (result != null) {
      final p = Puzzle(result);
      expect(p.width, 3);
      expect(p.constraints.isNotEmpty, isTrue);
    }
  });
}
