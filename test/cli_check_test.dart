import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main() {
  test('countSolutions detects the invalid puzzle found in try_me.txt', () {
    // This 4x6 puzzle from default.txt (cplx=100) is entirely empty with
    // insufficient constraints to determine a unique solution.
    // Found by running `dart run bin/generate.dart --check assets/try_me.txt`.
    // Regression test: ensures countSolutions correctly identifies multi-solution puzzles.
    final p = Puzzle(
      'v2_12_4x6_000000000000000000000000_FM:2.2.2;FM:1.1.2;PA:10.left;LT:A.11.12;FM:2.1.2;PA:18.top_0:0_100',
    );
    expect(p.countSolutions(), 2);
  });
}
