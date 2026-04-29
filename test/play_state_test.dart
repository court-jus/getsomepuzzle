import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  // 3x3 puzzle, cell 0 prefilled with value 1 (readonly), constraint FM:11.
  // No solution stored, complexity 0. Format: 7 underscore-separated fields.
  const baseLine = 'v2_12_3x3_100000000_FM:11_0:0_0';

  group('Puzzle play-state field', () {
    test('legacy 7-field line parses without restored-progress flag', () {
      // Backward compatibility: puzzles saved before this feature carry no
      // 8th field, and `hasRestoredProgress` must stay false.
      final p = Puzzle(baseLine);
      expect(p.hasRestoredProgress, isFalse);
      expect(p.cellValues, [1, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('p:<values> trailing field restores non-readonly cells', () {
      // Cell 0 stays as the readonly initial value (1). The play-state
      // tries to set cells 1, 4, 8 to value 2 — all non-readonly, so they
      // take effect. Cell 0's saved play-state digit is ignored because
      // the cell is readonly.
      final p = Puzzle('${baseLine}_p:120020002');
      expect(p.hasRestoredProgress, isTrue);
      expect(p.cellValues, [1, 2, 0, 0, 2, 0, 0, 0, 2]);
    });

    test('readonly cells are not overwritten by play-state', () {
      // Even if the saved play-state contradicts the readonly value, the
      // readonly cell wins. Cell 0 stays at 1 even though the play-state
      // requests 2.
      final p = Puzzle('${baseLine}_p:200000000');
      expect(p.cellValues[0], 1);
      // Length-mismatch check is independent: this state matches the grid
      // length so the field IS applied (just with cell 0 ignored).
      expect(p.hasRestoredProgress, isTrue);
    });

    test('play-state with wrong length is silently ignored', () {
      // Defensive: an 8-field line whose play-state length doesn't match
      // the grid is treated as if no field were present, so a malformed
      // save can't corrupt the puzzle on reload.
      final p = Puzzle('${baseLine}_p:12');
      expect(p.hasRestoredProgress, isFalse);
      expect(p.cellValues, [1, 0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('lineWithPlayState round-trips current cell values', () {
      // The export must (a) preserve every original field verbatim and
      // (b) append/replace the trailing `p:<values>` segment with the
      // puzzle's *current* cellValues — including the readonly cell, so
      // length stays consistent with the grid.
      final p = Puzzle(baseLine);
      p.setValue(1, 2);
      p.setValue(4, 2);
      final out = p.lineWithPlayState();
      expect(out, '${baseLine}_p:120020000');
    });

    test('lineWithPlayState replaces an existing play-state suffix', () {
      // Saving twice in a row must not stack two `p:` fields. Re-saving
      // after a new move replaces the previous suffix in place.
      final p = Puzzle('${baseLine}_p:120000000');
      p.setValue(4, 2);
      final out = p.lineWithPlayState();
      // Single `p:` field, latest values.
      expect(out.split('_').where((s) => s.startsWith('p:')).length, 1);
      expect(out.endsWith('_p:120020000'), isTrue);
    });

    test('save → reload round-trip yields the same cell values', () {
      // End-to-end check: play, save, reparse, and verify the player sees
      // the same puzzle state. This is the user-facing guarantee the
      // feature exists for.
      final original = Puzzle(baseLine);
      original.setValue(1, 2);
      original.setValue(4, 1);
      original.setValue(7, 2);
      final savedLine = original.lineWithPlayState();

      final reloaded = Puzzle(savedLine);
      expect(reloaded.cellValues, original.cellValues);
      expect(reloaded.hasRestoredProgress, isTrue);
    });
  });
}
