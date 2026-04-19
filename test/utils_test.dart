import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

void main() {
  group("groups utils", () {
    test('toVirtualGroups', () {
      final p = Puzzle('v2_12_3x3_010100002__0:0_0');
      final vGroups = toVirtualGroups(p);
      expect(vGroups.length, 4);
      expect(
        vGroups,
        containsAll([
          containsAll([0]), // Free group
          containsAll([2, 4, 5, 6, 7]), // Free group
          containsAll([0, 1, 2, 3, 4, 5, 6, 7]), // Black group
          containsAll([2, 4, 5, 6, 7, 8]), // White group
        ]),
      );
    });
  });
}
