import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Helper: parse a shape string like "111" or "10.11" into a 2D list.
List<List<int>> _parse(String s) {
  return s
      .split('.')
      .map((row) => row.split('').map(int.parse).toList())
      .toList();
}

/// Build a puzzle from a grid string (domain [1,2]).
/// Each digit is a cell value (0=empty, 1=black, 2=white), rows separated by
/// newlines.
Puzzle _make(String grid) {
  final rows = grid
      .trim()
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  final h = rows.length;
  final w = rows.first.length;
  final p = Puzzle.empty(w, h, [1, 2]);
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      final v = int.parse(rows[r][c]);
      if (v != 0) {
        p.cells[r * w + c].setForSolver(v);
      }
    }
  }
  return p;
}

void main() {
  group('allRotations', () {
    test(
      'horizontal line produces 2 distinct variants (horizontal + vertical)',
      () {
        // "111" → horizontal 1×3 and vertical 3×1, nothing else.
        final variants = allRotations(_parse('111'));
        expect(variants.length, 2);
        expect(variants, contains(equals(_parse('111'))));
        expect(variants, contains(equals(_parse('1.1.1'))));
      },
    );

    test('L-shape produces 4 distinct variants', () {
      // "10.11" (L-shape): mirror of L = J, and each rotation is distinct.
      // 4 rotations cover both L and J orientations.
      //   1 0    1 1    1 1    0 1
      //   1 1    1 0    0 1    1 1
      final variants = allRotations(_parse('10.11'));
      expect(variants.length, 4);
      expect(variants, contains(equals(_parse('10.11'))));
      expect(variants, contains(equals(_parse('11.10'))));
      expect(variants, contains(equals(_parse('11.01'))));
      expect(variants, contains(equals(_parse('01.11'))));
    });

    test('2x2 square produces 1 variant (fully symmetric)', () {
      final variants = allRotations(_parse('11.11'));
      expect(variants.length, 1);
      expect(variants.first, equals(_parse('11.11')));
    });

    test('S-shape produces 4 distinct variants', () {
      // "01.11.10" is an S-shape. 180° rotation gives back the same shape,
      // so S has 2 distinct rotations. Its mirror (Z) also has 2 distinct
      // rotations, giving 4 total variants.
      final variants = allRotations(_parse('01.11.10'));
      expect(variants.length, 4);
      expect(variants, contains(equals(_parse('01.11.10'))));
      expect(variants, contains(equals(_parse('110.011'))));
      expect(variants, contains(equals(_parse('10.11.01'))));
      expect(variants, contains(equals(_parse('011.110'))));
    });

    test('T-shape produces 4 distinct variants', () {
      // "111.010" is a T. 4 rotations are all distinct, mirror of T = itself.
      //   1 1 1    0 1 0    0 1    1 0
      //   0 1 0    1 1 1    1 1    1 1
      //                     0 1    1 0
      final variants = allRotations(_parse('111.010'));
      expect(variants.length, 4);
      expect(variants, contains(equals(_parse('111.010'))));
      expect(variants, contains(equals(_parse('010.111'))));
      expect(variants, contains(equals(_parse('01.11.01'))));
      expect(variants, contains(equals(_parse('10.11.10'))));
    });

    test('single cell produces 1 variant', () {
      final variants = allRotations(_parse('1'));
      expect(variants.length, 1);
      expect(variants.first, equals(_parse('1')));
    });

    test('preserves color value 2', () {
      // "222" should produce 2 variants with 2s: horizontal and vertical.
      final variants = allRotations(_parse('222'));
      expect(variants.length, 2);
      expect(variants, contains(equals(_parse('222'))));
      expect(variants, contains(equals(_parse('2.2.2'))));
    });
  });

  group('normalizeShape', () {
    test('horizontal and vertical lines have same canonical form', () {
      // "111" (horizontal) and "1.1.1" (vertical) are related by 90° rotation.
      final h = normalizeShape(_parse('111'));
      final v = normalizeShape(_parse('1.1.1'));
      expect(h, equals(v));
    });

    test('all rotations of L produce same canonical form', () {
      final forms = ['10.11', '11.01', '11.10', '01.11'];
      final canonicals = forms.map((f) => normalizeShape(_parse(f))).toList();
      for (final c in canonicals) {
        expect(c, equals(canonicals.first));
      }
    });

    test(
      'S-shape and Z-shape have same canonical form (mirror equivalence)',
      () {
        // S: "01.11.10", Z: "10.11.01"
        final s = normalizeShape(_parse('01.11.10'));
        final z = normalizeShape(_parse('10.11.01'));
        expect(s, equals(z));
      },
    );

    test('different shapes have different canonical forms', () {
      // Line of 3 vs L-shape: not equivalent.
      final line = normalizeShape(_parse('111'));
      final lShape = normalizeShape(_parse('11.10'));
      expect(line, isNot(equals(lShape)));
    });

    test('different colors have different canonical forms', () {
      // "111" (black) vs "222" (white): same geometry but different color.
      final black = normalizeShape(_parse('111'));
      final white = normalizeShape(_parse('222'));
      expect(black, isNot(equals(white)));
    });

    test('trims empty borders before comparing', () {
      // Shape with padding zeros should normalize the same as without.
      final padded = [
        [0, 0, 0],
        [0, 1, 1],
        [0, 0, 0],
      ];
      final clean = normalizeShape(_parse('11'));
      expect(normalizeShape(padded), equals(clean));
    });
  });

  group('shapesAreEquivalent', () {
    test('"110.011" ≡ "011.110" ≡ "10.11.01" (rotation + mirror)', () {
      expect(shapesAreEquivalent(_parse('110.011'), _parse('011.110')), isTrue);
      expect(
        shapesAreEquivalent(_parse('110.011'), _parse('10.11.01')),
        isTrue,
      );
    });

    test('"111" ≡ "1.1.1" (rotation)', () {
      expect(shapesAreEquivalent(_parse('111'), _parse('1.1.1')), isTrue);
    });

    test('"111" ≢ "11.10" (genuinely different)', () {
      expect(shapesAreEquivalent(_parse('111'), _parse('11.10')), isFalse);
    });

    test('"111" ≢ "222" (same geometry, different color)', () {
      expect(shapesAreEquivalent(_parse('111'), _parse('222')), isFalse);
    });
  });

  group('shapeColor', () {
    test('extracts color 1 from black shape', () {
      expect(shapeColor(_parse('10.11')), 1);
    });

    test('extracts color 2 from white shape', () {
      expect(shapeColor(_parse('20.22')), 2);
    });

    test('throws on mixed colors', () {
      expect(() => shapeColor(_parse('12')), throwsA(isA<ArgumentError>()));
    });

    test('throws on empty shape', () {
      expect(() => shapeColor(_parse('0')), throwsA(isA<ArgumentError>()));
    });
  });

  group('ShapeConstraint', () {
    test('parses black horizontal line', () {
      final c = ShapeConstraint('111');
      expect(c.color, 1);
      expect(c.shapeSize, 3);
      expect(c.slug, 'SH');
      // Canonical form: the lexicographically smallest among "111" and "1.1.1"
      expect(c.motif, equals(_parse('1.1.1')));
      // 2 variants: horizontal and vertical
      expect(c.variants.length, 2);
    });

    test('parses white L-shape', () {
      final c = ShapeConstraint('20.22');
      expect(c.color, 2);
      expect(c.shapeSize, 3);
      expect(c.variants.length, 4);
    });

    test('toString returns canonical form', () {
      // "1.1.1" is the canonical form of a line of 3 (lexicographically < "111")
      final c = ShapeConstraint('111');
      expect(c.toString(), '1.1.1');
    });

    test('serialize preserves original params', () {
      expect(ShapeConstraint('111').serialize(), 'SH:111');
      expect(ShapeConstraint('20.22').serialize(), 'SH:20.22');
    });

    test('toHuman describes the constraint', () {
      expect(ShapeConstraint('111').toHuman(), contains('black'));
      expect(ShapeConstraint('222').toHuman(), contains('white'));
      expect(ShapeConstraint('111').toHuman(), contains('shape'));
    });

    test('equivalent inputs produce same canonical shape', () {
      // "111" and "1.1.1" are the same shape (rotation).
      final a = ShapeConstraint('111');
      final b = ShapeConstraint('1.1.1');
      expect(a.motif, equals(b.motif));
      expect(a.color, equals(b.color));
      expect(a.shapeSize, equals(b.shapeSize));
    });

    test('throws on mixed-color shape', () {
      expect(() => ShapeConstraint('12'), throwsA(isA<ArgumentError>()));
    });
  });

  group('ShapeConstraint.verify', () {
    test('complete puzzle, all groups match shape → true', () {
      // SH:111 = all black groups must be horizontal/vertical lines of 3.
      // Grid 3×3:
      //   1 1 1
      //   2 2 2
      //   1 1 1
      // Two black groups, both are lines of 3.
      final p = _make('111\n222\n111');
      expect(ShapeConstraint('111').verify(p), isTrue);
    });

    test('complete puzzle, group has wrong shape → false', () {
      // SH:111 = line of 3. Grid 3×3:
      //   1 1 2
      //   2 1 2
      //   2 2 2
      // Black group is an L (11.01), not a line.
      final p = _make('112\n212\n222');
      expect(ShapeConstraint('111').verify(p), isFalse);
    });

    test('complete puzzle, group has wrong size → false', () {
      // SH:111 = line of 3. Grid 3×2:
      //   1 1
      //   2 2
      //   2 2
      // Black group has 2 cells, not 3.
      final p = _make('11\n22\n22');
      expect(ShapeConstraint('111').verify(p), isFalse);
    });

    test('complete puzzle, rotated shape matches → true', () {
      // SH:111 = line of 3. Vertical line should also match (rotation).
      // Grid 3×3:
      //   1 2 2
      //   1 2 2
      //   1 2 2
      final p = _make('122\n122\n122');
      expect(ShapeConstraint('111').verify(p), isTrue);
    });

    test('incomplete puzzle, open group compatible → true', () {
      // SH:111 = line of 3. Grid 3×3:
      //   1 1 0
      //   0 0 0
      //   0 0 0
      // Black group of size 2 is open and can still grow into "111".
      final p = _make('110\n000\n000');
      expect(ShapeConstraint('111').verify(p), isTrue);
    });

    test('incomplete puzzle, closed group with wrong shape → false', () {
      // SH:111 = line of 3. Grid 3×3:
      //   1 1 2
      //   2 1 2
      //   2 2 0
      // Black group is closed (all neighbors are filled) and is an L, not
      // a line.
      final p = _make('112\n212\n220');
      expect(ShapeConstraint('111').verify(p), isFalse);
    });

    test('incomplete puzzle, open group too large → false', () {
      // SH:11 = line of 2. Grid 3×3:
      //   1 1 1
      //   0 0 0
      //   0 0 0
      // Black group has 3 cells, shape only allows 2 → already invalid.
      final p = _make('111\n000\n000');
      expect(ShapeConstraint('11').verify(p), isFalse);
    });

    test('incomplete puzzle, open group bbox exceeds all variants → false', () {
      final p = _make('100\n110\n000');
      expect(ShapeConstraint('111').verify(p), isFalse);
    });

    test('incomplete puzzle, open group bbox fits after rotation → true', () {
      final p = _make('100\n100\n000');
      expect(ShapeConstraint('10.11').verify(p), isTrue);
    });

    test(
      'incomplete puzzle, open group geometrically incompatible → false',
      () {
        // SH:10.11 (L-shape). Open group that is a 2×2 square:
        //   1 1 0
        //   1 1 0
        //   0 0 0
        // 4 cells > 3 (shapeSize) → false by cell count.
        final p = _make('110\n110\n000');
        expect(ShapeConstraint('10.11').verify(p), isFalse);
        final p2 = _make('1100\n1100\n0000');
        expect(ShapeConstraint('111.001').verify(p2), isFalse);
      },
    );

    test('white shape constraint ignores black groups', () {
      final p = _make('222\n110\n100');
      expect(ShapeConstraint('222').verify(p), isTrue);
    });

    test('multiple groups, one invalid → false', () {
      // SH:111 = line of 3. Grid 3×4:
      //   1 1 1 2
      //   2 2 2 2
      //   1 1 2 2
      // First black group (row 0): line of 3 → ok.
      // Second black group (row 2): size 2, closed → wrong size → false.
      final p = _make('1112\n2222\n1122');
      expect(ShapeConstraint('111').verify(p), isFalse);
    });

    test('specific scenario', () {
      final p = _make('112\n122\n222');
      expect(ShapeConstraint('11.10').verify(p), isTrue);
      final p2 = _make('112\n212\n222');
      expect(ShapeConstraint('11.10').verify(p2), isTrue);
    });
  });

  group('ShapeConstraint.apply', () {
    test('level 1: closed group wrong shape → impossible', () {
      // SH:111 (line of 3). Closed L-shaped black group:
      //   1 1 2
      //   2 1 2
      //   2 2 0
      final p = _make('112\n212\n220');
      final move = ShapeConstraint('111').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('level 2: open group already matches → close borders', () {
      // SH:111 (line of 3). Black group [0,1,2] is already a line of 3,
      // but cell 3 is free. It must be set to white (opposite).
      //   1 1 1 0
      //   0 0 0 0
      final p = _make('1110\n0000');
      final sh = ShapeConstraint('111');
      final move = sh.apply(p);
      expect(move, isNotNull);
      // The move should set a free neighbor of the group to opposite (white=2).
      expect(move!.value, 2);
      // It should target a free neighbor of the group (cell 3, 4, 5, or 6).
      final groupFreeNeighbors = {3, 4, 5, 6};
      expect(groupFreeNeighbors, contains(move.idx));
    });

    test('level 3: open group too large → impossible', () {
      // SH:11 (line of 2). Open group of 3 black cells:
      //   1 1 1 0
      final p = _make('1110');
      final move = ShapeConstraint('11').apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('level 4: extension would break shape → block neighbor', () {
      final p = _make('110\n000\n000');
      final sh = ShapeConstraint('111');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 2);
      // Cell 3 (right of group) is a valid extension (stays a line) → not blocked.
      // Cell 4 (below cell 0) would create L → blocked.
      // Cell 5 (below cell 1) would create L → blocked.
      // The apply returns the first blocked neighbor it finds.
      expect({3, 4, 5}, contains(move.idx));
    });

    test('level 5: cell in all completions → force color', () {
      // SH:111 (line of 3).
      // Grid 3×1:
      //   1
      //   0
      //   0
      // Only possible completion: vertical line [0,1,2]. Cell 1 is in ALL
      // completions → must be black.
      final p = _make('1\n0\n0');
      final sh = ShapeConstraint('111');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 1);
      expect(move.idx, 1);
    });

    test('level 5: single completion on narrow grid → force mandatory', () {
      // SH:111 (line of 3). Grid 2×3 (width=2), group [0] at top-left:
      //   1 0
      //   0 0
      //   0 0
      // Only completion is vertical [0,2,4] (no horizontal line fits in
      // width=2). Cell 2 is mandatory → forced to black.
      final p = _make('10\n00\n00');
      final sh = ShapeConstraint('111');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 1);
      expect(move.idx, 2);
    });

    test('level 5: no completions on narrow grid → impossible', () {
      // SH:10.11 (L-shape, 3 cells, needs 2×2 bbox). Grid 1×2 (width=1):
      //   1
      //   0
      // No L variant fits in a 1-wide grid → no completions → impossible.
      final p = _make('1\n0');
      final sh = ShapeConstraint('10.11');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('level 5: completion rejected due to merge → block', () {
      // SH:11 (line of 2). Grid 1×3, two groups with a free cell between:
      //   1 0 1
      // Group [0]: only horizontal completion is [0,1], but cell 1 is
      // adjacent to cell 2 (same color, other group) → merge → rejected.
      // Vertical completion needs height≥2, grid is 1 row → impossible.
      // No valid completions for group [0] → impossible.
      //
      // (In this puzzle both black and white on cell 1 lead to violation,
      //  so impossibility is the correct deduction.)
      final p = _make('101');
      final sh = ShapeConstraint('11');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.isImpossible, isNotNull);
    });

    test('level 5: merge-aware blocking preserves valid completions', () {
      // SH:11 (line of 2). Grid 3×3:
      //   0 0 0
      //   1 0 1
      //   0 0 0
      // Groups: [3] at (1,0) and [5] at (1,2). Cell 4 at (1,1) between them.
      //
      // Group [3] completions:
      //   - horizontal [3,4]: cell 4 adj. to [5] → merge → rejected; must be 2
      //   - vertical [0,3]: valid → completion {0}
      //   - vertical [3,6]: valid → completion {6}
      final p = _make('000\n101\n000');
      final sh = ShapeConstraint('11');
      final move = sh.apply(p);
      expect(move, isNotNull);
      expect(move!.value, 2);
      expect(move.idx, 4);
    });

    test(
      'level 5: same-color cell in variant area is separate group → should accept',
      () {
        final p = _make('012\n100\n000');
        final sh = ShapeConstraint('11.10');
        final completions = sh.findAllCompletions([1], p);
        expect(completions.length, 2);
        expect(completions.any((c) => c.length == 1 && c.contains(0)), isTrue);
        expect(completions.any((c) => c.length == 1 && c.contains(4)), isTrue);
      },
    );
    test(
      'level 5: same-color cell in variant area is separate group → should not accept if merged group does not match the constraint',
      () {
        final p = _make('122\n022\n122');
        final sh = ShapeConstraint('110.011');
        final completions = sh.findAllCompletions([0], p);
        expect(completions.length, 0);
      },
    );

    test('level 6: merge of distant groups → block', () {
      // SH:111 (line of 3). Grid 3×3:
      //   1 1 0
      //   0 0 1
      //   0 0 1
      final p = _make('110\n001\n001');
      final sh = ShapeConstraint('111');
      final move = sh.apply(p);
      // L which can't fit in a line-of-3 variant.
      expect(move, isNotNull);
      expect(move!.value, 2);
      expect(move.idx, 3);
    });

    test('apply returns null when no deduction possible', () {
      // SH:111 (line of 3). Fully empty 3×3 grid — no groups yet.
      final p = _make('000\n000\n000');
      final move = ShapeConstraint('111').apply(p);
      expect(move, isNull);
    });

    test('apply ignores groups of other color', () {
      // SH:111 constrains black. White groups can be any shape.
      //   2 2 0
      //   0 2 0
      //   0 0 0
      // White group is an L — but SH:111 only constrains black, so no move.
      final p = _make('220\n020\n000');
      final move = ShapeConstraint('111').apply(p);
      expect(move, isNull);
    });
    group('specific scenario', () {
      test('specific scenario, step 1', () {
        final p = _make('012\n112\n222');
        final move = ShapeConstraint('11.10').apply(p);
        expect(move, isNotNull);
        expect(move!.value, 2);
        expect(move.idx, 0);
      });
      test('specific scenario, step 2', () {
        final p = _make('210\n112\n222');
        final move = ShapeConstraint('11.10').apply(p);
        expect(move, isNotNull);
        expect(move!.value, 2);
        expect(move.idx, 2);
      });
      test('specific scenario, step 3', () {
        final p = _make('212\n110\n222');
        final move = ShapeConstraint('11.10').apply(p);
        expect(move, isNotNull);
        expect(move!.value, 2);
        expect(move.idx, 5);
      });
      test('specific scenario, step 4', () {
        final p = _make('212\n112\n022');
        final move = ShapeConstraint('11.10').apply(p);
        expect(move, isNotNull);
        expect(move!.value, 2);
        expect(move.idx, 6);
      });
      test('specific scenario, step 5', () {
        final p = _make('212\n112\n202');
        final move = ShapeConstraint('11.10').apply(p);
        expect(move, isNotNull);
        expect(move!.value, 2);
        expect(move.idx, 7);
      });
    });
  });
  test('ShapeConstraint.findAdditionalPositions', () {
    final p = _make('110\n120\n000');
    p.constraints.add(ShapeConstraint("11.10"));
    final positions = ShapeConstraint.findAdditionalPositions(p);
    expect(positions.length, 1);
    expect(positions.first.$1, (1, 1));
    expect(positions.first.$2, [
      [0, 1],
      [1, 1],
    ]);
  });
}
