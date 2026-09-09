import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/onboarding_completions.dart';

/// Synthesize the on-disk stat-line format (see `PuzzleData.getStat`).
/// SLD = "___" (no skip/like/dislike); empty extras after the dashes.
String stat(String puzzleLine, [String finishedIso = '2026-03-15T10:00:00']) =>
    '$finishedIso 30s 0f $puzzleLine - ___ -  -  -  - 0h - 0e - 0fc - 0lg';

/// A structurally distinct v2 puzzle line declaring [slugs]. Varying
/// [variant] (1–9) changes the prefill, so each variant is a distinct
/// puzzle for identity-key purposes (distinct plays of the same puzzle
/// must collapse to a single completion).
String puzzleWithSlugs(List<String> slugs, int variant) {
  final constraints = slugs.map((s) => '$s:1').join(';');
  return 'v2_12_3x3_0000${variant}0000_${constraints}_1:21212121${variant}_6';
}

void main() {
  group('Database.reconcileOnboardingWithStats', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'adopts a completed history and releases the onboarding filters',
      () async {
        // A device whose local prefs only reached the QA phase (P8)
        // activates a stats sync folder holding another device's
        // completed history. firstSeen alone is already rebuilt by
        // loadStats; the phase counter and the pinned rule chips must
        // follow, otherwise the player stays stuck on the "learning
        // track" preset with no new-rule dialog ever firing again.
        final progress = ConstraintProgress();
        final db = Database(playerLevel: 50, progress: progress);
        db.onboardingCompletions = strictCompletionsUpTo(8);
        // The merged history proves the onboarding is over: one puzzle
        // covering every known slug (so firstSeen completes) plus four
        // more distinct QA finishes (QA 1→5 crosses the last strict
        // phase).
        final all = OnboardingPhase.allKnownSlugs.toList();
        final lines = <String>[
          stat(puzzleWithSlugs(all, 1)),
          for (var i = 2; i <= 5; i++) stat(puzzleWithSlugs(['QA'], i)),
        ];
        db.loadStats(lines.map((l) => StatEntry.parse(l)!).toList());
        expect(progress.firstSeen.length, OnboardingPhase.allKnownSlugs.length);
        // Open-page chips pinned to the P8 preset.
        db.currentFilters.wantedRules = {'QA'};
        db.currentFilters.bannedRules = {
          'RT',
          'MI',
          'SY',
          'SH',
          'JC',
          'CH',
          'CT',
          'GC',
          'MJ',
          'IM',
          'IS',
          'JR',
          'BB',
          'RE',
          'SZ',
        };
        expect(db.currentPhase?.introducing, 'QA');
        expect(db.isInOnboarding, isTrue);

        await db.reconcileOnboardingWithStats(wasInOnboarding: true);

        expect(db.onboardingCompletions['QA'], 5);
        expect(db.currentPhase, isNull);
        expect(db.isInOnboarding, isFalse);
        expect(db.currentFilters.wantedRules, isEmpty);
        expect(db.currentFilters.bannedRules, isEmpty);
        expect(db.onboardingCompletedAt, isNotNull);
      },
    );

    test('RC plays feed the merged CC/RC phase arithmetic', () async {
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      // Local progress: strict phases 0–2 done → the merged CC/RC
      // phase (index 3) is pending.
      db.onboardingCompletions = strictCompletionsUpTo(3);
      expect(db.currentPhase?.introducing, 'CC');
      // Merged history: 5 distinct RC puzzles finished elsewhere.
      final rcLines = [
        for (var i = 1; i <= 5; i++) puzzleWithSlugs(['RC'], i),
      ];
      db.loadStats(rcLines.map((l) => StatEntry.parse(stat(l))!).toList());

      await db.reconcileOnboardingWithStats(wasInOnboarding: true);

      expect(db.onboardingCompletions['RC'], 5);
      // CC (0) + RC (5) ≥ 5 → the merged phase passes.
      expect(db.currentPhase?.introducing, 'GS');
    });

    test('advances a partial phase and re-pins the advanced preset', () async {
      // Local progress sits at P1 (NC at 2/5); the merged history
      // brings 5 NC finishes. The player must land on the P2 preset,
      // not keep the stale P1 chips.
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = {'FM': 5, 'NC': 2};
      expect(db.currentPhase?.introducing, 'NC');
      db.currentFilters.wantedRules = {'NC'};
      db.currentFilters.bannedRules = OnboardingPhase.allKnownSlugs.difference({
        'FM',
        'NC',
      });
      final ncLines = [
        for (var i = 1; i <= 5; i++) puzzleWithSlugs(['NC'], i),
      ];
      db.loadStats(ncLines.map((l) => StatEntry.parse(stat(l))!).toList());

      await db.reconcileOnboardingWithStats(wasInOnboarding: true);

      expect(db.onboardingCompletions['NC'], 5);
      expect(db.currentPhase?.introducing, 'PA');
      expect(db.currentFilters.wantedRules, {'PA'});
      expect(
        db.currentFilters.bannedRules,
        OnboardingPhase.allKnownSlugs.difference({'FM', 'PA', 'NC'}),
      );
      expect(db.isInOnboarding, isTrue);
    });

    test(
      'releases the soft-filter chips when the merge completes firstSeen',
      () async {
        // A post-strict player still missing one rule sees the soft
        // filter elect it; the merged history proves the final play.
        final progress = ConstraintProgress();
        final db = Database(playerLevel: 50, progress: progress);
        db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
        const missing = 'SZ';
        expect(OnboardingPhase.allKnownSlugs, contains(missing));
        final seen = OnboardingPhase.allKnownSlugs
            .where((s) => s != missing)
            .toList();
        final partial = [stat(puzzleWithSlugs(seen, 1))];
        db.loadStats(partial.map((l) => StatEntry.parse(l)!).toList());
        expect(db.isInOnboarding, isTrue);
        expect(db.electedSoftSlug, missing);
        // Terminal-case chips ("force the missing slug").
        db.currentFilters.wantedRules = {missing};
        db.currentFilters.bannedRules = <String>{};
        // The sync folder now brings one finished SZ puzzle.
        db.loadStats([
          StatEntry.parse(stat(puzzleWithSlugs(seen, 1)))!,
          StatEntry.parse(stat(puzzleWithSlugs([missing], 2)))!,
        ]);
        expect(progress.firstSeen, contains(missing));

        await db.reconcileOnboardingWithStats(wasInOnboarding: true);

        expect(db.isInOnboarding, isFalse);
        expect(db.currentFilters.wantedRules, isEmpty);
        expect(db.currentFilters.bannedRules, isEmpty);
      },
    );

    test('max semantics: a younger merged history never regresses', () async {
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = {'FM': 5, 'NC': 2};
      // History proves only 3 FM finishes — fewer than the local 5.
      final fmLines = [
        for (var i = 1; i <= 3; i++) puzzleWithSlugs(['FM'], i),
      ];
      db.loadStats(fmLines.map((l) => StatEntry.parse(stat(l))!).toList());

      await db.reconcileOnboardingWithStats(wasInOnboarding: true);

      expect(db.onboardingCompletions['FM'], 5);
      expect(db.onboardingCompletions['NC'], 2);
      expect(db.currentPhase?.introducing, 'NC');
    });

    test('skipped and unfinished plays never count toward the phase', () async {
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = {};
      final skippedLine =
          '2026-03-15T10:00:00 0s 0f '
          '${puzzleWithSlugs(['FM'], 1)} - S__ - '
          '2026-03-15T10:01:00 -  -  -  - 0h - 0e - 0fc - 0lg';
      final unfinishedLine =
          'unfinished 0s 0f ${puzzleWithSlugs(['FM'], 2)} '
          '- ___ -  -  -  - 0h - 0e - 0fc - 0lg';
      db.loadStats([
        StatEntry.parse(skippedLine)!,
        StatEntry.parse(unfinishedLine)!,
      ]);

      await db.reconcileOnboardingWithStats(wasInOnboarding: true);

      expect(db.onboardingCompletions, isEmpty);
    });

    test(
      'replays of the same puzzle collapse into a single completion',
      () async {
        final progress = ConstraintProgress();
        final db = Database(playerLevel: 50, progress: progress);
        db.onboardingCompletions = {};
        final line = puzzleWithSlugs(['FM'], 3);
        // Two finished rows for the same puzzle on distinct dates.
        db.loadStats([
          StatEntry.parse(stat(line, '2026-03-15T10:00:00'))!,
          StatEntry.parse(stat(line, '2026-03-16T10:00:00'))!,
        ]);

        await db.reconcileOnboardingWithStats(wasInOnboarding: true);

        expect(db.onboardingCompletions['FM'], 1);
      },
    );

    test('keeps a graduated player\'s own filters untouched', () async {
      // A player already out of onboarding who re-picks their sync
      // folder must keep their explicit rule chips — reconcile must
      // only release the onboarding-imposed envelope when this merge is
      // what ended the onboarding.
      final progress = ConstraintProgress();
      final db = Database(playerLevel: 50, progress: progress);
      db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      final all = OnboardingPhase.allKnownSlugs.toList();
      db.loadStats([StatEntry.parse(stat(puzzleWithSlugs(all, 1)))!]);
      expect(db.isInOnboarding, isFalse);
      db.currentFilters.wantedRules = {'GS'};
      db.currentFilters.bannedRules = {'FM'};

      await db.reconcileOnboardingWithStats(wasInOnboarding: false);

      expect(db.currentFilters.wantedRules, {'GS'});
      expect(db.currentFilters.bannedRules, {'FM'});
      expect(db.isInOnboarding, isFalse);
    });

    test(
      'a plain load never adopts (replay-onboarding survives a restart)',
      () {
        // Regression guard for the "Rejouer l'onboarding" flow: it clears
        // the phase counter while the full history stays on disk, then
        // re-runs loadPuzzlesFile (loadStats) in the same session. The
        // adoption must live in reconcileOnboardingWithStats only — a
        // plain load keeps the player in phase 0, otherwise replay would
        // end at the next launch.
        final progress = ConstraintProgress();
        final db = Database(playerLevel: 50, progress: progress);
        db.onboardingCompletions = {};
        final qaLines = [
          for (var i = 1; i <= 5; i++) puzzleWithSlugs(['QA'], i),
        ];
        db.loadStats(qaLines.map((l) => StatEntry.parse(stat(l))!).toList());

        expect(db.onboardingCompletions, isEmpty);
        expect(db.currentPhase?.index, 0);
        expect(db.isInOnboarding, isTrue);
      },
    );
  });
}
