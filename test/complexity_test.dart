import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

void main() {
  test('Complexity is 0 for propagation-only puzzles', () {
    // This puzzle (cplx=0 in default.txt) is mostly solved by propagation
    final p = Puzzle('v2_12_3x3_000000001_PA:1.bottom;FM:11;LT:A.6.7;PA:8.top;GS:0.1_0:0_0');
    final cplx = p.computeComplexity();
    print('cplx=0 puzzle → computed=$cplx');
    expect(cplx, lessThan(20)); // Should be low
  });

  test('Complexity increases with difficulty', () {
    final samples = [
      ('v2_12_3x3_000000001_PA:1.bottom;FM:11;LT:A.6.7;PA:8.top;GS:0.1_0:0_0', 'easy'),
      ('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_2', 'medium'),
      ('v2_12_3x3_000000000_LT:A.3.8;PA:0.right;PA:5.left;FM:12_0:0_3', 'medium+'),
    ];

    int? prev;
    for (final (line, label) in samples) {
      final p = Puzzle(line);
      final cplx = p.computeComplexity();
      print('$label → cplx=$cplx');
      if (prev != null) {
        expect(cplx, greaterThanOrEqualTo(prev), reason: '$label should be >= previous');
      }
      prev = cplx;
    }
  });

  test('Complexity is high for hard puzzles', () {
    // This puzzle (cplx=100 in default.txt) is hard — many force rounds needed
    final p = Puzzle('v2_12_3x3_000000000_LT:A.8.2;LT:B.4.6;FM:1.2.2;FM:122;GS:0.1_0:0_100');
    final cplx = p.computeComplexity();
    print('cplx=100 puzzle → computed=$cplx');
    expect(cplx, greaterThan(20));
  });

  test('Complexity is between 0 and 100', () {
    final lines = [
      'v2_12_4x4_2000000000000001_PA:7.bottom;FM:10.01;PA:8.top;GS:0.1;PA:5.right;FM:01.21;PA:6.left;GS:14.2;PA:14.left;QA:1.7_0:0_1',
      'v2_12_4x5_00000100000000000010_GS:6.1;FM:2.1.2;PA:9.top;GS:2.1;PA:19.top;GS:1.1;PA:6.left;GS:8.5;PA:9.bottom;FM:22.01;GS:18.9_0:0_5',
      'v2_12_4x8_00000111010000000000020000000020_PA:29.right;GS:11.3;FM:20.21;PA:10.left;FM:12.02;PA:9.top;FM:22.01;PA:26.left;FM:21.12;PA:19.top;GS:29.4;PA:4.bottom;PA:21.right;PA:12.bottom_0:0_12',
    ];
    for (final line in lines) {
      final p = Puzzle(line);
      final cplx = p.computeComplexity();
      final expected = int.parse(line.split('_').last);
      print('expected=$expected → computed=$cplx');
      expect(cplx, greaterThanOrEqualTo(0));
      expect(cplx, lessThanOrEqualTo(100));
    }
  });
}
