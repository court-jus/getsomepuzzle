import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

import 'helpers/make_puzzle.dart';

void main() {
  group('ForbiddenMotif.verify', () {
    test('2x1 motif absent → valid', () {
      // FM:12 (NB horizontal) absent from all-black grid
      final p = makePuzzle('111\n111');
      expect(ForbiddenMotif('12').verify(p), isTrue);
    });

    test('2x1 motif present → invalid', () {
      // FM:12 present at (0,0)-(1,0): N then B
      final p = makePuzzle('12\n11');
      expect(ForbiddenMotif('12').verify(p), isFalse);
    });

    test('2x2 motif absent → valid', () {
      // FM:12.21 absent: grid has no 2x2 block matching NB/BN
      final p = makePuzzle('11\n11');
      expect(ForbiddenMotif('12.21').verify(p), isTrue);
    });

    test('2x2 motif present → invalid', () {
      // FM:12.21 present at (0,0): NB/BN
      final p = makePuzzle('12\n21');
      expect(ForbiddenMotif('12.21').verify(p), isFalse);
    });

    test('motif with wildcards (0) matches any value', () {
      // FM:10 means N followed by anything → forbids N in any non-last column
      // Grid NN: matches at pos 0 (N then N, wildcard=0 matches N)
      final p = makePuzzle('11');
      expect(ForbiddenMotif('10').verify(p), isFalse);
    });

    test('1x3 motif', () {
      // FM:121 = NBN horizontal
      final p = makePuzzle('121\n222');
      expect(ForbiddenMotif('121').verify(p), isFalse);
      final p2 = makePuzzle('112\n222');
      expect(ForbiddenMotif('121').verify(p2), isTrue);
    });
  });

  group('GroupSize.verify', () {
    test('correct group size → valid', () {
      // 121/121/222: groups of 1 at {0,3} and {2,5} (size 2 each),
      // group of 2 at {1,4,6,7,8} (size 5)
      final p = makePuzzle('121\n121\n222');
      expect(GroupSize('0.2').verify(p), isTrue);
      expect(GroupSize('1.5').verify(p), isTrue);
      expect(GroupSize('2.2').verify(p), isTrue);
    });

    test('wrong group size → invalid', () {
      final p = makePuzzle('121\n121\n222');
      expect(GroupSize('0.1').verify(p), isFalse);
      expect(GroupSize('1.2').verify(p), isFalse);
      expect(GroupSize('0.3').verify(p), isFalse);
    });
  });

  group('ParityConstraint.verify', () {
    test('right: equal count → valid', () {
      // 1221: idx 1 right=[2,1] → 1 odd, 1 even → valid
      final p = makePuzzle('1221');
      expect(ParityConstraint('1.right').verify(p), isTrue);
    });

    test('left: unequal count → invalid', () {
      // 22212: idx 2, left side [2,2] → 0 odd, 2 even → invalid
      final p = makePuzzle('22212');
      expect(ParityConstraint('2.left').verify(p), isFalse);
    });

    test('top/bottom on column', () {
      // 3x3: 111/222/111 → idx 8 (row 2, col 2), top has [1,2] → valid
      final p = makePuzzle('111\n222\n111');
      expect(ParityConstraint('8.top').verify(p), isTrue);
      // 3x3: 111/222/111 → idx 0 (row 0, col 0), bottom has [2,1] → valid
      expect(ParityConstraint('0.bottom').verify(p), isTrue);
    });

    test('vertical: both sides must be balanced', () {
      // Column 1x5: 1,2,1,2,1 → idx 2, top=[1,2] bottom=[2,1] → both balanced → valid
      final p = makePuzzle('1\n2\n1\n2\n1');
      expect(ParityConstraint('2.vertical').verify(p), isTrue);
      // 1,1,X,2,1: top=[1,1] → 2 odd, 0 even → invalid
      final p2 = makePuzzle('1\n1\n1\n2\n1');
      expect(ParityConstraint('2.vertical').verify(p2), isFalse);
    });

    test('incomplete side, too many evens → invalid (unreachable)', () {
      // 5x1 row, idx 0 right side = [2, 0, 2, 2]: even=3 > half=2 → target
      // `even == odd == 2` can no longer be reached whatever fills the 0.
      final p = makePuzzle('22022');
      expect(ParityConstraint('0.right').verify(p), isFalse);
    });

    test('incomplete side, too many odds → invalid (unreachable)', () {
      final p = makePuzzle('11011');
      expect(ParityConstraint('0.right').verify(p), isFalse);
    });

    test('incomplete side, target still reachable → valid', () {
      // 5x1 row, idx 0 right side = [2, 0, 1, 2]: even=2, odd=1, half=2.
      // Filling the 0 with 1 reaches the balanced target.
      final p = makePuzzle('12012');
      expect(ParityConstraint('0.right').verify(p), isTrue);
    });
  });

  group('QuantityConstraint.verify', () {
    test('complete puzzle with exact count → valid', () {
      // 2x2 grid with two '1' cells, target 2
      final p = makePuzzle('12\n21');
      expect(QuantityConstraint('1.2').verify(p), isTrue);
    });

    test('complete puzzle with wrong count → invalid', () {
      final p = makePuzzle('12\n21');
      expect(QuantityConstraint('1.1').verify(p), isFalse);
    });

    test('incomplete puzzle with count already exceeded → invalid', () {
      // Three '1' cells placed, target 2 → already over.
      final p = makePuzzle('11\n01');
      expect(QuantityConstraint('1.2').verify(p), isFalse);
    });

    test('incomplete puzzle, target still reachable → valid', () {
      // 1 '1' placed, 2 free cells, target 2 → reachable by colouring one free
      final p = makePuzzle('12\n00');
      expect(QuantityConstraint('1.2').verify(p), isTrue);
    });

    test('incomplete puzzle with target unreachable → invalid', () {
      // 0 '1' cells placed, 2 free cells, target 3 → max achievable 2 < 3.
      final p = makePuzzle('00\n22');
      expect(QuantityConstraint('1.3').verify(p), isFalse);
    });
  });

  group('Puzzle.getGroups', () {
    test('2x2 with two groups', () {
      final p = makePuzzle('11\n22');
      final groups = getGroups(p);
      expect(groups.length, 2);
      expect(
        groups.any((g) => g.length == 2 && g.contains(0) && g.contains(1)),
        isTrue,
      );
      expect(
        groups.any((g) => g.length == 2 && g.contains(2) && g.contains(3)),
        isTrue,
      );
    });

    test('3x3 with two groups of different sizes', () {
      // 212/212/222 → value 2: {0,2,3,5,6,7,8} size 7, value 1: {1,4} size 2
      final p = makePuzzle('212\n212\n222');
      final groups = getGroups(p);
      expect(groups.any((g) => g.length == 7), isTrue);
      expect(
        groups.any((g) => g.length == 2 && g.contains(1) && g.contains(4)),
        isTrue,
      );
    });
  });

  group('GroupSize.apply merge-too-big', () {
    test('single group merge blocked', () {
      // 3x3: 101 / 001 / 000
      // GS at idx 0 (value=1), target=2. myGroup={0}, margin=1.
      // Free neighbors: idx 1 and idx 3 (two exits, so single-exit rule doesn't fire).
      // idx 1 touches group {2,5} (size 2, ≥ margin 1) → blocked.
      final p = makePuzzle('''
        101
        001
        000
      ''');
      final gs = GroupSize('0.2');
      p.constraints.add(gs);
      final move = gs.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 2);
    });

    test('multi-group merge blocked', () {
      // 3x3: 010 / 101 / 000
      // GS at idx 3 (row1,col0, value=1), target=3. myGroup={3}, margin=2.
      // Free neighbor idx 4 (center) touches two separate groups: {1} and {5}, each size 1.
      // Each individually < margin (1 < 2), but sum = 2 ≥ margin → blocked.
      // Coloring idx 4 as 1 would create a merged group of size 4 > target 3.
      final p = makePuzzle('''
        010
        101
        000
      ''');
      final gs = GroupSize('3.3');
      p.constraints.add(gs);
      final move = gs.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 4);
      expect(move.value, 2);
    });

    test('merge within limit is not blocked', () {
      // 3x3:
      //   0 1 0
      //   1 0 0
      //   0 0 0
      // GS at idx 3 (row1,col0, value=1), target=4. myGroup={3}, margin=3.
      // Free neighbor idx 4 touches group {1} (size 1). Sum=1 < 3 → not blocked.
      final p = makePuzzle('''
        010
        100
        000
      ''');
      final gs = GroupSize('3.4');
      p.constraints.add(gs);
      final move = gs.apply(p);
      // Should NOT return a merge-blocking move on idx 4
      // (it might return null or a different deduction, but not blocking idx 4)
      if (move != null) {
        expect(move.idx != 4 || move.value != 2, isTrue);
      }
    });
  });

  group('GroupSize.apply reachability', () {
    test('color eliminated when empty region too small', () {
      // 3x4: 010 / 010 / 101 / 000
      // GS:7.5 — cell 7 (row2,col1) must be in group of size 5. Cell 7 is empty.
      // Flood-fill from c7 through empty-or-color cells.
      // Color=2: c7 is blocked by three value-1 neighbors except c10.
      //   Reachable = {7, 10, 9, 11} (4 cells) < 5 → impossible.
      // Color=1: flood-fill spans the full grid via empty + value-1 cells.
      //   Reachable = all 12 cells ≥ 5 → OK.
      // → cell 7 forced to value 1.
      final p = makePuzzle('''
        010
        010
        101
        000
      ''');
      final gs = GroupSize('7.5');
      p.constraints.add(gs);
      final move = gs.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 7);
      expect(move.value, 1);
    });

    test('multi-merge: groups reachable via intermediate empty cell', () {
      // Regression for puzzle v2_12_3x3_000010001_GS:7.6 in state 121210101:
      //   1 2 1
      //   2 1 0
      //   1 0 1
      // GS:7.6 — c7 must be in a group of size 6. c7 is empty.
      // Naive "empty region + adjacent same-color groups" underestimates:
      //   c7's empty region is just {7} (c5 is not adjacent to c7), and
      //   the three adjacent value-1 singletons {4},{6},{8} give only 1+3=4<6.
      // Correct flood-fill through empty-or-color-1 reaches {7,4,6,8,5,2} = 6,
      // because c5 (empty) bridges c4/c8 to c2 (value 1).
      // Color=2 reachable = {7} alone → impossible. → c7 forced to value 1.
      final p = makePuzzle('''
        121
        210
        101
      ''');
      final gs = GroupSize('7.6');
      p.constraints.add(gs);
      final move = gs.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 7);
      expect(move.value, 1);
    });

    test('no deduction when both colors reachable', () {
      // 3x3: 000 / 010 / 000
      // GS:4.3 — cell 4 (center) empty, target=3.
      // Empty region = all 8 empty cells. Both colors have max ≥ 3. No deduction.
      final p = makePuzzle('''
        000
        010
        000
      ''');
      final gs = GroupSize('4.3');
      p.constraints.add(gs);
      final move = gs.apply(p);
      expect(move, isNull);
    });
  });

  group('DifferentFromConstraint.verify', () {
    test('right: different values → valid', () {
      // Cell (1,1)=N and cell (2,1)=B are different
      final p = makePuzzle('12\n12');
      expect(DifferentFromConstraint('0.right').verify(p), isTrue);
    });

    test('right: same values → invalid', () {
      // Cell (1,1)=N and cell (2,1)=N are the same
      final p = makePuzzle('11\n12');
      expect(DifferentFromConstraint('0.right').verify(p), isFalse);
    });

    test('down: different values → valid', () {
      // Cell (1,1)=N and cell (1,2)=B are different
      final p = makePuzzle('12\n21');
      expect(DifferentFromConstraint('0.down').verify(p), isTrue);
    });

    test('down: same values → invalid', () {
      // Cell (1,1)=N and cell (1,2)=N are the same
      final p = makePuzzle('12\n11');
      expect(DifferentFromConstraint('0.down').verify(p), isFalse);
    });
  });

  group('DifferentFromConstraint.generateAllParameters', () {
    test('creates all valid positions', () {
      // 2x2 grid: 4 possible DF constraints
      // idx 0 → right (0,1), down (0,2)
      // idx 1 → down (1,3)
      // idx 2 → right (2,3)
      final params = DifferentFromConstraint.generateAllParameters(2, 2, [
        1,
        2,
      ], null);
      expect(params, contains('0.right'));
      expect(params, contains('0.down'));
      expect(params, contains('1.down'));
      expect(params, contains('2.right'));
      expect(params.length, 4);
    });

    test('excludes specified indices', () {
      // Exclude cells 0 and 1: no constraint can reference them
      final params = DifferentFromConstraint.generateAllParameters(
        2,
        2,
        [1, 2],
        {0, 1},
      );
      expect(params.contains('0.right'), isFalse);
      expect(params.contains('0.down'), isFalse);
      expect(params.contains('1.down'), isFalse);
      expect(params, contains('2.right'));
    });
  });

  group('DifferentFromConstraint.toHuman', () {
    test('right uses actual puzzle width, not a hardcoded approximation', () {
      // Cell 2 (1-based: 3) right-of-constraint points at cell 3 (1-based: 4)
      // on a 4-wide grid. The prior implementation hardcoded width=100,
      // which would have produced "3 ≠ 4" only by luck (idx+1 for right).
      // Here we verify the down direction where width matters.
      final p = Puzzle.empty(4, 4, [1, 2]);
      expect(DifferentFromConstraint('2.down').toHuman(p), '3 ≠ 7');
      // For comparison: on a 5-wide grid, down from idx 2 is idx 7 → "3 ≠ 8".
      final p5 = Puzzle.empty(5, 4, [1, 2]);
      expect(DifferentFromConstraint('2.down').toHuman(p5), '3 ≠ 8');
    });
  });

  group('GroupCountConstraint.verify', () {
    test('correct group count → valid', () {
      // 2x2: 2 black groups
      // 1 0
      // 0 1  → 2 isolated black cells = 2 groups
      final p = makePuzzle('10\n01');
      expect(GroupCountConstraint('1.2').verify(p), isTrue);
    });

    test('wrong group count → valid', () {
      // 2x2: 2 black groups but constraint asks for 1
      // still valid because groups can merge
      final p = makePuzzle('10\n01');
      expect(GroupCountConstraint('1.1').verify(p), isTrue);
    });

    test('wrong group count → invalid', () {
      // 2x2: 2 black groups but constraint asks for 1
      // invalid because groups cannot merge
      final p = makePuzzle('10\n22\n01');
      expect(GroupCountConstraint('1.1').verify(p), isFalse);
    });

    test('incomplete puzzle with less groups than target → valid', () {
      // 2x2 with 1 black cell filled, target is 2 groups
      final p = makePuzzle('10\n00');
      expect(GroupCountConstraint('1.2').verify(p), isTrue);
    });

    test('incomplete puzzle with more groups than target → valid', () {
      // 2x2 with 2 black groups but target is 1
      final p = makePuzzle('10\n01');
      expect(GroupCountConstraint('1.1').verify(p), isTrue);
    });

    test('incomplete puzzle without room for new groups → invalid', () {
      final p = makePuzzle('20\n21');
      expect(GroupCountConstraint('1.2').verify(p), isFalse);
    });

    test('incomplete puzzle with groups that cannot merge → invalid', () {
      final p = makePuzzle('111\n222\n010');
      expect(GroupCountConstraint('1.1').verify(p), isFalse);
    });
  });

  group('GroupCountConstraint.generateAllParameters', () {
    test('generates valid parameters', () {
      final params = GroupCountConstraint.generateAllParameters(2, 2, [
        1,
        2,
      ], null);
      expect(params, contains('1.1'));
      expect(params, contains('1.2'));
      expect(params, contains('2.1'));
      expect(params, contains('2.2'));
    });

    test('max count is ceil(width*height/2)', () {
      // 3x3 = 9 cells → max 5 groups (ceil(9/2))
      final params = GroupCountConstraint.generateAllParameters(3, 3, [
        1,
        2,
      ], null);
      expect(params, contains('1.5'));
      expect(params, isNot(contains('1.6')));
    });
  });

  group('GroupCountConstraint.apply - too many groups', () {
    test('contradiction when groups cannot merge enough', () {
      final p = makePuzzle('100\n022\n021');
      final gc = GroupCountConstraint('1.1'); // target: 1 group - impossible
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('force merge when single cell can merge groups', () {
      // Only one cell can merge both groups → force color it black
      final p = makePuzzle('100\n000\n120');
      final gc = GroupCountConstraint('1.1');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 3);
      expect(move.value, 1);
    });

    test('impossible when unique merge overshoots target', () {
      // 7x4 grid: four isolated color-1 singletons around cell 9. Cell 9
      // is the only free cell and the only merge-cell, adjacent to all 4
      // groups. Colouring it merges all 4 → count drops from 4 to 1.
      // Reachable counts = {4, 1}. Target 3 is unreachable, so apply()
      // must flag isImpossible directly (not force a wrong merge first).
      final p = makePuzzle(
        '2212222\n'
        '2101222\n'
        '2212222\n'
        '2222222',
      );
      final gc = GroupCountConstraint('1.3');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('multi-step merge via flood-fill is NOT flagged impossible', () {
      // Regression: two isolated color-1 cells (0 at (0,0) and 24 at (3,3))
      // on a 7x4 grid with many free cells between them. There is NO free
      // cell directly adjacent to both groups (they're too far apart), but
      // they CAN merge via a chain of intermediate free cells colored with
      // 1. Target GC:1.1 must be reachable — verify() returns true and
      // apply() returns no isImpossible.
      final p = Puzzle('v2_12_7x4_1000000000020000000000001000__0:0_0');
      final gc = GroupCountConstraint('1.1');
      p.constraints.add(gc);
      expect(gc.verify(p), isTrue);
      final move = gc.apply(p);
      if (move != null) expect(move.isImpossible, isNull);
    });

    test(
      'single direct merge-cell does NOT force when multi-step paths exist',
      () {
        // Regression: three color-1 groups — {0,1,7}, a big middle group, and
        // a singleton {22}. Cell 23 is the ONLY direct merge-cell (adj to the
        // singleton and the middle group), but the singleton can also reach
        // the middle group via a multi-step path through cells 21, 14, 7, 0,
        // 1, 2, 3. So cell 23 = 1 is not a forced deduction — apply must
        // not return Move(23, 1).
        final p = Puzzle('v2_12_7x4_1100111122121202111110101121__0:0_0');
        final gc = GroupCountConstraint('1.1');
        p.constraints.add(gc);
        final move = gc.apply(p);
        if (move != null) {
          expect(move.idx != 23 || move.value != 1, isTrue);
        }
      },
    );
  });

  group('GroupCountConstraint.apply - not enough groups', () {
    test('contradiction when not enough cells to create groups', () {
      final p = makePuzzle('112\n122\n011');
      final gc = GroupCountConstraint('2.3');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('force fill when exactly remaining cells needed', () {
      final p = makePuzzle('100');
      final gc = GroupCountConstraint('1.2');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 2);
      expect(move.value, 1);
    });

    test(
      'impossible when candidates are adjacent and cannot all be isolated',
      () {
        // 1x3 state 000 + GC:1.3: all three cells are candidates, but they
        // form a single path so colouring them all merges into 1 group, not 3.
        // Target unreachable → impossible detected up-front.
        final p = makePuzzle('000');
        final gc = GroupCountConstraint('1.3');
        p.constraints.add(gc);
        final move = gc.apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNotNull);
      },
    );

    test('force fill when candidates are independent and count matches', () {
      // 1x5 state 02020 + GC:1.3: candidates are cells 0, 2, 4 (separated
      // by color-2 cells, pairwise non-adjacent). current + candidates = 3
      // = target, so every candidate must become its own group → force the
      // first one to black.
      final p = makePuzzle('02020');
      final gc = GroupCountConstraint('1.3');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 0);
      expect(move.value, 1);
    });
  });

  group('GroupCountConstraint.apply - exact count', () {
    test('force opposite when no new groups can be created', () {
      // 2x2: 1 0 / 0 1 → 2 black groups (at 0 and 3)
      // Empty cell idx 1: neighbor black=0 → would merge, not create new
      // Empty cell idx 2: neighbor black=3 → would merge, not create new
      // getFreeCellsWithoutNeighborColor = none
      // current=2, target=2, candidates=0 → force opposite (color 2) on any cell that would merge
      final p = makePuzzle('10\n01');
      final gc = GroupCountConstraint('1.2');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNotNull);
      // Any cell that would merge, force to white instead
      expect(move!.idx, isIn([1, 2]));
      expect(move.value, 2);
    });

    test('no deduction on candidates even with no merge-cell present', () {
      // 3x3: 1 0 0 / 0 0 0 / 0 0 0 — one black group at cell 0, target=1.
      // Candidates exist (e.g., cell 8), merge-cells don't (only 1 group).
      // Naive "force candidates to opposite" would be wrong: the full grid
      // 1 1 1 / 1 1 1 / 1 1 1 is a valid completion (one connected black
      // group) because coloring intermediate cells also rejoins the
      // candidate to the existing group.
      final p = makePuzzle('100\n000\n000');
      final gc = GroupCountConstraint('1.1');
      p.constraints.add(gc);
      expect(gc.apply(p), isNull);
    });

    test('no deduction when candidates and merge-cells coexist', () {
      // 3x3: 1 0 1 / 0 0 0 / 0 0 0 — two black groups {0} and {2}, target=2.
      // Merge-cell: {1} (adjacent to both groups → merging them drops count to 1).
      // Candidates: {4,6,7,8} (cells with no color-1 neighbor → creating a new
      // group raises count to 3).
      // Either effect alone would violate the target, but both can coexist
      // in a valid completion (e.g., color cell 1 AND cell 8 → count stays 2).
      // So GroupCountConstraint.apply must NOT force a deduction here — it
      // should defer to force/backtracking.
      final p = makePuzzle('101\n000\n000');
      final gc = GroupCountConstraint('1.2');
      p.constraints.add(gc);
      final move = gc.apply(p);
      expect(move, isNull);
    });

    test(
      'force candidate to opposite when colouring it makes target unreachable',
      () {
        // 3x3: 1 2 2 / 2 . 2 / 2 2 1 — cell 4 is the only free cell and the
        // only candidate. Colouring cell 4 = 1 completes the puzzle with 3
        // isolated color-1 groups ({0}, {4}, {8}); no merge-cell remains,
        // so reachable = {3}. Target 2 is unreachable, so cell 4 must be 2.
        final p = makePuzzle('122\n202\n221');
        final gc = GroupCountConstraint('1.2');
        p.constraints.add(gc);
        final move = gc.apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNull);
        expect(move.idx, 4);
        expect(move.value, 2);
      },
    );
  });

  // NC: center cell in 3x3 grid is idx 4, with 4 neighbors at idx 1/3/5/7.
  group('NeighborCountConstraint.verify', () {
    test('complete puzzle with exact count → valid', () {
      // neighbors of idx 4: 1=1, 3=1, 5=1, 7=1 → 4 color-1 neighbors
      final p = makePuzzle('212\n111\n212');
      expect(NeighborCountConstraint('4.1.4').verify(p), isTrue);
    });

    test('complete puzzle with wrong count → invalid', () {
      // same grid, constraint asks for 2 color-1 neighbors but there are 4
      final p = makePuzzle('212\n111\n212');
      expect(NeighborCountConstraint('4.1.2').verify(p), isFalse);
    });

    test('incomplete puzzle, target still reachable → valid', () {
      // Regression for the bug fixed by H1: previously `verify` returned
      // `targetColorNeighbors + freeNeighbors == count`, so a fully-open
      // neighborhood with count < freeNeighbors was wrongly flagged invalid.
      // Here: center=1, all 4 neighbors free, count=2 → perfectly reachable.
      final p = makePuzzle('000\n010\n000');
      expect(NeighborCountConstraint('4.1.2').verify(p), isTrue);
    });

    test('incomplete puzzle with already too many color neighbors → invalid', () {
      // 3 color-1 neighbors (idx 1/3/5), 1 free (idx 7), count=2 → already exceeded
      final p = makePuzzle('010\n111\n000');
      expect(NeighborCountConstraint('4.1.2').verify(p), isFalse);
    });

    test('incomplete puzzle with target unreachable → invalid', () {
      // idx 1=2, 3=2, 5=2, 7=0 → 0 color-1, 1 free. count=2 cannot be reached.
      final p = makePuzzle('020\n202\n000');
      expect(NeighborCountConstraint('4.1.2').verify(p), isFalse);
    });

    test('incomplete puzzle with target exactly reachable → valid', () {
      // 0 color-1, 1 free neighbor, count=1 — only reachable by coloring the
      // last free neighbor; `verify` must still accept the state.
      final p = makePuzzle('020\n202\n000');
      expect(NeighborCountConstraint('4.1.1').verify(p), isTrue);
    });
  });

  group('NeighborCountConstraint.apply', () {
    test(
      'target already reached → forces remaining free neighbors to opposite',
      () {
        // Neighbors of idx 4: 1=1, 3=0, 5=0, 7=1. count=2 already satisfied
        // by the two color-1 neighbors, so any remaining free neighbor must
        // be color-2. `apply` returns one such deduction.
        final p = makePuzzle('010\n000\n010');
        final move = NeighborCountConstraint('4.1.2').apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNull);
        expect([3, 5], contains(move.idx));
        expect(move.value, 2);
      },
    );

    test('free cells exactly match remaining need → forces all to target', () {
      // 0 color-1 neighbors, 2 free (idx 5, 7), count=2 → every free
      // neighbor must take color 1 to reach the target.
      final p = makePuzzle('020\n201\n000');
      final move = NeighborCountConstraint('4.1.2').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect([5, 7], contains(move.idx));
      expect(move.value, 1);
    });

    test('already too many target-color neighbors → reports impossibility', () {
      // 3 color-1 neighbors (1, 3, 5), 1 free (7), count=2 → no recovery
      // possible; `apply` must flag the puzzle as impossible.
      final p = makePuzzle('010\n111\n000');
      final move = NeighborCountConstraint('4.1.2').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('not enough remaining cells → reports impossibility', () {
      // 0 color-1, 1 free (7), count=2 → target unreachable even if the
      // last free neighbor is coloured, so `apply` must detect the
      // contradiction rather than silently returning null.
      final p = makePuzzle('020\n202\n000');
      final move = NeighborCountConstraint('4.1.2').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('slack available → no deduction', () {
      // 1 color-1 (idx 1), 3 free (3, 5, 7), count=2 → any two of the free
      // neighbors can satisfy the target; nothing is forced yet.
      final p = makePuzzle('010\n000\n000');
      expect(NeighborCountConstraint('4.1.2').apply(p), isNull);
    });
  });

  group('NeighborCountConstraint.isCompleteFor', () {
    test('all neighbors filled and target reached → complete', () {
      // Satisfied and no free neighbor remains → grayout signal must fire:
      // no future play can ever re-trigger `apply`.
      final p = makePuzzle('212\n111\n212');
      expect(NeighborCountConstraint('4.1.4').isCompleteFor(p), isTrue);
    });

    test('target reached but a free neighbor remains → not complete', () {
      // targetColorNeighbors==count is satisfied but a free neighbor exists;
      // `apply` will still fire (to force the opposite color) so the
      // constraint must NOT be grayed out yet.
      final p = makePuzzle('010\n000\n010');
      expect(NeighborCountConstraint('4.1.2').isCompleteFor(p), isFalse);
    });

    test('invalid state (too many targets) → not complete', () {
      // `isCompleteFor` must return false when `verify` fails, even though
      // no future play could recover the state.
      final p = makePuzzle('010\n111\n000');
      expect(NeighborCountConstraint('4.1.2').isCompleteFor(p), isFalse);
    });
  });

  group('EyesConstraint.verify', () {
    test('reachable-but-incomplete state → valid', () {
      // 3x3, eye at (1,1) with count=2, color=1. Already sees 1 cell up and
      // has plenty of room left/right/down to gain a second.
      final p = makePuzzle('010\n000\n000');
      expect(EyesConstraint('4.1.2').verify(p), isTrue);
    });

    test('current count exceeds target → invalid', () {
      // count=0 but the eye already sees one cell of color 1 above it: the
      // constraint is broken now (and forever, since seen cannot decrease).
      final p = makePuzzle('010\n000\n000');
      expect(EyesConstraint('4.1.0').verify(p), isFalse);
    });

    test('max possible count below target → invalid', () {
      // 3x3 grid: an eye at any cell can see at most (W-1)+(H-1) = 4 cells.
      // count=5 is unreachable from any state, so verify must reject the
      // initial empty grid (regression for the old buggy verify).
      final p = makePuzzle('000\n000\n000');
      expect(EyesConstraint('4.1.5').verify(p), isFalse);
    });

    test('all directions blocked, count > 0 → invalid', () {
      // The eye is surrounded by opposite-coloured neighbours so no future
      // fill can ever produce a colour-1 cell in line of sight. count=1 is
      // unreachable.
      final p = makePuzzle('020\n202\n020');
      expect(EyesConstraint('4.1.1').verify(p), isFalse);
    });
  });

  group('EyesConstraint.apply - lower-bound deductions', () {
    test('count saturates the only direction with empties → forces colour', () {
      // 3x3 with all neighbours of the eye blocked except the right cell.
      // count=1 must come from that cell, so it is forced to colour 1.
      // (Same case the original `apply` already handled.)
      final p = makePuzzle('020\n200\n020');
      final move = EyesConstraint('4.1.1').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 5);
      expect(move.value, 1);
    });

    test(
      'eye 4 with 2 free left, blocked up/right → forces 2 down (user example)',
      () {
        // 5x7 grid, eye at (0,2) (idx 2), color=1, count=4. Cell (0,3) is the
        // opposite colour blocking right; up is out of bounds; left has 2
        // reachable empties. The four-cell target therefore needs at least 2
        // colour-1 cells downward — apply must force the first cell below.
        final p = makePuzzle(
          '00020\n'
          '00000\n'
          '00000\n'
          '00000\n'
          '00000\n'
          '00000\n'
          '00000',
        );
        final move = EyesConstraint('2.1.4').apply(p);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNull);
        expect(move.idx, 7);
        expect(move.value, 1);
      },
    );

    test('after the first downward force, the second one chains', () {
      // Same setup as above but with the first cell below the eye already
      // coloured. The eye now sees 1 down and still needs 1 more from below
      // (left only contributes 2 max) → the next cell down is forced.
      final p = makePuzzle(
        '00020\n'
        '00100\n'
        '00000\n'
        '00000\n'
        '00000\n'
        '00000\n'
        '00000',
      );
      final move = EyesConstraint('2.1.4').apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 12);
      expect(move.value, 1);
    });
  });

  group('EyesConstraint.apply - upper-bound deductions', () {
    test('totalSeen == count forces remaining empty to opposite', () {
      // 3x3 eye sees 1 up + 1 left = 2 = count. The single empty in line of
      // sight (idx 5 to the right) must therefore become opposite so the
      // count cannot grow past 2.
      final p = makePuzzle('010\n100\n020');
      final move = EyesConstraint('4.1.2').apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 5);
      expect(move.value, 2);
    });

    test(
      'budget already consumed elsewhere → forces lone empty to opposite',
      () {
        // 5x3, eye at idx 7. count=1; right side already shows 1 colour-1
        // (cell 8). Up/down are blocked by opposite cells. The left direction
        // therefore must contribute 0 colour-1 cells, and there is exactly one
        // empty at position 0 in line of sight → force it to opposite.
        final p = makePuzzle('00200\n00010\n00200');
        final move = EyesConstraint('7.1.1').apply(p);
        expect(move, isNotNull);
        expect(move!.idx, 6);
        expect(move.value, 2);
      },
    );
  });

  group('EyesConstraint.apply - impossibility', () {
    test('seeing more than count → impossible', () {
      // count=0 but the eye already sees one colour-1 cell above it.
      final p = makePuzzle('010\n000\n000');
      final move = EyesConstraint('4.1.0').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('not enough reachable cells to ever reach count → impossible', () {
      // All four neighbours of the eye are opposite-coloured: max possible
      // count is 0, but target is 1. apply must flag impossibility instead
      // of returning a no-op.
      final p = makePuzzle('020\n202\n020');
      final move = EyesConstraint('4.1.1').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });
  });

  group('EyesConstraint.isCompleteFor', () {
    test('count reached and no empty in line of sight → complete', () {
      // Eye sees exactly count=2 (1 up, 1 left); right and down are blocked
      // by opposite cells with no empties in line of sight → no future move
      // can change the constraint, grayout signal must fire.
      final p = makePuzzle('010\n122\n020');
      expect(EyesConstraint('4.1.2').isCompleteFor(p), isTrue);
    });

    test(
      'count reached but an empty remains in line of sight → not complete',
      () {
        // Same target reached but an empty at idx 5 means apply will still
        // fire (forcing it to opposite); the constraint is not done yet.
        final p = makePuzzle('010\n100\n020');
        expect(EyesConstraint('4.1.2').isCompleteFor(p), isFalse);
      },
    );
  });

  group('LetterGroup aggregation', () {
    test('multiple LT constraints sharing a letter merge into one', () {
      // Generation outputs LT pairs (`A.idx1.idx2`); the loader rolls them
      // up into a single constraint listing every cell of the letter so
      // display and deduction can reason about the whole letter at once.
      final p = Puzzle('v2_12_3x3_000000000_LT:A.0.4;LT:A.4.8;LT:B.1.7_0:0_0');
      final lts = p.constraints.whereType<LetterGroup>().toList();
      expect(lts.length, 2);
      final a = lts.firstWhere((c) => c.letter == 'A');
      final b = lts.firstWhere((c) => c.letter == 'B');
      expect(a.indices.toSet(), {0, 4, 8});
      expect(b.indices.toSet(), {1, 7});
    });
  });

  group('LetterGroup.apply - articulation', () {
    test('lone exit of a member group is forced (single-exit case)', () {
      // 3x3, LT:A.0.8: cell 3 is colour 2, sealing cell 0's downward side.
      // Cell 0's only free neighbour is cell 1, so cell 1 must be colour 1
      // — otherwise cell 0 stays isolated and the two A members can never
      // share a group.
      final p = makePuzzle('100\n200\n001');
      final lt = LetterGroup('A.0.8');
      p.constraints.add(lt);
      final move = lt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNull);
      expect(move.idx, 1);
      expect(move.value, 1);
    });

    test('cell on the unique merge path is forced (corridor)', () {
      // 1x5 corridor: letter A pinned at the two ends. Every middle cell
      // sits on the only possible merge path, so the first encountered
      // articulation point is forced to colour 1. (Subsequent applies
      // would then force the others one by one.)
      final p = makePuzzle('10001');
      final lt = LetterGroup('A.0.4');
      p.constraints.add(lt);
      final move = lt.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 1);
    });

    test('opposite-colour wall splits the corridor → impossible', () {
      // 1x5: letter A at 0 and 4, cell 2 is colour 2 cutting the corridor
      // in two. No virtual group covers both members → apply must report
      // impossibility, not silently return null.
      final p = makePuzzle('10201');
      final lt = LetterGroup('A.0.4');
      p.constraints.add(lt);
      final move = lt.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('multi-member aggregated indices use the same articulation rule', () {
      // 1x5 with three letter-A cells (0, 2, 4) and an empty between each
      // pair. Both empties are articulation points; the lower-index one is
      // forced first. Exercises an aggregated LetterGroup with N>2.
      final p = makePuzzle('10101');
      final lt = LetterGroup('A.0.2.4');
      p.constraints.add(lt);
      final move = lt.apply(p);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 1);
    });
  });
}
