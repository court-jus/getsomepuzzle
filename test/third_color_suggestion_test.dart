import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

/// Smallest line representations that [PuzzleData] accepts: the
/// constructor needs at least 7 underscore-separated segments to read
/// the cplx tail. Domain "12" → 2-colour puzzle, "123" → 3-colour.
const _twoColourLine = 'v2_12_3x3_000000000_FM:02.12_0:0_0';
const _threeColourLine = 'v2_123_3x3_000000000_NC:4.3.4_0:0_0';
// QA is the introducing slug of the last onboarding phase, so a QA
// puzzle is what a player in that phase is actually served — and thus
// what graduates them when they finish it.
const _qaLine = 'v2_12_3x3_000000000_QA:1.4_0:0_0';

// Puzzle line with two QA constraints — used to verify that duplicate
// slugs do not inflate onboardingCompletions.
const _qaDupLine = 'v2_12_3x3_000000000_QA:1.4;QA:2.7_0:0_0';

Map<String, int> _allPhasesDone() => {
  for (final p in OnboardingPhase.phases)
    p.introducing: OnboardingPhase.phaseLength,
};

Map<String, int> _allPhasesDoneMinusOne() {
  final map = _allPhasesDone();
  // Drop the last phase's introducing slug by one so the player is one
  // play short of full graduation.
  final last = OnboardingPhase.phases.last.introducing;
  map[last] = OnboardingPhase.phaseLength - 1;
  return map;
}

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
      db.onboardingCompletions = _allPhasesDone();
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
      db.onboardingCompletions = <String, int>{
        OnboardingPhase.phases.first.introducing: 5,
      }; // still in phase 0
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
      db.onboardingCompletions = _allPhasesDone();
      db.onboardingCompletedAt = DateTime.now();
      db.postOnboardingCompletions = 100;
      db.hasPlayedThirdColor = true;
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns false if the suggestion has already been shown', () {
      // Once dismissed (either button), the modal must not reappear.
      // The player can still opt in via the filters page.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions = _allPhasesDone();
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
      db.onboardingCompletions = _allPhasesDone();
      db.onboardingCompletedAt = null;
      db.postOnboardingCompletions = 100;
      expect(db.shouldSuggestThirdColor(), isFalse);
    });

    test('returns true when all four conditions are met', () {
      // The happy path. 50+ plays past graduation, no 3-colour
      // experience yet, modal never shown.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions = _allPhasesDone();
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
      // Setup: one QA play short of graduation (QA is the last phase's
      // introducing slug). The play that crosses the boundary must be a
      // QA puzzle — that's what the player is served in the QA phase —
      // and it should record a timestamp; the previous plays did not.
      final db = Database(playerLevel: 0);
      db.onboardingCompletions = _allPhasesDoneMinusOne();
      expect(db.onboardingCompletedAt, isNull);
      expect(db.currentPhase, isNotNull);

      db.notePuzzleCompleted(PuzzleData(_qaLine));
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
        db.loadStats([
          StatEntry.parse(
            '2026-05-13T18:00:00 30s 0f $_twoColourLine - ___ -  -  -  - 0 - 0h',
          )!,
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
        db.loadStats([
          StatEntry.parse(
            '2026-05-13T18:00:00 30s 0f $_threeColourLine - ___ -  -  -  - 0 - 0h',
          )!,
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
      db.onboardingCompletions = _allPhasesDone();
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.postOnboardingCompletions, 1);
      db.notePuzzleCompleted(PuzzleData(_twoColourLine));
      expect(db.postOnboardingCompletions, 2);
    });

    test(
      'duplicate slugs in a puzzle do not inflate onboardingCompletions',
      () {
        // Regression: the onboardingCompletions loop used puz.rules (a List)
        // instead of puz.rules.toSet(). A puzzle with two QA constraints
        // counted as 2 completions instead of 1, accelerating phase
        // progression.
        final db = Database(playerLevel: 0, progress: ConstraintProgress());
        db.onboardingCompletions = _allPhasesDoneMinusOne();
        final before = db.onboardingCompletions['QA'] ?? 0;

        db.notePuzzleCompleted(PuzzleData(_qaDupLine));

        expect(db.onboardingCompletions['QA'] ?? 0, before + 1);
      },
    );

    test('replaying a puzzle does not inflate postOnboardingCompletions', () {
      // The stats file now keeps every play (keep-history), but the
      // post-onboarding counter must still reflect distinct puzzles, not
      // replays. loadStats collapses the history per canonical key
      // (Phase 1) before counting (Phase 2), so five finished plays of one
      // puzzle backfill the counter to 1, not 5.
      final db = Database(playerLevel: 0);
      db.onboardingCompletedAt = DateTime(2026, 1, 1);
      db.postOnboardingCompletions = 0;
      final replays = [
        for (var i = 0; i < 5; i++)
          '2026-02-0${i + 1}T12:00:00 30s 0f $_twoColourLine'
              ' - ___ -  -  -  -  - 0h - 0e - 0fc - 0lg',
      ];
      db.loadStats(replays.map((l) => StatEntry.parse(l)!).toList());
      expect(db.postOnboardingCompletions, 1);
    });
  });
}
