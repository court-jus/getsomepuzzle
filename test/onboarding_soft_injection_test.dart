import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression for the post-strict soft-discovery stall: a beginner who clears
/// every strict phase but never switches collections used to never meet the
/// rare soft-discovery rules (`RT`, `SY`, …) — the weighted sampler drowned
/// them under the abundant "refresh" draws, so onboarding never completed.
///
/// The fix (`Database._injectElectedSoftRule`) splices the elected rule into
/// the batch on a cadence ([Database.softElectedInjectPeriod]) rather than
/// every batch or never, drawing from the current collection first and the
/// widened higher-level pool when the collection is too thin (Axe B).
///
/// This test pins the *mechanism* deterministically (no assets, no RNG luck):
/// the elected rule is absent while the cadence counter is below the period,
/// then forced into the upcoming batch once it elapses — here sourced purely
/// from the injected widened pool, proving the widening path.

/// A small valid v2 line carrying exactly the given constraint slug.
String _line(String slug) => 'v2_12_3x3_000000000_$slug:0.1';

/// A soft-phase database: every strict phase complete, no soft slug met yet,
/// so `electedSoftSlug == 'RT'` and `_softFilterActive` is true.
Database _softDb() {
  final progress = ConstraintProgress();
  final seen = DateTime(2026, 1, 1);
  for (final p in OnboardingPhase.phases) {
    progress.noteSeen(p.introducing, seen);
  }
  final db = Database(playerLevel: 50, progress: progress);
  db.onboardingCompletions = {
    for (final p in OnboardingPhase.phases)
      p.introducing: OnboardingPhase.phaseLength,
  };
  // Mirror the soft-filter recommendation the app would have applied.
  db.currentFilters.wantedRules = {};
  db.currentFilters.bannedRules = OnboardingPhase.postStrictDiscoveryOrder
      .where((s) => s != 'RT')
      .toSet();
  db.samplingRandom = math.Random(42);
  return db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the elected soft-discovery rule is absent until the cadence period '
      'elapses, then is spliced into the batch from the widened pool', () {
    final db = _softDb();
    expect(db.electedSoftSlug, 'RT', reason: 'first post-strict slug');

    // Current collection holds only already-known "refresh" puzzles (no RT);
    // the only RT candidate lives in the widened higher-level pool (Axe B).
    db.puzzles = List.generate(20, (_) => PuzzleData(_line('FM')));
    db.softDiscoveryPoolForTest = [PuzzleData(_line('RT'))];

    bool batchHasRt() => db
        .getPuzzlesByLevel(50)
        .take(Database.playlistBatchSize)
        .any((p) => p.rules.contains('RT'));

    // First pass initialises the cadence (elected just observed) — the rule
    // must NOT yet be forced in, since the pool is only consulted on
    // injection and the counter is below the period.
    expect(
      batchHasRt(),
      isFalse,
      reason: 'no injection before the cadence period elapses',
    );

    // Simulate soft-phase plays until the cadence period is reached.
    final refresh = PuzzleData(_line('FM'));
    for (var i = 0; i < Database.softElectedInjectPeriod; i++) {
      db.notePuzzleCompleted(refresh);
    }

    expect(
      batchHasRt(),
      isTrue,
      reason:
          'once the period elapses the elected rule is injected into the '
          'upcoming batch from the widened pool',
    );
  });
}
