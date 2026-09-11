// Play model shared by the app (`Database.computePlayerLevel`) and the batch
// tools in `bin/` (e.g. `bin/analyze_stats.dart`).
//
// Deliberately free of Flutter imports: `bin/` scripts run under plain
// `dart run` and cannot import `database.dart` (Flutter + shared_preferences).
// Keeping the model here is what lets those tools use the production
// formulas instead of hand-mirroring the constants.

import 'dart:math' as math;

/// Fields of a v2 puzzle line that the duration/skill model needs.
typedef PuzzleLineFields = ({int cplx, int cells, int nCons});

/// Lightweight extraction of [PuzzleLineFields] from a v2 puzzle line
/// `v2_<domain>_<WxH>_<cells>_<constraints>_<solution>_<cplx>[_p:…][_scenario:…]`.
///
/// No `Puzzle`/`PuzzleData` construction — pure string parse. `cells` comes
/// from the `WxH` field [2], `cplx` from the cached-complexity field [6]
/// (0 when absent or unparseable; trailing fields are never consulted), and
/// `nCons` from the `;`-separated constraint field [4].
///
/// Tolerant by design: returns `null` when the dimensions are missing or
/// unparseable instead of throwing like `PuzzleData`.
PuzzleLineFields? parsePuzzleLineFields(String line) {
  final parts = line.split('_');
  if (parts.length <= 4) return null;
  final dims = parts[2].split('x');
  final w = int.tryParse(dims[0]);
  final h = dims.length > 1 ? int.tryParse(dims[1]) : null;
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  final cplx = parts.length > 6 ? (int.tryParse(parts[6]) ?? 0) : 0;
  final nCons = parts[4].split(';').length;
  return (cplx: cplx, cells: w * h, nCons: nCons);
}

/// Cached complexity (v2 field [6]) of a puzzle line, or 0 when the line is
/// malformed or the field is absent/unparseable.
int cplxFromLine(String line) => parsePuzzleLineFields(line)?.cplx ?? 0;

/// Expected duration (seconds) for a puzzle of given `cplx`, `cells`,
/// `failures`, and `nConstraints` (the puzzle's constraint count).
///
/// Refit by OLS on real plays after stricter outlier rejection (see
/// notes below). Anchored model:
///   log(dur) ≈ 1.197 + 0.00808·cplx + 0.515·log(cells)
///                    + 0.151·failures + 0.102·n_constraints
///   ≈ 3.31 · cells^0.515 · exp(cplx/123.8)
///        · 1.163^failures · 1.107^n_constraints       (R²=0.50, MAPE=50 %)
///
/// The intercept is anchored so that — on the calibration corpus — the
/// **mean** `level_i` lands on 50 rather than on the corpus's mean
/// `cplx`. Concretely: a player who solves at the same pace as the
/// calibration corpus converges to level 50; faster players go above,
/// slower below. This places the "average" right in the middle of
/// [0, 100] instead of bunching at the low end.
///
/// **Why these constants and not the previous ones (3.3108, 123.82, …)**:
/// the previous set was calibrated on the *capped* cplx distribution
/// (effort cap 90, total cap 100). The 2026-08 formula change —
/// unbounded score, `(domain−2)·5` domain term, `+1` prune bump on
/// domains > 2 — recomputed the corpus with a wider, domain-aware cplx
/// scale (mean cplx on the calibration corpus rose to ~35.75). Under
/// the old constants every recomputed play then read as max level
/// (56 % saturated at 0/100, mean level 88). The current set is the OLS
/// refit on the recomputed corpus (same `longestGapMs ≤ 30 s` AFK
/// rule), with the intercept shifted by +0.2399 so the cohort mean
/// lands on 50 again. The steeper `exp(cplx/59.4)` slope reflects the
/// unclamped scale restoring discrimination at the top end: R² = 0.621,
/// MAPE = 46 % on the recomputed corpus.
///
/// See `bin/analyze_stats.dart` for the regression tool (it both
/// applies the same cleaning and prints anchored constants ready to
/// paste back into this file).
const double _kBase = 4.8834;
const double _kCellsExp = 0.3437;
const double _kCplxScale = 59.39;
const double _kFailMul = 1.1943;
const double _kNConsMul = 1.0614;

/// Cap on the `cplx` fed to the duration/skill model. `cplx` itself is
/// unbounded (and stays so); this only stops `exp(cplx / _kCplxScale)`
/// from extrapolating far outside the calibration range — `cplx` 564
/// predicts 404 308 s and yields `level_i ≈ 1 033`.
///
/// Applied **only** inside [expectedDuration] and [playLevel]. Selection,
/// the Gaussian, the display, `parsePuzzleLineFields` and the difficulty
/// tiers keep the true value.
const int kCplxModelMax = 120;

double expectedDuration(int cplx, int cells, int failures, int nConstraints) {
  final c = cplx.clamp(0, kCplxModelMax);
  return _kBase *
      math.pow(cells, _kCellsExp) *
      math.exp(c / _kCplxScale) *
      math.pow(_kFailMul, failures) *
      math.pow(_kNConsMul, nConstraints);
}

/// Algebraic inverse of [expectedDuration]: the `cplx` the model would have
/// predicted for `duration`.
double impliedCplx(int duration, int cells, int failures, int nConstraints) {
  return _kCplxScale *
      (math.log(duration) -
          math.log(_kBase) -
          _kCellsExp * math.log(cells) -
          failures * math.log(_kFailMul) -
          nConstraints * math.log(_kNConsMul));
}

/// Per-play implicit skill level: when the play's duration matches the
/// expected duration for its `cplx`, `level == cplx`; faster ⇒ above,
/// slower ⇒ below. `Database.computePlayerLevel` winsorizes this value;
/// `bin/analyze_stats.dart` reports it raw.
double playLevel(
  int duration,
  int cplx,
  int cells,
  int failures,
  int nConstraints,
) {
  final c = cplx.clamp(0, kCplxModelMax);
  return 2.0 * c - impliedCplx(duration, cells, failures, nConstraints);
}
