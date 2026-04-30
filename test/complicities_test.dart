import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  // LT:A on cells 6,0 (rows 2 and 0) + FM:2.2 (vertical 2s forbidden)
  // → A must be color 1 (black), because a path of 2s can't cross rows.
  const puzzleLine = 'v2_12_3x3_000000000_LT:A.6.0;FM:2.2;LT:B.5.4_0:0_100';

  test('LTFMComplicity is detected on cross-row LT + vertical FM', () {
    final puzzle = Puzzle(puzzleLine);
    expect(puzzle.complicities, hasLength(1));
    expect(puzzle.complicities.first, isA<LTFMComplicity>());
  });

  test('LTFMComplicity.apply forces LT:A to black (color 1)', () {
    final puzzle = Puzzle(puzzleLine);
    final move = puzzle.complicities.first.apply(puzzle);

    expect(move, isNotNull);
    final ltA = puzzle.constraints.whereType<LetterGroup>().first;
    expect(ltA.letter, 'A');

    expect(move!.isImpossible, isNull);
    // The move targets one of LT:A's cells (6 or 0)…
    expect(ltA.indices, contains(move.idx));
    // …with color 1 (black)…
    expect(move.value, 1);
    // …and is given by the complicity itself, not a Constraint.
    expect(move.givenBy, puzzle.complicities.first);
    // Combination deduction: weight tier 3 (per docs/dev/complexity.md).
    expect(move.complexity, 3);
  });

  test('LTFMComplicity is not detected when FM direction does not match', () {
    // LT:A spans rows (cells 6 and 0, both at col 0 but rows 0 and 2).
    // The connecting path must include a vertical step. FM:22 is a
    // horizontal pair — it blocks horizontal adjacency, not vertical —
    // so the complicity must NOT trigger here.
    final puzzle = Puzzle('v2_12_3x3_000000000_LT:A.6.0;FM:22_0:0_100');
    expect(puzzle.complicities, isEmpty);
  });

  test(
    'Puzzle.apply() falls through to complicities when constraints stuck',
    () {
      final puzzle = Puzzle(puzzleLine);
      // None of the regular constraints can deduce anything on this empty
      // grid, but the complicity can.
      final move = puzzle.apply();
      expect(move, isNotNull);
      expect(move!.givenBy, isA<LTFMComplicity>());
    },
  );
}
