import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

// A 5x5 grid whose centre cell (index 12) has 2 cells on each side —
// every PA side/axis is therefore valid on that anchor.
const _line5x5 = 'v2_12_5x5_0000000000000000000000000';

void main() {
  group('ParityConstraint.mergeSides', () {
    test('truth table: same axis merges, cross axis does not', () {
      // `vertical` requires the top side AND the bottom side to each be
      // balanced (parity.dart builds one independent side list per
      // direction), so vertical ⟺ top ∧ bottom. The merge table below is
      // the direct consequence; cross-axis pairs have no single-side
      // representation and must return null.
      expect(ParityConstraint.mergeSides('top', 'bottom'), 'vertical');
      expect(ParityConstraint.mergeSides('vertical', 'bottom'), 'vertical');
      expect(ParityConstraint.mergeSides('top', 'vertical'), 'vertical');
      expect(ParityConstraint.mergeSides('left', 'right'), 'horizontal');
      expect(ParityConstraint.mergeSides('horizontal', 'left'), 'horizontal');
      // Identical sides dedupe to themselves.
      expect(ParityConstraint.mergeSides('top', 'top'), 'top');
      expect(
        ParityConstraint.mergeSides('horizontal', 'horizontal'),
        'horizontal',
      );
      // Cross-axis: not mergeable.
      expect(ParityConstraint.mergeSides('top', 'left'), isNull);
      expect(ParityConstraint.mergeSides('vertical', 'horizontal'), isNull);
      expect(ParityConstraint.mergeSides('bottom', 'right'), isNull);
    });
  });

  group('ParityConstraint merge through addConstraint', () {
    test('PA top + PA bottom on the same anchor parse into PA vertical', () {
      // top ∧ bottom is exactly vertical: legacy lines carrying the two
      // halves must deserialise into the single combined constraint, the
      // same way LT pairs sharing a letter aggregate at parse.
      final p = Puzzle('${_line5x5}_PA:12.top;PA:12.bottom_0:0_0');
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(1));
      expect(pas.single.serialize(), 'PA:12.vertical');
    });

    test('a side subsumed by an axis-wide constraint is absorbed', () {
      // `vertical` already demands a balanced bottom side, so a separate
      // PA bottom adds nothing — it must vanish into the existing one.
      final p = Puzzle('${_line5x5}_PA:12.vertical;PA:12.bottom_0:0_0');
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(1));
      expect(pas.single.serialize(), 'PA:12.vertical');
    });

    test('adding the exact same PA twice dedupes to one constraint', () {
      // Same anchor, same side: mergeSides(a, a) == a, so the duplicate
      // is a pure no-op instead of a second redundant constraint.
      final p = Puzzle('${_line5x5}_FM:11_0:0_0');
      p.addConstraint(ParityConstraint('12.top'));
      p.addConstraint(ParityConstraint('12.top'));
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(1));
      expect(pas.single.serialize(), 'PA:12.top');
    });

    test('cross-axis PAs on the same anchor stay separate', () {
      // left + top cannot be expressed as a single side value — both
      // constraints are genuinely needed.
      final p = Puzzle('${_line5x5}_FM:11_0:0_0');
      p.addConstraint(ParityConstraint('12.left'));
      p.addConstraint(ParityConstraint('12.top'));
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(2));
      expect(pas.map((c) => c.side).toSet(), {'left', 'top'});
    });

    test('same-axis PAs on different anchors stay separate', () {
      // The merge key is (anchor, axis): cells 12 and 13 each keep their
      // own constraint even though the sides could merge.
      final p = Puzzle('${_line5x5}_FM:11_0:0_0');
      p.addConstraint(ParityConstraint('12.top'));
      p.addConstraint(ParityConstraint('13.bottom'));
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(2));
    });
  });

  group('ParityConstraint merge through prependConstraint', () {
    test('prepending the other half merges and moves the entry to front', () {
      // `simplify` uses the front-insertion path so a candidate's moves
      // take priority; the merge contract must hold there too, with the
      // combined constraint landing in position 0.
      final p = Puzzle('${_line5x5}_FM:11;PA:12.top_0:0_0');
      p.prependConstraint(ParityConstraint('12.bottom'));
      final pas = p.constraints.whereType<ParityConstraint>().toList();
      expect(pas, hasLength(1));
      expect(pas.single.serialize(), 'PA:12.vertical');
      expect(p.constraints.first, same(pas.single));
    });
  });
}
