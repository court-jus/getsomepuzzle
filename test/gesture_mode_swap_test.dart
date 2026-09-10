import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';

// Regression coverage for the swapped long-press / right-click on 3-colour
// puzzles: the alternate gesture applies the *other* tap mode's action
// (normal mode → prune an option dot, remove-option mode → cycle forward).
// 2-colour puzzles keep the backward `decrValue` cycle, and the right-drag
// paint stays unchanged.

// 3-colour fixture (reused from decr_value_test.dart /
// cycle_remove_option_test.dart). Cell 0 is pre-coloured black (readonly),
// the other 8 cells are free with the full [black, white, purple] option set.
PuzzleData _three() => PuzzleData('v2_123_3x3_100000000_LT:A.0.4_0:0_0');

// 2-colour fixture: cell 0 black readonly, cells 1..8 free with
// [black, white] options.
PuzzleData _two() => PuzzleData('v2_12_3x3_100000000_LT:A.0.2;LT:B.1.4');

void main() {
  group('handleLongPress swapped on 3 colours', () {
    test('normal mode prunes one option dot', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        expect(game.handleLongPress(4), isTrue);
        expect(game.currentPuzzle!.cellValues[4], CellValue.free);
        // Black (domain[0]) is dropped, leaving white + purple.
        expect(game.currentPuzzle!.cells[4].options.toSet(), {
          CellValue.white,
          CellValue.purple,
        });

        game.dispose();
      });
    });

    test('remove-option mode cycles the colour forward', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        expect(game.handleLongPress(4, removeOptionMode: true), isTrue);
        expect(game.currentPuzzle!.cellValues[4], CellValue.black);

        game.dispose();
      });
    });

    test('coloured cell in normal mode falls back to incrValue', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);
        game.currentPuzzle!.setValue(4, CellValue.black);

        expect(game.handleLongPress(4), isTrue);
        expect(game.currentPuzzle!.cellValues[4], CellValue.white);

        game.dispose();
      });
    });

    test('readonly cell is a no-op', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        expect(game.handleLongPress(0), isFalse);
        expect(game.currentPuzzle!.cellValues[0], CellValue.black);

        game.dispose();
      });
    });
  });

  group('handleLongPress keeps backward cycle on 2 colours', () {
    test('free cell jumps to the last domain colour (white)', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_two(), 1);

        expect(game.handleLongPress(4), isTrue);
        expect(game.currentPuzzle!.cellValues[4], CellValue.white);

        game.dispose();
      });
    });
  });

  group('right-click commit swapped on 3 colours', () {
    test('pure right-click in normal mode prunes one option dot', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        game.handleRightDrag(4);
        game.handleRightDragEnd();

        expect(game.currentPuzzle!.cellValues[4], CellValue.free);
        expect(game.currentPuzzle!.cells[4].options.toSet(), {
          CellValue.white,
          CellValue.purple,
        });

        game.dispose();
      });
    });

    test('pure right-click in remove-option mode cycles colour forward', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        game.handleRightDrag(4);
        game.handleRightDragEnd(removeOptionMode: true);

        expect(game.currentPuzzle!.cellValues[4], CellValue.black);

        game.dispose();
      });
    });

    test('right-drag paint is unchanged', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_three(), 1);

        game.handleRightDrag(4);
        game.handleRightDrag(5);

        expect(game.currentPuzzle!.cellValues[4], CellValue.purple);
        expect(game.currentPuzzle!.cellValues[5], CellValue.purple);

        game.dispose();
      });
    });

    test('pure right-click keeps the backward cycle on 2 colours', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_two(), 1);

        game.handleRightDrag(4);
        game.handleRightDragEnd();

        expect(game.currentPuzzle!.cellValues[4], CellValue.white);

        game.dispose();
      });
    });
  });
}
