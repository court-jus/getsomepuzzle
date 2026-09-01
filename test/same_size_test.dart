import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/same_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('SameSize serialization and parameters', () {
    test('serializes, parses and rotates symbol-marked cells', () {
      final constraint = SameSize('H.0.3.5');
      expect(constraint.serialize(), 'SZ:H.0.3.5');
      expect(constraint.glyph, '♥');
      expect(constraint.rotated(2, 3).serialize(), 'SZ:H.2.4.3');
    });

    test('generates unordered pairs for all four symbols', () {
      final params = SameSize.generateAllParameters(2, 2, defaultDomain, null);
      expect(params.length, 24);
      expect(params.toSet().length, params.length);
      expect(params, contains('H.0.1'));
      expect(params, contains('D.0.1'));
      expect(params, contains('S.2.3'));
      expect(params, contains('C.0.3'));
    });
  });

  group('SameSize.verify', () {
    test('accepts equal-sized distinct groups', () {
      final p = makePuzzle('1122\n2211');
      final constraint = SameSize('H.0.6');
      expect(constraint.verify(p), isTrue);
      expect(constraint.isCompleteFor(p), isTrue);
    });

    test('rejects marked cells in the same group', () {
      final p = makePuzzle('11');
      final constraint = SameSize('H.0.1');
      expect(constraint.verify(p), isFalse);
      expect(constraint.isCompleteFor(p), isFalse);
      expect(constraint.apply(p), isA<Impossible>());
    });

    test('rejects an incomplete state with marked cells already connected', () {
      final p = makePuzzle('110');
      expect(SameSize('H.0.1').verify(p), isFalse);
    });

    test('keeps distinct marked groups from merging through one free cell', () {
      final p = makePuzzle('101');
      final constraint = SameSize('H.0.2');
      final move = constraint.apply(p);
      expect(move, isA<RemoveOption>());
      expect(move!.idx, 1);
      expect(move.removeOption, CellValue.black);
    });

    test('keeps a free marked cell out of an existing marked group', () {
      final p = makePuzzle('10');
      final constraint = SameSize('H.0.1');
      final move = constraint.apply(p);
      expect(move, isA<RemoveOption>());
      expect(move!.idx, 1);
      expect(move.removeOption, CellValue.black);
    });

    test('rejects a smaller group that cannot grow', () {
      final p = makePuzzle('120\n220\n000');
      expect(SameSize('H.0.1').verify(p), isFalse);
    });
  });

  group('SameSize.apply', () {
    test('reuses GroupSize growth and retags the move', () {
      final p = makePuzzle('100\n200\n022');
      final constraint = SameSize('H.0.7');
      final move = constraint.apply(p);
      expect(move, isA<SetValue>());
      final actualMove = move!;
      expect(actualMove.idx, 1);
      expect(actualMove.value, CellValue.black);
      expect(actualMove.givenBy, same(constraint));
    });

    test('returns no move when all relevant groups already match', () {
      final p = makePuzzle('1122\n2211');
      expect(SameSize('H.0.6').apply(p), isNull);
    });

    test(
      'does not prune a growth path that would overshoot the current maximum',
      () {
        // 2x4, SZ:H marking black 4 (group {4,5}, size 2) and white 6
        // (group {6}, size 1). The white group's exits are 2 and 7; entering
        // exit 2 merges the same-colour group {3} and would take the group to
        // 3 — above the current maximum of 2. That must NOT prune white from
        // 2: the marked groups may equalise at any shared size >= 2 (here 4,
        // in the completion 1122/1122). The old exact-size logic rejected the
        // merge and made the puzzle IMPOSSIBLE.
        final p = makePuzzle('0002\n1120');
        final constraint = SameSize('H.4.6');
        // No forced deduction at this point: {6} can grow via 2 or 7, and
        // {4,5} is already at the floor. The bad prune would have returned
        // RemoveOption(2, white).
        expect(constraint.apply(p), isNull);
        // And the stored completion keeps both marked groups distinct and
        // equal-sized, so verify accepts it.
        final done = makePuzzle('1122\n1122');
        expect(constraint.verify(done), isTrue);
      },
    );

    test('grows a smaller marked group through its only exit to the floor', () {
      // 2x4, SZ:H marking black 0 (group {0}, size 1) and white 4 (group
      // {4,5}, size 2). The black group's only exit is 1; entering it merges
      // black {2}, so under an EXACT target of 2 that growth would overshoot
      // (1 + 1 > 1) and the old logic declared the state impossible. Under a
      // floor the exit MUST still take black — {0} has to reach the floor,
      // and the merged group may legitimately be larger (both groups finish
      // at 4 in the completion 1111/2222).
      final p = makePuzzle('1010\n2200');
      final constraint = SameSize('H.0.4');
      final move = constraint.apply(p);
      expect(move, isA<SetValue>());
      final actualMove = move!;
      expect(actualMove.idx, 1);
      expect(actualMove.value, CellValue.black);
      expect(actualMove.givenBy, same(constraint));
    });

    test(
      'solves the 3x10 regression puzzle instead of declaring IMPOSSIBLE',
      () {
        // Corpus puzzle whose stored solution is valid (every constraint
        // verifies, including both SZ), but whose solver run used to end in
        // "IMPOSSIBLE detected by SZ:D.12.15": the exact-size growth of the
        // white marked group pruned white from (5,0) (cell 15), merging both
        // D-marked cells into one group.
        final p = Puzzle(
          'v2_12_3x10_000000000000000020000000000000_CC:0.1.5;CC:2.1.5;'
          'DF:19.down;NC:2.1.2;NC:23.2.3;NC:28.1.0;RC:1.2.2;RC:7.2.2;'
          'CC:1.1.4;RC:2.2.1;RC:4.2.1;RC:6.1.1;SZ:D.12.15;SZ:S.13.16_'
          '1:111221211121112221212122122222_100_scenario:classic',
        );
        final trace = p.solveTrace();
        expect(
          trace.impossibleBy,
          isNull,
          reason: 'Solver must not declare the puzzle impossible',
        );
        final falsePrune = trace.steps.any(
          (s) =>
              s is RemoveOptionStep &&
              s.cellIdx == 15 &&
              s.option == CellValue.white,
        );
        expect(
          falsePrune,
          isFalse,
          reason:
              'SZ must not prune white from (5,0): the stored solution '
              'needs it to grow the white marked group',
        );
        // The provided solution is genuine: painting it satisfies every
        // constraint including both SZ rules.
        final sol = p.cachedSolution!;
        final replay = p.clone();
        for (var i = 0; i < replay.cells.length; i++) {
          replay.cells[i].setForSolver(sol[i]);
        }
        for (final c in replay.constraints) {
          expect(
            c.verify(replay),
            isTrue,
            reason: '${c.serialize()} violated by the stored solution',
          );
        }
      },
    );
  });
  group('Puzzle SameSize aggregation', () {
    test('merges constraints sharing a symbol', () {
      final p = Puzzle.empty(2, 2, defaultDomain);
      p.addConstraint(SameSize('H.0.1'));
      p.addConstraint(SameSize('H.2.3'));
      p.addConstraint(SameSize('D.0.2'));
      expect(p.constraints.whereType<SameSize>(), hasLength(2));
      final hearts = p.constraints.whereType<SameSize>().firstWhere(
        (c) => c.symbol == 'H',
      );
      expect(hearts.indices, [0, 1, 2, 3]);
    });
  });
}
