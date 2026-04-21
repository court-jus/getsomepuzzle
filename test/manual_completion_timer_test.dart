import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

/// Build a minimal 2x2 PuzzleData with no real constraints.
/// "NOOP" is an unknown slug — the parser silently drops it, leaving a
/// trivially-valid empty-constraint puzzle, which is the shortest possible
/// fixture for exercising completion-driven timer behaviour.
PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

void main() {
  group('Manual-mode completion freezes the timer', () {
    test(
      'stopwatch pauses when puzzle becomes complete, resumes when broken',
      () {
        final game = GameModel();
        final settings = Settings(
          validateType: ValidateType.manual,
          liveCheckType: LiveCheckType.complete,
        );
        game.openPuzzle(_fixture(), 1);
        expect(game.currentMeta!.stats!.timer.isRunning, isTrue);

        for (var i = 0; i < 4; i++) {
          game.currentPuzzle!.setValue(i, 1);
        }
        game.handleCheck(settings, onPuzzleCompleted: () {});
        expect(
          game.currentMeta!.stats!.timer.isRunning,
          isFalse,
          reason: 'timer must freeze once puzzle is complete in manual mode',
        );

        // Breaking completeness must restart the stopwatch on the next check.
        game.currentPuzzle!.setValue(0, 0);
        game.handleCheck(settings, onPuzzleCompleted: () {});
        expect(
          game.currentMeta!.stats!.timer.isRunning,
          isTrue,
          reason: 'timer must resume once a cell is cleared again',
        );
      },
    );

    test('manual pause/resume keeps timer frozen while complete', () {
      final game = GameModel();
      final settings = Settings(
        validateType: ValidateType.manual,
        liveCheckType: LiveCheckType.complete,
      );
      game.openPuzzle(_fixture(), 1);
      for (var i = 0; i < 4; i++) {
        game.currentPuzzle!.setValue(i, 1);
      }
      game.handleCheck(settings, onPuzzleCompleted: () {});
      expect(game.currentMeta!.stats!.timer.isRunning, isFalse);

      // Simulate the user toggling the pause button: resume() must NOT
      // restart the stopwatch while the completion freeze is active.
      game.pause();
      game.resume();
      expect(
        game.currentMeta!.stats!.timer.isRunning,
        isFalse,
        reason: 'resume() must not override the completion freeze',
      );
    });

    test('non-manual validation does not freeze on completion', () {
      final game = GameModel();
      final settings = Settings(
        validateType: ValidateType.automatic,
        liveCheckType: LiveCheckType.complete,
      );
      game.openPuzzle(_fixture(), 1);
      for (var i = 0; i < 4; i++) {
        game.currentPuzzle!.setValue(i, 1);
      }
      game.handleCheck(settings, onPuzzleCompleted: () {});
      expect(
        game.currentMeta!.stats!.timer.isRunning,
        isTrue,
        reason:
            'in automatic mode, the auto-check path (not this feature) '
            'stops the stopwatch; before it fires the timer keeps ticking',
      );
    });
  });
}
