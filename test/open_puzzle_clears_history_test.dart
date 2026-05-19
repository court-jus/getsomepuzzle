import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';

PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

void main() {
  // Regression: opening a new puzzle used to leave `history` populated
  // with the previous puzzle's move indices, so Undo stayed enabled and
  // would pop a stale (and possibly out-of-bounds) cell on the new grid.
  test('openPuzzle clears stale history from a previous puzzle', () {
    final game = GameModel();
    game.openPuzzle(_fixture(), 1);
    game.history = [0, 1, 2];

    game.openPuzzle(_fixture(), 1);

    expect(game.history, isEmpty);
  });
}
