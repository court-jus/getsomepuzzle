import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

// Cycle-state probes used in the loop assertions below: each tuple is
// (set-of-still-available-options, expected-value). The cell starts free
// with the full 3-colour option set, then a tap is supposed to drop one
// option at a time in domain order, and finally to wrap back to the
// full set. The expected-value column is null while the cell stays
// free (≥2 options remaining); the cycle never collapses to a setValue
// on a 3-colour domain because every step keeps at least 2 options.
void _expectState(Puzzle p, int idx, Set<CellValue> options, CellValue? value) {
  expect(p.cells[idx].options.toSet(), options, reason: 'options at $idx');
  expect(p.cellValues[idx], value ?? CellValue.free, reason: 'value at $idx');
}

void main() {
  // 3-colour puzzle line reused from auto_shrink_domain_test.dart. Cell 0
  // is pre-coloured black; the other 8 cells are free and have the full
  // [black, white, purple] option set. The constraint payload doesn't
  // matter — we never solve, just exercise the tap-cycle on cell 4.
  Puzzle make() => Puzzle('v2_123_3x3_100000000_LT:A.0.4_0:0_0');

  test(
    'cycleRemoveOption walks domain in order then wraps back to full set',
    () {
      final p = make();
      const target = 4;
      // Sanity: free cell starts with all three options.
      _expectState(p, target, {
        CellValue.black,
        CellValue.white,
        CellValue.purple,
      }, null);

      // Step 1: drop black.
      p.cycleRemoveOption(target);
      _expectState(p, target, {CellValue.white, CellValue.purple}, null);

      // Step 2: restore black, drop white.
      p.cycleRemoveOption(target);
      _expectState(p, target, {CellValue.black, CellValue.purple}, null);

      // Step 3: restore white, drop purple.
      p.cycleRemoveOption(target);
      _expectState(p, target, {CellValue.black, CellValue.white}, null);

      // Step 4: last domain colour was dropped → wrap back to full set.
      p.cycleRemoveOption(target);
      _expectState(p, target, {
        CellValue.black,
        CellValue.white,
        CellValue.purple,
      }, null);
    },
  );

  test('cycleRemoveOption on a coloured cell falls back to incrValue', () {
    final p = make();
    const target = 4;
    // Bring the cell to black first via setValue (mirrors what the player
    // would see after a prior incrValue tap).
    p.setValue(target, CellValue.black);
    expect(p.cellValues[target], CellValue.black);

    // In removeOption mode on a coloured cell, behaviour must match
    // incrValue: black → white.
    p.cycleRemoveOption(target);
    expect(p.cellValues[target], CellValue.white);

    // white → purple.
    p.cycleRemoveOption(target);
    expect(p.cellValues[target], CellValue.purple);

    // purple (last) → free, options restored to the full domain (this is
    // the same wrap that `incrValue` does through `resetCell`).
    p.cycleRemoveOption(target);
    _expectState(p, target, {
      CellValue.black,
      CellValue.white,
      CellValue.purple,
    }, null);
  });

  test('cycleRemoveOption on a readonly cell is a no-op', () {
    // Cell 0 is pre-coloured (`1` at offset 0 in the cell string) and
    // therefore readonly. Tapping it in removeOption mode must not
    // mutate the cell (no incrValue fallback either — the regular tap
    // handler in GameModel.handleTap already bails on readonly).
    final p = make();
    expect(p.cells[0].readonly, true);
    final before = p.cellValues[0];
    p.cycleRemoveOption(0);
    expect(p.cellValues[0], before);
  });

  test('cycleRemoveOption recovers from a non-canonical option set', () {
    // If the player previously pruned options out of order (e.g. via
    // right-click) the cell may end up with two options missing.
    // The cycle treats that as "start fresh": resets, then drops the
    // first domain colour, so the next steps walk the cycle from a
    // known state.
    final p = make();
    const target = 4;
    // Force a non-canonical state: only purple left as an option (but
    // not collapsed to a setValue because we set both fields by hand).
    p.cells[target].options = [CellValue.purple];
    p.cells[target].value = CellValue.free;

    p.cycleRemoveOption(target);
    // After reset + removeOption(black): [white, purple].
    _expectState(p, target, {CellValue.white, CellValue.purple}, null);
  });
}
