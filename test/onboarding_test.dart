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
        phaseForCompletions(OnboardingPhase.strictCompletionTargets),
        isNull,
      );
    });

    test('returns the first incomplete phase, even when later phases are '
        'already complete', () {
      // Boundary contract: `phaseForCompletions` walks phases in order
      // and returns the first one whose introducing slug has < phaseLength
      // completions. Equivalently: `null` iff every phase is complete.
      //
      // For each phase i: mark every OTHER phase's introducing slug
      // complete and leave phase i one short. The walk MUST land on
      // phase i — proving (a) non-null whenever any phase is short, and
      // (b) the in-order traversal is not broken by an early-exit or
      // an over-eager skip past an already-complete entry.
      for (final target in OnboardingPhase.phases) {
        final completions = <String, int>{
          for (final ph in OnboardingPhase.phases)
            ph.introducing: ph.index == target.index
                ? OnboardingPhase.phaseLength - 1
                : OnboardingPhase.phaseLength,
        };
        final result = phaseForCompletions(completions);
        expect(
          result?.index,
          target.index,
          reason:
              'only phase ${target.index} (${target.introducing}) incomplete; '
              'expected phaseForCompletions to land on it, got ${result?.index}',
        );
      }
    });
  });

  group('OnboardingPhase.postStrictDiscoveryOrder', () {
    test('contains exactly the slugs not introduced by any strict phase', () {
      // Strict phases introduce {FM, NC, PA, CC, RC, GS}; everything
      // else from the registry must end up in the post-strict
      // discovery list so the soft filter has a slug to elect for
      // every remaining unseen rule.
      final strict = OnboardingPhase.phases.map((p) => p.introducing).toSet();
      final post = OnboardingPhase.postStrictDiscoveryOrder;
      expect(post.toSet().intersection(strict), isEmpty);
      expect(
        post.toSet().union(strict),
        equals(OnboardingPhase.allKnownSlugs),
        reason:
            'every registered slug must be covered either by a strict '
            'phase or by postStrictDiscoveryOrder; missing slugs would '
            'silently never be introduced.',
      );
    });

    test('preserves registry declaration order', () {
      // The soft filter elects the first not-yet-seen slug in this
      // list. Pinning the order keeps the discovery sequence
      // predictable and reviewable; if someone reorders the registry,
      // the order test fails and we revisit it intentionally.
      expect(OnboardingPhase.postStrictDiscoveryOrder, [
        'RT',
        'SY',
        'SH',
        'CH',
        'CT',
        'GC',
        'MJ',
      ]);
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
