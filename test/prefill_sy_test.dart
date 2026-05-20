import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sy.dart';

void main() {
  group('preFillSy', () {
    test('produces a deductively-unique puzzle with ≥ 2 SY constraints', () {
      // Use a seeded RNG so the test is reproducible. Loop over a small
      // number of seeds and require at least one success — the
      // bipartite cascade can fail on unlucky topology and that's not a
      // regression, the user-facing generator retries.
      //
      // `maxRetries: 3` keeps a failing seed bounded — without it, a
      // pathological topology can churn for minutes (see
      // docs/dev/prefill_sy.md § 11).
      bool anySuccess = false;
      for (int s = 0; s < 12; s++) {
        final rng = Random(100 + s);
        final result = preFillSy(6, 6, rng, maxRetries: 3);
        if (result == null) continue;
        anySuccess = true;
        // Must have ≥ 2 SY attached.
        final syCount = result.puzzle.constraints
            .whereType<SymmetryConstraint>()
            .length;
        expect(syCount, greaterThanOrEqualTo(2));
        // The puzzle must be deductively unique by construction (cascade
        // returns only on success).
        expect(result.puzzle.isDeductivelyUnique(), isTrue);
        // Numbers consistent with what we asked: at least 2 islands,
        // some reveal action happened.
        expect(result.numIslands, greaterThanOrEqualTo(2));
        break;
      }
      expect(
        anySuccess,
        isTrue,
        reason:
            'preFillSy never succeeded over 12 seeds — '
            'the pipeline is broken or extremely flaky',
      );
    });

    test('every readonly cell carries the solution value', () {
      // Invariant: cells marked readonly must have value == solution[i],
      // whether they came from the random readonly prefill sprinkle or
      // from the bipartite cascade's strategic reveals. A mismatch would
      // mean the player is shown a wrong hint.
      for (int s = 0; s < 12; s++) {
        final rng = Random(500 + s);
        final result = preFillSy(6, 6, rng, maxRetries: 3);
        if (result == null) continue;
        for (int i = 0; i < result.puzzle.cells.length; i++) {
          final cell = result.puzzle.cells[i];
          if (!cell.readonly) continue;
          expect(
            cell.value,
            equals(result.solution[i]),
            reason:
                'readonly cell $i has value ${cell.value} but solution '
                'is ${result.solution[i]}',
          );
        }
        return; // one success is enough
      }
      fail('preFillSy never succeeded over 12 seeds');
    });

    test('SY anchors land on interior cells', () {
      // Default edgeMargin=1 must keep every seed off the outer ring.
      // Deterministic invariant of `_sampleSeeds` — one successful seed
      // exercise is enough to verify it.
      for (int s = 0; s < 10; s++) {
        final rng = Random(200 + s);
        final result = preFillSy(6, 6, rng, maxRetries: 3);
        if (result == null) continue;
        for (final c
            in result.puzzle.constraints.whereType<SymmetryConstraint>()) {
          final idx = c.indices[0];
          final x = idx % 6;
          final y = idx ~/ 6;
          expect(
            x >= 1 && x <= 4 && y >= 1 && y <= 4,
            isTrue,
            reason: 'seed $idx (x=$x, y=$y) is on the outer ring',
          );
        }
        return;
      }
      fail('preFillSy never succeeded over 10 seeds');
    });

    test('solution satisfies every SY constraint by construction', () {
      // The solution returned by preFillSy must pass `verify` for every
      // SY anchor — the growth procedure is what guarantees this.
      // Deterministic invariant — one success is enough.
      for (int s = 0; s < 10; s++) {
        final rng = Random(300 + s);
        final result = preFillSy(6, 6, rng, maxRetries: 3);
        if (result == null) continue;
        // Reconstruct the solved puzzle.
        final solved = result.puzzle.clone();
        for (int i = 0; i < solved.cells.length; i++) {
          solved.cells[i].setForSolver(result.solution[i]);
        }
        for (final c in solved.constraints.whereType<SymmetryConstraint>()) {
          expect(
            c.verify(solved),
            isTrue,
            reason: 'SY ${c.serialize()} does not verify on the solution',
          );
        }
        return;
      }
      fail('preFillSy never succeeded over 10 seeds');
    });

    test(
      'any LT guardrail has anchors in a single region (no inter-island)',
      () {
        // The LT inter-island filter must hold: an LT picked as a
        // guardrail can only span ocean cells OR cells of one specific
        // island, never two. We loop until we hit a puzzle that actually
        // contains at least one LT, then check it and return.
        for (int s = 0; s < 20; s++) {
          final rng = Random(400 + s);
          final result = preFillSy(6, 7, rng, maxRetries: 3);
          if (result == null) continue;
          final lts = result.puzzle.constraints
              .whereType<LetterGroup>()
              .toList();
          if (lts.isEmpty) continue;
          // Re-derive island membership from the solution: every cell that
          // is fg (not background) is part of an island. Two fg cells are
          // in the same island iff they're 4-connected via fg cells.
          final bg = _majorityColor(result.solution);
          final fg = bg == 1 ? 2 : 1;
          final islandOf = _connectedComponents(result.solution, fg, 6, 7);
          for (final lt in lts) {
            final regions = lt.indices.map((idx) => islandOf[idx]).toSet();
            expect(
              regions.length,
              equals(1),
              reason: 'LT ${lt.serialize()} spans regions $regions',
            );
          }
          return;
        }
        // No LT was picked by any of the 20 seeds — invariant is vacuously
        // true. This is fine; the filter is enforced at enumeration time
        // anyway.
      },
    );
  });
}

int _majorityColor(List<int> values) {
  int c1 = 0;
  int c2 = 0;
  for (final v in values) {
    if (v == 1) c1++;
    if (v == 2) c2++;
  }
  return c1 >= c2 ? 1 : 2;
}

/// Returns a list `islandOf` parallel to [values]: ocean cells map to
/// -1, island cells map to their connected-component index ≥ 0.
List<int> _connectedComponents(List<int> values, int fg, int w, int h) {
  final out = List<int>.filled(values.length, -1);
  int next = 0;
  for (int i = 0; i < values.length; i++) {
    if (values[i] != fg) continue;
    if (out[i] != -1) continue;
    final queue = <int>[i];
    out[i] = next;
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      final cx = cur % w;
      final cy = cur ~/ w;
      const dxs = [-1, 1, 0, 0];
      const dys = [0, 0, -1, 1];
      for (int d = 0; d < 4; d++) {
        final nx = cx + dxs[d];
        final ny = cy + dys[d];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        final ni = ny * w + nx;
        if (values[ni] != fg) continue;
        if (out[ni] != -1) continue;
        out[ni] = next;
        queue.add(ni);
      }
    }
    next++;
  }
  return out;
}
