import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

PuzzleData _fixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

void main() {
  group('Settings.idleTimeoutDuration maps the enum to a duration', () {
    test('disabled returns null', () {
      final s = Settings(idleTimeout: IdleTimeout.disabled);
      expect(s.idleTimeoutDuration, isNull);
    });

    test('each enum value maps to the documented duration', () {
      final cases = {
        IdleTimeout.s5: const Duration(seconds: 5),
        IdleTimeout.s10: const Duration(seconds: 10),
        IdleTimeout.s30: const Duration(seconds: 30),
        IdleTimeout.m1: const Duration(minutes: 1),
        IdleTimeout.m2: const Duration(minutes: 2),
      };
      for (final entry in cases.entries) {
        final s = Settings(idleTimeout: entry.key);
        expect(
          s.idleTimeoutDuration,
          entry.value,
          reason: '${entry.key} should map to ${entry.value}',
        );
      }
    });
  });

  group('GameModel.markInteraction arms the idle watchdog', () {
    test('fires autoPause(idle) after the configured duration', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_fixture(), 1);
        game.markInteraction(const Duration(seconds: 5));

        async.elapse(const Duration(seconds: 4));
        expect(game.paused, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(game.paused, isTrue);
        expect(game.autoPauseReason, AutoPauseReason.idle);

        game.dispose();
      });
    });

    test('each interaction re-arms the timer from 0', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_fixture(), 1);
        game.markInteraction(const Duration(seconds: 5));

        async.elapse(const Duration(seconds: 4));
        game.markInteraction(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 4));
        expect(
          game.paused,
          isFalse,
          reason: 'interaction at 4s must restart the 5s window',
        );

        async.elapse(const Duration(seconds: 2));
        expect(game.paused, isTrue);

        game.dispose();
      });
    });

    test('null duration disables the watchdog', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_fixture(), 1);
        game.markInteraction(null);
        async.elapse(const Duration(minutes: 5));
        expect(game.paused, isFalse);
        game.dispose();
      });
    });

    test('no puzzle open → no timer armed', () {
      fakeAsync((async) {
        final game = GameModel();
        // currentPuzzle is null.
        game.markInteraction(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 10));
        expect(game.paused, isFalse);
        game.dispose();
      });
    });

    test('manual pause cancels the pending idle timer', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_fixture(), 1);
        game.markInteraction(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 2));
        game.pause();
        async.elapse(const Duration(seconds: 10));
        // No auto-pause reason: pause was manual.
        expect(game.autoPauseReason, isNull);
        game.dispose();
      });
    });

    test(
      'after idle auto-pause, subsequent markInteraction calls are ignored',
      () {
        fakeAsync((async) {
          final game = GameModel();
          game.openPuzzle(_fixture(), 1);
          game.markInteraction(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 6));
          expect(game.autoPauseReason, AutoPauseReason.idle);

          // An accidental tap must NOT re-arm the watchdog until resume runs.
          game.markInteraction(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 10));
          // Still idle-paused; no new timer fired anything.
          expect(game.autoPauseReason, AutoPauseReason.idle);

          game.dispose();
        });
      },
    );

    test('resume allows markInteraction to arm a fresh watchdog', () {
      fakeAsync((async) {
        final game = GameModel();
        game.openPuzzle(_fixture(), 1);
        game.markInteraction(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 6));
        expect(game.autoPauseReason, AutoPauseReason.idle);

        game.resume();
        expect(game.autoPauseReason, isNull);
        game.markInteraction(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 6));
        expect(game.autoPauseReason, AutoPauseReason.idle);

        game.dispose();
      });
    });
  });
}
