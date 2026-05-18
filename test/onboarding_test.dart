import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';

void main() {
  group('phaseForCompletions', () {
    test('returns phase 0 for a brand-new player (zero completions)', () {
      // The first phase is "FM only" — what a fresh-install player
      // sees on their very first batch.
      final phase = phaseForCompletions({});
      expect(phase, isNotNull);
      expect(phase!.index, 0);
      expect(phase.introducing, 'FM');
      expect(phase.allowed, {'FM'});
    });

    test('rolls into the next phase when enough puzzles are completed', () {
      expect(phaseForCompletions({"FM": 3})!.index, 0);
      expect(phaseForCompletions({"FM": 5})!.index, 1);
      expect(phaseForCompletions({"FM": 5, "NC": 2})!.index, 1);
      expect(phaseForCompletions({"FM": 5, "NC": 5})!.index, 2);
    });

    test('returns null once the player has graduated past the last phase', () {
      expect(
        phaseForCompletions({
          "FM": 5,
          "NC": 5,
          "PA": 5,
          "CC": 5,
          "RC": 5,
          "GS": 5,
        }),
        isNull,
      );
    });
  });

  group('puzzlePassesSoftFilter', () {
    test('passes a puzzle whose slugs are all seen', () {
      // Pure refresh case: the player has met every constraint in
      // this puzzle. isFirstTimeForSlug returns false for all → 0
      // unseen → passes.
      bool isFirstTime(String _) => false;
      expect(puzzlePassesSoftFilter(['FM', 'GS', 'PA'], isFirstTime), isTrue);
    });

    test('passes a puzzle introducing exactly one new slug', () {
      // Single new slug → modal fires for it, the rest is familiar.
      // The player handles one new concept at a time. OK.
      bool isFirstTime(String s) => s == 'NC';
      expect(puzzlePassesSoftFilter(['FM', 'NC'], isFirstTime), isTrue);
      expect(puzzlePassesSoftFilter(['NC'], isFirstTime), isTrue);
    });

    test('rejects a puzzle introducing two or more new slugs', () {
      // Two unseen slugs would fire two modals back-to-back and pile up
      // cognitive load — filter rejects so the player meets them
      // separately on later puzzles. isFirstTime is true for every
      // slug here → all unseen → fails the ≤1 cap.
      bool isFirstTime(String _) => true;
      expect(puzzlePassesSoftFilter(['LT', 'QA'], isFirstTime), isFalse);
      expect(puzzlePassesSoftFilter(['FM', 'LT', 'QA'], isFirstTime), isFalse);
    });

    test('skips empty and TX entries when counting', () {
      // Defensive: stale TX legacy entries or empty splits don't
      // count toward the "unseen" budget. Even with isFirstTime
      // returning true (everything reportedly unseen), TX and ''
      // should not be counted.
      bool isFirstTime(String _) => true;
      expect(puzzlePassesSoftFilter(['FM', 'TX', ''], isFirstTime), isTrue);
    });
  });

  group('puzzleEligibleForPhase', () {
    test('accepts puzzles within the allowed envelope and containing'
        ' the introducing slug', () {
      // Phase 2 allows {FM, PA, NC} and introduces PA. Puzzles that
      // stay within the envelope AND declare PA are eligible.
      final phase = OnboardingPhase.phases[2];
      expect(puzzleEligibleForPhase(['FM', 'PA'], phase), isTrue);
      expect(puzzleEligibleForPhase(['PA'], phase), isTrue);
      expect(puzzleEligibleForPhase(['FM', 'PA', 'NC'], phase), isTrue);
    });

    test('rejects puzzles missing the introducing slug (no refresh share)', () {
      // Load-bearing for the Q1 decision (v1.6.x review): during a
      // strict phase, refresh-only puzzles (slugs within envelope but
      // no introducing slug) must NOT surface — they would dilute the
      // teaching focus given the short 5-puzzle budget per phase.
      // Phase 2 introduces PA: an FM-only or NC-only puzzle is a
      // refresh, not a teaching opportunity.
      final phase = OnboardingPhase.phases[2];
      expect(puzzleEligibleForPhase(['FM'], phase), isFalse);
      expect(puzzleEligibleForPhase(['NC'], phase), isFalse);
      expect(puzzleEligibleForPhase(['FM', 'NC'], phase), isFalse);
    });

    test('rejects puzzles with any slug outside the allowed set', () {
      // Phase 2 disallows GS. Even though FM and PA are inside the
      // envelope, the GS slug pushes the puzzle out-of-phase. The
      // envelope check fires before the introducing check.
      final phase = OnboardingPhase.phases[2];
      expect(puzzleEligibleForPhase(['FM', 'PA', 'GS'], phase), isFalse);
      expect(puzzleEligibleForPhase(['SY'], phase), isFalse);
    });

    test('skips empty and TX entries', () {
      // The legacy TX (HelpText) slug is dropped at parse time but
      // could still appear in stale stat lines or imported playlists.
      // The eligibility check tolerates it without counting it for
      // either the envelope or the introducing check.
      final phase = OnboardingPhase.phases[0];
      expect(puzzleEligibleForPhase(['FM', 'TX', ''], phase), isTrue);
    });
  });
}
