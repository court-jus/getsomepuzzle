import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

/// Minimal 2x2 puzzle, no real constraints → trivially valid when full.
PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

void _fill(GameModel game) {
  for (var i = 0; i < 4; i++) {
    game.currentPuzzle!.setValue(i, 1);
  }
}

void main() {
  group('Completion switch is debounced by 1s', () {
    test('LiveCheckType.all defers onPuzzleCompleted by 1s', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        // Must not switch immediately — the user needs to register completion.
        async.elapse(const Duration(milliseconds: 500));
        expect(completed, 0);

        // Fires after the full 1s window.
        async.elapse(const Duration(milliseconds: 600));
        expect(completed, 1);

        game.dispose();
      });
    });

    test('LiveCheckType.count also defers by 1s', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.count,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        async.elapse(const Duration(milliseconds: 500));
        expect(completed, 0);
        async.elapse(const Duration(milliseconds: 600));
        expect(completed, 1);

        game.dispose();
      });
    });

    test('clearing a cell during the 1s window cancels the switch', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        // Half a second in, the user taps a cell twice to clear it back to 0:
        // 1 → 2 (puzzle still complete), 2 → 0 (puzzle now incomplete).
        async.elapse(const Duration(milliseconds: 500));
        game.handleTap(0);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);
        game.handleTap(0);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        async.elapse(const Duration(seconds: 2));
        expect(
          completed,
          0,
          reason:
              'debounce must be cancelled by the mutation that broke '
              'completeness',
        );

        game.dispose();
      });
    });

    test('LiveCheckType.complete keeps the 1s delay (regression)', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.complete,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        async.elapse(const Duration(milliseconds: 500));
        expect(completed, 0);
        async.elapse(const Duration(milliseconds: 600));
        expect(completed, 1);

        game.dispose();
      });
    });

    test('manual validate button fires immediately (no debounce)', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.manual,
          liveCheckType: LiveCheckType.complete,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        // Simulate the in-app "Validate" button click.
        game.checkPuzzle(
          settings,
          manualCheck: true,
          onPuzzleCompleted: () => completed++,
        );
        expect(completed, 1, reason: 'manual validation must not debounce');

        game.dispose();
      });
    });

    test('each tap re-arms the debounce from 0', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        // 900 ms later (close to the edge), user taps again — puzzle still
        // complete (1 → 2) but debounce must restart from 0.
        async.elapse(const Duration(milliseconds: 900));
        game.handleTap(0);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        // 500 ms after the new tap is still within the 1s window.
        async.elapse(const Duration(milliseconds: 500));
        expect(completed, 0, reason: 'debounce must not fire 500ms after tap');

        // Full 1s after the new tap: fires.
        async.elapse(const Duration(milliseconds: 600));
        expect(completed, 1);

        game.dispose();
      });
    });

    test('errors only surface 1s after the last interaction', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        // QA:1.2 expects exactly two cells of value 1 in a 2x2 grid.
        // Filling with four 1s therefore fails the constraint.
        game.openPuzzle(PuzzleData('v2_12_2x2_0000_QA:1.2_0_0'), 1);
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () {});

        // Before the debounce fires, the top message is still empty — the
        // user has not yet been told about the error.
        async.elapse(const Duration(milliseconds: 500));
        expect(game.topMessage, '', reason: 'error must not appear instantly');

        // After the full 1s window, the error is revealed.
        async.elapse(const Duration(milliseconds: 600));
        expect(game.topMessage.isNotEmpty, isTrue);

        game.dispose();
      });
    });

    test('pausing during the 1s window cancels the switch', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(settings, onPuzzleCompleted: () => completed++);

        async.elapse(const Duration(milliseconds: 400));
        game.pause();
        async.elapse(const Duration(seconds: 2));
        expect(completed, 0, reason: 'pause must cancel the pending switch');

        game.dispose();
      });
    });
  });
}
