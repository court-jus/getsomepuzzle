import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Minimal [CanApply] used to construct moves without a real constraint —
/// the weight-under-test only reads `Move.complexity` / `forceDepth`, never
/// `givenBy`.
class _FakeCanApply extends CanApply {
  @override
  Move? apply(Puzzle puzzle) => null;
  @override
  String serialize() => 'FAKE';
}

void main() {
  test('Complexity is 0 for propagation-only puzzles', () {
    // This puzzle (cplx=0 in default.txt) is mostly solved by propagation
    final p = Puzzle(
      'v2_12_3x3_000000001_PA:1.bottom;FM:11;LT:A.6.7;PA:8.top;GS:0.1_0:0_0',
    );
    // `force: true` — the v2 lines below carry stored cplx values
    // (field [6]) which the constructor now loads into the cache.
    // We want the actual computation under test, not the stored read.
    final cplx = p.computeComplexity(force: true);
    print('cplx=0 puzzle → computed=$cplx');
    expect(cplx, lessThan(20)); // Should be low
  });

  test('Complexity increases with difficulty', () {
    final samples = [
      (
        'v2_12_3x3_000000001_PA:1.bottom;FM:11;LT:A.6.7;PA:8.top;GS:0.1_0:0_0',
        'easy',
      ),
      ('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_2', 'medium'),
      (
        'v2_12_3x3_000000000_LT:A.3.8;PA:0.right;PA:5.left;FM:12_0:0_3',
        'medium+',
      ),
    ];

    int? prev;
    for (final (line, label) in samples) {
      final p = Puzzle(line);
      // `force: true` — the v2 lines below carry stored cplx values
      // (field [6]) which the constructor now loads into the cache.
      // We want the actual computation under test, not the stored read.
      final cplx = p.computeComplexity(force: true);
      print('$label → cplx=$cplx');
      if (prev != null) {
        expect(
          cplx,
          greaterThanOrEqualTo(prev),
          reason: '$label should be >= previous',
        );
      }
      prev = cplx;
    }
  });

  test('Complexity is high for hard puzzles', () {
    // This puzzle (cplx=100 in default.txt) is hard — many force rounds needed
    final p = Puzzle(
      'v2_12_3x3_000000000_LT:A.8.2;LT:B.4.6;FM:1.2.2;FM:122;GS:0.1_0:0_100',
    );
    // `force: true` — the v2 lines below carry stored cplx values
    // (field [6]) which the constructor now loads into the cache.
    // We want the actual computation under test, not the stored read.
    final cplx = p.computeComplexity(force: true);
    print('cplx=100 puzzle → computed=$cplx');
    expect(cplx, greaterThan(20));
  });

  test('Complexity is non-negative', () {
    final lines = [
      'v2_12_4x4_2000000000000001_PA:7.bottom;FM:10.01;PA:8.top;GS:0.1;PA:5.right;FM:01.21;PA:6.left;GS:14.2;PA:14.left;QA:1.7_0:0_1',
      'v2_12_4x5_00000100000000000010_GS:6.1;FM:2.1.2;PA:9.top;GS:2.1;PA:19.top;GS:1.1;PA:6.left;GS:8.5;PA:9.bottom;FM:22.01;GS:18.9_0:0_5',
      'v2_12_4x8_00000111010000000000020000000020_PA:29.right;GS:11.3;FM:20.21;PA:10.left;FM:12.02;PA:9.top;FM:22.01;PA:26.left;FM:21.12;PA:19.top;GS:29.4;PA:4.bottom;PA:21.right;PA:12.bottom_0:0_12',
    ];
    for (final line in lines) {
      final p = Puzzle(line);
      // `force: true` — the v2 lines below carry stored cplx values
      // (field [6]) which the constructor now loads into the cache.
      // We want the actual computation under test, not the stored read.
      final cplx = p.computeComplexity(force: true);
      final expected = int.parse(line.split('_').last);
      print('expected=$expected → computed=$cplx');
      // No upper bound: the score is a plain sum of non-negative parts and
      // may legitimately exceed 100 (see the unbounded test below).
      expect(cplx, greaterThanOrEqualTo(0));
    }
  });

  test('Complexity is unbounded — force-heavy puzzles exceed 100', () {
    // Real mad-collection line whose current-weight trace is force-heavy.
    // Under the old 90-cap on effort this and its peers were all flattened
    // around 96-100; with the cap removed the score sums the true effort.
    const line =
        'v2_12_3x4_000000010000_GS:9.4;SY:7.2;SY:1.2;SY:2.3;CT:1.1'
        '_1:121222212111_98_scenario:classic';
    final p = Puzzle(line);
    final cplx = p.computeComplexity(force: true);
    print('mad line → computed=$cplx');
    expect(cplx, greaterThan(100), reason: 'no longer clamped at 100');

    // The trace-based path must agree with the live solve path.
    final steps = p.solveExplained();
    final q = Puzzle(line);
    q.computeComplexityFromSteps(steps);
    expect(q.cachedComplexity, cplx);

    // Not-deductively-solvable puzzles still return the sentinel.
    final broken = Puzzle('v2_12_2x2_0000_GS:0.5_0:0_0');
    expect(broken.computeComplexity(force: true), kUnsolvableComplexity);
  });

  test('moveComplexity bumps RemoveOption only on domains > 2', () {
    final by = _FakeCanApply();
    final d2 = Puzzle.empty(2, 2, const [CellValue.black, CellValue.white]);
    final d3 = Puzzle.empty(2, 2, const [
      CellValue.black,
      CellValue.white,
      CellValue.purple,
    ]);
    const tier = 2;
    final prune = RemoveOption(0, CellValue.black, by, complexity: tier);
    final set = SetValue(0, CellValue.black, by, complexity: tier);
    final force = RemoveOption(
      0,
      CellValue.black,
      by,
      complexity: 0,
      isForce: true,
      forceDepth: 1,
    );

    // On a 2-colour domain a prune is semantically an assignment, so it
    // keeps its bare tier.
    expect(d2.moveComplexity(prune), tier);
    // On 3+ colours the prune pays the domain bump on top of its tier.
    expect(d3.moveComplexity(prune), tier + kRemoveOptionComplexityBump);
    // SetValue never bumps, whatever the domain.
    expect(d3.moveComplexity(set), tier);
    // Force moves never bump: their weight is derived from forceDepth and
    // their recorded complexity stays 0.
    expect(d3.moveComplexity(force), 0);
  });

  test('RemoveOption bump reaches the computed complexity (domain 3)', () {
    // 4x3 domain-3 fixture, solvable by pure propagation, whose trace
    // contains 4 RemoveOption steps (all tier 0 → recorded as 1, i.e.
    // + kRemoveOptionComplexityBump each).
    const line =
        'v2_123_4x3_301000010000_CC:0.1.1;CC:1.1.1;CC:3.2.1;'
        'PA:0.right;PA:3.left;RC:1.2.1;RC:2.3.3_1:321311213332_7_scenario:classic';
    final p = Puzzle(line);
    final steps = p.solveExplained();

    final pruneSteps = steps
        .where(
          (s) => s is RemoveOptionStep && s.method == SolveMethod.propagation,
        )
        .length;
    expect(pruneSteps, greaterThan(0), reason: 'fixture must contain prunes');
    // Every recorded prune carries the bump over its bare tier.
    for (final s in steps.whereType<RemoveOptionStep>()) {
      if (s.method == SolveMethod.propagation) {
        expect(s.complexity, greaterThanOrEqualTo(kRemoveOptionComplexityBump));
      }
    }

    // Both scoring paths (live solve and recorded trace) must agree.
    p.computeComplexityFromSteps(steps);
    final bumped = p.cachedComplexity!;
    final viaSolver = Puzzle(line).computeComplexity(force: true);
    expect(viaSolver, bumped);

    // Absolute value on this fixture:
    //   effort = 4 (4 prunes × 1) + 0 (7 trivial sets)
    //   rule diversity = 2 (CC, PA, RC)
    //   emptiness = 5 (9/12 free)
    //   domain bonus = 5 (3-colour domain)
    expect(
      bumped,
      16,
      reason: '4 effort + 2 diversity + 5 emptiness + 5 domain',
    );

    // Stripping the prune bump from the trace drops the score by exactly
    // pruneSteps × bump (no clamping on this toy puzzle).
    final debumped = [
      for (final s in steps)
        if (s is RemoveOptionStep && s.method == SolveMethod.propagation)
          RemoveOptionStep(
            cellIdx: s.cellIdx,
            option: s.option,
            constraint: s.constraint,
            method: s.method,
            forceDepth: s.forceDepth,
            complexity: s.complexity - kRemoveOptionComplexityBump,
            isComplicity: s.isComplicity,
          )
        else
          s,
    ];
    final q = Puzzle(line);
    q.computeComplexityFromSteps(debumped);
    expect(
      bumped - q.cachedComplexity!,
      pruneSteps * kRemoveOptionComplexityBump,
    );
  });

  test('domain size adds (domain - 2) * kDomainSizeComplexityBump', () {
    // Flat per-puzzle bonus, independent of the trace: 0 on the 2-colour
    // baseline, +kDomainSizeComplexityBump per extra colour.
    expect((2 - 2) * kDomainSizeComplexityBump, 0);
    expect((3 - 2) * kDomainSizeComplexityBump, 5);
    expect((4 - 2) * kDomainSizeComplexityBump, 10);
    // d2 puzzles in the corpus keep their scores (first test asserts
    // < 20 on a d2 line); the d3 fixture pays exactly +5 on top of its
    // non-domain components (effort 4 + diversity 2 + emptiness 5 = 11),
    // as pinned absolutely (16) by the previous test.
    final d3 = Puzzle(
      'v2_123_4x3_301000010000_CC:0.1.1;CC:1.1.1;CC:3.2.1;'
      'PA:0.right;PA:3.left;RC:1.2.1;RC:2.3.3_1:321311213332_7_scenario:classic',
    );
    expect(
      d3.computeComplexity(force: true),
      11 + (d3.domain.length - 2) * kDomainSizeComplexityBump,
    );
  });
}
