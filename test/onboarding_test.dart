import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';

void main() {
  group('phaseForCompletions', () {
    test('returns phase 0 for a brand-new player (zero completions)', () {
      // The first phase is "FM only" — what a fresh-install player
      // sees on their very first batch.
      final phase = phaseForCompletions(0);
      expect(phase, isNotNull);
      expect(phase!.index, 0);
      expect(phase.introducing, 'FM');
      expect(phase.allowed, {'FM'});
    });

    test('rolls into the next phase exactly at every multiple of 10', () {
      // The phase boundary is at the 10th completion: completions == 10
      // moves into phase 1. Completions 9 is the last play of phase 0.
      expect(phaseForCompletions(9)!.index, 0);
      expect(phaseForCompletions(10)!.index, 1);
      expect(phaseForCompletions(19)!.index, 1);
      expect(phaseForCompletions(20)!.index, 2);
    });

    test('returns null once the player has graduated past the last phase', () {
      // The strict phases cover [0, 40). Beyond that the player drops
      // into the soft-filter mode (any collection, ≤1 unseen slug per
      // puzzle).
      expect(phaseForCompletions(39)!.index, 3);
      expect(phaseForCompletions(40), isNull);
      expect(phaseForCompletions(999), isNull);
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
    test('accepts puzzles whose slugs are a subset of allowed', () {
      // Phase 2 allows {FM, PA, NC}. A puzzle declaring just FM and PA
      // is eligible.
      final phase = OnboardingPhase.phases[2];
      expect(puzzleEligibleForPhase(['FM', 'PA'], phase), isTrue);
      expect(puzzleEligibleForPhase(['FM'], phase), isTrue);
      expect(puzzleEligibleForPhase(['NC'], phase), isTrue);
    });

    test('rejects puzzles with any slug outside the allowed set', () {
      // Phase 2 disallows GS. A puzzle that uses both FM and GS is
      // out-of-phase and must be filtered.
      final phase = OnboardingPhase.phases[2];
      expect(puzzleEligibleForPhase(['FM', 'GS'], phase), isFalse);
      expect(puzzleEligibleForPhase(['SY'], phase), isFalse);
    });

    test('skips empty and TX entries', () {
      // The legacy TX (HelpText) slug is dropped at parse time but
      // could still appear in stale stat lines or imported playlists.
      // The eligibility check tolerates it.
      final phase = OnboardingPhase.phases[0];
      expect(puzzleEligibleForPhase(['FM', 'TX', ''], phase), isTrue);
    });
  });

  group('phaseWeight', () {
    test('returns 0 for ineligible puzzles', () {
      // Out-of-phase puzzles must drop out of sampling entirely.
      final phase = OnboardingPhase.phases[0];
      expect(phaseWeight(['FM', 'GS'], phase), 0.0);
    });

    test('boosts puzzles containing the introducing slug', () {
      // 4:1 ratio gives ≈ 80 % expected share when refresh and
      // introduction puzzles are present in roughly equal numbers.
      final phase = OnboardingPhase.phases[1]; // introducing NC
      expect(phaseWeight(['NC'], phase), 4.0);
      expect(phaseWeight(['FM', 'NC'], phase), 4.0);
    });

    test('keeps eligible refresh puzzles at the baseline weight', () {
      // A puzzle that is in-phase but doesn't contain the
      // introducing slug stays in the pool at baseline weight, giving
      // the player a refresher of an already-mastered slug.
      final phase = OnboardingPhase.phases[1]; // introducing NC
      expect(phaseWeight(['FM'], phase), 1.0);
    });
  });
}
