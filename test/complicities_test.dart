import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  // LT:A on cells 6,0 (rows 2 and 0) + FM:2.2 (vertical 2s forbidden)
  // → A must be color 1 (black), because a path of 2s can't cross rows.
  const puzzleLine = 'v2_12_3x3_000000000_LT:A.6.0;FM:2.2;LT:B.5.4_0:0_100';

  test(
    'LTFMComplicity is detected on puzzle with cross-row LT + vertical FM',
    () {
      final puzzle = Puzzle(puzzleLine);

      expect(puzzle.complicities, hasLength(1));
      expect(puzzle.complicities.first, isA<LTFMComplicity>());
    },
  );

  test('LTFMComplicity.apply forces LT:A to black (color 1)', () {
    final puzzle = Puzzle(puzzleLine);
    final move = puzzle.complicities.first.apply(puzzle);

    expect(move, isNotNull);
    // The move must target one of LT:A's cells (6 or 0) with color 1
    final ltA = puzzle.constraints.whereType<LetterGroup>().first;
    expect(ltA.letter, 'A');

    // We have a valid move ...
    expect(move!.isImpossible, isNull);
    // ... that tells us that one of cells of the LT rule...
    expect(ltA.indices, contains(move.idx));
    // ... must be black...
    expect(move.value, 1);
    // ... this move is givenBy the complicity itself
    expect(move.givenBy, puzzle.complicities.first);
  });
}
