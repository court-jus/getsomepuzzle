import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/canonical.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// Three real-world puzzles whose union of constraint slugs covers every
/// player-facing constraint type (FM, PA, GS, LT, QA, SY, DF, CC, RC, GC,
/// NC, EY, SH). Picked from `assets/*.txt`. Each one stresses one aspect
/// ratio: square, landscape (W>H), portrait (H>W).
const _squarePuzzle =
    'v2_12_4x4_0000000022100000_CC:0.1.2;DF:0.right;FM:20.21;'
    'GC:1.2;GS:2.3;LT:C.12.13;NC:13.1.2;NC:8.2.2;SY:15.4_1:1222211122111112_22';

const _landscapePuzzle =
    'v2_12_6x5_000000000000020100020000101012_CC:4.1.4;DF:4.right;'
    'EY:14.2.3;FM:21.12;GC:1.1;GS:6.5;LT:F.28.8;NC:17.1.3;PA:1.bottom;'
    'QA:1.22;RC:3.1.4;RC:4.1.5;SY:17.4_1:111121211111221112122111111112_32';

const _portraitPuzzle =
    'v2_12_4x6_001000000001000000000002_CC:0.1.5;DF:12.right;'
    'EY:15.1.6;EY:7.1.5;GS:15.1;LT:B.20.13;NC:10.1.4;PA:9.right;QA:2.7;'
    'SH:2;SY:19.1_1:121111111121211211211212_30';

void main() {
  group('rotateIdx90CW', () {
    test('top-left corner of a 4x3 grid → top-right of the rotated 3x4', () {
      // (col=0, row=0) on (W=4, H=3) becomes (newCol=H-1-row=2, newRow=col=0)
      // on a 3x4 grid → newIdx = 0 * 3 + 2 = 2.
      expect(rotateIdx90CW(0, 4, 3), 2);
    });

    test('top-right corner becomes bottom-right after 90° CW', () {
      // (col=3, row=0) → (newCol=2, newRow=3) on 3x4 → newIdx = 3*3+2 = 11.
      expect(rotateIdx90CW(3, 4, 3), 11);
    });

    test('bottom-left corner becomes top-left after 90° CW', () {
      // (col=0, row=2) on (4, 3) → (newCol=0, newRow=0) → newIdx = 0.
      expect(rotateIdx90CW(8, 4, 3), 0);
    });

    test('four 90° rotations compose to identity', () {
      // For every cell, rotating 4 times must return to the start. Property
      // holds for any rectangular shape; we verify on a non-square 5x3.
      const w = 5, h = 3;
      for (int idx = 0; idx < w * h; idx++) {
        final r1 = rotateIdx90CW(idx, w, h);
        final r2 = rotateIdx90CW(r1, h, w);
        final r3 = rotateIdx90CW(r2, w, h);
        final r4 = rotateIdx90CW(r3, h, w);
        expect(r4, idx, reason: 'idx=$idx');
      }
    });
  });

  group('rotate2D90CW', () {
    test(
      'a 2x3 motif rotates into a 3x2 motif with values mapped correctly',
      () {
        // Source:                  Expected (90° CW):
        //   1 2 3                    4 1
        //   4 5 6                    5 2
        //                            6 3
        final src = [
          [1, 2, 3],
          [4, 5, 6],
        ];
        final rotated = rotate2D90CW(src);
        expect(rotated, [
          [4, 1],
          [5, 2],
          [6, 3],
        ]);
      },
    );
  });

  group('Constraint.rotated — 4-fold identity per slug', () {
    // Every constraint must be equivalent to itself after four 90° rotations.
    // We check by serializing: rotation must come back to the original string.
    // (W=4, H=3) is non-square so rotation actually swaps dimensions; doing
    // it four times comes back to (4, 3) and the constraint must match.
    const w = 4, h = 3;

    test('QuantityConstraint (QA) — global, identity under rotation', () {
      final c = QuantityConstraint('1.5');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('GroupCountConstraint (GC) — global, identity under rotation', () {
      final c = GroupCountConstraint('2.3');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('GroupSize (GS) — index transforms back after 4 rotations', () {
      final c = GroupSize('5.4');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('LetterGroup (LT) — every index transforms back', () {
      final c = LetterGroup('A.0.5.11');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('NeighborCountConstraint (NC) — index transforms back', () {
      final c = NeighborCountConstraint('7.1.2');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('EyesConstraint (EY) — index transforms back', () {
      final c = EyesConstraint('5.2.3');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('ShapeConstraint (SH) — invariant under rotation', () {
      // SH is rotation-agnostic by design (its `variants` field already
      // covers all 8 rotation/mirror equivalents), so rotated() returns a
      // clone with the same serialization regardless of the rotation count.
      final c = ShapeConstraint('111.010');
      final r = c.rotated(w, h);
      expect(r.serialize(), c.serialize());
    });

    test(
      'ColumnCountConstraint (CC) — round-trips via RC after 2 rotations',
      () {
        // CC at column c → RC at row c (one rotation). After another rotation,
        // RC at row c → CC at column (origHeight - 1 - c). After 4 rotations
        // we must be back to the original CC.
        final c = ColumnCountConstraint('2.1.3');
        final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
        expect(r.serialize(), c.serialize());
      },
    );

    test('RowCountConstraint (RC) — round-trips via CC after 2 rotations', () {
      final c = RowCountConstraint('1.2.4');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });

    test('ParityConstraint (PA) — side cycles back after 4 rotations', () {
      // PA sides cycle: left→top→right→bottom→left (4-cycle). And
      // horizontal↔vertical (2-cycle, so 4 rotations also identity).
      for (final side in [
        'left',
        'right',
        'top',
        'bottom',
        'horizontal',
        'vertical',
      ]) {
        final c = ParityConstraint('5.$side');
        final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
        expect(r.serialize(), c.serialize(), reason: 'side=$side');
      }
    });

    test(
      'DifferentFromConstraint (DF) — direction cycles via anchor shift',
      () {
        // DF.right and DF.down each map to the other; after 4 rotations the
        // anchor and direction must return to the original.
        // Right at idx 5 (col=1, row=1 on 4x3): pair (5, 6).
        final c1 = DifferentFromConstraint('5.right');
        final r1 = c1.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
        expect(r1.serialize(), c1.serialize());

        // Down at idx 1 (col=1, row=0 on 4x3): pair (1, 5).
        final c2 = DifferentFromConstraint('1.down');
        final r2 = c2.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
        expect(r2.serialize(), c2.serialize());
      },
    );

    test('SymmetryConstraint (SY) — axes cycle back after 4 rotations', () {
      for (int axis = 1; axis <= 5; axis++) {
        final c = SymmetryConstraint('6.$axis');
        final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
        expect(r.serialize(), c.serialize(), reason: 'axis=$axis');
      }
    });

    test('ForbiddenMotif (FM) — 2D pattern rotates back after 4 rotations', () {
      // 2x3 asymmetric motif so rotation is non-trivial.
      final c = ForbiddenMotif('120.012');
      final r = c.rotated(w, h).rotated(h, w).rotated(w, h).rotated(h, w);
      expect(r.serialize(), c.serialize());
    });
  });

  group('Puzzle.rotated — 4-fold identity', () {
    // Rotating a puzzle four times must return to a logically equivalent
    // puzzle. Since cell prefill, constraint set and dimensions are all
    // restored, the canonical key is the right invariant to compare.
    test('square 4x4 puzzle returns to canonical form after 4 rotations', () {
      final p = Puzzle(_squarePuzzle);
      final r = p.rotated().rotated().rotated().rotated();
      expect(
        canonicalPuzzleKey(r.lineRepresentation),
        canonicalPuzzleKey(p.lineRepresentation),
      );
    });

    test(
      'landscape 6x5 puzzle returns to canonical form after 4 rotations',
      () {
        final p = Puzzle(_landscapePuzzle);
        final r = p.rotated().rotated().rotated().rotated();
        expect(
          canonicalPuzzleKey(r.lineRepresentation),
          canonicalPuzzleKey(p.lineRepresentation),
        );
      },
    );

    test('portrait 4x6 puzzle returns to canonical form after 4 rotations', () {
      final p = Puzzle(_portraitPuzzle);
      final r = p.rotated().rotated().rotated().rotated();
      expect(
        canonicalPuzzleKey(r.lineRepresentation),
        canonicalPuzzleKey(p.lineRepresentation),
      );
    });

    test('rotation swaps dimensions on a non-square puzzle', () {
      final p = Puzzle(_landscapePuzzle);
      final r = p.rotated();
      expect(r.width, p.height);
      expect(r.height, p.width);
    });
  });

  group('Puzzle.rotated preserves solubility', () {
    // For each puzzle, verify that solving the rotated form produces the
    // rotation of the original solution. This is the strongest end-to-end
    // check that the constraint rotation logic is consistent: any mistake
    // in any per-constraint rotation breaks deductive solvability.

    void expectRotatedSolveMatches(String line) {
      final original = Puzzle(line);
      final rotated = Puzzle(line).rotated();

      // Solve both copies independently with the unified solver
      // (propagation + force, no backtracking). All real puzzles in
      // assets/ are deductively solvable, so both must succeed.
      expect(
        original.solve(),
        isTrue,
        reason: 'original puzzle should be deductively solvable',
      );
      expect(
        rotated.solve(),
        isTrue,
        reason: 'rotated puzzle should be deductively solvable',
      );

      // Every solved cell of the original must equal the solved cell at
      // the rotated index in the rotated puzzle.
      for (int origIdx = 0; origIdx < original.cells.length; origIdx++) {
        final newIdx = rotateIdx90CW(origIdx, original.width, original.height);
        expect(
          rotated.cellValues[newIdx],
          original.cellValues[origIdx],
          reason: 'cell origIdx=$origIdx mismatched after rotation',
        );
      }
    }

    test('square puzzle: rotated solution = rotation of original solution', () {
      expectRotatedSolveMatches(_squarePuzzle);
    });

    test(
      'landscape puzzle: rotated solution = rotation of original solution',
      () {
        expectRotatedSolveMatches(_landscapePuzzle);
      },
    );

    test(
      'portrait puzzle: rotated solution = rotation of original solution',
      () {
        expectRotatedSolveMatches(_portraitPuzzle);
      },
    );
  });

  group('canonicalPuzzleKey rotation invariance', () {
    // The canonical key is rotation-invariant: a puzzle and its 90° rotation
    // must produce the same key, so that stats stay shared across the auto-
    // rotation triggered by screen orientation mismatches.
    void expectSameKeyAsRotation(String line) {
      final rotatedLine = Puzzle(line).rotated().lineRepresentation;
      expect(
        canonicalPuzzleKey(rotatedLine),
        canonicalPuzzleKey(line),
        reason: 'rotated form should canonicalize to the same key',
      );
    }

    test('square puzzle and its 90° rotation share one canonical key', () {
      expectSameKeyAsRotation(_squarePuzzle);
    });

    test('landscape puzzle and its 90° rotation share one canonical key', () {
      expectSameKeyAsRotation(_landscapePuzzle);
    });

    test('portrait puzzle and its 90° rotation share one canonical key', () {
      expectSameKeyAsRotation(_portraitPuzzle);
    });
  });
}
