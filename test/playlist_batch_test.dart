import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

/// Minimal-but-valid `PuzzleData` line. Mirrors the helper in
/// `adapt_to_player_test.dart` but inlined here since it's the only
/// thing that file shares.
PuzzleData _puz({
  required int cplx,
  int width = 5,
  int height = 5,
  int nCons = 1,
  String constraintSlug = 'FM',
}) {
  final cellsStr = '0' * (width * height);
  final cons = List.filled(nCons, constraintSlug).map((s) => '$s:1').join(';');
  return PuzzleData('v2_12_${width}x${height}_${cellsStr}_${cons}_0:0_$cplx');
}

void main() {
  group('Database.preparePlaylist — batch cap', () {
    test('caps at playlistBatchSize on built-in level collections', () {
      // The post-Gaussian playlist is sliced to `playlistBatchSize` so
      // `EndOfPlaylist` fires every batch — surfacing the level
      // rotation suggestion. Without the cap, a collection with ~1k
      // puzzles would never exhaust and the prompt would never appear.
      // The exact constant value is a UX knob; the test asserts the
      // cap is applied, not the magic number.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      db.puzzles = List.generate(
        Database.playlistBatchSize + 30,
        (i) => _puz(cplx: 20),
      );
      db.preparePlaylist();
      expect(db.playlist.length, Database.playlistBatchSize);
    });

    test('does not cap on `custom` (player-curated)', () {
      // Custom puzzles are explicitly the ones the player has
      // generated for themselves. Capping them would feel arbitrary —
      // the player chose to make exactly those puzzles.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = List.generate(
        Database.playlistBatchSize + 30,
        (i) => _puz(cplx: 20),
      );
      db.preparePlaylist();
      expect(db.playlist.length, Database.playlistBatchSize + 30);
    });

    test('shuffle mode is also capped on level collections', () {
      // The cap is about end-of-batch UX, not about ordering. Even
      // when the user explicitly shuffles, we still want the
      // EndOfPlaylist hook to fire at the batch boundary.
      final db = Database(playerLevel: 50);
      db.collection = '3-advanced';
      db.shouldShuffle = true;
      db.puzzles = List.generate(
        Database.playlistBatchSize + 30,
        (i) => _puz(cplx: 30),
      );
      db.preparePlaylist();
      expect(db.playlist.length, Database.playlistBatchSize);
    });
  });

  group('Database.preparePlaylist — custom/user_ filters & shuffle', () {
    test('bannedRules filters out matching puzzles on custom', () {
      // Regression: previously the custom branch bypassed the filter
      // pipeline, so a player who banned `FM` would still be served
      // FM puzzles. The fix routes custom/user_* through `filter()`
      // exactly like the level branches.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = [
        _puz(cplx: 20, constraintSlug: 'FM'),
        _puz(cplx: 20, constraintSlug: 'PA'),
        _puz(cplx: 20, constraintSlug: 'GS'),
      ];
      db.currentFilters.bannedRules = {'FM'};
      db.preparePlaylist();
      expect(db.playlist.map((p) => p.rules.first), ['PA', 'GS']);
    });

    test('bannedRules filters apply on user_* playlists too', () {
      // Same contract for named user playlists — they share the
      // custom branch in `preparePlaylist`.
      final db = Database(playerLevel: 50);
      db.collection = 'user_my_list';
      db.puzzles = [
        _puz(cplx: 20, constraintSlug: 'FM'),
        _puz(cplx: 20, constraintSlug: 'PA'),
      ];
      db.currentFilters.bannedRules = {'PA'};
      db.preparePlaylist();
      expect(db.playlist.map((p) => p.rules.first), ['FM']);
    });

    test('shuffle reorders the playlist on custom', () {
      // The shuffle toggle now affects custom/user_*. We can't assert
      // a specific order (it's random), but with a large enough list
      // the chance of `shuffle()` returning the input order is
      // vanishingly small — assert "ordering differs" instead.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      // 50 puzzles is plenty to make accidental fixed-point shuffles
      // statistically negligible (1/50! ≈ 0).
      db.puzzles = List.generate(50, (i) => _puz(cplx: i));
      final originalCplx = db.puzzles.map((p) => p.cplx).toList();
      db.shouldShuffle = true;
      db.preparePlaylist();
      final shuffledCplx = db.playlist.map((p) => p.cplx).toList();
      expect(shuffledCplx, hasLength(50));
      expect(shuffledCplx, isNot(equals(originalCplx)));
    });

    test('shuffle off keeps insertion order on custom', () {
      // Preserves the long-standing contract: when shuffle is off the
      // player gets the puzzles in the exact order they appear in
      // the on-disk file.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = List.generate(10, (i) => _puz(cplx: i));
      db.shouldShuffle = false;
      db.preparePlaylist();
      expect(db.playlist.map((p) => p.cplx).toList(), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
    });
  });

  group('Database.hasMoreCandidatesInCurrentCollection', () {
    test('true when filtered catalog exceeds the active batch', () {
      // batchSize+10 unplayed → batch holds batchSize, 10 left over.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      db.puzzles = List.generate(
        Database.playlistBatchSize + 10,
        (i) => _puz(cplx: 20),
      );
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isTrue);
    });

    test('false when the entire filtered catalog is in the batch', () {
      // batchSize-1 unplayed → all fit in the batch, no leftover.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      final n = Database.playlistBatchSize > 1
          ? Database.playlistBatchSize - 1
          : 1;
      db.puzzles = List.generate(n, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isFalse);
    });

    test('false on non-playable collections (custom)', () {
      // Custom doesn't use the batch concept; hasMore is meaningless
      // there and we want to suppress the "Continue" affordance to
      // avoid confusing UX.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = List.generate(
        Database.playlistBatchSize + 30,
        (i) => _puz(cplx: 20),
      );
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isFalse);
    });
  });
}
