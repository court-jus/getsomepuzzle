import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  test('solveExplained returns all steps for a propagation-only puzzle', () {
    // 6x7 puzzle with many prefilled cells — fully solvable by propagation
    final p = Puzzle(
      'v2_12_6x7_002000210001022011020210200200100010202211_FM:12;FM:1.1.2;PA:17.top_0:0_0',
    );
    final freeCount = p.cellValues.where((v) => v == CellValue.free).length;
    final steps = p.solveExplained();

    // Should determine all free cells
    expect(steps.length, freeCount);
    // All steps should be propagation
    expect(steps.every((s) => s.method == SolveMethod.propagation), isTrue);
    // Each step should reference a constraint
    expect(steps.every((s) => s.constraint.isNotEmpty), isTrue);
    // The puzzle should not be modified
    expect(p.cellValues.where((v) => v == CellValue.free).length, freeCount);
  });

  test('solveExplained includes force steps when needed', () {
    // This puzzle still requires force even after the complicity
    // layer: two LT groups + several FMs leave at least one cell
    // that no single constraint or complicity can deduce on its own.
    final p = Puzzle(
      'v2_12_3x3_000000000_LT:A.8.2;LT:B.4.6;FM:1.2.2;FM:122;GS:0.1_0:0_100',
    );
    final steps = p.solveExplained();

    // Should determine all 9 cells
    expect(steps.length, 9);
    // Should have at least one force step
    expect(steps.any((s) => s.method == SolveMethod.force), isTrue);
    // Force steps have no constraint name
    for (final s in steps.where((s) => s.method == SolveMethod.force)) {
      expect(s.constraint, isEmpty);
    }
  });

  test('solveExplained does not modify the original puzzle', () {
    final p = Puzzle('v2_12_3x3_000000000_FM:1.2;GS:0.1;PA:8.top_0:0_2');
    final before = List<CellValue>.from(p.cellValues);
    p.solveExplained();
    expect(p.cellValues, before);
  });

  test('solveExplained trace carries removeOption moves end-to-end', () {
    // Regression: SolveStep used to be built without forwarding
    // `m.removeOption`, so any constraint that emitted a removeOption
    // move ended up as a no-op step in the trace. Replaying the trace
    // then left those cells free and made `replay.complete` false —
    // every generated 4+-cell 2-colour puzzle was rejected as
    // "!isUnique" in the generator's validity check.
    final p = Puzzle(
      'v2_12_6x7_002000210001022011020210200200100010202211_FM:12;FM:1.1.2;PA:17.top_0:0_0',
    );
    final freeCount = p.cellValues.where((v) => v == CellValue.free).length;
    final steps = p.solveExplained();
    // The fixture is dominated by FM/PA constraints, all of which now
    // emit `removeOption` rather than `value`. At least one step must
    // therefore carry a non-null `removeOption`, otherwise the trace
    // can't possibly drive the puzzle to completion.
    expect(
      steps.any((s) => s.removeOption != null),
      isTrue,
      reason: 'fixture should produce at least one removeOption step',
    );
    // Replay the trace on a fresh clone and verify completeness. This
    // is exactly what the generator's validity check does.
    final replay = p.clone();
    for (final s in steps) {
      if (s.value != null) {
        replay.setValue(s.cellIdx, s.value!);
      } else if (s.removeOption != null) {
        replay.removeOption(s.cellIdx, s.removeOption!);
      }
    }
    expect(
      replay.complete,
      isTrue,
      reason: 'replaying every SolveStep should drive the puzzle to '
          'completion when the trace originally completed; if this '
          'fails, the trace probably dropped a removeOption.',
    );
    expect(
      replay.cellValues.where((v) => v == CellValue.free).length,
      0,
    );
    // sanity: every free cell was eventually touched.
    final touched = steps.map((s) => s.cellIdx).toSet();
    expect(touched.length, freeCount);
  });

  test(
    'solveExplained reports complexity and complicity flag on prop steps',
    () {
      // FM:2.1;PA:8.top is the canonical PAFMComplicity case (see
      // complicities_test.dart): individual constraints can't deduce
      // cell 2 alone, only the cross-constraint complicity can. So the
      // resolution trace must contain at least one step flagged
      // isComplicity=true with complexity=3.
      final p = Puzzle('v2_12_3x3_000000000_FM:2.1;PA:8.top_0:0_100');
      final steps = p.solveExplained();

      // At least one prop step is flagged as a complicity.
      expect(steps.any((s) => s.isComplicity), isTrue);
      // That complicity step should carry a non-zero complexity tier
      // (PAFMComplicity defaults to 3).
      expect(steps.any((s) => s.isComplicity && s.complexity > 0), isTrue);
      // Force steps never set those fields.
      for (final s in steps.where((s) => s.method == SolveMethod.force)) {
        expect(s.complexity, 0);
        expect(s.isComplicity, isFalse);
      }
    },
  );
}
