import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/game_model.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/settings.dart';

/// Heavy-prefilled 6x7 puzzle that is fully solvable by propagation. Reused
/// from `solve_explained_test.dart` — guarantees `findAMove` returns a real
/// deducible move once the help debounce fires.
PuzzleData _deducibleFixture() => PuzzleData(
  'v2_12_6x7_002000210001022011020210200200100010202211_FM:12;FM:1.1.2;PA:17.top_0:0_0',
);

/// Empty 2x2 with no real constraints. `findAMove` will return null because
/// nothing is deducible — used to exercise the `helpMove == null` guards.
PuzzleData _emptyFixture() => PuzzleData('v2_12_2x2_0000_NOOP_0_0');

const HintTexts _texts = HintTexts(
  someConstraintsInvalid: 'invalid',
  hintCellWrong: 'wrong cell',
  hintAllCorrectSoFar: 'all correct',
  hintCellDeducible: 'cell deducible',
  hintImpossible: 'impossible',
  hintForce: 'force',
  hintDeducedFrom: _hintDeducedFrom,
  hintConstraintAdded: 'constraint added',
  hintConstraintNone: 'no more constraints',
);

String _hintDeducedFrom(Constraint givenBy) => 'deduced from ${givenBy.slug}';

void main() {
  group('Hint multi-tap flow — deducibleCell mode', () {
    test('full 4-tap cycle advances stage 0→1→2→3 then resets on apply', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(hintType: HintType.deducibleCell);
        game.openPuzzle(_deducibleFixture(), 1);

        // Wait past the 300 ms debounce so `helpMove` is computed.
        async.elapse(const Duration(milliseconds: 350));
        expect(
          game.helpMove,
          isNotNull,
          reason: 'fixture must produce a deducible move once debounced',
        );
        final targetIdx = game.helpMove!.idx;
        final targetValue = game.helpMove!.value;
        final beforeValue = game.currentPuzzle!.cellValues[targetIdx];
        expect(game.hintStage, 0);

        // Tap 1: errors / "all correct" pass.
        game.onHintTap(settings, _texts);
        expect(game.hintStage, 1);
        expect(game.hintText, 'all correct');

        // Tap 2: cell-only reveal — cell highlighted, no constraint.
        game.onHintTap(settings, _texts);
        expect(game.hintStage, 2);
        expect(game.hintText, 'cell deducible');
        expect(game.currentPuzzle!.cells[targetIdx].isHighlighted, isTrue);

        // Tap 3: cell + constraint reveal.
        game.onHintTap(settings, _texts);
        expect(game.hintStage, 3);
        expect(
          game.hintText,
          anyOf(equals('force'), startsWith('deduced from')),
          reason: 'tap 3 surfaces either the source constraint or "force"',
        );

        // Tap 4: apply move. Mutation goes through `_afterMutation`, which
        // resets `hintStage` to 0 and re-arms the help debounce.
        game.onHintTap(settings, _texts);
        expect(game.currentPuzzle!.cellValues[targetIdx], targetValue);
        expect(
          game.currentPuzzle!.cellValues[targetIdx],
          isNot(beforeValue),
          reason: 'apply must actually flip the cell value',
        );
        expect(game.hintStage, 0);

        game.dispose();
      });
    });

    test('reaching stage 3 increments the hint counter exactly once', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(hintType: HintType.deducibleCell);
        game.openPuzzle(_deducibleFixture(), 1);
        async.elapse(const Duration(milliseconds: 350));
        final hintsBefore = game.currentMeta!.hints;

        game.onHintTap(settings, _texts); // stage 1 — diagnostic only
        game.onHintTap(settings, _texts); // stage 2 — cell only
        expect(
          game.currentMeta!.hints,
          hintsBefore,
          reason: 'taps 1 and 2 are non-committal, must not bill the player',
        );

        game.onHintTap(settings, _texts); // stage 3 — full reveal
        expect(
          game.currentMeta!.hints,
          hintsBefore + 1,
          reason: 'the constraint+arrow reveal is the chargeable hint',
        );

        game.dispose();
      });
    });
  });

  group('Hint multi-tap flow — addConstraint mode', () {
    test(
      'tap 2 cycles back to stage 0 even when no constraint is available',
      () {
        // The hint Isolate never runs in unit tests, so the candidate list
        // stays empty and `addHintConstraint()` returns false. The cycle
        // must still reset to 0 so the next tap re-runs the error pass.
        final game = GameModel();
        final settings = Settings(hintType: HintType.addConstraint);
        game.openPuzzle(_emptyFixture(), 1);

        game.onHintTap(settings, _texts); // stage 0 → 1
        expect(game.hintStage, 1);
        expect(game.hintText, 'all correct');

        game.onHintTap(settings, _texts); // stage 1 → 0 (terminal)
        expect(game.hintStage, 0);
        expect(
          game.hintText,
          'no more constraints',
          reason: 'with an empty candidate list the user sees the fallback',
        );

        game.dispose();
      },
    );
  });

  group('Hint cycle reset', () {
    test('resetHintCycle clears intermediate stage and highlights', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(hintType: HintType.deducibleCell);
        game.openPuzzle(_deducibleFixture(), 1);
        async.elapse(const Duration(milliseconds: 350));

        game.onHintTap(settings, _texts); // stage 1
        game.onHintTap(settings, _texts); // stage 2
        expect(game.hintStage, 2);
        expect(game.currentPuzzle!.cells.any((c) => c.isHighlighted), isTrue);

        // Use case: the player flips the hint mode mid-cycle.
        game.resetHintCycle();
        expect(game.hintStage, 0);
        expect(game.hintText, '');
        expect(
          game.currentPuzzle!.cells.every((c) => !c.isHighlighted),
          isTrue,
          reason: 'reset must drop any active hint highlight',
        );

        game.dispose();
      });
    });

    test('any cell mutation resets the hint stage via _afterMutation', () {
      fakeAsync((async) {
        final game = GameModel();
        final settings = Settings(hintType: HintType.deducibleCell);
        game.openPuzzle(_deducibleFixture(), 1);
        async.elapse(const Duration(milliseconds: 350));

        game.onHintTap(settings, _texts); // stage 1
        expect(game.hintStage, 1);

        // Tap any free, non-readonly cell. `handleTap` runs `_afterMutation`,
        // which clears the hint state — guarantees a stale hint can't be
        // applied to a now-mutated puzzle.
        final freeIdx = game.currentPuzzle!.cells
            .firstWhere((c) => !c.readonly)
            .idx;
        expect(game.handleTap(freeIdx), isTrue);
        expect(game.hintStage, 0);
        expect(game.helpMove, isNull, reason: 'mutation must drop helpMove');

        game.dispose();
      });
    });
  });

  group('Hint flow — debounce-race safety', () {
    test('tapping before the help debounce fires is a graceful no-op', () {
      // Tap 4 times in a row immediately after openPuzzle. `_helpDebounce`
      // hasn't fired yet, so `helpMove == null` for the entire sequence.
      // The state machine must not crash and must not mutate the puzzle.
      final game = GameModel();
      final settings = Settings(hintType: HintType.deducibleCell);
      game.openPuzzle(_deducibleFixture(), 1);
      final before = List<int>.from(game.currentPuzzle!.cellValues);
      expect(game.helpMove, isNull);

      game.onHintTap(settings, _texts); // 0 → 1: errors path always works
      expect(game.hintStage, 1);
      game.onHintTap(settings, _texts); // 1 → 2: _revealCellOnly no-ops
      expect(game.hintStage, 2);
      game.onHintTap(
        settings,
        _texts,
      ); // 2 → 3: _revealCellAndConstraint no-ops
      expect(game.hintStage, 3);
      game.onHintTap(
        settings,
        _texts,
      ); // 3 → apply: _applyHelpMove early-returns

      expect(
        game.currentPuzzle!.cellValues,
        before,
        reason: 'no mutation must occur when helpMove is null',
      );

      game.dispose();
    });
  });
}
