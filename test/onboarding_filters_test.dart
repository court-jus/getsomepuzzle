import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mark each strict-phase introducing slug as fully completed so the
/// player is past every strict phase. Mirrors what `phaseForCompletions`
/// expects (≥ `phaseLength` for every entry in `OnboardingPhase.phases`).
Map<String, int> _allStrictPhasesCompleted() => {
  for (final p in OnboardingPhase.phases)
    p.introducing: OnboardingPhase.phaseLength,
};

void main() {
  group('Database.recommendedOnboardingFilters — strict phases', () {
    test('P0 wants FM, bans every other registered slug', () {
      // Fresh player: currentPhase is P0 ('FM' only allowed). The
      // recommendation must exactly reproduce puzzleEligibleForPhase
      // (envelope + introducing) as a (wantedRules, bannedRules) pair.
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      final reco = db.recommendedOnboardingFilters;
      expect(reco, isNotNull);
      expect(reco!.wantedRules, {'FM'});
      // bannedRules is "every known slug except FM" — we don't enumerate
      // them literally to stay registry-driven, but we assert the
      // semantic invariant.
      expect(
        reco.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({'FM'}),
      );
    });

    test('P3 wants CC, bans every slug not in {FM, PA, NC, CC}', () {
      // P3 introduces CC and allows {FM, PA, NC, CC}. Anything else in
      // the registry must be banned so the catalog narrows to that
      // envelope, and the puzzle must contain CC (wantedRules).
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      // Mark P0..P2 introducers complete so phaseForCompletions lands on P3.
      db.onboardingCompletions = {
        'FM': OnboardingPhase.phaseLength,
        'NC': OnboardingPhase.phaseLength,
        'PA': OnboardingPhase.phaseLength,
      };
      final phase = db.currentPhase!;
      expect(phase.introducing, 'CC');
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, {'CC'});
      expect(
        reco.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({'FM', 'PA', 'NC', 'CC'}),
      );
    });

    test('P5 (last strict phase) wants GS, bans only post-strict slugs', () {
      // P5 introduces GS and allows {FM, PA, NC, CC, RC, GS}. The banned
      // set narrows to the post-strict tail (LT, QA, SY, DF, SH, GC, MJ,
      // EY) — exactly what postStrictDiscoveryOrder will manage next.
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      db.onboardingCompletions = {
        'FM': OnboardingPhase.phaseLength,
        'NC': OnboardingPhase.phaseLength,
        'PA': OnboardingPhase.phaseLength,
        'CC': OnboardingPhase.phaseLength,
        'RC': OnboardingPhase.phaseLength,
      };
      final phase = db.currentPhase!;
      expect(phase.introducing, 'GS');
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, {'GS'});
      expect(
        reco.bannedRules,
        OnboardingPhase.postStrictDiscoveryOrder.toSet(),
      );
    });
  });

  group('Database.recommendedOnboardingFilters — soft filter', () {
    test('elects the first unseen post-strict slug, bans the rest', () {
      // Player has graduated every strict phase. They have seen LT
      // already (e.g. from a stray puzzle). The next slug in
      // postStrictDiscoveryOrder that is still unseen is QA — that's
      // the elected slug. Every OTHER unseen post-strict slug must be
      // in bannedRules; wantedRules stays empty so puzzles with 0 new
      // slugs (pure refresh) still pass.
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.phases.map((p) => p.introducing)) {
        progress.noteSeen(s, now);
      }
      progress.noteSeen('LT', now);
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, isEmpty);
      // elected = QA (first unseen in postStrictDiscoveryOrder after LT).
      // banned = postStrict \ {seen-LT, elected-QA} = {SY, DF, SH, GC, MJ, EY}.
      expect(reco.bannedRules, {'SY', 'DF', 'SH', 'GC', 'MJ', 'EY'});
    });

    test('returns null once every known slug has been seen', () {
      // No more discovery to drive: every constraint has been met.
      // recommendedOnboardingFilters drops back to null and the player
      // exits onboarding entirely (isInOnboarding == false).
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.allKnownSlugs) {
        progress.noteSeen(s, now);
      }
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      expect(db.recommendedOnboardingFilters, isNull);
      expect(db.isInOnboarding, isFalse);
    });
  });

  group(
    'Database.recommendedOnboardingFilters — null when not in onboarding',
    () {
      test('returns null when progress is missing (CLI / tests)', () {
        // CLI tools and some unit tests construct Database without a
        // ConstraintProgress. The strict-phase recommendation still works
        // (it doesn't need progress) but the soft-filter branch can't
        // run, and once the player has graduated all strict phases the
        // overall getter returns null.
        final db = Database(playerLevel: 50);
        db.onboardingCompletions = _allStrictPhasesCompleted();
        expect(db.recommendedOnboardingFilters, isNull);
      });
    },
  );

  group('Database.maybeApplyOnboardingFilterDefaults', () {
    test('first launch (no flag) applies P3 recommendation', () async {
      // Pre-migration state for a player mid-P3: the migration flag
      // was added in this refactor, so it's absent from prefs. The
      // very first call to maybeApplyOnboardingFilterDefaults must
      // pre-fill currentFilters with the P3 recommendation AND set
      // the flag.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      db.onboardingCompletions = {
        'FM': OnboardingPhase.phaseLength,
        'NC': OnboardingPhase.phaseLength,
        'PA': OnboardingPhase.phaseLength,
      };
      await db.maybeApplyOnboardingFilterDefaults(prefs);
      expect(db.currentFilters.wantedRules, {'CC'});
      expect(
        db.currentFilters.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({'FM', 'PA', 'NC', 'CC'}),
      );
      expect(prefs.getBool('onboardingFiltersApplied'), isTrue);
    });

    test('second launch (flag present) leaves filters untouched', () async {
      // Once the player has been migrated, their manual overrides win.
      // Here we simulate a returning player who explicitly cleared
      // every filter — the next loadPuzzlesFile must NOT re-apply the
      // P0 defaults on top of their choice.
      SharedPreferences.setMockInitialValues({
        'onboardingFiltersApplied': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      // Brand-new player state (P0), but flag says "already applied".
      db.currentFilters.wantedRules = {};
      db.currentFilters.bannedRules = {};
      await db.maybeApplyOnboardingFilterDefaults(prefs);
      expect(db.currentFilters.wantedRules, isEmpty);
      expect(db.currentFilters.bannedRules, isEmpty);
    });

    test('resetOnboardingProgress clears the migration flag', () async {
      // Replay-onboarding must re-arm the migration so the next
      // loadPuzzlesFile re-applies the freshly reset P0 recommendation.
      // Without clearing the flag, the player would land on P0 with
      // their stale custom filters and the learning track wouldn't
      // self-restore.
      SharedPreferences.setMockInitialValues({
        'onboardingFiltersApplied': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      await db.resetOnboardingProgress();
      expect(prefs.getBool('onboardingFiltersApplied'), isNull);
    });

    test('skipOnboarding clears the migration flag', () async {
      // Symmetric to the reset case: even when the player chose to
      // skip past the strict phases, the next launch should re-evaluate
      // the recommendation (now soft-filter-shaped, or null if every
      // slug has already been seen). Leaving the flag set would freeze
      // them on their previous P-phase filters indefinitely.
      SharedPreferences.setMockInitialValues({
        'onboardingFiltersApplied': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      await db.skipOnboarding();
      expect(prefs.getBool('onboardingFiltersApplied'), isNull);
    });

    test('graduated player sets the flag without touching filters', () async {
      // recommendedOnboardingFilters is null once every slug has been
      // seen. We still set the flag so subsequent boots stop probing —
      // otherwise every launch would re-evaluate the recommendation
      // for nothing.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.allKnownSlugs) {
        progress.noteSeen(s, now);
      }
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      db.currentFilters.wantedRules = {'SY'};
      db.currentFilters.bannedRules = {'FM'};
      await db.maybeApplyOnboardingFilterDefaults(prefs);
      expect(db.currentFilters.wantedRules, {'SY'});
      expect(db.currentFilters.bannedRules, {'FM'});
      expect(prefs.getBool('onboardingFiltersApplied'), isTrue);
    });
  });
}
