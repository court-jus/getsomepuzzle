import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/onboarding_completions.dart';

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

    test('P3 wants CC, bans every slug not in {FM, PA, NC, CC, RC}', () {
      // P3 introduces CC and allows {FM, PA, NC, CC, RC}. Anything else in
      // the registry must be banned so the catalog narrows to that
      // envelope, and the puzzle must contain CC (wantedRules).
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      // Mark P0..P2 introducers complete so phaseForCompletions lands on P3.
      db.onboardingCompletions = strictCompletionsUpTo(3);
      final phase = db.currentPhase!;
      expect(phase.introducing, 'CC');
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, {'CC'});
      expect(
        reco.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({
          'FM',
          'PA',
          'NC',
          'CC',
          'RC',
        }),
      );
    });

    test('P8 (last strict phase) wants QA, bans only post-strict slugs', () {
      // P8 introduces QA and allows {'FM', 'PA', 'NC', 'CC', 'RC', 'GS', 'EY', 'DF', 'LT', 'QA'}. The banned
      // set narrows to the post-strict tail (RC, RT, SY, SH, CH, CT, GC, MJ)
      // — exactly what postStrictDiscoveryOrder will manage next.
      final db = Database(playerLevel: 50, progress: ConstraintProgress());
      db.onboardingCompletions = strictCompletionsUpTo(8);
      final phase = db.currentPhase!;
      expect(phase.introducing, 'QA');
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, {'QA'});
      // RC shares the CC phase and is in every strict phase's allowed set
      // (propagated from the merged P3), so it is not banned. The remaining
      // post-strict slugs (SY, SH, CH, GC, MJ) plus CT and RT make up the
      // full banned set.
      expect(
        reco.bannedRules,
        OnboardingPhase.postStrictDiscoveryOrder.toSet().difference(
          phase.allowed,
        ),
      );
    });
  });

  group('Database.recommendedOnboardingFilters — soft filter', () {
    test('elects the first unseen post-strict slug, bans the rest', () {
      // Player has graduated every strict phase. Every post-strict slug
      // is unseen. The first in postStrictDiscoveryOrder (RT) is
      // elected, the rest are banned. wantedRules stays empty so puzzles
      // with 0 new slugs (pure refresh) still pass.
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.phases.map((p) => p.introducing)) {
        progress.noteSeen(s, now);
      }
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, isEmpty);
      final postStrict = OnboardingPhase.postStrictDiscoveryOrder;
      expect(reco.bannedRules, postStrict.sublist(1).toSet());
    });

    test('skips already-seen post-strict slugs when electing', () {
      // Player has graduated every strict phase AND has already met the
      // first post-strict slug ad hoc (e.g. a stray puzzle from a hand-
      // edited playlist surfaced it). The election must skip that slug
      // and pick the next unseen one in postStrictDiscoveryOrder — the
      // skipped slug is *not* banned (no need, the player already knows
      // it), and *not* wanted (we don't want to refocus on something
      // already learned).
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.phases.map((p) => p.introducing)) {
        progress.noteSeen(s, now);
      }
      final postStrict = OnboardingPhase.postStrictDiscoveryOrder;
      progress.noteSeen(postStrict.first, now);
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      final reco = db.recommendedOnboardingFilters!;
      // wantedRules stays empty (refresh-friendly soft filter).
      expect(reco.wantedRules, isEmpty);
      // Elected = postStrict[1] (next unseen). Banned = everything still
      // unseen and not elected, i.e. postStrict[2..]. The already-seen
      // postStrict.first never enters either set.
      expect(reco.bannedRules, postStrict.sublist(2).toSet());
      expect(reco.bannedRules.contains(postStrict.first), isFalse);
    });

    test('forces the last unseen post-strict slug into wantedRules', () {
      // Terminal soft-filter case: every post-strict slug has been seen
      // except one. The default soft-filter shape ({}, unseen \ elected)
      // would collapse to ({}, {}) — an empty recommendation that makes
      // the open-page banner show without any visible chip and grays
      // out the reset action. Flipping to wantedRules: {elected} keeps
      // a single chip visible AND focuses the next playlist on the
      // missing slug.
      final progress = ConstraintProgress();
      final now = DateTime(2026, 5, 19);
      for (final s in OnboardingPhase.phases.map((p) => p.introducing)) {
        progress.noteSeen(s, now);
      }
      // Seen everything in postStrictDiscoveryOrder except the last one.
      final lastSlug = OnboardingPhase.postStrictDiscoveryOrder.last;
      for (final s in OnboardingPhase.postStrictDiscoveryOrder) {
        if (s == lastSlug) continue;
        progress.noteSeen(s, now);
      }
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = _allStrictPhasesCompleted();
      final reco = db.recommendedOnboardingFilters!;
      expect(reco.wantedRules, {lastSlug});
      expect(reco.bannedRules, isEmpty);
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
      db.onboardingCompletions = strictCompletionsUpTo(3);
      await db.maybeApplyOnboardingFilterDefaults(prefs);
      expect(db.currentFilters.wantedRules, {'CC'});
      expect(
        db.currentFilters.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({
          'FM',
          'PA',
          'NC',
          'CC',
          'RC',
        }),
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

    test(
      'resetRuleFilters clears wanted/banned rules but keeps sizes',
      () async {
        // Leaving onboarding must drop the onboarding-imposed slug
        // envelope (otherwise the player stays pinned to the closing
        // onboarding slug). Size/flag filters are unrelated to onboarding
        // and must survive the reset.
        SharedPreferences.setMockInitialValues({});
        final db = Database(playerLevel: 50, progress: ConstraintProgress());
        db.currentFilters.wantedRules = {'EY'};
        db.currentFilters.bannedRules = {'FM', 'PA'};
        db.currentFilters.minWidth = 5;
        db.currentFilters.maxWidth = 8;
        await db.resetRuleFilters();
        expect(db.currentFilters.wantedRules, isEmpty);
        expect(db.currentFilters.bannedRules, isEmpty);
        expect(db.currentFilters.minWidth, 5);
        expect(db.currentFilters.maxWidth, 8);
      },
    );

    test('graduated player does not set the flag (reco is null)', () async {
      // recommendedOnboardingFilters is null once every slug has been
      // seen. The flag remains absent so a future state regression
      // (e.g. corrupted onboardingCompletions) can still apply fresh
      // filters on next launch.
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
      expect(prefs.getBool('onboardingFiltersApplied'), isNull);
    });
  });

  group('Filters.threeColorShare', () {
    test('defaults to 0 (only 2-colour) on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final filters = Filters();
      await filters.load();
      expect(filters.threeColorShare, 0);
    });

    test('migrates a legacy d2 ban to the fully-3-colour end', () async {
      // Old chips: banning d2 meant "3 colours only".
      SharedPreferences.setMockInitialValues({
        'bannedDomainsFilter': ['d2'],
      });
      final filters = Filters();
      await filters.load();
      expect(filters.threeColorShare, 1);
    });

    test('migrates a mixed legacy pool to the middle', () async {
      SharedPreferences.setMockInitialValues({
        'wantedDomainsFilter': ['d2', 'd3'],
        'bannedDomainsFilter': <String>[],
      });
      final filters = Filters();
      await filters.load();
      expect(filters.threeColorShare, 0.5);
    });

    test('save round-trips the share and drops the chip keys', () async {
      SharedPreferences.setMockInitialValues({});
      final filters = Filters()..threeColorShare = 0.2;
      await filters.save();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('wantedDomainsFilter'), isNull);
      expect(prefs.getStringList('bannedDomainsFilter'), isNull);
      final reloaded = Filters();
      await reloaded.load();
      expect(reloaded.threeColorShare, 0.2);
    });
  });
}
