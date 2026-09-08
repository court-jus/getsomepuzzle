import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/stats.dart';

import 'helpers/onboarding_completions.dart';

/// Minimal-but-valid `PuzzleData` line. The constraint section repeats
/// `FM` `nCons` times by default so `PuzzleData.rules.length == nCons`,
/// which the duration model now consumes. Pass `slugs` to override the
/// default `FM` repetition with an explicit list (e.g. `['FM', 'GS']`) —
/// each slug gets a distinct dummy parameter appended, since the
/// adapt-to-player logic only cares about the slug name.
///
/// The params are made distinct per occurrence (`FM:0;FM:1;…`) on purpose:
/// the level computation counts constraints from the *stored* puzzle line,
/// which is normalized by `normalizeV2Line` (exact-duplicate constraints
/// are dropped), so identical repeats would collapse and change `nCons`.
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
  final slugsToUse = slugs ?? List.filled(nCons, 'FM');
  final cons = slugsToUse
      .asMap()
      .entries
      .map((e) => '${e.value}:${e.key}')
      .join(';');
  return PuzzleData('v2_12_${width}x${height}_${cellsStr}_${cons}_0:0_$cplx');
}

/// Mirror of the private `Database._expectedDuration`. Tests use it to craft
/// durations that satisfy the model's equilibrium so we can check the
/// invariant `level ≈ cplx`. Must stay in sync with the constants in
/// `database.dart` (anchored model: log(dur) = 1.586 + 0.01684·cplx
/// + 0.3437·log(cells) + 0.1775·failures + 0.0596·n_cons).
double _expectedFor(int cplx, int cells, int failures, int nCons) =>
    4.8834 *
    math.pow(cells, 0.3437) *
    math.exp(cplx / 59.39) *
    math.pow(1.1943, failures) *
    math.pow(1.0614, nCons);

/// `n` finished, non-skipped stat entries for a puzzle played at the
/// expected duration of `cplx` (so each play's implicit level ≈ `cplx`).
/// All entries share the same puzzle line but carry distinct completion
/// stamps, so they count as `n` separate samples (full-history semantics).
/// `durationS` overrides the duration (e.g. a left-open outlier);
/// `longestGapMs` plants an idle gap (AFK outlier); `stampOffsetSeconds`
/// shifts the completion stamps so two lists can be concatenated without
/// colliding in the `(canonical key, completion stamp)` dedup.
List<StatEntry> nPlays(
  int n, {
  required int cplx,
  int width = 4,
  int height = 5,
  int nCons = 3,
  int? durationS,
  int? longestGapMs,
  int stampOffsetSeconds = 0,
}) {
  final cells = width * height;
  final dur = durationS ?? _expectedFor(cplx, cells, 0, nCons).round();
  final prefill = '0' * cells;
  final cons = List.generate(nCons, (i) => 'FM:$i').join(';');
  final line = 'v2_12_${width}x${height}_${prefill}_${cons}_0:0_$cplx';
  final gap = longestGapMs == null ? '' : ' ${longestGapMs}lg';
  return List.generate(n, (i) {
    final s = stampOffsetSeconds + i;
    final stamp =
        '2026-01-01T12:${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return StatEntry.parse('$stamp ${dur}s 0f $line$gap')!;
  });
}

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

    test('counts plays across all collections, not just the loaded one', () {
      // Regression for "played a bunch but Lv 0": the sample must come from
      // the global play history. Here the current collection has no
      // in-memory plays at all (returning player who just switched
      // collections), yet the 12 finished plays recorded elsewhere still
      // drive the level.
      final db = Database(playerLevel: 0);
      db.collection = '2-player';
      db.puzzles = [];
      db.loadStats(nPlays(12, cplx: 40));
      expect(db.computePlayerLevel(fallback: 0), closeTo(40, 2));
    });

    test('replays of the same puzzle count as separate samples', () {
      // Full-history semantics: 12 plays of the *same* puzzle line with
      // distinct completion stamps are 12 samples, not one. A history
      // collapsed to one entry per puzzle would yield a single sample and
      // fall back instead.
      final db = Database(playerLevel: 0);
      db.loadStats(nPlays(12, cplx: 40));
      expect(db.computePlayerLevel(fallback: 0), closeTo(40, 2));
    });

    test(
      'a single left-open play cannot drag the level to 0 (winsorization)',
      () {
        // The left-open play clamps its duration to 10×expected, which would
        // give level_i ≈ cplx − 285 ≈ −245; without winsorization the
        // weighted average (the newest play weighs 1.0) collapses below 0 and
        // is pinned at 0. The floor max(cplx − 30, 0) = 10 bounds it instead,
        // so the result stays a plausible mix of the two plays.
        final db = Database(playerLevel: 0);
        const cplx = 40;
        const nCons = 3;
        final expected = _expectedFor(cplx, 20, 0, nCons);
        db.loadStats([
          ...nPlays(1, cplx: cplx, nCons: nCons),
          ...nPlays(
            1,
            cplx: cplx,
            nCons: nCons,
            durationS: (expected * 10).round(),
            stampOffsetSeconds: 300,
          ),
        ]);
        final level = db.computePlayerLevel(fallback: 0);
        expect(level, greaterThan(0));
        expect(level, lessThan(cplx));
      },
    );

    test('plays with an idle gap > 5 min are dropped (AFK guard)', () {
      // The 6 AFK plays (left-open duration + 400 000 ms idle gap) are
      // dropped; only the 6 at-expected plays remain, so the level stays
      // ≈ cplx. Without the guard the long outliers would drag it toward
      // the winsorization floor.
      final db = Database(playerLevel: 0);
      final expected = _expectedFor(40, 20, 0, 3);
      db.loadStats([
        ...nPlays(6, cplx: 40),
        ...nPlays(
          6,
          cplx: 40,
          durationS: (expected * 10).round(),
          longestGapMs: 400000,
          stampOffsetSeconds: 300,
        ),
      ]);
      expect(db.computePlayerLevel(fallback: 0), closeTo(40, 2));
    });

    test('plays without a cached complexity are skipped', () {
      // Custom / user playlists may carry no cplx tail (field [6] == 0):
      // those plays would give level_i = −impliedCplx < 0 and drag the
      // level to 0, so they must be excluded from the sample.
      final db = Database(playerLevel: 0);
      db.loadStats([
        ...nPlays(6, cplx: 40),
        ...nPlays(6, cplx: 0, stampOffsetSeconds: 300),
      ]);
      expect(db.computePlayerLevel(fallback: 0), closeTo(40, 2));
    });

    test('a very fast player can exceed level 100 (no upper clamp)', () {
      // 12 plays solved in 1 s at cplx 100: level_i ≈ 2·100 −
      // impliedCplx(1 s) ≈ 590, winsorized to cplx + 60 = 160 — still above
      // 100. The level must not be clamped back to 100.
      final db = Database(playerLevel: 0);
      db.loadStats(nPlays(12, cplx: 100, durationS: 1));
      expect(db.computePlayerLevel(fallback: 0), greaterThan(100));
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

    /// Single-GS 5×5 puzzle with an explicit `idx.size` parameter — the
    /// `_puz` helper only emits a bare `:1` dummy, which can't express a real
    /// group size. `size == 1` is the trivial isolated-cell instance.
    PuzzleData gsPuz(int size, {int cplx = 16}) =>
        PuzzleData('v2_12_5x5_${'0' * 25}_GS:0.${size}_0:0_$cplx');

    test('demotes trivial size-1 GS while GS is being introduced', () {
      // During the strict phase that introduces GS, a GS:.1 (isolated cell)
      // is a poor teaching instance and must be strongly deprioritised vs an
      // equivalent non-trivial GS:.3 of the same cplx. Both stay in the
      // catalog (last-resort drawable), but the non-trivial one should top
      // the sampled order far more often.
      final db = Database(playerLevel: 0)..samplingRandom = math.Random(42);
      // Reach phase P5 (introducing GS): every earlier phase's slug cleared,
      // GS still below the threshold.
      db.onboardingCompletions = strictCompletionsUpTo(4);
      expect(db.currentPhase?.introducing, 'GS');
      final trivial = gsPuz(1);
      final nonTrivial = gsPuz(3);
      db.puzzles = [trivial, nonTrivial];
      var nonTrivialFirst = 0;
      var trivialFirst = 0;
      for (var i = 0; i < 200; i++) {
        final first = db.getPuzzlesByLevel(16).first;
        if (identical(first, nonTrivial)) nonTrivialFirst++;
        if (identical(first, trivial)) trivialFirst++;
      }
      // With a ×0.05 penalty the trivial puzzle wins the head ~5 % of the
      // time; require the non-trivial to dominate by a wide margin.
      expect(nonTrivialFirst, greaterThan(trivialFirst * 3));
    });

    test('no GS demotion outside the GS introduction phase', () {
      // Gating check: when GS is not the rule being introduced (here phase
      // P0/FM, completions empty), trivial and non-trivial GS puzzles of the
      // same cplx carry the same weight and top the order at comparable
      // rates. Guards against the penalty leaking into normal play.
      final db = Database(playerLevel: 0)..samplingRandom = math.Random(42);
      expect(db.currentPhase?.introducing, isNot('GS'));
      final trivial = gsPuz(1);
      final nonTrivial = gsPuz(3);
      db.puzzles = [trivial, nonTrivial];
      var nonTrivialFirst = 0;
      var trivialFirst = 0;
      for (var i = 0; i < 200; i++) {
        final first = db.getPuzzlesByLevel(16).first;
        if (identical(first, nonTrivial)) nonTrivialFirst++;
        if (identical(first, trivial)) trivialFirst++;
      }
      // Neither side should dominate: a ~50/50 split, so each stays well
      // within 3× of the other (the bound the demotion test relies on).
      expect(nonTrivialFirst, lessThan(trivialFirst * 3));
      expect(trivialFirst, lessThan(nonTrivialFirst * 3));
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
    //
    // Each line must be a genuinely distinct puzzle: `loadStats` now
    // collapses the full play history to one entry per canonical key, so
    // lines that differ only by the trailing complexity field (which
    // `canonicalPuzzleKey` drops) would all fold into a single play. We
    // vary the grid height instead — a structural field that survives
    // canonicalization and can't alias another via rotation (rotation
    // preserves the {w, h} set).
    List<StatEntry> nFinishedStatLines(int n) => List.generate(n, (i) {
      final height = i + 4;
      final prefill = '0' * (4 * height);
      return StatEntry.parse(
        '2026-01-0${(i % 9) + 1}T12:00:00 30s 0f '
        'v2_12_4x${height}_${prefill}_FM:1_0:0_$i',
      )!;
    });

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
      // playerLevel 80 → mad, but the player is in '2-player' (index 1).
      // The ±1 gradual clamp caps the suggestion one tier up → '3-advanced'.
      final db = Database(playerLevel: 80);
      db.collection = '2-player';
      db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, '3-advanced');
    });

    test('counts plays globally — the loaded `puzzles` list is irrelevant', () {
      // Returning player: 0 puzzles loaded in memory (e.g., they just
      // switched to a fresh collection mid-session), but their stats
      // history holds enough finished plays from other collections.
      // The recommendation must surface immediately, not wait for
      // fresh plays in the current bucket.
      final db = Database(playerLevel: 80);
      db.collection = '2-player';
      db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      db.puzzles = []; // nothing loaded in memory
      db.loadStats(nFinishedStatLines(enough));
      // playerLevel 80 → mad, clamped to one tier above '2-player'.
      expect(db.recommendedCollectionKey, '3-advanced');
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
      db.onboardingCompletions = {
        ...OnboardingPhase.strictCompletionTargets,
        "GS": 4,
      };
      expect(db.recommendedCollectionKey, null);
      expect(db.currentPhase?.index, 4);
      // Synthesize a played puzzle that contains the last constraint that has not been fully onboarded yet.
      // We play it enough times so the recommendation thinks we played enough puzzles
      final puz = PuzzleData('v2_12_3x3_000020000_GS:0.1__');
      for (var i = 0; i < enough; i++) {
        db.notePuzzleCompleted(puz);
      }
      expect(db.currentPhase, null);
      // playerLevel 80 → mad, clamped to one tier above '2-player'.
      expect(db.recommendedCollectionKey, '3-advanced');
    });

    test('null while still in a strict onboarding phase', () {
      // A fast learner could otherwise see a level-up suggestion at the
      // end of their first batch even though they've barely met FM. The
      // recommendation is suppressed for the whole strict window (P0-P3)
      // regardless of how high `playerLevel` climbs.
      final db = Database(playerLevel: 80);
      db.collection = '1-easy';
      db.loadStats(nFinishedStatLines(enough));
      // When the onboarding is not done, even though player level says mad.
      db.onboardingCompletions = {
        ...strictCompletionsUpTo(5),
        "RC": 4,
        "GS": 2,
      };
      expect(db.recommendedCollectionKey, isNull);
      // Once across the strict boundary, recommendation resumes — but the
      // ±1 clamp caps it one tier above '1-easy' → '2-player'.
      db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      expect(db.recommendedCollectionKey, '2-player');
    });

    test('gradual clamp limits the suggestion to one tier up or down', () {
      // The recommendation never jumps more than one tier from the
      // currently played playlist, so a player climbs/descends gradually.
      // Up: a very fast player on '1-easy' (playerLevel 80 → mad) is only
      // nudged to '2-player', not straight to '6-mad'.
      final up = Database(playerLevel: 80);
      up.collection = '1-easy';
      up.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      up.loadStats(nFinishedStatLines(enough));
      expect(up.recommendedCollectionKey, '2-player');

      // Down: a slow player on '6-mad' (playerLevel 0 → beginner) is only
      // stepped down to '5-expert', not straight to '1-easy'.
      final down = Database(playerLevel: 0);
      down.collection = '6-mad';
      down.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      down.loadStats(nFinishedStatLines(enough));
      expect(down.recommendedCollectionKey, '5-expert');
    });

    test(
      'recommendedCollectionDirection is up when nudged one tier harder',
      () {
        // playerLevel 80 → mad, clamped one tier above '1-easy' → '2-player'.
        // The modal should congratulate the player for moving up.
        final db = Database(playerLevel: 80);
        db.collection = '1-easy';
        db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
        db.loadStats(nFinishedStatLines(enough));
        expect(db.recommendedCollectionKey, '2-player');
        expect(
          db.recommendedCollectionDirection,
          CollectionSuggestionDirection.up,
        );
      },
    );

    test(
      'recommendedCollectionDirection is down when stepped one tier easier',
      () {
        // playerLevel 0 → beginner, clamped one tier below '6-mad' →
        // '5-expert'. The modal should use the softer invitation.
        final db = Database(playerLevel: 0);
        db.collection = '6-mad';
        db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
        db.loadStats(nFinishedStatLines(enough));
        expect(db.recommendedCollectionKey, '5-expert');
        expect(
          db.recommendedCollectionDirection,
          CollectionSuggestionDirection.down,
        );
      },
    );

    test('recommendedCollectionDirection is null without a recommendation', () {
      // playerLevel 50 → strong ('4-strong') matches the active
      // collection: no suggestion, hence no direction.
      final db = Database(playerLevel: 50);
      db.collection = '4-strong';
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, isNull);
      expect(db.recommendedCollectionDirection, isNull);
    });

    test('recommendedCollectionDirection is null for tierless collections', () {
      // custom / user_* playlists sit outside the difficulty ladder — no
      // reference tier — so there is no direction even though a
      // suggestion exists (kept unclamped, straight to the natural
      // level). The widget falls back to the soft caption.
      final db = Database(playerLevel: 80);
      db.collection = 'custom';
      db.onboardingCompletions = OnboardingPhase.strictCompletionTargets;
      db.loadStats(nFinishedStatLines(enough));
      expect(db.recommendedCollectionKey, '6-mad');
      expect(db.recommendedCollectionDirection, isNull);
    });
  });
}
