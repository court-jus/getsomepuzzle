import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Minimal-but-valid `PuzzleData` line: `v2_12_WxH_0..0_FM:12_0:0_CPLX`.
/// We keep the constraint section trivial (`FM:12`) because none of the
/// adapt-to-player code cares about semantic validity — only width, height,
/// and the trailing `cplx` value.
PuzzleData _puz({required int cplx, int width = 5, int height = 5}) {
  final cellsStr = '0' * (width * height);
  return PuzzleData('v2_12_${width}x${height}_${cellsStr}_FM:12_0:0_$cplx');
}

/// Mirror of the private `Database._expectedDuration`. Tests use it to craft
/// durations that satisfy the model's equilibrium so we can check the
/// invariant `level ≈ cplx`.
double _expectedFor(int cplx, int cells, int failures) =>
    0.92 *
    cells *
    math.exp(cplx.clamp(0, 80) / 75.0) *
    math.pow(1.65, failures);

void main() {
  group('Database.computePlayerLevel', () {
    test('falls back to the stored level when fewer than 10 usable plays', () {
      // Threshold preserves any manually set level while the history is thin.
      final db = Database(playerLevel: 0);
      db.puzzles = List.generate(9, (i) {
        return _puz(cplx: 30)
          ..played = true
          ..duration = 40
          ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i));
      });
      expect(db.computePlayerLevel(fallback: 42), 42);
    });

    test('yields ≈ cplx when every duration matches the expected model', () {
      // Invariant: if each play's duration equals _expectedDuration for its
      // puzzle, the inferred per-play level equals that puzzle's cplx.
      // Averaging 12 plays at cplx=40 must therefore give ~40.
      final db = Database(playerLevel: 0);
      const cplx = 40;
      final dur = _expectedFor(cplx, 25, 0).round();
      db.puzzles = List.generate(12, (i) {
        return _puz(cplx: cplx)
          ..played = true
          ..duration = dur
          ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i));
      });
      expect(db.computePlayerLevel(fallback: 0), closeTo(cplx, 2));
    });

    test('skipped puzzles are excluded from the sample', () {
      // 5 finished plays + 10 skipped ones: only 5 are usable, so we should
      // fall back rather than emit a level based on a tiny sample.
      final db = Database(playerLevel: 0);
      const cplx = 40;
      final dur = _expectedFor(cplx, 25, 0).round();
      db.puzzles = [
        for (int i = 0; i < 5; i++)
          (_puz(cplx: cplx)
            ..played = true
            ..duration = dur
            ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i))),
        for (int i = 0; i < 10; i++)
          (_puz(cplx: cplx)
            ..played = true
            ..duration = dur
            ..finished = DateTime(2026, 1, 1).add(Duration(minutes: i + 10))
            ..skipped = DateTime(2026, 1, 1)),
      ];
      expect(db.computePlayerLevel(fallback: 77), 77);
    });
  });

  group('Database.getPuzzlesByLevel', () {
    test(
      'returns only puzzles in the asymmetric [level-1, level+2] window',
      () {
        // The window is intentionally biased upward: one easier tier, two
        // harder tiers. For level 16 that means cplx in {15, 16, 17, 18}.
        final db = Database(playerLevel: 0);
        db.puzzles = [
          for (final c in [13, 14, 15, 16, 17, 18, 19, 20]) _puz(cplx: c),
        ];
        final got = db.getPuzzlesByLevel(16).map((p) => p.cplx).toSet();
        expect(got, {15, 16, 17, 18});
      },
    );

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

  group('Database.hasUnplayedAtLevelIgnoringFilters', () {
    test('ignores user-configured size filters', () {
      // EndOfPlaylist uses this to distinguish "filters are hiding puzzles"
      // from "everything at this level has been played". A strict maxWidth
      // must not make the 8x8 puzzle vanish from this probe.
      final db = Database(playerLevel: 0);
      db.puzzles = [_puz(cplx: 20, width: 8, height: 8)];
      db.currentFilters.maxWidth = 5;
      expect(db.getPuzzlesByLevel(20), isEmpty);
      expect(db.hasUnplayedAtLevelIgnoringFilters(20), isTrue);
    });

    test('returns false when every candidate has been played or skipped', () {
      final db = Database(playerLevel: 0);
      db.puzzles = [
        _puz(cplx: 20)
          ..played = true
          ..finished = DateTime(2026, 1, 1),
        _puz(cplx: 21)..skipped = DateTime(2026, 1, 1),
      ];
      expect(db.hasUnplayedAtLevelIgnoringFilters(20), isFalse);
    });
  });

  group('Database.nextPopulatedLevel', () {
    test('returns the smallest higher level that would produce candidates', () {
      // A puzzle at cplx=30 is usable at any level whose window [l-1, l+2]
      // contains 30, i.e. levels in [28, 31]. Starting from 16, the smallest
      // such level strictly above 16 is 28.
      final db = Database(playerLevel: 0);
      db.puzzles = [_puz(cplx: 30)];
      expect(db.nextPopulatedLevel(16), 28);
    });

    test('returns null when no higher level is covered by the catalog', () {
      final db = Database(playerLevel: 0);
      db.puzzles = [_puz(cplx: 20)]; // covers levels [18, 21] only
      expect(db.nextPopulatedLevel(50), isNull);
    });
  });
}
