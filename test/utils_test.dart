import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// Build a puzzle from a grid string — rows separated by newlines,
/// digits 0/1/2.
Puzzle _make(String grid) {
  final rows = grid
      .trim()
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  final h = rows.length;
  final w = rows.first.length;
  final line =
      'v2_12_${w}x$h'
      '_${rows.join()}'
      '__0:0_0';
  return Puzzle(line);
}

void main() {
  group('toVirtualGroups', () {
    test('mixed grid with free/black/white cells — original regression', () {
      // 3x3 grid 010 / 100 / 002
      // Free cells: 0, 2, 4, 5, 6, 7.  Black: 1, 3.  White: 8.
      // Expected virtual groups:
      //   {0}                      — free cell with no free neighbour
      //   {2,4,5,6,7}              — connected free region
      //   {0,1,2,3,4,5,6,7}        — black or free (cell 8 blocks)
      //   {2,4,5,6,7,8}            — white or free (cells 1,3 block cell 0)
      final p = _make('010\n100\n002');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 4);
      expect(
        vGroups,
        containsAll([
          containsAll([0]),
          containsAll([2, 4, 5, 6, 7]),
          containsAll([0, 1, 2, 3, 4, 5, 6, 7]),
          containsAll([2, 4, 5, 6, 7, 8]),
        ]),
      );
    });

    test('fully free grid — one free component, one component per color', () {
      // 2x2 all-free grid. Every cell belongs to:
      //   - the single free component {0,1,2,3} (anchored on free cells)
      //   - the single black component {0,1,2,3} (no black cell → no anchor)
      //   - the single white component {0,1,2,3} (no white cell → no anchor)
      // With no anchors for color, only the free component exists.
      final p = _make('00\n00');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 1);
      expect(vGroups.first, unorderedEquals([0, 1, 2, 3]));
    });

    test('fully filled grid — one component per actual group', () {
      // 2x2 grid 11/22: two color groups, no free cells → the virtual
      // groups match the real groups exactly (one per color).
      final p = _make('11\n22');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 2);
      expect(
        vGroups,
        containsAll([
          unorderedEquals([0, 1]),
          unorderedEquals([2, 3]),
        ]),
      );
    });

    test('checkerboard — each colour cell is isolated by the other', () {
      // 2x2 grid 12/21: alternating colors, no free cells. Each cell is
      // its own virtual group (black and white are fully separated).
      final p = _make('12\n21');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 4);
      expect(
        vGroups,
        containsAll([
          [0],
          [3], // black singletons
          [1],
          [2], // white singletons
        ]),
      );
    });

    test('single-color grid — one color component, no free component', () {
      // 2x2 all-black. No free cells so no free component.
      final p = _make('11\n11');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 1);
      expect(vGroups.first, unorderedEquals([0, 1, 2, 3]));
    });

    test('free cells with no color anchors — only free components', () {
      // 3x1 grid 0 0 0: three free cells in a row, no colored cells at all.
      // Domain has [1,2] but no anchor of those colors → no colored virtual
      // groups. Only one free component containing all cells.
      final p = _make('000');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 1);
      expect(vGroups.first, unorderedEquals([0, 1, 2]));
    });

    test(
      'two isolated black groups with white barrier — virtual groups split',
      () {
        // 1x5 grid 1 2 0 2 1: two black anchors separated by colour-2 walls
        // (cells 1 and 3). From cell 0 (black), we can only reach cell 0
        // itself (neighbour cell 1 is white). Symmetrically for cell 4. The
        // middle free cell 2 is boxed in by whites and can only be its own
        // free component.
        final p = _make('12021');
        final vGroups = toVirtualGroups(p);
        // Free components: {2}. Black components: {0}, {4}.
        // White component: {1, 2, 3} (white cells + free cell between them).
        expect(vGroups.length, 4);
        expect(
          vGroups,
          containsAll([
            unorderedEquals([2]), // free
            unorderedEquals([0]), // black
            unorderedEquals([4]), // black
            unorderedEquals([1, 2, 3]), // white
          ]),
        );
      },
    );
  });
}
