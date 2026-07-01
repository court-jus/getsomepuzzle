// Regression tests pinning a known soundness bug in `isDeductivelyUnique`:
// some 3-color puzzles pass the deductive uniqueness check but a brute-force
// enumeration finds multiple valid completions. Reported by the user via
// `todo_next.md` (2026-05-13). The two failing puzzles share the pattern
// SH + SY + SH in domain {black, white, purple} — pointing at a `verify()`
// implementation that's too aggressive on the "still reachable" criterion
// when the third color expands the search space.
//
// These tests pin the contract that those puzzles are NOT uniquely solvable:
// brute force finds ≥ 2 completions and `isDeductivelyUnique` returns false.
// The underlying `verify()` bug has since been fixed, so the suite is green —
// these tests now guard against a regression of that fix.
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
    // Restore via reset() (not setValue(free)) so the cell regains its full
    // options on backtrack — option-aware verify()s treat a free cell with an
    // emptied option set as impossible and would over-prune the search.
    puzzle.cells[idx].reset();
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

  group('GSQAComplicity does not over-count out-of-group cells', () {
    // Regression: two 2-colour puzzles `--check` accepted on master but
    // rejected after the third-colour merge. `GSQAComplicity` over-counted
    // already-placed same-colour cells as "outside" the GS anchor's group
    // — even cells still reachable through free intermediates — and forced
    // a wrong colour, so `solve()` reached a contradictory completion (or
    // stalled) and `isDeductivelyUnique()` flipped to false. On master the
    // bug stayed latent because stronger 2-colour SY deductions coloured
    // the connecting cells early; the weaker 3-colour SY port exposed it.
    // The fix only counts a placed cell as out-of-group when its distance
    // over {colour ∪ free} is ≥ the group size.
    const reportedPuzzles = [
      'v2_12_6x6_200100000000000100020001000000100000_'
          'GS:0.2;GS:2.1;GS:22.4;GS:31.14;PA:15.right;PA:20.left;QA:1.19;'
          'PA:22.left;PA:7.bottom;PA:7.right;FM:11.22;SY:23.3;SY:26.3;'
          'PA:24.top;SY:35.4_1:212122211122112112122121121222112111_42',
      'v2_12_5x6_000000000000010020000000000200_'
          'GS:0.4;GS:14.1;GS:8.2;PA:12.horizontal;QA:1.18;GS:19.11;GS:28.11;'
          'PA:29.left;PA:5.right;PA:6.bottom;SY:21.4;SY:27.4;SY:8.2;'
          'PA:7.right_1:211212212121112122111112112211_42',
    ];

    for (var i = 0; i < reportedPuzzles.length; i++) {
      test('reported puzzle #$i stays deductively unique', () {
        expect(Puzzle(reportedPuzzles[i]).isDeductivelyUnique(), isTrue);
      });
    }
  });

  group('SY/LT 3-colour deductions are not over-weakened', () {
    // Regression: valid, *uniquely* solvable puzzles that `--check` wrongly
    // rejected after the third-colour port deliberately weakened deductions.
    // Each has exactly one solution (brute-force confirmed), so a false
    // rejection — not an ambiguity — is the bug.
    //
    //  * The 2-colour SY case lost the empty-anchor "mirror = nv" force when
    //    the anchor never gets fixed by another rule (gated back on domain 2).
    //  * The 3-colour LT cases forced a rival cell to one specific opposite
    //    colour instead of pruning the shared colour (now `removeOption`).
    const recoveredPuzzles = [
      // 2-colour, SY-heavy (from master's 5-expert corpus).
      'v2_12_5x6_022020000200000010100000020000_'
          'CC:2.2.4;EY:24.1.1;GS:16.1;LT:D.2.21;MJ:2.2.3.3.1;NC:9.1.0;QA:1.7;'
          'RC:4.2.4;CT:0.0;CT:3.2;RT:3.3;SY:22.1;GC:2.2;PA:8.bottom_'
          '1:222222122222112212112212222222_26_scenario:classic',
      // 3-colour, LT-only.
      'v2_123_4x4_0331021210300000_'
          'LT:A.8.12.13.4.15.14.9;LT:C.10.11;LT:B.2.0_1:3331121211331111_5',
      'v2_123_4x4_0000030011003102_'
          'LT:A.10.13.11.14.9.3.2.6.7;LT:B.5.4.1.0_1:3311331111113112_6',
      'v2_123_4x5_20320023000200301200_'
          'LT:D.10.6.1.5.19.15.9.18;LT:B.13.14.4.8_1:22323223322233321222_10',
    ];

    for (var i = 0; i < recoveredPuzzles.length; i++) {
      test('recovered puzzle #$i is deductively unique', () {
        final p = Puzzle(recoveredPuzzles[i]);
        // Genuinely unique (not masked ambiguity).
        expect(countSolutions(p.clone(), limit: 2), 1);
        expect(p.isDeductivelyUnique(), isTrue);
      });
    }
  });
}
