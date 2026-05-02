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
}) {
  final cellsStr = '0' * (width * height);
  final cons = List.filled(nCons, 'FM').map((s) => '$s:1').join(';');
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

    test('does not cap on `tutorial` (pedagogical order)', () {
      // Tutorial uses a fixed pedagogical order that must be played
      // through in full. Cap would break the teaching sequence.
      final db = Database(playerLevel: 50);
      db.collection = 'tutorial';
      final size = Database.playlistBatchSize + 10;
      db.puzzles = List.generate(size, (i) => _puz(cplx: 5));
      db.preparePlaylist();
      expect(db.playlist.length, size);
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
