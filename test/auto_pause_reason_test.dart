import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';

PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

void main() {
  group('AutoPauseReason scaffolding', () {
    test('autoPause sets paused + reason and pauses the stopwatch', () {
      final game = GameModel();
      game.openPuzzle(_fixture(), 1);
      expect(game.paused, isFalse);
      expect(game.autoPauseReason, isNull);

      game.autoPause(AutoPauseReason.idle);
      expect(game.paused, isTrue);
      expect(game.autoPauseReason, AutoPauseReason.idle);
      expect(game.currentMeta!.stats!.timer.isRunning, isFalse);
    });

    test('resume clears the auto-pause reason', () {
      final game = GameModel();
      game.openPuzzle(_fixture(), 1);
      game.autoPause(AutoPauseReason.focusLost);
      expect(game.autoPauseReason, AutoPauseReason.focusLost);

      game.resume();
      expect(game.paused, isFalse);
      expect(
        game.autoPauseReason,
        isNull,
        reason: 'resume must clear the reason, not carry it across sessions',
      );
    });

    test('manual pause has no reason (user knows why)', () {
      final game = GameModel();
      game.openPuzzle(_fixture(), 1);
      game.pause();
      expect(game.paused, isTrue);
      expect(game.autoPauseReason, isNull);
    });

    test('autoPause is a no-op when already paused (earliest reason wins)', () {
      final game = GameModel();
      game.openPuzzle(_fixture(), 1);
      // Idle fires first, then focus-loss fires before the user returns.
      game.autoPause(AutoPauseReason.idle);
      game.autoPause(AutoPauseReason.focusLost);
      expect(
        game.autoPauseReason,
        AutoPauseReason.idle,
        reason: 'the first auto-pause reason must be preserved',
      );
    });
  });
}
