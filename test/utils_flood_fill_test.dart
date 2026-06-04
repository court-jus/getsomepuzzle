import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

import 'helpers/make_puzzle.dart';

// Direct tests of the shared floodFill/canReach helpers in utils/groups.dart.
// The 12 call sites (groups.dart, CH, GS, SY, GSQA, GSAll) are covered by
// their own constraint tests; here we only pin down the edge cases of the
// helpers' contract that no call-site test exercises explicitly.
void main() {
  group('floodFill', () {
    test('multiple starts merge into one visited set', () {
      // Two color-1 corners separated by a color-2 wall: a fill seeded from
      // both corners must visit both components even though they are not
      // connected to each other.
      final p = makePuzzle('100\n222\n001');
      final visited = floodFill(p, [0, 8], (i) => p.cellValues[i] == 1);
      expect(visited, {0, 8});
    });

    test('starts are visited even when canTraverse rejects them', () {
      // Contract: starts are visited unconditionally. Seeding from a free
      // cell while traversing only color-1 cells must include the seed
      // (callers like reachableComponentSize rely on this).
      final p = makePuzzle('011\n000\n000');
      final visited = floodFill(p, [0], (i) => p.cellValues[i] == 1);
      expect(visited, {0, 1, 2});
    });
  });

  group('canReach', () {
    test('a start cell can be its own target', () {
      // Contract: isTarget is also tested on the starts themselves. On a
      // 1-wide grid a border cell lies on both left and right sides — CH
      // relies on this to not report a false blockage.
      final p = makePuzzle('1\n0\n0');
      expect(canReach(p, [0], (i) => i == 0, (i) => false), isTrue);
    });

    test('empty starts → false', () {
      // Contract: no start means nothing is reachable (CH maps this to
      // "blocked" when a whole border is the opposite color).
      final p = makePuzzle('000\n000\n000');
      expect(canReach(p, [], (i) => true, (i) => true), isFalse);
    });
  });
}
