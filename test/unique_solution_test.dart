// Regression tests pinning a known soundness bug in `isDeductivelyUnique`:
// some 3-color puzzles pass the deductive uniqueness check but a brute-force
// enumeration finds multiple valid completions. Reported by the user via
// `todo_next.md` (2026-05-13). The two failing puzzles share the pattern
// SH + SY + SH in domain {black, white, purple} — pointing at a `verify()`
// implementation that's too aggressive on the "still reachable" criterion
// when the third color expands the search space.
//
// These tests assert the EXPECTED contract (the puzzles are NOT uniquely
// solvable, brute force finds ≥ 2 completions, and `isDeductivelyUnique`
// MUST return false). They currently FAIL because of the bug — fixing the
// underlying verify() will make them pass.
//
// The brute-force enumerator is the same minimal one used by
// `bin/inspect_puzzle.dart`; we keep a copy here so the test stays
// self-contained.

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Count valid completions of [puzzle] by brute-forcing every free cell
/// across `puzzle.domain`. Stops as soon as [limit] is reached, so callers
/// can use `limit: 2` to cheaply detect non-uniqueness.
int countSolutions(Puzzle puzzle, {required int limit}) {
  final freeIdx = <int>[];
  for (int i = 0; i < puzzle.cells.length; i++) {
    if (puzzle.cells[i].value == CellValue.free) freeIdx.add(i);
  }
  int found = 0;
  void rec(int k) {
    if (found >= limit) return;
    if (k == freeIdx.length) {
      if (puzzle.check(saveResult: false).isEmpty) found++;
      return;
    }
    final idx = freeIdx[k];
    for (final v in puzzle.domain) {
      // ignoreOptions: setValue clears the cell's `options` on transition;
      // backtracking to free leaves it empty, so subsequent trials need the
      // bypass. Brute-force validates via constraints' verify(), not via
      // propagated options.
      puzzle.cells[idx].setValue(v, ignoreOptions: true);
      if (puzzle.check(saveResult: false).isEmpty) {
        rec(k + 1);
      }
      if (found >= limit) return;
    }
    puzzle.cells[idx].setValue(CellValue.free, ignoreOptions: true);
  }

  rec(0);
  return found;
}

void main() {
  group('isDeductivelyUnique soundness in domain 3', () {
    // Puzzle #2 from todo_next.md.
    const puzzle2 =
        'v2_123_4x5_20022000000000002000_'
        'SH:11.11;SY:13.3;SH:3_'
        '1:22222222211221122222_96';

    // Puzzle #3 from todo_next.md.
    const puzzle3 =
        'v2_123_4x4_0000000003000300_'
        'SH:2222.0200;SY:0.5;SH:1_'
        '1:3233222233333333_96';

    test('puzzle #2 (4x5 SH+SY+SH) is NOT uniquely solvable', () {
      final p = Puzzle(puzzle2);
      // Brute-force across {black, white, purple} finds at least 2 valid
      // completions — proof the puzzle has multiple solutions.
      expect(countSolutions(p.clone(), limit: 2), greaterThanOrEqualTo(2));
      // The validity gate MUST reject a non-unique puzzle. Currently fails:
      // the in-game solve() reaches the cached completion without exploring
      // the alternatives that brute force exposes.
      expect(p.isDeductivelyUnique(), isFalse);
    });

    test('puzzle #3 (4x4 SH+SY+SH) is NOT uniquely solvable', () {
      final p = Puzzle(puzzle3);
      expect(countSolutions(p.clone(), limit: 2), greaterThanOrEqualTo(2));
      expect(p.isDeductivelyUnique(), isFalse);
    });
  });
}
