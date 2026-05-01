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
    test('caps at 20 on built-in level collections', () {
      // 50 puzzles loaded into '2-player'. The post-Gaussian playlist
      // should be sliced to 20 — `EndOfPlaylist` will then fire after
      // the player has consumed those 20, surfacing the level
      // rotation suggestion. Without the cap, the player could go
      // months on this collection and never see the prompt.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      db.puzzles = List.generate(50, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.playlist.length, 20);
    });

    test('does not cap on `custom` (player-curated)', () {
      // Custom puzzles are explicitly the ones the player has
      // generated for themselves. Capping them would feel arbitrary —
      // the player chose to make exactly those puzzles.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = List.generate(50, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.playlist.length, 50);
    });

    test('does not cap on `tutorial` (pedagogical order)', () {
      // Tutorial uses a fixed pedagogical order that must be played
      // through in full. Cap would break the teaching sequence.
      final db = Database(playerLevel: 50);
      db.collection = 'tutorial';
      db.puzzles = List.generate(30, (i) => _puz(cplx: 5));
      db.preparePlaylist();
      expect(db.playlist.length, 30);
    });

    test('shuffle mode is also capped on level collections', () {
      // The cap is about end-of-batch UX, not about ordering. Even
      // when the user explicitly shuffles, we still want the
      // EndOfPlaylist hook to fire after 20.
      final db = Database(playerLevel: 50);
      db.collection = '3-advanced';
      db.shouldShuffle = true;
      db.puzzles = List.generate(50, (i) => _puz(cplx: 30));
      db.preparePlaylist();
      expect(db.playlist.length, 20);
    });
  });

  group('Database.hasMoreCandidatesInCurrentCollection', () {
    test('true when filtered catalog exceeds the active batch', () {
      // 30 unplayed puzzles, batch shows 20 → 10 left for next batch.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      db.puzzles = List.generate(30, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isTrue);
    });

    test('false when the entire filtered catalog is in the batch', () {
      // 15 unplayed puzzles, batch holds them all → nothing left for
      // a "Continue" affordance to surface.
      final db = Database(playerLevel: 50);
      db.collection = '2-player';
      db.puzzles = List.generate(15, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isFalse);
    });

    test('false on non-playable collections (custom)', () {
      // Custom doesn't use the batch concept; hasMore is meaningless
      // there and we want to suppress the "Continue" affordance to
      // avoid confusing UX.
      final db = Database(playerLevel: 50);
      db.collection = 'custom';
      db.puzzles = List.generate(50, (i) => _puz(cplx: 20));
      db.preparePlaylist();
      expect(db.hasMoreCandidatesInCurrentCollection(), isFalse);
    });
  });
}
