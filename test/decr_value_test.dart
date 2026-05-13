import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

// `decrValue` mirrors `incrValue` but walks the domain backward. The two
// shipping consumers — right-click (desktop) and long-press (mobile) —
// both go through this method, so the cycle's correctness is what unlocks
// reaching the last domain colour in a single gesture on a 3-colour
// puzzle.

void main() {
  // 3-colour fixture (reused from auto_shrink_domain_test.dart /
  // cycle_remove_option_test.dart). Cell 0 is pre-coloured black
  // (readonly), the other 8 cells are free with the full
  // [black, white, purple] option set.
  Puzzle make3() => Puzzle('v2_123_3x3_100000000_LT:A.0.4_0:0_0');

  // 2-colour fixture: cell 0 black readonly, cells 1..8 free with
  // [black, white] options.
  Puzzle make2() => Puzzle('v2_12_3x3_100000000_LT:A.0.2;LT:B.1.4');

  group('decrValue on 3 colours', () {
    test('free cell jumps straight to the last domain colour (purple)', () {
      // The whole point of `decrValue`: a tap-backward goes from free
      // to the *last* colour in one step, instead of three steps via
      // `incrValue`. Without this, purple is unreachable in one tap
      // on a 3-colour puzzle.
      final p = make3();
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.purple);
    });

    test('cycle walks purple → white → black → free → purple', () {
      // Full backward loop. The free → purple wrap restores the full
      // option set (same `resetCell` dance `incrValue` does), so the
      // next `decrValue` sees a canonical free cell.
      final p = make3();
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.purple);
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.white);
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.black);
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.free);
      expect(
        p.cells[4].options.toSet(),
        {CellValue.black, CellValue.white, CellValue.purple},
        reason: 'wrap to free must restore the full option set',
      );
      // One more step proves the cycle is truly cyclic (not a one-shot).
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.purple);
    });

    test('incrValue then decrValue returns to the starting state', () {
      // Symmetry property: the two methods are exact mirrors. Holds
      // for every starting value in the cycle (free, black, white,
      // purple). Tested by walking through each.
      for (final start in [
        CellValue.free,
        CellValue.black,
        CellValue.white,
        CellValue.purple,
      ]) {
        final p = make3();
        if (start != CellValue.free) p.setValue(4, start);
        p.incrValue(4);
        p.decrValue(4);
        expect(
          p.cellValues[4],
          start,
          reason: 'starting from $start: incr then decr should be identity',
        );
      }
    });

    test('readonly cell is a no-op', () {
      // Cell 0 is the pre-coloured (`1` at offset 0) readonly black
      // cell. Tapping right-click / long-press on it must not mutate
      // anything — symmetric with `incrValue`, which the upstream
      // `handleTap` already guards on readonly.
      final p = make3();
      expect(p.cells[0].readonly, true);
      final before = p.cellValues[0];
      p.decrValue(0);
      expect(p.cellValues[0], before);
    });
  });

  group('decrValue on 2 colours', () {
    test('cycle walks white → black → free → white', () {
      // 2-colour puzzles still see the backward cycle (uniformity
      // between domains). The trade-off is that erasing a white cell
      // takes two right-clicks (`white → black → free`) instead of the
      // old one-step toggle; the test pins this regression so it
      // doesn't drift accidentally.
      final p = make2();
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.white);
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.black);
      p.decrValue(4);
      expect(p.cellValues[4], CellValue.free);
      expect(p.cells[4].options.toSet(), {CellValue.black, CellValue.white});
    });
  });
}
