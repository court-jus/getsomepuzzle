import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';

void main() {
  group('Database.load resilience', () {
    test('skips malformed lines but keeps the valid puzzles around them', () {
      // A truncated `custom.txt` row — here the orphan tail fragments
      // `:classic` (0 underscores) and `3_scenario:classic` (one underscore)
      // left behind by a partial write — used to throw in the PuzzleData
      // constructor (`attributesStr[2]` RangeError) and brick startup. load()
      // must skip them and still parse the surrounding valid puzzles.
      final db = Database(playerLevel: 1);
      final cells = '0' * 25;
      final valid = 'v2_12_5x5_${cells}_FM:1_0:0_3';
      db.load([valid, ':classic', '3_scenario:classic', valid]);
      expect(db.puzzles.length, 2);
    });
  });
}
