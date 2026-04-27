import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  test('isDeductivelyUnique rejects an under-constrained 4x6 puzzle', () {
    // This 4x6 puzzle from default.txt (cplx=100) is entirely empty with
    // insufficient constraints to determine a unique solution.
    // Found by running `dart run bin/generate.dart --check assets/try_me.txt`.
    // Regression test: ensures the validity check catches it.
    final p = Puzzle(
      'v2_12_4x6_000000000000000000000000_FM:2.2.2;FM:1.1.2;PA:10.left;LT:A.11.12;FM:2.1.2;PA:18.top_0:0_100',
    );
    expect(p.isDeductivelyUnique(), isFalse);
  });

  test('isDeductivelyUnique rejects a 7x4 puzzle ambiguous at cell 23', () {
    // This 7x4 puzzle was exported by the old generator, which only checked
    // that propagation + force reduced the free ratio, not that the resulting
    // puzzle had a unique solution. Cell 23 can legally be either 1 or 2.
    // Regression test pins the ambiguity so we notice if the validity check
    // regresses.
    final p = Puzzle(
      'v2_12_7x4_1000000000020000000000001000_GC:1.1;CC:4.1.3;SY:11.3;GS:26.1;PA:11.horizontal;FM:12.21;SY:8.1;FM:21.21;CC:6.2.1_1:1111111122121212111111111121_39',
    );
    expect(p.isDeductivelyUnique(), isFalse);
  });
}
