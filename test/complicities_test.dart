import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/fmfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/gsall.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/gsgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/ltgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/pafm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/shgs.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/syfm.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

void main() {
  // LT:A on cells 6,0 (rows 2 and 0) + FM:2.2 (vertical 2s forbidden)
  // → A must be color 1 (black), because a path of 2s can't cross rows.
  const puzzleLine = 'v2_12_3x3_000000000_LT:A.6.0;FM:2.2;LT:B.5.4_0:0_100';

  test('LTFMComplicity is detected on cross-row LT + vertical FM', () {
    final puzzle = Puzzle(puzzleLine);
    expect(puzzle.complicities, hasLength(1));
    expect(puzzle.complicities.first, isA<LTFMComplicity>());
  });

  test('LTFMComplicity.apply forces LT:A to black (color 1)', () {
    final puzzle = Puzzle(puzzleLine);
    final move = puzzle.complicities.first.apply(puzzle);

    expect(move, isNotNull);
    final ltA = puzzle.constraints.whereType<LetterGroup>().first;
    expect(ltA.letter, 'A');

    expect(move!.isImpossible, isNull);
    // The move targets one of LT:A's cells (6 or 0)…
    expect(ltA.indices, contains(move.idx));
    // …with color 1 (black)…
    expect(move.value, 1);
    // …and is given by the complicity itself, not a Constraint.
    expect(move.givenBy, puzzle.complicities.first);
    // Combination deduction: weight tier 3 (per docs/dev/complexity.md).
    expect(move.complexity, 3);
  });

  test('LTFMComplicity is not detected when FM direction does not match', () {
    // LT:A spans rows (cells 6 and 0, both at col 0 but rows 0 and 2).
    // The connecting path must include a vertical step. FM:22 is a
    // horizontal pair — it blocks horizontal adjacency, not vertical —
    // so the complicity must NOT trigger here.
    final puzzle = Puzzle('v2_12_3x3_000000000_LT:A.6.0;FM:22_0:0_100');
    expect(puzzle.complicities, isEmpty);
  });

  test(
    'Puzzle.apply() falls through to complicities when constraints stuck',
    () {
      final puzzle = Puzzle(puzzleLine);
      // None of the regular constraints can deduce anything on this empty
      // grid, but the complicity can.
      final move = puzzle.apply();
      expect(move, isNotNull);
      expect(move!.givenBy, isA<LTFMComplicity>());
    },
  );

  group('PAFMComplicity', () {
    test('detected with vertical FM + top PA', () {
      // 3x3, FM:2.1 forces columns to read `1* 2*` (top to bottom).
      // PA:8.top = parity on column 2 above cell 8 (rows 0..1, length 2).
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:2.1;PA:8.top_0:0_100');
      expect(puzzle.complicities.whereType<PAFMComplicity>(), hasLength(1));
    });

    test('apply forces vertical pattern (FM:2.1, PA:8.top)', () {
      // Top side of length 2 on column 2: cells [2, 5]. Pattern is
      // (1, 2) → cell 2 must be 1 (first half), cell 5 must be 2.
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:2.1;PA:8.top_0:0_100');
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      final move = pafm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 2);
      expect(move.value, 1);
      expect(move.complexity, 3);
    });

    test('apply forces horizontal pattern (FM:21, PA:N.right)', () {
      // FM:21 forces rows to read `1* 2*`. PA:0.right is the row 0
      // segment to the right of cell 0 — cells [1, 2] on a 3x3 grid.
      // First half = 1, second half = 2 → cell 1 must be 1.
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:21;PA:0.right_0:0_100');
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      final move = pafm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 1);
    });

    test('apply returns null when FM and PA axes are orthogonal', () {
      // FM:21 is horizontal, PA:8.top is vertical. The FM doesn't
      // restrict any vertical configuration of the side, so every
      // balanced colouring survives the enumeration → no force.
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:21;PA:8.top_0:0_100');
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      expect(pafm.apply(puzzle), isNull);
    });

    test('apply returns null when FM does not bind on the side', () {
      // FM:11 forbids two horizontal 1s. PA:0.right is on a 2-cell
      // horizontal side (cells 1, 2). The two configurations 1,2 and
      // 2,1 are both safe for FM:11 (no horizontal pair of 1s either
      // way). Both survive → nothing forced.
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:11;PA:0.right_0:0_100');
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      expect(pafm.apply(puzzle), isNull);
    });

    test('skips already-correct cells and fills the next empty one', () {
      // 3x3, FM:2.1 → columns are `1* 2*`. PA:14.top on a 5x4 grid
      // would be too long; use a wider example: 5x4 grid, PA:14.top
      // means column 2 above row 3, rows 0..2 (length 3, odd → skipped).
      // Switch to a length-4 vertical: 5x5 grid, PA:22.top, col 2 rows
      // 0..3, length 4. Pattern (1, 2): expected = [1, 1, 2, 2].
      // Pre-fill cell 2 (row 0 col 2) with 1; the apply must target
      // the first non-matching empty: cell 7 (row 1 col 2) = 1.
      final puzzle = Puzzle(
        'v2_12_5x5_0010000000000000000000000_FM:2.1;PA:22.top_0:0_100',
      );
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      final move = pafm.apply(puzzle);
      expect(move, isNotNull);
      // Column 2 indices on a 5-wide grid: [2, 7, 12, 17, 22].
      // Anchor 22 → top side rows 0..3 → [2, 7, 12, 17]. Cell 2 is
      // already 1 (matches first half) → next empty is 7, also 1.
      expect(move!.idx, 7);
      expect(move.value, 1);
    });

    test('apply returns null when 3-cell FM leaves multiple survivors', () {
      // 3x5 grid (width 3, height 5). PA:13.top is the col-1 segment
      // rows 0..3 → cells [1, 4, 7, 10] (4 cells, parity 2/2).
      // FM:1.2.2 (vertical 1-2-2 forbidden) eliminates the configs
      // 1,1,2,2 and 1,2,2,1 — four survive: 1,2,1,2 / 2,1,1,2 /
      // 2,1,2,1 / 2,2,1,1. No free cell takes the same value across
      // every survivor, so the complicity declines to force.
      final puzzle = Puzzle(
        'v2_12_3x5_000000000000000_PA:13.top;FM:1.2.2_0:0_100',
      );
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      expect(pafm.apply(puzzle), isNull);
    });

    test(
      'apply collapses 3-cell FM survivors to one when an adjacent cell is fixed',
      () {
        // Same setup, but cell 1 is pre-coloured 1 (the puzzle from
        // bin/measure_complicities.dart's exploration). Of the four
        // FM-compatible configs, only (1,2,1,2) starts with cell 1 = 1.
        // The complicity must now force cell 4 = 2 (the next empty
        // free position with a uniquely determined value).
        final puzzle = Puzzle(
          'v2_12_3x5_010000000000000_PA:13.top;FM:1.2.2_0:0_100',
        );
        final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
        final move = pafm.apply(puzzle);
        expect(move, isNotNull);
        expect(move!.idx, 4);
        expect(move.value, 2);
        expect(move.complexity, 3);
      },
    );

    test('apply reports impossibility when no configuration survives', () {
      // 3x3, PA:0.right is the 2-cell side [1, 2]. FM:12 (horizontal
      // 1-2) AND FM:21 (horizontal 2-1) together rule out both
      // possible balanced fills (1,2 and 2,1) → no survivor.
      final puzzle = Puzzle(
        'v2_12_3x3_000000000_PA:0.right;FM:12;FM:21_0:0_100',
      );
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      final move = pafm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('apply uses an FM with a wildcard touching a pre-coloured cell', () {
      // 3x3 grid, cell 7 = 1. FM:12.01 forbids the 2x2 pattern
      //   1 2
      //   ? 1
      // PA:5.left is the row-1 side cells [3, 4]. Of the two balanced
      // configs, (3=1, 4=2) lines up with the FM (the wildcard sits
      // on cell 6, the trailing 1 lines up with the pre-coloured cell
      // 7). Only (3=2, 4=1) survives → cell 3 is forced to 2.
      final puzzle = Puzzle('v2_12_3x3_000000010_FM:12.01;PA:5.left_0:0_100');
      final pafm = puzzle.complicities.whereType<PAFMComplicity>().first;
      final move = pafm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 3);
      expect(move.value, 2);
      expect(move.complexity, 3);
    });
  });

  group('SHGSComplicity', () {
    test('detected when SH and GS sizes disagree', () {
      // SH:111 → color 1 must form 3-cell shapes. GS:0.2 says cell 0
      // is in a 2-cell group → cell 0 cannot be 1. The complicity is
      // present.
      final puzzle = Puzzle('v2_12_3x3_000000000_SH:111;GS:0.2_0:0_100');
      expect(puzzle.complicities.whereType<SHGSComplicity>(), hasLength(1));
    });

    test('not detected when SH and GS sizes agree', () {
      // SH:111 (size 3) + GS:0.3 (size 3): both already agree, no
      // cross-deduction available.
      final puzzle = Puzzle('v2_12_3x3_000000000_SH:111;GS:0.3_0:0_100');
      expect(puzzle.complicities.whereType<SHGSComplicity>(), isEmpty);
    });

    test('apply forces opposite colour when only one SH disagrees', () {
      // SH:111 (color 1, size 3) + GS:0.2 → cell 0 must be 2.
      final puzzle = Puzzle('v2_12_3x3_000000000_SH:111;GS:0.2_0:0_100');
      final shgs = puzzle.complicities.whereType<SHGSComplicity>().first;
      final move = shgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 0);
      expect(move.value, 2);
      expect(move.complexity, 3);
    });

    test('apply reports impossibility when both SHs disagree', () {
      // SH:111 (color 1, size 3) + SH:22 (color 2, size 2) + GS:0.4 →
      // cell 0 can be neither colour → impossible.
      final puzzle = Puzzle('v2_12_3x3_000000000_SH:111;SH:22;GS:0.4_0:0_100');
      final shgs = puzzle.complicities.whereType<SHGSComplicity>().first;
      final move = shgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('skips GS anchors that are already coloured', () {
      // GS:0.2 anchor cell 0 is already 2 (consistent: cell 0 is the
      // opposite of the SH:111 colour, so SH-vs-GS doesn't apply).
      // No further deduction at cell 0 → returns null.
      final puzzle = Puzzle('v2_12_3x3_200000000_SH:111;GS:0.2_0:0_100');
      final shgs = puzzle.complicities.whereType<SHGSComplicity>().first;
      final move = shgs.apply(puzzle);
      expect(move, isNull);
    });
  });

  group('SYFMComplicity', () {
    test('detected on any SY + FM combo', () {
      final puzzle = Puzzle('v2_12_3x3_000010000_SY:4.4;FM:1.1.1_0:0_100');
      expect(puzzle.complicities.whereType<SYFMComplicity>(), hasLength(1));
    });

    test('not detected when only SY is present', () {
      final puzzle = Puzzle('v2_12_3x3_000010000_SY:4.4_0:0_100');
      expect(puzzle.complicities.whereType<SYFMComplicity>(), isEmpty);
    });

    test('apply forces opposite when SY mirror + FM trips a triple', () {
      // Anchor cell 4 (centre, value 1) with axis=4 (horizontal mirror,
      // i.e. mirror across the anchor's row). FM:1.1.1 forbids three
      // vertical 1s.
      // Free neighbour cell 1 (above anchor) → mirror = cell 7 (below).
      // Hypothesis: cell 1 = 1 + cell 7 = 1, with anchor cell 4 = 1.
      // Column 1 reads 1, 1, 1 → FM:1.1.1 violated → cell 1 must be 2.
      final puzzle = Puzzle('v2_12_3x3_000010000_SY:4.4;FM:1.1.1_0:0_100');
      final syfm = puzzle.complicities.whereType<SYFMComplicity>().first;
      final move = syfm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 2);
      expect(move.complexity, 4);
    });

    test('apply does nothing when anchor colour is unknown', () {
      // Same setup as above, but the anchor (cell 4) is not pre-filled.
      // Without the anchor colour we cannot drive the symmetry argument.
      final puzzle = Puzzle('v2_12_3x3_000000000_SY:4.4;FM:1.1.1_0:0_100');
      final syfm = puzzle.complicities.whereType<SYFMComplicity>().first;
      final move = syfm.apply(puzzle);
      expect(move, isNull);
    });

    test('apply does nothing when FM does not catch the triple', () {
      // SY config that would create a vertical triple of 1s, but the
      // FM (FM:11) only forbids horizontal 2-pairs. Vertical triples
      // are allowed → no deduction.
      final puzzle = Puzzle('v2_12_3x3_000010000_SY:4.4;FM:11_0:0_100');
      final syfm = puzzle.complicities.whereType<SYFMComplicity>().first;
      final move = syfm.apply(puzzle);
      expect(move, isNull);
    });

    test(
      'empty anchor: forces a cell shared across both colour hypotheses',
      () {
        // 3×3 grid:
        //   . . .
        //   2 1 .
        //   1 . 1
        // FM:01.20 forbids the 2×2 pattern (?, 1, 2, ?). SY:7.2 has its
        // anchor (cell 7) empty, axis 2 = vertical mirror through col 1.
        //
        // Anchor = 1 hypothesis: cell 7 = 1, anchor's group is
        // {4, 6, 7, 8}. SY.apply notices that cell 3 = 2 is adjacent
        // to the group and forces its mirror (cell 5) to 2.
        // Anchor = 2 hypothesis: cell 7 = 2. The 2×2 window at (1, 1)
        // becomes (1, ?, 2, 1) — FM.apply forces cell 5 to NOT 1 → 2.
        //
        // Both hypotheses determine cell 5 = 2 (and cell 1 = 2 also
        // ends up forced). The complicity surfaces the lowest-indexed
        // unanimously-determined free cell (cell 1).
        final puzzle = Puzzle('v2_12_3x3_000210101_FM:01.20;SY:7.2_0:0_100');
        final syfm = puzzle.complicities.whereType<SYFMComplicity>().first;
        final move = syfm.apply(puzzle);
        expect(move, isNotNull);
        expect(move!.isImpossible, isNull);
        expect(move.complexity, 4);
        // The forced value must be 2 — that's the unanimous outcome
        // of both hypotheses for the cells we expect to be determined.
        expect(move.value, 2);
      },
    );

    test('empty anchor: forces the anchor when one colour is infeasible', () {
      // 3×3 grid with a configuration that makes only one anchor
      // colour feasible. We use the same setup as the user's
      // example but pre-fill cell 5 = 1 so that anchor = 1 directly
      // contradicts (cell 5 in group + cell 5 sym = cell 3 = 2 ≠ 1).
      // Anchor = 2 stays feasible. Therefore the anchor is forced
      // to 2.
      final puzzle = Puzzle('v2_12_3x3_000211101_FM:01.20;SY:7.2_0:0_100');
      final syfm = puzzle.complicities.whereType<SYFMComplicity>().first;
      final move = syfm.apply(puzzle);
      expect(move, isNotNull);
      // The complicity might force the anchor (cell 7) directly, or
      // a downstream cell determined by both hypotheses; either way
      // the move's value must be 2.
      expect(move!.value, 2);
    });
  });

  group('LTGSComplicity', () {
    test('detected when GS is at an LT cell with insufficient size', () {
      // LT:A on cells 0 and 8 (3x3, opposite corners, Manhattan = 4).
      // GS:0.2 — group size 2, but at least 5 cells are needed to
      // connect (0,0) to (2,2). Impossibility → complicity present.
      final puzzle = Puzzle(
        'v2_12_3x3_000000000_LT:A.0.8;GS:0.2;LT:B.4.1_0:0_100',
      );
      expect(puzzle.complicities.whereType<LTGSComplicity>(), hasLength(1));
    });

    test('apply reports impossibility when GS size is too small', () {
      // Same setup as above; apply must return an isImpossible move.
      final puzzle = Puzzle(
        'v2_12_3x3_000000000_LT:A.0.8;GS:0.2;LT:B.4.1_0:0_100',
      );
      final ltgs = puzzle.complicities.whereType<LTGSComplicity>().first;
      final move = ltgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('apply forces line cells when LT colour is known and GS fits', () {
      // LT:A on cells 0 and 2 (3x3, same row, Manhattan = 2). GS:0.3
      // — exact fit. Cell 0 is pre-filled with 1, so the line colour
      // is known. Cell 1 (between 0 and 2) must be 1. The complicity
      // must surface that.
      final puzzle = Puzzle(
        'v2_12_3x3_100000000_LT:A.0.2;GS:0.3;LT:B.4.7_0:0_100',
      );
      final ltgs = puzzle.complicities.whereType<LTGSComplicity>().first;
      final move = ltgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 1);
      expect(move.complexity, 4);
    });

    test('not detected when GS size is loose', () {
      // GS:0.5 leaves slack — the group can have more than the
      // strict minimum, so the complicity has nothing to add over the
      // base constraints.
      final puzzle = Puzzle(
        'v2_12_3x3_000000000_LT:A.0.2;GS:0.5;LT:B.4.7_0:0_100',
      );
      expect(puzzle.complicities.whereType<LTGSComplicity>(), isEmpty);
    });

    test('not detected when GS is on a non-LT cell', () {
      // GS:4.2 anchors on the centre, which is not part of LT:A.
      // The complicity only fires when GS shares a cell with LT.
      final puzzle = Puzzle(
        'v2_12_3x3_000000000_LT:A.0.2;GS:4.2;LT:B.6.7_0:0_100',
      );
      expect(puzzle.complicities.whereType<LTGSComplicity>(), isEmpty);
    });

    test('apply forces interior cells of a 3-cell collinear LT', () {
      // 4x1 grid (4 columns, 1 row). LT:A on the three cells 0, 1, 3
      // (parser sees them as members of the same letter A; aggregation
      // merges them into one LetterGroup with indices = [0, 1, 3]).
      // All on row 0 → collinear. Min group size = 4 (cells 0..3).
      // GS:0.4 fits exactly. With cell 0 already coloured 1, the
      // complicity must force cell 2 (the only empty interior cell).
      final puzzle = Puzzle('v2_12_4x1_1000_LT:A.0.1;LT:A.1.3;GS:0.4_0:0_100');
      final ltgs = puzzle.complicities.whereType<LTGSComplicity>().first;
      final move = ltgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 2);
      expect(move.value, 1);
    });
  });

  group('GSGSComplicity', () {
    test('detected when adjacent GSs have different sizes', () {
      final puzzle = Puzzle(
        'v2_12_5x5_0000000000000000000000000_GS:0.3;GS:1.5_0:0_100',
      );
      expect(puzzle.complicities.whereType<GSGSComplicity>(), hasLength(1));
    });

    test('not detected when adjacent GSs have equal sizes', () {
      final puzzle = Puzzle(
        'v2_12_5x5_0000000000000000000000000_GS:0.3;GS:1.3_0:0_100',
      );
      expect(puzzle.complicities.whereType<GSGSComplicity>(), isEmpty);
    });

    test('not detected when GSs are not adjacent', () {
      // Cells 0 and 8 are diagonal corners in a 3x3 (not 4-neighbours).
      final puzzle = Puzzle('v2_12_3x3_000000000_GS:0.3;GS:8.5_0:0_100');
      expect(puzzle.complicities.whereType<GSGSComplicity>(), isEmpty);
    });

    test('apply forces opposite when one anchor is coloured', () {
      // 5x5 grid roomy enough that GS reachability doesn't fire first.
      // Cell 0 = 1, GS:0.3 + GS:1.5 → cell 1 must be 2 (sharing a
      // group is impossible because the sizes disagree).
      final puzzle = Puzzle(
        'v2_12_5x5_1000000000000000000000000_GS:0.3;GS:1.5_0:0_100',
      );
      final gsgs = puzzle.complicities.whereType<GSGSComplicity>().first;
      final move = gsgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 1);
      expect(move.value, 2);
      expect(move.complexity, 3);
    });

    test('apply reports impossibility when both anchors share a colour', () {
      // Both anchors already coloured 1 with different size targets:
      // a single group of two conflicting sizes — impossible.
      final puzzle = Puzzle(
        'v2_12_5x5_1100000000000000000000000_GS:0.3;GS:1.5_0:0_100',
      );
      final gsgs = puzzle.complicities.whereType<GSGSComplicity>().first;
      final move = gsgs.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('apply does nothing when both anchors are empty', () {
      // We know they must be different colours but cannot pick a
      // specific value yet. The complicity returns null and waits for
      // a later step to colour one of them.
      final puzzle = Puzzle(
        'v2_12_5x5_0000000000000000000000000_GS:0.3;GS:1.5_0:0_100',
      );
      final gsgs = puzzle.complicities.whereType<GSGSComplicity>().first;
      final move = gsgs.apply(puzzle);
      expect(move, isNull);
    });
  });

  group('GSAllComplicity', () {
    test('detected on any GS + FM combo', () {
      final puzzle = Puzzle('v2_12_3x3_000000211_GS:8.3;FM:12.01_0:0_100');
      expect(puzzle.complicities.whereType<GSAllComplicity>(), hasLength(1));
    });

    test('not detected when no GS is present', () {
      final puzzleNoGS = Puzzle('v2_12_3x3_000000211_FM:12.01_0:0_100');
      expect(puzzleNoGS.complicities.whereType<GSAllComplicity>(), isEmpty);
    });

    test('apply forces a cell via PA+GS interaction (no FM involved)', () {
      // 5x2 grid. Cell 6 = 2 (initial), cell 9 = 2 (initial). PA:5.right
      // covers cells [6, 7, 8, 9] with parity 2/2. GS:9.2 says cell 9's
      // group has size 2.
      // Trying expansion via cell 8 makes cell 8 = 2; together with the
      // pre-coloured cell 6 = 2 the right side has three 2s, breaking
      // PA. Only the {4, 9} expansion survives → cell 4 must be 2.
      final puzzle = Puzzle('v2_12_5x2_0000002002_PA:5.right;GS:9.2_0:0_100');
      final gsall = puzzle.complicities.whereType<GSAllComplicity>().first;
      final move = gsall.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 4);
      expect(move.value, 2);
    });

    test('apply forces an empty anchor when only one colour is feasible', () {
      // 3x3 with cells 2, 4, 6 = 1 (initial). GS:8.2 — cell 8 empty.
      // If cell 8 = 1, every connected expansion of size 2 merges with
      // the existing 1-clusters and overshoots the target → no
      // surviving sealing. If cell 8 = 2, expansions {5, 8} and
      // {7, 8} are both valid → at least one survivor. Therefore the
      // anchor is forced to 2 (the only feasible colour).
      final puzzle = Puzzle('v2_12_3x3_001010100_GS:8.2_0:0_100');
      final gsall = puzzle.complicities.whereType<GSAllComplicity>().first;
      final move = gsall.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 8);
      expect(move.value, 2);
      expect(move.complexity, 4);
    });

    test(
      'apply forces the unique connected expansion that survives FM filtering',
      () {
        // 3x3 grid. Cells 6=2, 7=1, 8=1. GS:8.3 — group of cell 8
        // has size 3. Current group {7, 8} (cell 7 and 8 both 1,
        // adjacent), size 2 → needs 1 more cell. Frontier = {4, 5}.
        // FM:12.01 forbids the 2x2 pattern with `1 2 / ? 1`.
        // Expansion {4, 7, 8}: sealing cell 5 to 2 plus cell 4 = 1
        // creates the forbidden motif at top-left (1, 1) — cells
        // 4=1, 5=2, 7=?(wildcard), 8=1 → MATCH → rejected.
        // Expansion {5, 7, 8}: only valid one. Cell 5 must be 1 (in
        // group), cell 4 must be 2 (sealed border), and the
        // complicity forces the first determined cell (cell 5 → 1).
        final puzzle = Puzzle('v2_12_3x3_000000211_GS:8.3;FM:12.01_0:0_100');
        final gsall = puzzle.complicities.whereType<GSAllComplicity>().first;
        final move = gsall.apply(puzzle);
        expect(move, isNotNull);
        expect(move!.idx, 5);
        expect(move.value, 1);
        expect(move.complexity, 3);
      },
    );

    test('apply does nothing when the anchor is not yet coloured', () {
      // Cell 8 still empty: the complicity needs the anchor's colour
      // to know which colour to grow.
      final puzzle = Puzzle('v2_12_3x3_000000200_GS:8.3;FM:12.01_0:0_100');
      final gsall = puzzle.complicities.whereType<GSAllComplicity>().first;
      expect(gsall.apply(puzzle), isNull);
    });

    test('apply reports impossibility when no expansion survives', () {
      // 3x3, cells 6=2, 7=1, 8=1, GS:8.3 — needs cell 4 or cell 5 for
      // the 1-cell expansion. FM:12.01 rules out cell 4 (as in the
      // earlier test). FM:21.10 forbids the mirrored pattern with
      // `2 1 / 1 ?` at top-right — sealing cell 4 = 2 with cell 5 = 1
      // creates the motif at (1, 1) — cells 4=2, 5=1, 7=1, 8=wildcard
      // → MATCH → rules out the {5, 7, 8} expansion too. No survivor.
      final puzzle = Puzzle(
        'v2_12_3x3_000000211_GS:8.3;FM:12.01;FM:21.10_0:0_100',
      );
      final gsall = puzzle.complicities.whereType<GSAllComplicity>().first;
      final move = gsall.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });
  });

  group('FMFMComplicity', () {
    test('detected when two FMs differ in one cell covering the domain', () {
      // FM:2.2.1 and FM:1.2.1 share the bottom two cells (2 over 1)
      // and differ at the top (2 vs 1) — together they cover the
      // domain. The complicity must be detected and synthesize one
      // motif (FM:0.2.1).
      final puzzle = Puzzle('v2_12_3x4_000000000000_FM:2.2.1;FM:1.2.1_0:0_100');
      expect(puzzle.complicities.whereType<FMFMComplicity>(), hasLength(1));
    });

    test('not detected on a single FM', () {
      final puzzle = Puzzle('v2_12_3x4_000000000000_FM:2.2.1_0:0_100');
      expect(puzzle.complicities.whereType<FMFMComplicity>(), isEmpty);
    });

    test('not detected when FMs differ in more than one cell', () {
      // Different shape and value pattern — no synthesis possible.
      final puzzle = Puzzle('v2_12_3x3_000000000_FM:1.2.1;FM:2.1.2_0:0_100');
      expect(puzzle.complicities.whereType<FMFMComplicity>(), isEmpty);
    });

    test('apply forces a cell via the synthesized motif', () {
      // 3-wide × 4-tall grid. Cell 6 (row 2, col 0) is pre-coloured 1.
      // FM:2.2.1 + FM:1.2.1 synthesize FM:0.2.1 — `(?, 2, 1)` is
      // forbidden whenever a 3-cell vertical window fits. With cell
      // 6 = 1, the window at column 0 / rows 0–2 fixes the bottom
      // (cell 6 = 1); the synthesized motif then forces cell 3
      // (the middle, row 1) away from value 2 → cell 3 = 1.
      final puzzle = Puzzle('v2_12_3x4_000000100000_FM:2.2.1;FM:1.2.1_0:0_100');
      final fmfm = puzzle.complicities.whereType<FMFMComplicity>().first;
      final move = fmfm.apply(puzzle);
      expect(move, isNotNull);
      expect(move!.idx, 3);
      expect(move.value, 1);
      expect(move.complexity, 4);
      // The move is attributed to the complicity itself, not to a
      // synthetic FM that the player would not see.
      expect(move.givenBy, fmfm);
    });

    test('synthesized motifs do not appear in puzzle.constraints', () {
      // The complicity is internal: the visible constraint list must
      // remain exactly what the player sees on the puzzle line.
      final puzzle = Puzzle('v2_12_3x4_000000000000_FM:2.2.1;FM:1.2.1_0:0_100');
      final fmCount = puzzle.constraints
          .map((c) => c.serialize())
          .where((s) => s.startsWith('FM:'))
          .length;
      expect(fmCount, 2);
    });

    test(
      'synthesized motif does not fire on top rows where the window does not fit',
      () {
        // 3×3 grid with cell 0 = 2 (row 0, col 0) and cell 3 = 1
        // (row 1, col 0): a vertical (2, 1) pair at the very top of
        // the grid. The two FMs synthesize FM:0.2.1, whose 3-cell
        // window must fit entirely inside the grid — the (2, 1) at
        // rows 0–1 would need a wildcard row at -1, so the motif
        // simply cannot match here.
        //
        // Naively reducing the two FMs to FM:2.1 (a 2-cell motif)
        // would fire on this configuration and force the puzzle to
        // be impossible — that would be a soundness bug. The test
        // pins down that we keep the full 3-cell window and stay
        // silent on top-row pairs.
        final puzzle = Puzzle('v2_12_3x3_200100000_FM:2.2.1;FM:1.2.1_0:0_100');
        final fmfm = puzzle.complicities.whereType<FMFMComplicity>().first;
        expect(fmfm.apply(puzzle), isNull);
      },
    );
  });
}
