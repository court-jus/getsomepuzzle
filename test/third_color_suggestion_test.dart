import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';

/// Smallest line representations that [PuzzleData] accepts: the
/// constructor needs at least 7 underscore-separated segments to read
/// the cplx tail. Domain "12" → 2-colour puzzle, "123" → 3-colour.
const _twoColourLine = 'v2_12_3x3_000000000_FM:02.12_0:0_0';
const _threeColourLine = 'v2_123_3x3_000000000_NC:4.3.4_0:0_0';

void main() {
  group('Database.shouldSuggestThirdColor', () {
    // The gate fires only when all four conditions hold. Each test
    // below isolates one condition so a regression in the AND chain
    // points straight at the culprit.

    test('returns false right after the player finishes onboarding', () {
      // currentPhase becomes null at this completion count, but
      // postOnboardingCompletions is still 0 — well below the 50
      // threshold. The player has just graduated; suggesting 3
      // colours now would be premature.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 0;
      expect(db.currentPhase, isNull);
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns false while the player is still in onboarding', () {
      // The threshold is met (50 plays) but currentPhase != null →
      // skip. This guards against the edge case where a player
      // somehow accumulates post-onboarding completions before
      // graduating (shouldn't happen in practice, but the check is
      // cheap insurance).
      final db = Database(playerLevel: 0);
      db.onboardingCompletions = 5; // still in phase 0
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 60;
      expect(db.currentPhase, isNotNull);
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns false if hasPlayedThirdColor is already true', () {
      // The whole point of the modal is to introduce 3 colours to
      // someone who's never seen them. If the flag is already true
      // (history-derived or current-session), the modal would be
      // redundant.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 100;
      db.hasPlayedThirdColor = true;
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns false if the suggestion has already been shown', () {
      // Once dismissed (either button), the modal must not reappear.
      // The player can still opt in via the filters page.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 100;
      db.thirdColorSuggestionShown = true;
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns false if onboardingCompletedAt is null', () {
      // Defensive: a graduated player without a recorded timestamp
      // would normally be backfilled by loadPuzzlesFile to DateTime.now,
      // but the gate must still refuse if that backfill hasn't run yet.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.onboardingCompletedAt = null;
      db.postOnboardingCompletions = 100;
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns true when all four conditions are met', () {
      // The happy path. 50+ plays past graduation, no 3-colour
      // experience yet, modal never shown.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 50;
      expect(db.shouldSuggestThirdColor(), isTrue);
    });
  });

  group('Database.notePuzzleCompleted', () {
    // Drive the counters through a play event and confirm the latch
    // and the timestamp behave as documented. We can call this in a
    // unit test without a Flutter binding because the inner
    // `_persist*` calls are fire-and-forget and self-catch their
    // platform errors.

    test('latches hasPlayedThirdColor on the first 3-colour play', () {
      // Before: never seen 3 colours. After playing one: latch set.
      // Replaying another 3-colour puzzle keeps it true (idempotent).
      final db = Database(playerLevel: 0);
      expect(db.hasPlayedThirdColor, isFalse);

      db.notePuzzleCompleted(PuzzleData(_threeColourLine));
      expect(db.hasPlayedThirdColor, isTrue);

      db.notePuzzleCompleted(PuzzleData(_threeColourLine));
      expect(db.hasPlayedThirdColor, isTrue);
    });

    test('does not flip hasPlayedThirdColor on a 2-colour play', () {
      // The check is "does the puzzle's domain contain 3?". A 2-colour
      // puzzle (domain "12") must leave the flag at its initial value.
      final db = Database(playerLevel: 0);
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.hasPlayedThirdColor, isFalse);
    });

    test('stamps onboardingCompletedAt at the graduating play', () {
      // Setup: one play short of graduation. The play that crosses
      // the boundary should record a timestamp; the previous plays
      // should not have done so.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength - 1;
      expect(db.onboardingCompletedAt, isNull);
      expect(db.currentPhase, isNotNull);

      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.currentPhase, isNull);
      expect(db.onboardingCompletedAt, isNotNull);
    });

    test(
      'clears hasPlayedThirdColor when reloaded stats have no 3-colour play',
      () {
        // Regression: a stale `true` persisted in SharedPreferences (from
        // a prior play that has since been wiped via "Erase all stats")
        // used to stick around because loadStats only ever promoted the
        // flag, never demoted it. The result was a silent
        // disqualification from the third-colour suggestion modal that no
        // amount of stats clearing could undo. The fix makes loadStats
        // synchronise the flag with the current stats history.
        final db = Database(playerLevel: 0);
        db.hasPlayedThirdColor = true; // pretend a stale prefs value
        // Reload with stats that contain no 3-colour line.
        db.loadStats(<String>[
          '2026-05-13T18:00:00 30s 0f $_twoColourLine - ___ -  -  -  - 0 - 0h',
        ]);
        expect(db.hasPlayedThirdColor, isFalse);
      },
    );

    test(
      'promotes hasPlayedThirdColor when stats history has a 3-colour play',
      () {
        // The symmetric case: a fresh install (prefs all false) where
        // the stats file was restored from a backup. loadStats should
        // pick up the 3-colour line and flip the flag on.
        final db = Database(playerLevel: 0);
        expect(db.hasPlayedThirdColor, isFalse);
        db.loadStats(<String>[
          '2026-05-13T18:00:00 30s 0f $_threeColourLine - ___ -  -  -  - 0 - 0h',
        ]);
        expect(db.hasPlayedThirdColor, isTrue);
      },
    );

    test('increments postOnboardingCompletions only after graduation', () {
      // While onboarding: only onboardingCompletions grows.
      // After graduation: postOnboardingCompletions grows instead.
      final db = Database(playerLevel: 0);
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.postOnboardingCompletions, 0);

      // Jump past onboarding without going through every play.
      db.onboardingCompletions =
          OnboardingPhase.phases.length * OnboardingPhase.phaseLength;
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.postOnboardingCompletions, 1);
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.postOnboardingCompletions, 2);
    });
  });
}
