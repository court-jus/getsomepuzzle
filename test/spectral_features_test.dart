// Unit tests for the solution-geometry descriptors in bin/_solution_geometry.dart
// (emitted as the `spec_*` / `auto_*` / `period_*` / `checker_block_k` /
// `n_symmetries` / `rle_ratio` columns by bin/vectorize_puzzles.dart):
//   * `spectralFeatures` — translation- and colour-swap-invariant power
//     spectrum |F(u,v)|² of a solved grid.
//   * `autocorrelationFeatures` — its parity-robust spatial-domain dual.
//   * `periodX` / `periodY` / `checkerBlockK` / `countSymmetries` / `rleRatio`
//     — the interpretable scalar predicates.
//
// For the spectrum we test the four canonical solution geometries the feature
// is meant to distinguish — a 1×1 checkerboard (period-2 alternation), vertical
// colour bars, horizontal colour bars, uniform fill — plus a negative control
// (a lone black cell → diffuse spectrum) to confirm an *irregular* solution is
// NOT read as regular.
//
// For the autocorrelation we focus on the property the spectrum lacks: a 2×2
// damier must read as a damier regardless of the *parity* of the block count
// (4×4, 4×6, 6×6), and a shifted/diagonal motif must register via `auto_tile`
// where no pure-axis period exists.
//
// For the scalars we pin the designer-confirmed `stripes` (period 1 on an axis)
// and `checker` (checkerBlockK > 0) predicates plus the symmetry / RLE scalars.

import 'package:flutter_test/flutter_test.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

import '../bin/_solution_geometry.dart';

/// Build a row-major grid from glyph rows: '#' = black, anything else = white.
/// Returns the cells plus the inferred (width, height).
(List<CellValue>, int, int) grid(List<String> rows) {
  final h = rows.length;
  final w = rows.first.length;
  final cells = <CellValue>[];
  for (final row in rows) {
    assert(row.length == w, 'ragged grid');
    for (final ch in row.split('')) {
      cells.add(ch == '#' ? CellValue.black : CellValue.white);
    }
  }
  return (cells, w, h);
}

void main() {
  group('spectralFeatures', () {
    test('1×1 checkerboard → all energy in the Nyquist corner bin', () {
      // g[y][x] = (-1)^(x+y): a single pure frequency at (W/2, H/2). The whole
      // AC energy sits in that one corner bin, so peak == checker == 1 and the
      // pattern is maximally concentrated, with no pure-axis (bar) energy.
      final (cells, w, h) = grid(['#.#.', '.#.#', '#.#.', '.#.#']);
      final s = spectralFeatures(cells, w, h);
      expect(s.checker, closeTo(1.0, 1e-9));
      expect(s.peak, closeTo(1.0, 1e-9));
      expect(s.concentration, closeTo(1.0, 1e-9));
      expect(s.xbars, closeTo(0.0, 1e-9));
      expect(s.ybars, closeTo(0.0, 1e-9));
    });

    test(
      'vertical colour bars → energy on the v=0 row (xbars), not checker',
      () {
        // Every row identical (constant along y), period-2 along x. All energy
        // lands on the v=0 spectral row → xbars == 1; the checkerboard corner is
        // empty because the y-direction sum cancels.
        final (cells, w, h) = grid(['.#.#', '.#.#', '.#.#', '.#.#']);
        final s = spectralFeatures(cells, w, h);
        expect(s.xbars, closeTo(1.0, 1e-9));
        expect(s.peak, closeTo(1.0, 1e-9));
        expect(s.ybars, closeTo(0.0, 1e-9));
        expect(s.checker, closeTo(0.0, 1e-9));
      },
    );

    test('horizontal colour bars → energy on the u=0 column (ybars)', () {
      // Every column identical (constant along x), period-2 along y — the
      // transpose of the previous case. Energy is on the u=0 spectral column.
      final (cells, w, h) = grid(['####', '....', '####', '....']);
      final s = spectralFeatures(cells, w, h);
      expect(s.ybars, closeTo(1.0, 1e-9));
      expect(s.peak, closeTo(1.0, 1e-9));
      expect(s.xbars, closeTo(0.0, 1e-9));
      expect(s.checker, closeTo(0.0, 1e-9));
    });

    test('uniform solution → zero AC energy → all features 0', () {
      // A single-colour grid has all its energy in the (excluded) DC bin, so
      // E ≈ 0 and every fraction degenerates to 0 rather than NaN.
      final (cells, w, h) = grid(['####', '####', '####', '####']);
      final s = spectralFeatures(cells, w, h);
      expect(s.peak, 0.0);
      expect(s.xbars, 0.0);
      expect(s.ybars, 0.0);
      expect(s.checker, 0.0);
      expect(s.concentration, 0.0);
    });

    test('lone black cell → flat (diffuse) spectrum, NOT read as regular', () {
      // A single isolated black cell is a spatial delta: its AC spectrum is
      // flat (every non-DC bin equal). Concentration and peak must stay tiny —
      // the opposite of a periodic pattern — so an irregular solution never
      // masquerades as a global shortcut.
      final (cells, w, h) = grid(['#...', '....', '....', '....']);
      final s = spectralFeatures(cells, w, h);
      expect(s.peak, lessThan(0.1));
      expect(s.checker, lessThan(0.1));
      expect(s.concentration, lessThan(0.1));
    });
  });

  group('autocorrelationFeatures', () {
    test('2×2 damier on 4×4 → checker 1, tile 1, not a stripe', () {
      // A 2×2-block damier: both axes anti-correlate at a one-block shift, so
      // checker == 1. The opposite block aligns under the diagonal (2,2) shift
      // → tile == 1. Its cell-period (4) does not fit a width-4 window, so the
      // axial repetition peaks well below 1 — it must NOT be read as bars.
      final (cells, w, h) = grid(['##..', '##..', '..##', '..##']);
      final a = autocorrelationFeatures(cells, w, h);
      expect(a.checker, closeTo(1.0, 1e-9));
      expect(a.tile, closeTo(1.0, 1e-9));
      expect(a.band, lessThan(0.5));
    });

    test('2×2 damier on 6×6 → checker 1 (odd block count, parity-robust)', () {
      // The key parity case: a 2×2 damier tiled over a 3×3 block grid. A fixed
      // Nyquist spectral bin would miss it (odd block count), but the one-block
      // anti-correlation on both axes is intact → checker == 1.
      final (cells, w, h) = grid([
        '##..##',
        '##..##',
        '..##..',
        '..##..',
        '##..##',
        '##..##',
      ]);
      final a = autocorrelationFeatures(cells, w, h);
      expect(a.checker, closeTo(1.0, 1e-9));
    });

    test('2×2 damier on 4×6 → checker 1 (mismatched even/odd axes)', () {
      // Width gives an even block count, height an odd one. checker must stay 1
      // because it averages the per-axis anti-repetition, both of which are −1.
      final (cells, w, h) = grid([
        '##..',
        '##..',
        '..##',
        '..##',
        '##..',
        '##..',
      ]);
      final a = autocorrelationFeatures(cells, w, h);
      expect(a.checker, closeTo(1.0, 1e-9));
    });

    test('vertical colour bars → band 1, checker 0 (single-axis only)', () {
      // Rows are identical (R(0,k) == 1) and the columns alternate with
      // period 2 (R(2,0) == 1) → band == 1. Only one axis anti-correlates, so
      // the two-axis checker average is 0 — bars are not a damier.
      final (cells, w, h) = grid(['.#.#', '.#.#', '.#.#', '.#.#']);
      final a = autocorrelationFeatures(cells, w, h);
      expect(a.band, closeTo(1.0, 1e-9));
      expect(a.checker, closeTo(0.0, 1e-9));
    });

    test(
      'uniform solution → band 1, checker −1 (repeats, never alternates)',
      () {
        // Every shift overlaps identical cells, so R == 1 everywhere: band == 1
        // and tile == 1, while the per-axis minimum is +1 → checker == −1. The
        // spectral block (E ≈ 0 → spec_concentration 0) is what separates this
        // degenerate "regularity" from a structured one downstream.
        final (cells, w, h) = grid(['####', '####', '####', '####']);
        final a = autocorrelationFeatures(cells, w, h);
        expect(a.band, closeTo(1.0, 1e-9));
        expect(a.checker, closeTo(-1.0, 1e-9));
      },
    );

    test('diagonal period-5 motif → tile 1 > band (no axial period)', () {
      // Blacks where (x+y) % 5 == 0: (0,0), (3,2), (2,3). The motif repeats
      // under the diagonal shift (2,3)/(3,2) → tile == 1, but no pure-axis
      // shift aligns it within the window, so band stays strictly below tile.
      final (cells, w, h) = grid(['#...', '....', '...#', '..#.']);
      final a = autocorrelationFeatures(cells, w, h);
      expect(a.tile, closeTo(1.0, 1e-9));
      expect(a.band, lessThan(a.tile));
    });
  });

  // Interpretable scalar predicates (period / checker / symmetry / RLE) — the
  // designer-confirmed `stripes` (period 1 on an axis) and `checker`
  // (checkerBlockK > 0) signals plus the reported-only symmetry and RLE
  // scalars. These feed the `period_x` / `period_y` / `checker_block_k` /
  // `n_symmetries` / `rle_ratio` vector columns.
  group('solution-geometry scalars', () {
    test('vertical colour bars → period 1 on the constant axis', () {
      // Every row identical (constant along y) and period-2 along x. The
      // `stripes` predicate is "one axis fully constant" = period 1 on it.
      final (cells, w, h) = grid(['.#.#', '.#.#', '.#.#', '.#.#']);
      expect(periodY(cells, w, h), 1);
      expect(periodX(cells, w, h), 2);
    });

    test('checkerBlockK distinguishes 2×2-block, 1×1, and monochrome', () {
      // 2×2 monochrome blocks alternating → maille 2.
      final (b2, w2, h2) = grid(['##..', '##..', '..##', '..##']);
      expect(checkerBlockK(b2, w2, h2), 2);
      // Single-cell alternation → maille 1.
      final (b1, w1, h1) = grid(['#.#.', '.#.#', '#.#.', '.#.#']);
      expect(checkerBlockK(b1, w1, h1), 1);
      // A monochrome grid never alternates → 0 (no second colour present).
      final (uni, wu, hu) = grid(['##', '##']);
      expect(checkerBlockK(uni, wu, hu), 0);
    });

    test('countSymmetries: square uniform = 7 ops, single mirror = 1', () {
      // A uniform square is invariant under every non-identity dihedral op
      // (mirror H/V, rot180, transpose, anti-transpose, rot90, rot270) = 7.
      final (uni, wu, hu) = grid(['##', '##']);
      expect(countSymmetries(uni, wu, hu), 7);
      // Only the left-right mirror holds here (col0 == col2); the square-only
      // ops and the other rectangle ops all fail → exactly 1.
      final (mir, wm, hm) = grid(['#.#', '#.#', '...']);
      expect(countSymmetries(mir, wm, hm), 1);
    });

    test('rleRatio takes the cheaper of the row- and column-major scans', () {
      // Column-constant stripes: each column is a single run (4 runs) while
      // each row alternates (16 runs). The metric reports the min → 4/16.
      final (cells, w, h) = grid(['.#.#', '.#.#', '.#.#', '.#.#']);
      expect(rleRatio(cells, w, h), closeTo(0.25, 1e-9));
    });
  });
}
