import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

void main() {
  test('debug generateOne internals', () {
    final rng = Random();
    const domain = [1, 2];
    const width = 3, height = 3, size = 9;

    for (int attempt = 0; attempt < 5; attempt++) {
      final ratio = 0.8 + rng.nextDouble() * 0.2;
      final prefilled = (size * (1 - ratio)).ceil();

      final solved = Puzzle.empty(width, height, domain);
      for (int i = 0; i < size; i++) {
        solved.cells[i].setForSolver(domain[rng.nextInt(2)]);
      }
      print(
        '\n=== Attempt $attempt: solution=${solved.cellValues}, prefilled=$prefilled ===',
      );

      final pu = Puzzle.empty(width, height, domain);
      final indices = List.generate(size, (i) => i)..shuffle(rng);
      for (int i = 0; i < prefilled; i++) {
        pu.cells[indices[i]].setForSolver(solved.cellValues[indices[i]]);
        pu.cells[indices[i]].readonly = true;
      }
      print('Puzzle: ${pu.cellValues}');

      // Generate constraints
      final List<Constraint> all = [];
      for (final p in ForbiddenMotif.generateAllParameters(
        width,
        height,
        domain,
      )) {
        final c = ForbiddenMotif(p);
        if (c.verify(solved)) all.add(c);
      }
      for (final p in ParityConstraint.generateAllParameters(width, height)) {
        final c = ParityConstraint(p);
        if (c.verify(solved)) all.add(c);
      }
      for (final p in GroupSize.generateAllParameters(width, height)) {
        final c = GroupSize(p);
        if (c.verify(solved)) all.add(c);
      }
      for (final p in QuantityConstraint.generateAllParameters(
        width,
        height,
        domain,
      )) {
        final c = QuantityConstraint(p);
        if (c.verify(solved)) all.add(c);
      }
      for (final p in SymmetryConstraint.generateAllParameters(width, height)) {
        final c = SymmetryConstraint(p);
        if (c.verify(solved)) all.add(c);
      }
      all.shuffle(rng);
      print('Valid constraints: ${all.length}');

      if (all.isEmpty) continue;
      pu.constraints.add(all.removeAt(0));
      print('First constraint: ${pu.constraints.first.serialize()}');

      // Try solving with just first constraint
      var test = pu.clone();
      test.solve();
      print(
        'After first constraint solve: ratio=${test.computeRatio()}, cells=${test.cellValues}',
      );

      // Generator loop
      double bestRatio = 1.0;
      int added = 1;
      for (final c in all) {
        final cloned = pu.clone();
        cloned.solve();
        final before = cloned.computeRatio();

        cloned.constraints.add(c);
        cloned.solve();
        final after = cloned.computeRatio();

        if (after < before) {
          pu.constraints.add(c);
          bestRatio = after;
          added++;
          print('  +${c.serialize()} => $before -> $after');
          if (after == 0) break;
        }
      }
      print('Final: added=$added, ratio=$bestRatio');
    }
  });
}
