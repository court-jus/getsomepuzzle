import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Minimal-but-valid `PuzzleData` line. The constraint section repeats
/// `FM:12` `nCons` times by default so `PuzzleData.rules.length == nCons`,
/// which the duration model now consumes. Pass `slugs` to override the
/// default `FM` repetition with an explicit list (e.g. `['FM', 'GS']`) —
/// each slug gets a single dummy parameter `:1` appended, since the
/// adapt-to-player logic only cares about the slug name.
///
/// None of the adapt-to-player logic cares about semantic validity — only
/// width, height, the trailing `cplx`, and the parsed `rules`.
PuzzleData _puz({
  required int cplx,
  int width = 5,
  int height = 5,
  int nCons = 1,
  List<String>? slugs,
}) {
  final cellsStr = '0' * (width * height);
  final cons = (slugs ?? List.filled(nCons, 'FM')).map((s) => '$s:1').join(';');
  return PuzzleData('v2_12_${width}x${height}_${cellsStr}_${cons}_0:0_$cplx');
}

/// Mirror of the private `Database._expectedDuration`. Tests use it to craft
/// durations that satisfy the model's equilibrium so we can check the
/// invariant `level ≈ cplx`. Must stay in sync with the constants in
/// `database.dart` (anchored model: log(dur) = 1.197 + 0.00808·cplx
/// + 0.5146·log(cells) + 0.151·failures + 0.102·n_cons).
double _expectedFor(int cplx, int cells, int failures, int nCons) =>
    3.3108 *
    math.pow(cells, 0.5146) *
    math.exp(cplx / 123.82) *
    math.pow(1.1627, failures) *
    math.pow(1.1069, nCons);

void main() {
  group('Database.computePlayerLevel', () {
    test('falls back to the stored level when fewer than 2 usable plays', () {
      // Threshold preserves any manually set level while the history is too
      // thin to invert (one play is just noise on the per-play estimator).
      final db = Database(playerLevel: 0);
      db.puzzles = [
        _puz(cplx: 30)
          ..played = true
          ..duration = 40
          ..finished = DateTime(2026, 1, 1),
      ];
      expect(db.computePlayerLevel(fallback: 42), 42);
    });

    test('yields ≈ cplx when every duration matches the expected model', () {
      // Invariant of the skill inversion: when a play's duration equals
      // `_expectedDuration` for its puzzle, `level_i = cplx` exactly. So
      // averaging 12 plays at cplx=40 must give ~40 (small rounding only).
      // The fixture pins `nCons=3` to match the duration the helper feeds
      // back into `_expectedFor`, since the model now depends on it.
      final db = Database(playerLevel: 0);
      const cplx = 40;
      const nCons = 3;
      final dur = _expectedFor(cplx, 25, 0, nCons).round();
      db.puzzles = List.generate(12, (i) {
        return _puz(cplx: cplx, nCons: nCons)
          ..played = true
          ..duration = dur
          ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i));
      });
      expect(db.computePlayerLevel(fallback: 0), closeTo(cplx, 2));
    });

    test('skipped puzzles are excluded from the sample', () {
      // 1 finished + 10 skipped: only the finished play is usable, which
      // sits below the threshold of 2 — so the level inference must yield
      // the fallback rather than a value derived from the skipped ones.
      // (If skipped were counted, we would emit 77's neighbourhood, not
      // the fallback 77 itself; the test passes only because they're
      // genuinely excluded from the sample size check.)
      final db = Database(playerLevel: 0);
      const cplx = 40;
      const nCons = 3;
      final dur = _expectedFor(cplx, 25, 0, nCons).round();
      db.puzzles = [
        _puz(cplx: cplx, nCons: nCons)
          ..played = true
          ..duration = dur
          ..finished = DateTime(2026, 1, 1),
        for (int i = 0; i < 10; i++)
          (_puz(cplx: cplx, nCons: nCons)
            ..played = true
            ..duration = dur
            ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i + 10))
            ..skipped = DateTime(2026, 1, 1)),
      ];
      expect(db.computePlayerLevel(fallback: 77), 77);
    });

    test('level rises with constraint count when duration is held fixed', () {
      // n_constraints captures parsing/setup cost: at the same cplx,
      // cells, and duration, a puzzle with more constraints means the
      // player worked through more rules at the same speed → higher
      // implicit level. Locks in the sign of the n_cons coefficient so a
      // future regression that drops the term (or flips its sign) fails
      // here instead of silently undoing the recalibration.
      DateTime ts(int i) => DateTime(2026, 1, 1).add(Duration(minutes: i));
      Database build(int nCons) {
        final db = Database(playerLevel: 0);
        db.puzzles = List.generate(
          12,
          (i) => _puz(cplx: 20, nCons: nCons)
            ..played = true
            ..duration = 30
            ..finished = ts(i),
        );
        return db;
      }

      final lowCons = build(2).computePlayerLevel(fallback: 0);
      final highCons = build(15).computePlayerLevel(fallback: 0);
      expect(highCons, greaterThan(lowCons));
    });
  });

  group('Database.getPuzzlesByLevel', () {
    test('returns the entire filtered catalog (no hard cplx window)', () {
      // With Gaussian sampling, every filtered puzzle has a non-zero weight.
      // The list is the catalog ordered by likelihood-of-being-near-skill,
      // not a hard window. So a player at level 16 still occasionally sees
      // a cplx=99 puzzle — at the tail of the distribution, but present.
      final db = Database(playerLevel: 0);
      db.puzzles = [
        for (final c in [5, 10, 15, 16, 17, 20, 50, 99]) _puz(cplx: c),
      ];
      final got = db.getPuzzlesByLevel(16).map((p) => p.cplx).toList();
      expect(got, hasLength(8));
    });

    test('biases the order toward cplx near the player level', () {
      // Sanity check: across many calls, puzzles near the centre should
      // appear in the first slots more often than far-off ones. Pinning the
      // RNG keeps the test deterministic.
      final db = Database(playerLevel: 0)..samplingRandom = math.Random(42);
      db.puzzles = [
        for (final c in [0, 10, 16, 22, 50, 80, 99]) _puz(cplx: c),
      ];
      // Top 3 over 200 trials: count how often cplx=16 appears in the head.
      var nearTop = 0;
      var farTop = 0;
      for (var i = 0; i < 200; i++) {
        final head = db.getPuzzlesByLevel(16).take(3).map((p) => p.cplx);
        if (head.contains(16)) nearTop++;
        if (head.contains(99)) farTop++;
      }
      // The puzzle at the centre should land in the head far more often
      // than the one ~17σ away. Loose bound: near should beat far by ≥3×.
      expect(nearTop, greaterThan(farTop * 3));
    });

    test('excludes already-played puzzles via the default flag filter', () {
      final db = Database(playerLevel: 0);
      final played = _puz(cplx: 16)
        ..played = true
        ..finished = DateTime(2026, 1, 1);
      final unplayed = _puz(cplx: 16);
      db.puzzles = [played, unplayed];
      final got = db.getPuzzlesByLevel(16);
      expect(got, hasLength(1));
      expect(got.first, same(unplayed));
    });
  });

  group('Database.getPuzzlesByLevel — variety bias', () {
    /// Helper: mark a puzzle as a finished play, with a `finished` timestamp
    /// derived from `i` (lower i = more recent, since the variety stats sort
    /// by `finished` descending).
    PuzzleData play(PuzzleData p, int recencyIndex) {
      // Use a base far in the future and subtract `recencyIndex` minutes,
      // so a smaller `recencyIndex` is more recent. Duration > 0 is required
      // to keep the play in the sample.
      p.played = true;
      p.duration = 30;
      p.finished = DateTime(
        2030,
        1,
        1,
      ).subtract(Duration(minutes: recencyIndex));
      return p;
    }

    test('empty history yields gap = 0 for every candidate', () {
      // No plays in the catalog → recency-weighted distribution is empty,
      // so the variety multiplier degrades to 1 (no boost) and the
      // selection collapses to the legacy cplx-only Gaussian.
      final db = Database(playerLevel: 0);
      db.puzzles = [
        for (final c in [10, 16, 22]) _puz(cplx: c, slugs: ['FM']),
      ];
      final stats = db.buildRecencyWeightedStats(db.puzzles);
      expect(stats.totalPuzzles, 0);
      for (final p in db.puzzles) {
        expect(db.varietyGapForPuzzle(p, stats), 0.0);
      }
    });

    test('exponential decay applies weight 0.5^(i/30) per play', () {
      // The decay shape is the load-bearing tuning constant of the variety
      // bias. Pinning the half-life keeps a future drift (e.g. someone
      // halving the constant) from silently changing the user-visible
      // pacing of variety push.
      final db = Database(playerLevel: 0);
      // 31 plays of size 4×4 / slug FM, in chronological order: index 0 =
      // most recent, index 30 = oldest. Slug & size are kept identical so
      // every contribution lands in the same bucket.
      db.puzzles = [
        for (var i = 0; i < 31; i++)
          play(_puz(cplx: 16, width: 4, height: 4, slugs: ['FM']), i),
      ];
      final stats = db.buildRecencyWeightedStats(db.puzzles);
      // Σ_{i=0..30} 0.5^(i/30) — geometric series with ratio r = 0.5^(1/30).
      final r = math.pow(0.5, 1 / 30).toDouble();
      final expected = (1 - math.pow(r, 31)) / (1 - r);
      expect(stats.totalPuzzles, closeTo(expected, 1e-6));
      // Slug FM gets one tally per play → same total.
      expect(stats.slugCounts['FM'], closeTo(expected, 1e-6));
    });

    test('monomaniac player → unfamiliar slug has positive gap', () {
      // After 30 finished plays of 4×4 FM, the recency-weighted observed
      // share of FM is ~1.0 and of GS is 0.0. A new candidate with slug GS
      // should therefore see a strictly positive variety gap, while a new
      // candidate sticking with FM at the same size sees gap == 0.
      final db = Database(playerLevel: 0);
      final fmCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['FM']);
      final gsCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['GS']);
      db.puzzles = [
        fmCandidate,
        gsCandidate,
        for (var i = 0; i < 30; i++)
          play(_puz(cplx: 16, width: 4, height: 4, slugs: ['FM']), i),
      ];
      final stats = db.buildRecencyWeightedStats(db.puzzles);
      final fmGap = db.varietyGapForPuzzle(fmCandidate, stats);
      final gsGap = db.varietyGapForPuzzle(gsCandidate, stats);
      expect(fmGap, 0.0);
      expect(gsGap, greaterThan(0.0));
    });

    test('size axis: under-represented size yields positive gap', () {
      // Same setup but the candidates differ on size (FM/4×4 vs FM/6×6),
      // and the history is exclusively 4×4. The 6×6 candidate should pick
      // up a positive gap from the size axis alone.
      final db = Database(playerLevel: 0);
      final smallCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['FM']);
      final largeCandidate = _puz(cplx: 16, width: 6, height: 6, slugs: ['FM']);
      db.puzzles = [
        smallCandidate,
        largeCandidate,
        for (var i = 0; i < 30; i++)
          play(_puz(cplx: 16, width: 4, height: 4, slugs: ['FM']), i),
      ];
      final stats = db.buildRecencyWeightedStats(db.puzzles);
      // Both candidates share the same slug (FM) which is saturated, so
      // the slug component cancels out. The remaining gap comes from size.
      expect(
        db.varietyGapForPuzzle(largeCandidate, stats),
        greaterThan(db.varietyGapForPuzzle(smallCandidate, stats)),
      );
    });

    test('banned rule is excluded from the universe (no phantom gap)', () {
      // If the user bans GS via filters, the only reachable puzzles are FM.
      // The recency-weighted universe must therefore not list GS as a slug
      // — otherwise GS would always appear under-represented (count = 0)
      // and no candidate would benefit from "filling" it (since none can).
      // The universe is built from the *filtered* catalog, so banned slugs
      // disappear from the calculation.
      final db = Database(playerLevel: 0);
      db.puzzles = [
        for (var i = 0; i < 5; i++)
          play(_puz(cplx: 16, width: 4, height: 4, slugs: ['FM']), i),
      ];
      // Universe built from a filtered catalog containing only FM puzzles.
      final filtered = [
        _puz(cplx: 16, width: 4, height: 4, slugs: ['FM']),
      ];
      final stats = db.buildRecencyWeightedStats(filtered);
      expect(stats.nSlugs, 1);
      // A hypothetical GS candidate evaluated against this universe would
      // contribute 0 to the slug gap (avgK / nSlugs = 1 / 1 = 1, share = 0
      // → gap = 1, but for FM share = 1 → gap = 0; so the GS gap *would*
      // show up if GS were in the universe — but it isn't, so any GS
      // candidate is irrelevant to the selection).
      final fmCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['FM']);
      // FM is fully saturated under this universe → slug gap = 0.
      expect(db.varietyGapForPuzzle(fmCandidate, stats), 0.0);
    });

    test('biases toward under-represented categories at equal cplx', () {
      // End-to-end check: with the player having played 30 puzzles of
      // 4×4 FM, getPuzzlesByLevel called repeatedly should rank the GS
      // candidate higher than the FM candidate over many trials, even
      // though both share the same cplx (= the player level, so the
      // cplx-Gaussian is symmetric between them).
      //
      // Math: GS gap = 0.5 (slug under-represented), FM gap = 0. With
      // α=1.5 the multiplier ratio is 1.75/1 = 1.75, so over many trials
      // P(GS first) ≈ 1.75/2.75 ≈ 63.6 %. The threshold below is a loose
      // floor that catches a complete failure of the bias (e.g. the
      // multiplier never gets applied) while tolerating sampling noise.
      final db = Database(playerLevel: 0)..samplingRandom = math.Random(13);
      final fmCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['FM']);
      final gsCandidate = _puz(cplx: 16, width: 4, height: 4, slugs: ['GS']);
      db.puzzles = [
        fmCandidate,
        gsCandidate,
        for (var i = 0; i < 30; i++)
          play(_puz(cplx: 16, width: 4, height: 4, slugs: ['FM']), i),
      ];
      var gsHead = 0;
      var fmHead = 0;
      for (var i = 0; i < 1000; i++) {
        final ordered = db.getPuzzlesByLevel(16);
        if (ordered.first.rules.contains('GS')) gsHead++;
        if (ordered.first.rules.contains('FM')) fmHead++;
      }
      // GS should clearly win more than FM. Out of 1000 trials, expect
      // ≈636 GS wins; assert it beats FM by a wide margin.
      expect(gsHead, greaterThan(fmHead));
      expect(gsHead, greaterThan(550));
    });
  });

  group('Database.hasUnplayedIgnoringFilters', () {
    test('returns true when user filters hide otherwise-eligible puzzles', () {
      // EndOfPlaylist uses this to distinguish "filters are hiding puzzles"
      // from "everything has been played". A strict maxWidth must not make
      // the 8x8 puzzle vanish from this probe.
      final db = Database(playerLevel: 0);
      db.puzzles = [_puz(cplx: 20, width: 8, height: 8)];
      db.currentFilters.maxWidth = 5;
      expect(db.getPuzzlesByLevel(20), isEmpty);
      expect(db.hasUnplayedIgnoringFilters(), isTrue);
    });

    test(
      'returns false when every catalog puzzle is played/skipped/disliked',
      () {
        final db = Database(playerLevel: 0);
        db.puzzles = [
          _puz(cplx: 20)
            ..played = true
            ..finished = DateTime(2026, 1, 1),
          _puz(cplx: 21)..skipped = DateTime(2026, 1, 1),
        ];
        expect(db.hasUnplayedIgnoringFilters(), isFalse);
      },
    );
  });

  group('Database.areFiltersBlocking', () {
    test('true when user filters hide every otherwise-eligible puzzle', () {
      // 8x8 puzzle, maxWidth=5 → filter() empty, but the puzzle exists
      // unplayed → user filters are the cause. This is the only case
      // where EndOfPlaylist should invite the player to relax filters.
      final db = Database(playerLevel: 0);
      db.puzzles = [_puz(cplx: 20, width: 8, height: 8)];
      db.currentFilters.maxWidth = 5;
      expect(db.areFiltersBlocking, isTrue);
    });

    test(
      'false at end of batch — unconsumed candidates remain in filter()',
      () {
        // Regression: previous logic surfaced "filters hiding" at every
        // batch boundary because 1000+ unplayed puzzles remained in the
        // collection while the active 20-puzzle batch had been consumed.
        // Here we model 5 played + 5 unplayed; filter() returns the 5
        // unplayed → NOT a filter problem.
        final db = Database(playerLevel: 0);
        db.puzzles = [
          for (int i = 0; i < 5; i++)
            (_puz(cplx: 20)
              ..played = true
              ..finished = DateTime(2026, 1, 1)),
          for (int i = 0; i < 5; i++) _puz(cplx: 20),
        ];
        expect(db.areFiltersBlocking, isFalse);
      },
    );

    test('false when the catalog is genuinely exhausted', () {
      // Every puzzle has been played; filter() empty AND no unplayed
      // candidates → user is just done, not stuck on filters.
      final db = Database(playerLevel: 0);
      db.puzzles = [
        _puz(cplx: 20)
          ..played = true
          ..finished = DateTime(2026, 1, 1),
        _puz(cplx: 21)
          ..played = true
          ..finished = DateTime(2026, 1, 1),
      ];
      expect(db.areFiltersBlocking, isFalse);
    });
  });

  group('recommendedLevelFor', () {
    // The threshold function maps a `playerLevel` (0..100, anchored at 50
    // = cohort average) to a playable PuzzleLevel via hand-picked
    // boundaries. These tests pin the bucket boundaries and the edge
    // cases so a future tweak forces a deliberate test update.

    test('low playerLevel maps to beginner', () {
      expect(recommendedLevelFor(0), PuzzleLevel.beginner);
      expect(recommendedLevelFor(24), PuzzleLevel.beginner);
    });

    test('cohort-average playerLevel sits on the advanced/strong boundary', () {
      // 49 → advanced, 50 → strong. The boundary is intentional: an
      // average-paced player (per the cohort anchor) should sample from
      // both adjacent tiers depending on day-to-day variation.
      expect(recommendedLevelFor(49), PuzzleLevel.advanced);
      expect(recommendedLevelFor(50), PuzzleLevel.strong);
    });

    test('high playerLevel maps to mad', () {
      expect(recommendedLevelFor(80), PuzzleLevel.mad);
      expect(recommendedLevelFor(120), PuzzleLevel.mad);
    });

    test('every threshold transition is covered', () {
      // Each named boundary returns the bucket immediately below.
      expect(recommendedLevelFor(25), PuzzleLevel.player);
      expect(recommendedLevelFor(40), PuzzleLevel.advanced);
      expect(recommendedLevelFor(65), PuzzleLevel.expert);
    });
  });

  group('Database.recommendedCollectionKey', () {
    // Stats lines that parse to a finished, non-skipped entry. The
    // recommendation uses the global stats count (not the currently
    // loaded `puzzles` list), so a returning player who has played 100
    // puzzles in another collection still sees the badge as soon as
    // they switch collections — no need to grind 10 plays again.
    List<String> nFinishedStatLines(int n) => List.generate(
      n,
      (i) =>
          '2026-01-0${(i % 9) + 1}T12:00:00 30s 0f v2_12_4x4_0000000000000000_FM:1_0:0_$i',
    );

    // The gate is tied to `playlistBatchSize` with a floor of 3. We
    // pick test sizes well below (1) and well above (≥40, past the
    // last strict onboarding phase so the recommendation is no longer
    // suppressed by `currentPhase != null`) so the tests remain
    // robust to the constants being tweaked.
    const enough = 40;

    test('null below the onboarding noise floor (1 play)', () {
      final db = Database(playerLevel: 50);
      db.collection = '1-easy';
      db.loadStats(nFinishedStatLines(1));
      expect(db.recommendedCollectionKey, isNull);
    });

    test('null when the recommendation matches the current collection', () {
      // playerLevel 50 maps to strong → '4-strong'. With current
      // collection already '4-strong', no badge / banner needed.
      final db = Database(playerLevel: 50);
      db.collection = '4-strong';
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, isNull);
    });

    test('returns recommended key when it differs from current', () {
      // playerLevel 80 → mad ('6-mad'). Player is in '2-player'.
      final db = Database(playerLevel: 80);
      db.collection = '2-player';
      db.onboardingCompletions = enough; // past strict phases
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, '6-mad');
    });

    test('counts plays globally — the loaded `puzzles` list is irrelevant', () {
      // Returning player: 0 puzzles loaded in memory (e.g., they just
      // switched to a fresh collection mid-session), but their stats
      // history holds enough finished plays from other collections.
      // The recommendation must surface immediately, not wait for
      // fresh plays in the current bucket.
      final db = Database(playerLevel: 80);
      db.collection = '2-player';
      db.onboardingCompletions = enough; // past strict phases
      db.puzzles = []; // nothing loaded in memory
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, '6-mad');
    });

    test('notePuzzleCompleted clears the gate during a session', () {
      // Brand-new player: stats file empty, `loadStats` sees 0 usable
      // plays. They play their way through `enough` puzzles in the
      // session — `notePuzzleCompleted` must lift the gate even
      // before the first writeStats round-trips through the stats
      // file. Without this hook, the gate would only see the
      // boot-time count and stay closed across an entire session for
      // a fresh player.
      final db = Database(playerLevel: 80);
      db.collection = '2-player';
      db.loadStats(const []); // fresh stats, 0 plays
      expect(db.recommendedCollectionKey, isNull);
      // Synthesize a played puzzle just to satisfy the signature; the
      // counter increment doesn't depend on the puzzle's content.
      final puz = PuzzleData('v2_12_3x3_000020000_FM:11_1:212121212_6');
      for (int i = 0; i < enough; i++) {
        db.notePuzzleCompleted(puz);
      }
      expect(db.recommendedCollectionKey, '6-mad');
    });

    test('null while still in a strict onboarding phase', () {
      // A fast learner could otherwise see a "try 6-mad" suggestion at
      // the end of their first batch even though they've barely met
      // FM. The recommendation is suppressed for the whole strict
      // window (P0-P3) regardless of how high `playerLevel` climbs.
      final db = Database(playerLevel: 80);
      db.collection = '1-easy';
      db.loadStats(nFinishedStatLines(enough));
      // Within strict (39 < 40), even though player level says 6-mad.
      db.onboardingCompletions = 39;
      expect(db.recommendedCollectionKey, isNull);
      // Once across the strict boundary, recommendation resumes.
      db.onboardingCompletions = 40;
      expect(db.recommendedCollectionKey, '6-mad');
    });
  });
}
