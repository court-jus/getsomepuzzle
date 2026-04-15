import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';

/// Build a puzzle from a grid string (domain [1,2]).
/// Each digit is a cell value (0=empty, 1=black, 2=white), rows separated by newlines.
Puzzle _make(String grid) {
  final rows = grid
      .trim()
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  final h = rows.length;
  final w = rows.first.length;
  final p = Puzzle.empty(w, h, [1, 2]);
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      final v = int.parse(rows[r][c]);
      if (v != 0) {
        p.cells[r * w + c].setForSolver(v);
      }
    }
  }
  return p;
}

void main() {
  group('ForbiddenMotif.verify', () {
    test('2x1 motif absent → valid', () {
      // FM:12 (NB horizontal) absent from all-black grid
      final p = _make('111\n111');
      expect(ForbiddenMotif('12').verify(p), isTrue);
    });

    test('2x1 motif present → invalid', () {
      // FM:12 present at (0,0)-(1,0): N then B
      final p = _make('12\n11');
      expect(ForbiddenMotif('12').verify(p), isFalse);
    });

    test('2x2 motif absent → valid', () {
      // FM:12.21 absent: grid has no 2x2 block matching NB/BN
      final p = _make('11\n11');
      expect(ForbiddenMotif('12.21').verify(p), isTrue);
    });

    test('2x2 motif present → invalid', () {
      // FM:12.21 present at (0,0): NB/BN
      final p = _make('12\n21');
      expect(ForbiddenMotif('12.21').verify(p), isFalse);
    });

    test('motif with wildcards (0) matches any value', () {
      // FM:10 means N followed by anything → forbids N in any non-last column
      // Grid NN: matches at pos 0 (N then N, wildcard=0 matches N)
      final p = _make('11');
      expect(ForbiddenMotif('10').verify(p), isFalse);
    });

    test('1x3 motif', () {
      // FM:121 = NBN horizontal
      final p = _make('121\n222');
      expect(ForbiddenMotif('121').verify(p), isFalse);
      final p2 = _make('112\n222');
      expect(ForbiddenMotif('121').verify(p2), isTrue);
    });
  });

  group('GroupSize.verify', () {
    test('correct group size → valid', () {
      // 121/121/222: groups of 1 at {0,3} and {2,5} (size 2 each),
      // group of 2 at {1,4,6,7,8} (size 5)
      final p = _make('121\n121\n222');
      expect(GroupSize('0.2').verify(p), isTrue);
      expect(GroupSize('1.5').verify(p), isTrue);
      expect(GroupSize('2.2').verify(p), isTrue);
    });

    test('wrong group size → invalid', () {
      final p = _make('121\n121\n222');
      expect(GroupSize('0.1').verify(p), isFalse);
      expect(GroupSize('1.2').verify(p), isFalse);
      expect(GroupSize('0.3').verify(p), isFalse);
    });
  });

  group('ParityConstraint.verify', () {
    test('right: equal count → valid', () {
      // 1221: idx 1 right=[2,1] → 1 odd, 1 even → valid
      final p = _make('1221');
      expect(ParityConstraint('1.right').verify(p), isTrue);
    });

    test('left: unequal count → invalid', () {
      // 22212: idx 2, left side [2,2] → 0 odd, 2 even → invalid
      final p = _make('22212');
      expect(ParityConstraint('2.left').verify(p), isFalse);
    });

    test('top/bottom on column', () {
      // 3x3: 111/222/111 → idx 8 (row 2, col 2), top has [1,2] → valid
      final p = _make('111\n222\n111');
      expect(ParityConstraint('8.top').verify(p), isTrue);
      // 3x3: 111/222/111 → idx 0 (row 0, col 0), bottom has [2,1] → valid
      expect(ParityConstraint('0.bottom').verify(p), isTrue);
    });

    test('vertical: both sides must be balanced', () {
      // Column 1x5: 1,2,1,2,1 → idx 2, top=[1,2] bottom=[2,1] → both balanced → valid
      final p = _make('1\n2\n1\n2\n1');
      expect(ParityConstraint('2.vertical').verify(p), isTrue);
      // 1,1,X,2,1: top=[1,1] → 2 odd, 0 even → invalid
      final p2 = _make('1\n1\n1\n2\n1');
      expect(ParityConstraint('2.vertical').verify(p2), isFalse);
    });
  });

  group('Puzzle.getGroups', () {
    test('2x2 with two groups', () {
      final p = _make('11\n22');
      final groups = p.getGroups();
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
      final p = _make('212\n212\n222');
      final groups = p.getGroups();
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
      final p = _make('''
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
      final p = _make('''
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
      final p = _make('''
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
      // Empty region from 7: {0, 2, 3, 5, 7, 9, 10, 11} (8 cells).
      // If color=2: adjacent groups of value 2 = none. Max = 8 + 0 = 8 ≥ 5 → OK.
      // Wait — cells 6 and 8 are value 1 and block the path.
      // Empty region from 7: neighbors of 7 are 4(val=1), 6(val=1), 8(val=1), 10(val=0).
      // So from 7 only 10 is empty. From 10: neighbors 7(counted), 9(empty), 11(empty).
      // From 9: neighbors 6(val=1), 10(counted). From 11: neighbors 8(val=1), 10(counted).
      // Empty region = {7, 9, 10, 11} (4 cells).
      // Color 2: no adjacent value-2 groups → max = 4 < 5 → impossible.
      // Color 1: adjacent groups {1,4}(size 2), {6}(size 1), {8}(size 1) → max = 4 + 4 = 8 ≥ 5 → OK.
      // → cell 7 forced to value 1.
      final p = _make('''
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

    test('no deduction when both colors reachable', () {
      // 3x3: 000 / 010 / 000
      // GS:4.3 — cell 4 (center) empty, target=3.
      // Empty region = all 8 empty cells. Both colors have max ≥ 3. No deduction.
      final p = _make('''
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
      final p = _make('12\n12');
      expect(DifferentFromConstraint('0.right').verify(p), isTrue);
    });

    test('right: same values → invalid', () {
      // Cell (1,1)=N and cell (2,1)=N are the same
      final p = _make('11\n12');
      expect(DifferentFromConstraint('0.right').verify(p), isFalse);
    });

    test('down: different values → valid', () {
      // Cell (1,1)=N and cell (1,2)=B are different
      final p = _make('12\n21');
      expect(DifferentFromConstraint('0.down').verify(p), isTrue);
    });

    test('down: same values → invalid', () {
      // Cell (1,1)=N and cell (1,2)=N are the same
      final p = _make('12\n11');
      expect(DifferentFromConstraint('0.down').verify(p), isFalse);
    });
  });

  group('DifferentFromConstraint.generateAllParameters', () {
    test('creates all valid positions', () {
      // 2x2 grid: 4 possible DF constraints
      // idx 0 → right (0,1), down (0,2)
      // idx 1 → down (1,3)
      // idx 2 → right (2,3)
      final params = DifferentFromConstraint.generateAllParameters(2, 2);
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
        excludedIndices: {0, 1},
      );
      expect(params.contains('0.right'), isFalse);
      expect(params.contains('0.down'), isFalse);
      expect(params.contains('1.down'), isFalse);
      expect(params, contains('2.right'));
    });
  });
}
