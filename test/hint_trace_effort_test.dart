import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_worker_core.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// 6x7 puzzle fully solvable by propagation (shared with hint_flow_test). Its
/// line carries no cached solution, so tests call `computeComplexity()` first,
/// which solves it and populates `cachedSolution` — required by
/// `HintContext.forPuzzle`.
const _line =
    'v2_12_6x7_002000210001022011020210200200100010202211_'
    'FM:12;FM:1.1.2;PA:17.top_0:0_0';

/// Build the canonical solved grid the way `HintContext.forPuzzle` does.
Puzzle _solvedGrid(Puzzle puzzle) {
  final solved = Puzzle.empty(puzzle.width, puzzle.height, puzzle.domain);
  for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
    solved.cells[i].setForSolver(puzzle.cachedSolution![i]);
  }
  return solved;
}

void main() {
  group('Puzzle.traceEffort', () {
    test('a fully-solved grid has zero trace effort', () {
      // No free cells → no deduction step to weight → effort 0. This is the
      // baseline against which candidate constraints are compared.
      final puzzle = Puzzle(_line);
      puzzle.computeComplexity(force: true); // populate cachedSolution
      final solved = _solvedGrid(puzzle);

      expect(solved.freeCells(), isEmpty);
      expect(solved.traceEffort(), 0);
    });

    test('is deterministic across calls', () {
      // Pure function of the current state — two consecutive calls on an
      // untouched puzzle must agree.
      final puzzle = Puzzle(_line);
      puzzle.computeComplexity(force: true);
      expect(puzzle.traceEffort(), puzzle.traceEffort());
    });
  });

  group('validHintCandidate — compatibility with existing constraints', () {
    // Real bug repro (corpus puzzle). It already carries `LT:B.14.15`.
    // Successive `addConstraint` hints used to eventually offer a second LT
    // with a *different* letter sharing a cell/group with B — each valid
    // against the solution in isolation, but impossible to coexist (a cell
    // can't carry two letters). The compatibility filter must reject any such
    // candidate. The trailing `1:…` field carries the canonical solution.
    const bugLine =
        'v2_12_4x5_00000000000100000200_'
        'CC:1.1.3;EY:11.2.0;GS:10.8;NC:19.1.1;SY:10.2;CH:2.top.bottom;'
        'FM:10.21;LT:B.14.15_1:22222121211121112222_30_scenario:classic';

    test('rejects a solution-valid candidate that conflicts with an existing '
        'constraint', () {
      final puzzle = Puzzle(bugLine);
      puzzle.computeComplexity(force: true); // populate cachedSolution
      final ctx = HintContext.forPuzzle(puzzle);

      // Constraint-free solved grid — what the old filter verified against,
      // and what hid the LT-vs-LT conflict (no `cellConstraints` to read).
      final pristine = Puzzle.empty(puzzle.width, puzzle.height, puzzle.domain);
      for (int i = 0; i < puzzle.cachedSolution!.length; i++) {
        pristine.cells[i].setForSolver(puzzle.cachedSolution![i]);
      }

      // Walk the full candidate enumeration and assert two things:
      //  (a) every candidate the new filter ACCEPTS keeps the whole constraint
      //      set satisfiable on the canonical solution;
      //  (b) at least one candidate the OLD solution-only check would have
      //      accepted is now rejected — proving the filter actually bites
      //      (this is the conflicting-LT class that caused the bug).
      var foundNewlyRejected = false;
      for (final entry in constraintRegistry) {
        final params = entry.generateAllParameters(
          puzzle.width,
          puzzle.height,
          puzzle.domain,
          ctx.readonlyIndices,
        );
        for (final param in params) {
          final c = createConstraint(entry.slug, param);
          if (c == null) continue;
          if (ctx.existingSerialized.contains(c.serialize())) continue;
          if (c.isCompleteFor(ctx.puzzle)) continue;

          final accepted = validHintCandidate(ctx, entry.slug, param) != null;
          if (accepted) {
            final probe = ctx.solved.clone()..addConstraint(c);
            expect(
              probe.check(saveResult: false),
              isEmpty,
              reason:
                  'accepted "${c.serialize()}" must keep every constraint '
                  'satisfied on the solution',
            );
          } else if (c.verify(pristine)) {
            // Valid on the bare solution (old check would pass) yet rejected
            // by the compatibility check: exactly the bug class.
            foundNewlyRejected = true;
          }
        }
      }

      expect(
        foundNewlyRejected,
        isTrue,
        reason:
            'the compatibility filter must reject at least one '
            'solution-valid but incompatible candidate (e.g. a conflicting LT)',
      );
    });

    test('rejects a no-op candidate that adds nothing to the puzzle', () {
      // `LT:B.15.14` is a permutation of the existing `LT:B.14.15`: it merges
      // into the same letter group without adding a cell, so it escapes the
      // exact-serialize dedup yet changes nothing. Offering it would wrongly
      // claim "constraint added", so it must be rejected outright.
      final puzzle = Puzzle(bugLine);
      puzzle.computeComplexity(force: true);
      final ctx = HintContext.forPuzzle(puzzle);

      expect(validHintCandidate(ctx, 'LT', 'B.15.14'), isNull);
    });
  });

  group('pickHintConstraint', () {
    test('only ever offers a constraint valid for the solution', () async {
      // Whether it returns the first effort-reducing candidate or a random
      // valid fallback, the offered constraint must (a) parse, (b) not be one
      // the puzzle already carries, and (c) hold on the canonical solution —
      // we must never hand the player a constraint their solution violates.
      final puzzle = Puzzle(_line);
      puzzle.computeComplexity(force: true);
      final existing = puzzle.constraints.map((c) => c.serialize()).toSet();
      final solved = _solvedGrid(puzzle);

      final result = await pickHintConstraint(HintContext.forPuzzle(puzzle));

      if (result != null) {
        final colon = result.indexOf(':');
        final constraint = createConstraint(
          result.substring(0, colon),
          result.substring(colon + 1),
        );
        expect(constraint, isNotNull, reason: 'offered constraint must parse');
        expect(
          existing.contains(result),
          isFalse,
          reason: 'must not re-offer an already-present constraint',
        );
        expect(
          constraint!.verify(solved),
          isTrue,
          reason: 'offered constraint must hold on the canonical solution',
        );
      }
    });
  });
}
