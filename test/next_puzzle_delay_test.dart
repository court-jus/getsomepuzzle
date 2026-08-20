import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

/// Minimal 2x2 puzzle, no real constraints → trivially valid when full.
PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

const String _invalidMsg = 'invalid';
String _errorsMsg(int count) => '$count errors';

void _fill(GameModel game) {
  for (var i = 0; i < 4; i++) {
    game.currentPuzzle!.setValue(i, CellValue.black);
  }
}

void main() {
  group('Settings.nextPuzzleDelayDuration', () {
    test('maps s1/s3/s10 to durations and manual to null', () {
      final s1 = Settings(nextPuzzleDelay: NextPuzzleDelay.s1);
      expect(s1.nextPuzzleDelayDuration, const Duration(seconds: 1));
      final s3 = Settings(nextPuzzleDelay: NextPuzzleDelay.s3);
      expect(s3.nextPuzzleDelayDuration, const Duration(seconds: 3));
      final s10 = Settings(nextPuzzleDelay: NextPuzzleDelay.s10);
      expect(s10.nextPuzzleDelayDuration, const Duration(seconds: 10));
      final manual = Settings(nextPuzzleDelay: NextPuzzleDelay.manual);
      expect(manual.nextPuzzleDelayDuration, isNull);
    });

    test('defaults to s1 (preserves the historic 1s behaviour)', () {
      expect(Settings().nextPuzzleDelay, NextPuzzleDelay.s1);
      expect(Settings().nextPuzzleDelayDuration, const Duration(seconds: 1));
    });
  });

  group('Automatic next-puzzle delay is configurable', () {
    test('s3 defers onPuzzleCompleted by 3s (not 1s)', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          nextPuzzleDelay: NextPuzzleDelay.s3,
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(
          settings,
          invalidConstraintsText: _invalidMsg,
          errorsCountText: _errorsMsg,
          onPuzzleCompleted: () => completed++,
        );

        // Still within 1-2s: must not have fired.
        async.elapse(const Duration(seconds: 2));
        expect(completed, 0);

        async.elapse(const Duration(seconds: 2));
        expect(completed, 1);
        game.dispose();
      });
    });

    test('s10 defers onPuzzleCompleted by 10s', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          nextPuzzleDelay: NextPuzzleDelay.s10,
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(
          settings,
          invalidConstraintsText: _invalidMsg,
          errorsCountText: _errorsMsg,
          onPuzzleCompleted: () => completed++,
        );

        async.elapse(const Duration(seconds: 9));
        expect(completed, 0);
        async.elapse(const Duration(seconds: 1));
        expect(completed, 1);
        game.dispose();
      });
    });
  });

  group('Manual next-puzzle mode', () {
    test(
      'solved puzzle shows the FAB and freezes the stopwatch, no auto-advance',
      () {
        fakeAsync((async) {
          final game = GameModel();
          final settings = Settings(
            nextPuzzleDelay: NextPuzzleDelay.manual,
            validateType: ValidateType.automatic,
            liveCheckType: LiveCheckType.all,
            showRating: ShowRating.no,
          );
          game.openPuzzle(_fixture(), 1);
          var completed = 0;
          _fill(game);
          game.handleCheck(
            settings,
            invalidConstraintsText: _invalidMsg,
            errorsCountText: _errorsMsg,
            onPuzzleCompleted: () => completed++,
          );

          // No auto-advance after the settle debounce.
          async.elapse(const Duration(seconds: 2));
          expect(completed, 0, reason: 'manual mode must never auto-advance');
          expect(
            game.showNextFab,
            isTrue,
            reason: 'FAB must appear once the puzzle is solved',
          );
          expect(
            game.currentMeta!.stats!.timer.isRunning,
            isFalse,
            reason: 'solve time must freeze as soon as the puzzle is solved',
          );
          game.dispose();
        });
      },
    );

    test(
      'mutating a solved puzzle removes the FAB and resumes the stopwatch',
      () {
        fakeAsync((async) {
          final game = GameModel();
          final settings = Settings(
            nextPuzzleDelay: NextPuzzleDelay.manual,
            validateType: ValidateType.automatic,
            liveCheckType: LiveCheckType.all,
            showRating: ShowRating.no,
          );
          game.openPuzzle(_fixture(), 1);
          _fill(game);
          game.handleCheck(
            settings,
            invalidConstraintsText: _invalidMsg,
            errorsCountText: _errorsMsg,
            onPuzzleCompleted: () {},
          );
          async.elapse(const Duration(seconds: 2));
          expect(game.showNextFab, isTrue);

          // Player clears a cell → no longer solved.
          game.handleTap(0);
          expect(
            game.showNextFab,
            isFalse,
            reason: 'mutation must hide the next button',
          );
          expect(
            game.currentMeta!.stats!.timer.isRunning,
            isTrue,
            reason: 'stopwatch must resume once the solve is broken',
          );
          game.dispose();
        });
      },
    );

    test('advanceToNextPuzzle finalizes the play and records the solve', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(
          nextPuzzleDelay: NextPuzzleDelay.manual,
          validateType: ValidateType.automatic,
          liveCheckType: LiveCheckType.all,
          showRating: ShowRating.no,
        );
        game.openPuzzle(_fixture(), 1);
        var completed = 0;
        _fill(game);
        game.handleCheck(
          settings,
          invalidConstraintsText: _invalidMsg,
          errorsCountText: _errorsMsg,
          onPuzzleCompleted: () => completed++,
        );
        async.elapse(const Duration(seconds: 2));
        expect(game.showNextFab, isTrue);

        // Simulate the FAB tap.
        game.advanceToNextPuzzle(settings, () => completed++);

        expect(
          completed,
          1,
          reason: 'FAB tap must run the completion callback',
        );
        expect(game.showNextFab, isFalse);
        expect(
          game.currentMeta!.duration,
          greaterThanOrEqualTo(0),
          reason: 'solve duration must be recorded on finalize',
        );
        game.dispose();
      });
    });
  });
}
