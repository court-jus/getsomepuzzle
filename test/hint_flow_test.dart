import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
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
  hintConstraintInprogress: 'in progress',
  hintConstraintNone: 'no more constraints',
);

String _hintDeducedFrom(CanApply givenBy) => givenBy is Constraint
    ? 'deduced from ${givenBy.slug}'
    : 'deduced from ${givenBy.serialize()}';

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

    test('an already-ready candidate is attached on tap 2', () {
      // Simulate a completed search: one candidate ready. Tap 1 must NOT
      // re-trigger the search (it would wipe the ready result); tap 2 must
      // attach the candidate. We bypass the Isolate path by writing the
      // public fields directly.
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.openPuzzle(_emptyFixture(), 1);

      game.availableHintConstraints = ['FM:11', 'FM:22'];
      game.hintConstraintsReady = HintConstraintStatus.ready;

      expect(
        game.canAddHintConstraint,
        isTrue,
        reason: 'button must stay enabled while a candidate is ready',
      );

      final constraintsBefore = game.currentPuzzle!.constraints.length;
      game.onHintTap(settings, _texts); // stage 0 → 1 (errors pass)

      expect(
        game.hintConstraintsReady,
        HintConstraintStatus.ready,
        reason: 'tap 1 must not re-trigger and clobber a ready result',
      );

      game.onHintTap(settings, _texts); // stage 1 → terminal

      expect(
        game.currentPuzzle!.constraints.length,
        constraintsBefore + 1,
        reason: 'the ready candidate must be attached on demand',
      );
      expect(game.hintText, 'constraint added');

      game.dispose();
    });

    test('openPuzzle in addConstraint mode does not start a search', () {
      // The expensive search is on-demand (first hint tap), never eager on
      // open — this is what fixes the URL-open freeze on web.
      final game = GameModel();
      game.hintType = HintType.addConstraint;
      game.openPuzzle(_deducibleFixture(), 1);

      expect(
        game.hintConstraintsReady,
        isNot(HintConstraintStatus.inprogress),
        reason: 'no constraint search must run just from opening the puzzle',
      );

      game.dispose();
    });

    test('tap 1 in addConstraint mode starts the search', () {
      // With a cached solution available, tap 1 kicks the search (status
      // flips to inprogress synchronously, before the isolate completes).
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.hintType = HintType.addConstraint;
      game.openPuzzle(_deducibleFixture(), 1);
      // forPuzzle needs a cached solution; computeComplexity populates it.
      game.currentPuzzle!.computeComplexity(force: true);

      game.onHintTap(settings, _texts); // stage 0 → 1, triggers the search
      expect(game.hintStage, 1);
      expect(
        game.hintConstraintsReady,
        HintConstraintStatus.inprogress,
        reason: 'tap 1 must start the constraint search on demand',
      );

      game.dispose();
    });

    test('a no-op candidate shows "none", not "added", and is not billed', () {
      // Regression: `addHintConstraint` used to return true (→ "added") even
      // when `Puzzle.addConstraint` changed nothing — e.g. an LT permutation
      // merging into an existing same-letter group. Such a candidate must be
      // reported as "none" and must not bill a hint.
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.openPuzzle(_emptyFixture(), 1);

      // Existing LT on cells 0,1; the offered candidate is its permutation
      // (cells 1,0) → merges with no new cell → no-op.
      game.currentPuzzle!.addConstraint(createConstraint('LT', 'A.0.1')!);
      final constraintsBefore = game.currentPuzzle!.constraints.length;
      final hintsBefore = game.currentMeta!.hints;

      game.availableHintConstraints = ['LT:A.1.0'];
      game.hintConstraintsReady = HintConstraintStatus.ready;

      game.onHintTap(settings, _texts); // stage 0 → 1
      game.onHintTap(settings, _texts); // stage 1 → terminal

      expect(
        game.currentPuzzle!.constraints.length,
        constraintsBefore,
        reason: 'a no-op merge must not change the constraint set',
      );
      expect(
        game.hintText,
        'no more constraints',
        reason: 'nothing was added → show the "none" message, not "added"',
      );
      expect(
        game.currentMeta!.hints,
        hintsBefore,
        reason: 'a no-op add must not bill the player a hint',
      );
      expect(game.hintConstraintsReady, HintConstraintStatus.canceled);

      game.dispose();
    });

    test('a constraint computed while waiting is revealed automatically', () {
      // The player taps to reveal before the (slow) search finishes, so they
      // see the "computing…" message. When the worker reports a candidate, it
      // must be attached on its own — no extra tap required.
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.openPuzzle(_emptyFixture(), 1);

      // Simulate a search already running (worker spawned, not yet done) so
      // tap 1 won't start a real isolate.
      game.hintConstraintsReady = HintConstraintStatus.inprogress;

      game.onHintTap(settings, _texts); // stage 0 → 1, errors pass
      game.onHintTap(settings, _texts); // stage 1 → terminal, still computing
      expect(
        game.hintText,
        'in progress',
        reason: 'with the search unfinished, tap 2 shows the waiting message',
      );

      final constraintsBefore = game.currentPuzzle!.constraints.length;

      // Worker reports back: the pending reveal must fire automatically.
      game.onHintConstraintComputed('FM:11');
      expect(
        game.currentPuzzle!.constraints.length,
        constraintsBefore + 1,
        reason: 'completion must auto-attach the pending constraint',
      );
      expect(game.hintText, 'constraint added');

      game.dispose();
    });

    test('an empty result while waiting auto-shows the "none" message', () {
      // Same waiting scenario, but the search finds no helpful constraint.
      // The waiting message must resolve to the terminal "none" feedback
      // rather than stay stuck on "computing…".
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.openPuzzle(_emptyFixture(), 1);
      game.hintConstraintsReady = HintConstraintStatus.inprogress;

      game.onHintTap(settings, _texts); // stage 0 → 1
      game.onHintTap(settings, _texts); // stage 1 → terminal, still computing
      expect(game.hintText, 'in progress');

      game.onHintConstraintComputed(null); // search found nothing
      expect(game.hintText, 'no more constraints');

      game.dispose();
    });

    test('tap 1 does not start the search when the grid has an error', () {
      // If the error pass surfaces a mistake, the player must fix it first —
      // launching the (expensive) constraint search on a contradictory state
      // would be wasted work.
      final game = GameModel();
      final settings = Settings(hintType: HintType.addConstraint);
      game.hintType = HintType.addConstraint;
      game.openPuzzle(_deducibleFixture(), 1);
      game.currentPuzzle!.computeComplexity(force: true);

      // Fill a free cell with the wrong colour so tap 1 reports an error.
      final cell = game.currentPuzzle!.cells.firstWhere((c) => !c.readonly);
      final correct = game.currentPuzzle!.cachedSolution![cell.idx];
      game.currentPuzzle!.setValue(cell.idx, correct == 1 ? 2 : 1);

      game.onHintTap(settings, _texts); // stage 0 → 1, error pass
      expect(game.hintIsError, isTrue, reason: 'tap 1 must flag the mistake');
      expect(
        game.hintConstraintsReady,
        isNot(HintConstraintStatus.inprogress),
        reason: 'no search must start while an error is on the grid',
      );

      game.dispose();
    });
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
