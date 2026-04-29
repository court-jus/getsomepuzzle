import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Minimal-but-valid `PuzzleData` line. The constraint section repeats
/// `FM:12` `nCons` times so `PuzzleData.rules.length == nCons`, which the
/// duration model now consumes. None of the adapt-to-player logic cares
/// about semantic validity — only width, height, the trailing `cplx`, and
/// the parsed `rules` count.
PuzzleData _puz({
  required int cplx,
  int width = 5,
  int height = 5,
  int nCons = 1,
}) {
  final cellsStr = '0' * (width * height);
  final cons = List.filled(nCons, 'FM:12').join(';');
  return PuzzleData('v2_12_${width}x${height}_${cellsStr}_${cons}_0:0_$cplx');
}

/// Mirror of the private `Database._expectedDuration`. Tests use it to craft
/// durations that satisfy the model's equilibrium so we can check the
/// invariant `level ≈ cplx`. Must stay in sync with the constants in
/// `database.dart` (anchored model: log(dur) = 2.155 + 0.0366·cplx
/// + 0.442·log(cells) + 0.136·failures + 0.082·n_cons).
double _expectedFor(int cplx, int cells, int failures, int nCons) =>
    8.62 *
    math.pow(cells, 0.442) *
    math.exp(cplx / 27.3) *
    math.pow(1.145, failures) *
    math.pow(1.085, nCons);

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
}
