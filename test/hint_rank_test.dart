import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/hint_rank_worker_core.dart';

void main() {
  group('scoreCandidate', () {
    test('returns null when the candidate string has no slug separator', () {
      // Defensive: a malformed candidate (no ":") should be rejected
      // rather than crash the worker. Mirrors the parsing guard in
      // `scoreCandidate` itself.
      final (puzzle, baseline) = prepareRanking(
        width: 2,
        height: 2,
        domain: const [1, 2],
        cellValues: const [1, 0, 0, 0],
        existingConstraints: const [],
      );
      expect(scoreCandidate(puzzle, 'notAValidCandidate', baseline), isNull);
    });

    test('returns null when the candidate slug is not in the registry', () {
      // A well-formed string with an unknown slug should still classify
      // as non-useful (no constraint can be built, no extra deductions).
      final (puzzle, baseline) = prepareRanking(
        width: 2,
        height: 2,
        domain: const [1, 2],
        cellValues: const [1, 0, 0, 0],
        existingConstraints: const [],
      );
      expect(scoreCandidate(puzzle, 'ZZ:0.0', baseline), isNull);
    });

    test('returns null when no fixed cell gives the candidate a foothold', () {
      // Empty 2x2 grid: no fixed cells, no constraints. Adding any FM
      // motif has nothing to propagate from — every cell can still be
      // either color so the constraint fires zero deductions. Score is
      // null because the candidate does not unlock anything over the
      // (empty) baseline.
      final (puzzle, baseline) = prepareRanking(
        width: 2,
        height: 2,
        domain: const [1, 2],
        cellValues: const [0, 0, 0, 0],
        existingConstraints: const [],
      );
      expect(baseline, 0);
      expect(scoreCandidate(puzzle, 'FM:11', baseline), isNull);
    });

    test(
      'returns a strictly positive score when the candidate unlocks cells',
      () {
        // 2x2 grid with `(0,0) = black (1)`, no constraints. Baseline
        // propagation cannot deduce anything (only one fixed cell, no
        // constraint to drive it). Adding `FM:11` (no two adjacent
        // blacks) forces at least one orthogonal neighbour of `(0,0)` to
        // white — a strictly positive number of new cells deduced.
        //
        // The test asserts the contract (score is non-null and > 0)
        // without coupling to the exact count, which depends on
        // propagation ordering and motif rotation details.
        final (puzzle, baseline) = prepareRanking(
          width: 2,
          height: 2,
          domain: const [1, 2],
          cellValues: const [1, 0, 0, 0],
          existingConstraints: const [],
        );
        final score = scoreCandidate(puzzle, 'FM:11', baseline);
        expect(score, isNotNull);
        expect(score!, greaterThan(0));
      },
    );
  });
}
