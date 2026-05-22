import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('Puzzle.findAllMoves', () {
    test('no constraints → empty list', () {
      // A puzzle with no constraints has no deducible move, so findAllMoves
      // must return an empty list (not a singleton with a spurious entry).
      final p = makePuzzle('00');
      expect(p.findAllMoves(), isEmpty);
    });

    test('single constraint forcing one cell → exactly one move', () {
      // Grid "10": one black cell, one empty cell. Quantity('1.1') states
      // there must be exactly 1 black cell, so the free cell at idx 1 is
      // forced to white. Only this single constraint can fire → one move.
      final p = makePuzzle('10');
      p.addConstraint(QuantityConstraint('1.1'));
      final moves = p.findAllMoves();
      expect(moves, hasLength(1));
      expect(moves.first.idx, 1);
      expect(moves.first.value, 2);
    });

    test('two redundant constraints → two moves (no dedup)', () {
      // Two identical Quantity constraints both deduce idx 1 = white.
      // findAllMoves intentionally does NOT deduplicate: the script that
      // looks for single-path puzzles relies on `moves.length == 1` as a
      // strict signal, so a redundant constraint correctly counts twice.
      final p = makePuzzle('10');
      p.addConstraint(QuantityConstraint('1.1'));
      p.addConstraint(QuantityConstraint('1.1'));
      final moves = p.findAllMoves();
      expect(moves, hasLength(2));
      expect(moves.every((m) => m.idx == 1 && m.value == 2), isTrue);
    });

    test('coherence with apply(): empty iff apply returns null', () {
      // findAllMoves and apply walk the same constraints/complicities lists;
      // when there is nothing to deduce, both must agree. This guards
      // against future divergence between the two methods.
      final stuck = makePuzzle('00');
      expect(stuck.apply(), isNull);
      expect(stuck.findAllMoves(), isEmpty);

      final active = makePuzzle('10');
      active.addConstraint(QuantityConstraint('1.1'));
      expect(active.apply(), isNotNull);
      expect(active.findAllMoves(), isNotEmpty);
    });
  });
}
