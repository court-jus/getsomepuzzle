// Solution-geometry descriptors of a solved puzzle grid — translation- and
// colour-swap-invariant measures of the *global* regularity a player reads at
// a glance (perfect damier, colour bars, periodicity, symmetry) but the
// local-deduction trace is blind to.
//
// Two families, sharing this single source of truth:
//   * Invariant transforms — `spectralFeatures` (power spectrum |F(u,v)|²) and
//     `autocorrelationFeatures` (its parity-robust spatial-domain dual). Used
//     as continuous vector columns (`spec_*` / `auto_*`) for clustering / PCA.
//   * Interpretable scalars — `periodX`, `periodY`, `checkerBlockK`,
//     `countSymmetries`, `rleRatio`. Direct, human-readable predicates: a fully
//     constant axis (period 1) is colour bars, `checkerBlockK > 0` is a damier.
//
// All operate on a row-major grid of `CellValue` (`grid[r * w + c]`) with its
// width and height. Consumers: `vectorize_puzzles.dart` (CSV columns),
// `detect_regular_solutions.dart` (diagnostic report), and
// `test/spectral_features_test.dart`.

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

/// Translation- and colour-swap-invariant power-spectrum descriptors of a
/// solved grid, used to surface the *global* regularity a player reads at a
/// glance (perfect damier, colour bars) — a structure the local-deduction
/// trace is blind to.
///
/// The signal is the black mask `s[y][x] = +1` if black, `-1` otherwise (for a
/// 2-colour domain this is the exact 2-colouring; in domain 3 it is the
/// black-vs-rest mask). Its 2-D DFT power `P(u,v) = |Σ s·e^{-2πi(ux/W+vy/H)}|²`
/// is invariant to spatial shifts (translation → phase only) and to swapping
/// black↔white (global sign flip → |·|² unchanged).
///
/// All five scalars are fractions of the AC energy
/// `E = Σ_{(u,v)≠(0,0)} P(u,v)` (the DC bin, which only carries ink balance, is
/// excluded), hence size-invariant and in [0,1]:
///   * peak          — `max_{(u,v)≠(0,0)} P / E`: dominant single periodicity
///                     (damier / period-2 bars → ≈1).
///   * xbars         — `Σ_{u≥1} P(u,0) / E`: energy on the v=0 row ⇒ identical
///                     rows ⇒ vertical colour bars (constant along y).
///   * ybars         — `Σ_{v≥1} P(0,v) / E`: energy on the u=0 column ⇒
///                     horizontal colour bars (constant along x).
///   * checker       — `P(W~/2, H~/2) / E`: energy in the highest (near-Nyquist)
///                     corner bin ⇒ checkerboard.
///   * concentration — `Σ (P/E)²` (Herfindahl): global regularity (≈1 = few
///                     sharp peaks, ≈0 = diffuse / irregular).
///
/// A uniform solution (E ≈ 0) yields all zeros. Cost is O((W·H)²) ≤ 10⁴
/// multiply-adds per puzzle (grids are ≤ 10×10) using separable twiddle tables.
({
  double peak,
  double xbars,
  double ybars,
  double checker,
  double concentration,
})
spectralFeatures(List<CellValue> grid, int w, int h) {
  // Black mask, centred at ±1.
  final s = List<double>.generate(
    grid.length,
    (i) => grid[i] == CellValue.black ? 1.0 : -1.0,
  );

  // Separable twiddle tables: cosx[u][x] = cos(2π·u·x/W), etc. This turns the
  // per-bin DFT into pure multiply-adds (only W²+H² trig evaluations total).
  List<List<double>> cosTable(int n) =>
      List.generate(n, (a) => List.generate(n, (b) => cos(2 * pi * a * b / n)));
  List<List<double>> sinTable(int n) =>
      List.generate(n, (a) => List.generate(n, (b) => sin(2 * pi * a * b / n)));
  final cosx = cosTable(w);
  final sinx = sinTable(w);
  final cosy = cosTable(h);
  final siny = sinTable(h);

  final uc = w ~/ 2; // highest (near-Nyquist) x-frequency bin
  final vc = h ~/ 2; // highest (near-Nyquist) y-frequency bin

  double e = 0.0; // AC energy (excludes the DC bin)
  double peak = 0.0;
  double xbars = 0.0;
  double ybars = 0.0;
  double sumPsq = 0.0; // Σ P²  → concentration = sumPsq / E²
  double checkerP = 0.0;

  for (int v = 0; v < h; v++) {
    final cyv = cosy[v];
    final syv = siny[v];
    for (int u = 0; u < w; u++) {
      if (u == 0 && v == 0) continue; // skip DC (ink balance)
      final cxu = cosx[u];
      final sxu = sinx[u];
      double re = 0.0;
      double im = 0.0;
      for (int y = 0; y < h; y++) {
        final cy = cyv[y];
        final sy = syv[y];
        final row = y * w;
        for (int x = 0; x < w; x++) {
          final sv = s[row + x];
          if (sv == 0.0) continue;
          // exp(-2πi(ux/W+vy/H)) = (cxu·cy - sxu·sy) - i(cxu·sy + sxu·cy).
          // |F|² ignores the overall sign of the imaginary part.
          final cx = cxu[x];
          final sx = sxu[x];
          re += sv * (cx * cy - sx * sy);
          im += sv * (cx * sy + sx * cy);
        }
      }
      final p = re * re + im * im;
      e += p;
      sumPsq += p * p;
      if (p > peak) peak = p;
      if (v == 0) xbars += p; // v=0 row
      if (u == 0) ybars += p; // u=0 column
      if (u == uc && v == vc) checkerP = p;
    }
  }

  if (e < 1e-9) {
    return (
      peak: 0.0,
      xbars: 0.0,
      ybars: 0.0,
      checker: 0.0,
      concentration: 0.0,
    );
  }
  return (
    peak: peak / e,
    xbars: xbars / e,
    ybars: ybars / e,
    checker: checkerP / e,
    concentration: sumPsq / (e * e),
  );
}

/// Translation- and colour-swap-invariant *autocorrelation* descriptors of a
/// solved grid — the spatial-domain dual of [spectralFeatures] (Wiener-
/// Khinchin theorem), but summarised by *peak* rather than by per-bin fraction.
/// That summary is robust to the *parity* of the repeat count, where the fixed
/// Nyquist bin of `spec_checker_frac` only fires when the block count is even:
/// a 2×2 damier reads as a damier whether the grid is 4×4, 4×6 or 6×6.
///
/// For a shift `(dx,dy)` the truncated (non-circular) normalised overlap is
///   `R(dx,dy) = mean over the valid overlap of s(x,y)·s(x+dx,y+dy)  ∈ [-1,1]`
/// with `s = +1` black / `-1` white. `R = +1` means the pattern repeats exactly
/// under that shift, `R = -1` means it anti-repeats (a colour-swapped copy).
/// Three peaks:
///   * band    — `max` over the two axial half-lines `R(k,0)`, `R(0,k)` (k≥1):
///               the strongest 1-D repetition ⇒ colour bars / any axial period.
///   * checker — `-(min_k R(k,0) + min_k R(0,k)) / 2`: the strongest *anti*-
///               repetition on each axis, averaged ⇒ two-axis alternation
///               (damier of any maille; 1 only when BOTH axes alternate).
///   * tile    — `max` over diagonal shifts (dx≥1, dy≠0) of `R(dx,dy)`: the 2-D
///               / diagonal repetition the axial scans miss.
///
/// A uniform solution trivially repeats under every shift, so it reads
/// band 1 / checker -1 / tile 1; callers read these alongside the `spec_*`
/// block (e.g. `spec_concentration` separates uniform from structured). Cost is
/// O((W·H)²) ≤ 10⁴ multiply-adds per puzzle (grids are ≤ 10×10).
({double band, double checker, double tile}) autocorrelationFeatures(
  List<CellValue> grid,
  int w,
  int h,
) {
  // Black mask, centred at ±1.
  final s = List<int>.generate(
    grid.length,
    (i) => grid[i] == CellValue.black ? 1 : -1,
  );

  // Truncated (non-circular) normalised overlap correlation at shift (dx,dy).
  // Only the cells whose shifted partner stays inside the grid contribute, so
  // the result is a genuine local-overlap comparison (no wrap-around aliasing).
  double corr(int dx, int dy) {
    final xStart = dx >= 0 ? 0 : -dx;
    final xEnd = dx >= 0 ? w - dx : w; // exclusive
    final yStart = dy >= 0 ? 0 : -dy;
    final yEnd = dy >= 0 ? h - dy : h; // exclusive
    int sum = 0;
    int count = 0;
    for (int y = yStart; y < yEnd; y++) {
      final row = y * w;
      final shiftedRow = (y + dy) * w + dx;
      for (int x = xStart; x < xEnd; x++) {
        sum += s[row + x] * s[shiftedRow + x];
        count++;
      }
    }
    return count > 0 ? sum / count : 0.0;
  }

  // Axial scans: max (repetition) and min (anti-repetition) along each axis.
  double maxX = -1.0, minX = 1.0, maxY = -1.0, minY = 1.0;
  for (int k = 1; k < w; k++) {
    final r = corr(k, 0);
    if (r > maxX) maxX = r;
    if (r < minX) minX = r;
  }
  for (int k = 1; k < h; k++) {
    final r = corr(0, k);
    if (r > maxY) maxY = r;
    if (r < minY) minY = r;
  }

  // Diagonal scan: strongest genuine 2-D repetition (both shifts non-zero).
  double tile = -1.0;
  for (int dx = 1; dx < w; dx++) {
    for (int dy = -(h - 1); dy < h; dy++) {
      if (dy == 0) continue;
      final r = corr(dx, dy);
      if (r > tile) tile = r;
    }
  }

  return (
    band: maxX > maxY ? maxX : maxY,
    checker: -(minX + minY) / 2,
    tile: tile,
  );
}

/// Smallest k ≥ 1 such that the grid partitions into k×k *monochrome* blocks
/// that *alternate* colour like a checkerboard (block colour set by the parity
/// of blockRow+blockCol). Returns 0 if no such k divides both dimensions.
/// A monochrome grid does NOT qualify (alternation requires two colours).
int checkerBlockK(List<CellValue> g, int w, int h) {
  final maxK = w < h ? w : h;
  for (int k = 1; k <= maxK; k++) {
    if (w % k != 0 || h % k != 0) continue;
    if (_isCheckerWithBlock(g, w, h, k)) return k;
  }
  return 0;
}

bool _isCheckerWithBlock(List<CellValue> g, int w, int h, int k) {
  CellValue? even; // colour of even-parity blocks
  CellValue? odd; // colour of odd-parity blocks
  for (int br = 0; br * k < h; br++) {
    for (int bc = 0; bc * k < w; bc++) {
      // The block must be monochrome.
      final c0 = g[(br * k) * w + (bc * k)];
      for (int dr = 0; dr < k; dr++) {
        for (int dc = 0; dc < k; dc++) {
          if (g[(br * k + dr) * w + (bc * k + dc)] != c0) return false;
        }
      }
      // ...and match the parity-assigned colour.
      if ((br + bc).isEven) {
        if (even == null) {
          even = c0;
        } else if (even != c0) {
          return false;
        }
      } else {
        if (odd == null) {
          odd = c0;
        } else if (odd != c0) {
          return false;
        }
      }
    }
  }
  // Need genuine alternation: two distinct colours present.
  return even != null && odd != null && even != odd;
}

/// Smallest horizontal translation period p (1..w). Returns w if aperiodic.
/// The whole grid must satisfy g[r][c] == g[r][c+p] for every valid cell.
int periodX(List<CellValue> g, int w, int h) {
  for (int p = 1; p < w; p++) {
    var ok = true;
    for (int r = 0; r < h && ok; r++) {
      for (int c = 0; c + p < w; c++) {
        if (g[r * w + c] != g[r * w + c + p]) {
          ok = false;
          break;
        }
      }
    }
    if (ok) return p;
  }
  return w;
}

/// Smallest vertical translation period p (1..h). Returns h if aperiodic.
int periodY(List<CellValue> g, int w, int h) {
  for (int p = 1; p < h; p++) {
    var ok = true;
    for (int c = 0; c < w && ok; c++) {
      for (int r = 0; r + p < h; r++) {
        if (g[r * w + c] != g[(r + p) * w + c]) {
          ok = false;
          break;
        }
      }
    }
    if (ok) return p;
  }
  return h;
}

/// Count of dihedral operations leaving the grid invariant. Mirror-H, mirror-V
/// and rot180 apply to any rectangle; transpose / anti-transpose / rot90 /
/// rot270 only to squares.
int countSymmetries(List<CellValue> g, int w, int h) {
  int n = 0;
  CellValue at(int r, int c) => g[r * w + c];

  // Mirror horizontal (left-right).
  if (_all(w, h, (r, c) => at(r, c) == at(r, w - 1 - c))) n++;
  // Mirror vertical (top-bottom).
  if (_all(w, h, (r, c) => at(r, c) == at(h - 1 - r, c))) n++;
  // 180° rotation.
  if (_all(w, h, (r, c) => at(r, c) == at(h - 1 - r, w - 1 - c))) n++;

  if (w == h) {
    // Transpose (main diagonal).
    if (_all(w, h, (r, c) => at(r, c) == at(c, r))) n++;
    // Anti-transpose (anti-diagonal).
    if (_all(w, h, (r, c) => at(r, c) == at(w - 1 - c, h - 1 - r))) n++;
    // 90° rotation.
    if (_all(w, h, (r, c) => at(r, c) == at(c, h - 1 - r))) n++;
    // 270° rotation.
    if (_all(w, h, (r, c) => at(r, c) == at(w - 1 - c, r))) n++;
  }
  return n;
}

bool _all(int w, int h, bool Function(int r, int c) pred) {
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      if (!pred(r, c)) return false;
    }
  }
  return true;
}

/// Run-length-encoding density: (number of maximal same-colour runs) / cells,
/// taking the cheaper of a row-major and column-major scan (runs counted
/// independently per line). NOTE: empirically this conflates "regular" with
/// "unbalanced ink" — kept as a reported scalar, not an easy-pattern signal.
double rleRatio(List<CellValue> g, int w, int h) {
  int runsRow = 0;
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      if (c == 0 || g[r * w + c] != g[r * w + c - 1]) runsRow++;
    }
  }
  int runsCol = 0;
  for (int c = 0; c < w; c++) {
    for (int r = 0; r < h; r++) {
      if (r == 0 || g[r * w + c] != g[(r - 1) * w + c]) runsCol++;
    }
  }
  final cells = w * h;
  final minRuns = runsRow < runsCol ? runsRow : runsCol;
  return cells == 0 ? 1.0 : minRuns / cells;
}
