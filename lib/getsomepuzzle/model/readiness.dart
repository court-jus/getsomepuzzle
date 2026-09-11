// Readiness model — "can this player handle the next collection?".
//
// Deliberately separate from `playerLevel` (see the "Readiness" section of
// `docs/dev/adapt_to_player.md`). `playerLevel` blends the player's pace
// with the mix of puzzles they happen to play, so it moves when the mix
// moves, even at constant pace — fine for *selection*, wrong for
// *readiness*. Readiness is built from the relative pace
// `r = duration / expectedDuration(...)`, which is mix-independent: the
// same `r` means the same pace in every collection.
//
// Pure Dart, no Flutter, no state: everything is derivable from the
// stats history. Mirrors the style of `play_model.dart` so the offline
// tools in `bin/` can use the production code path instead of
// hand-mirroring the constants.

import 'dart:math' as math;

import 'play_model.dart';

/// Per-window verdict. [unknown] is what [sustainedVote] returns when the
/// player has not accumulated enough usable plays of the tier yet.
enum ReadinessVote { promote, hold, demote, unknown }

/// One usable, collection-attributed play. `duration` is in seconds,
/// `longestGapMs` in milliseconds (matching the stats grammar).
class ReadinessSample {
  final DateTime finished;
  final int duration;
  final int failures;
  final int cplx;
  final int cells;
  final int nCons;
  final int longestGapMs;

  const ReadinessSample({
    required this.finished,
    required this.duration,
    required this.failures,
    required this.cplx,
    required this.cells,
    required this.nCons,
    this.longestGapMs = 0,
  });
}

/// One evaluation of one [kWindow]-play window of a single tier.
class ReadinessWindow {
  /// Usable samples actually scored (after the AFK trim).
  final int samples;
  final double medianR;

  /// OLS of `ln r` on `cplx` inside the window. Sanity check only.
  final double slope;

  /// Share of plays at or above [kHardFactor] × expected.
  final double hardShare;

  /// `medianR × expectedDuration(next tier's reference puzzle)`.
  final double projectedSeconds;

  final ReadinessVote vote;

  const ReadinessWindow({
    required this.samples,
    required this.medianR,
    required this.slope,
    required this.hardShare,
    required this.projectedSeconds,
    required this.vote,
  });
}

/// Reference puzzle of a playable tier — the median `(cplx, cells, nCons)`
/// of the tier's shipped catalog, used to project how long the next tier's
/// typical puzzle would take. Regenerate when the collections change:
/// for each `assets/<key>.txt` (+ its `-overfilled` mirror) take the
/// median of field [6] (`cplx`), of `W·H` (field [2]), and of the
/// `;`-count of field [4].
class TierReference {
  final int cplx;
  final int cells;
  final int nCons;
  const TierReference(this.cplx, this.cells, this.nCons);
}

/// Indexed by `PuzzleLevel.index` of the six playable tiers
/// (`beginner` … `mad`). Values measured on the 2026-09-11 catalog.
const List<TierReference> kTierReferencePuzzles = [
  TierReference(16, 24, 12), // 1-easy   → ~39 s
  TierReference(30, 24, 11), // 2-player → ~47 s
  TierReference(36, 24, 8), // 3-advanced → ~43 s
  TierReference(48, 24, 9), // 4-strong → ~56 s
  TierReference(43, 28, 10), // 5-expert → ~58 s
  TierReference(115, 25, 9), // 6-mad    → ~175 s (blocked by the effort cap)
];

/// Expected seconds for the reference puzzle of [tier], or null when
/// [tier] is outside the playable range.
double? tierReferenceSeconds(int tier) {
  if (tier < 0 || tier >= kTierReferencePuzzles.length) return null;
  final ref = kTierReferencePuzzles[tier];
  return expectedDuration(ref.cplx, ref.cells, 0, ref.nCons);
}

// ---------------------------------------------------------------------------
// Calibration constants. Next re-calibration is a one-place edit.
// ---------------------------------------------------------------------------

/// Promote when the window's median relative pace is at or below this.
const double kPromoteR = 1.5;

/// Demote when the window's median relative pace is at or above this.
/// `kPromoteR < medianR < kDemoteR` is the hysteresis band: hold.
const double kDemoteR = 1.8;

/// Demote is unconditional above this median pace, even without a high
/// hard-play share.
const double kDemoteStrongR = 2.1;

/// Number of consecutive per-play verdicts that must agree before a vote
/// fires. With [kWindow] = 20 this needs ~39 usable plays of a tier.
const int kSustainedPlays = 20;

/// Play count per evaluated window.
const int kWindow = 20;

/// Usable samples required to evaluate a window at all.
const int kMinSamples = 15;

/// A tier whose newest usable play is older than this is `unknown` — the
/// player may have changed device, skill or build since.
const int kMaxSampleAgeDays = 14;

/// A promotion whose projected next-tier duration exceeds this is refused.
/// Real upward moves landed at 44–71 s.
const double kEffortCapSeconds = 90.0;

/// A play at or above this multiple of expected counts as "hard".
const double kHardFactor = 3.0;

/// Minimum hard-play share required for a demote whose median pace sits
/// between [kDemoteR] and [kDemoteStrongR].
const double kHardShareForDemote = 0.20;

/// Upper bound on the `ln r ~ cplx` slope for a promotion. Sanity only:
/// at n = 20 every confidence interval brackets 0, so this never fires on
/// its own.
const double kSlopeSanity = 0.03;

/// Plays lasting more than this multiple of the window's median duration
/// are treated as AFK proxies and dropped. `longestGapMs` telemetry is
/// too sparse (0–24 % coverage) to rely on alone.
const double kAfkFactor = 10.0;

/// Gross-AFK guard mirroring `Database._levelAfkMaxGapMs`.
const int kMaxGapMs = 5 * 60 * 1000;

/// Evaluate the newest window and the [windows] - 1 previous windows of
/// [tierSamples] (one tier only, any order, unfiltered).
///
/// Returns newest window first, or an empty list when the tier has no
/// usable history, fewer than [kMinSamples] usable plays, or a newest
/// sample older than [kMaxSampleAgeDays]. A promoted/demoted verdict
/// requires [kSustainedPlays] windows, i.e. ~39 usable plays.
List<ReadinessWindow> evaluateReadinessSeries(
  List<ReadinessSample> tierSamples,
  double nextTierExpectedSeconds, {
  int windows = kSustainedPlays,
  required DateTime now,
}) {
  final usable = <ReadinessSample>[];
  for (final s in tierSamples) {
    if (s.duration <= 0 || s.cplx <= 0) continue;
    if (s.longestGapMs > kMaxGapMs) continue;
    usable.add(s);
  }
  if (usable.length < kMinSamples) return const [];
  usable.sort((a, b) => a.finished.compareTo(b.finished));
  if (now.difference(usable.last.finished).inDays > kMaxSampleAgeDays) {
    return const [];
  }
  final out = <ReadinessWindow>[];
  for (var offset = 0; offset < windows; offset++) {
    final end = usable.length - offset;
    // A verdict needs full [kWindow]-play windows — with [kSustainedPlays]
    // windows on top, that is ~39 usable plays of the tier before anything
    // can fire. Shortening the window at the tail would let a thin history
    // promote, which is exactly the warm-up artefact this guards against.
    if (end < kWindow) break;
    out.add(
      _evaluateWindow(
        usable.sublist(end - kWindow, end),
        nextTierExpectedSeconds,
      ),
    );
  }
  return out;
}

/// `promote` requires every window to promote, `demote` every window to
/// demote; anything else is `hold`. A series shorter than [kSustainedPlays]
/// is `unknown` — never a fire.
ReadinessVote sustainedVote(
  List<ReadinessWindow> series, {
  int windows = kSustainedPlays,
}) {
  if (series.length < windows) return ReadinessVote.unknown;
  if (series.every((w) => w.vote == ReadinessVote.promote)) {
    return ReadinessVote.promote;
  }
  if (series.every((w) => w.vote == ReadinessVote.demote)) {
    return ReadinessVote.demote;
  }
  return ReadinessVote.hold;
}

ReadinessWindow _evaluateWindow(
  List<ReadinessSample> window,
  double nextTierExpectedSeconds,
) {
  // Trim AFK proxies against the window's own median duration. The
  // `longestGapMs` filter already ran, but that field is missing on most
  // legacy lines.
  final durations = window.map((s) => s.duration).toList()..sort();
  final medianDuration = _median(durations);
  final scored = medianDuration > 0
      ? window.where((s) => s.duration <= kAfkFactor * medianDuration).toList()
      : window;

  final rs = <double>[];
  final cplx = <double>[];
  var hard = 0;
  for (final s in scored) {
    final expected = expectedDuration(s.cplx, s.cells, s.failures, s.nCons);
    if (expected <= 0) continue;
    final r = s.duration / expected;
    rs.add(r);
    cplx.add(s.cplx.toDouble());
    if (s.duration >= kHardFactor * expected) hard++;
  }
  if (rs.isEmpty) {
    return const ReadinessWindow(
      samples: 0,
      medianR: 0,
      slope: 0,
      hardShare: 0,
      projectedSeconds: 0,
      vote: ReadinessVote.hold,
    );
  }

  final medianR = _median(rs);
  final slope = _olsSlope(cplx, rs.map(math.log).toList());
  final hardShare = hard / rs.length;
  final projectedSeconds = medianR * nextTierExpectedSeconds;

  final ReadinessVote vote;
  if (medianR <= kPromoteR &&
      slope <= kSlopeSanity &&
      projectedSeconds <= kEffortCapSeconds) {
    vote = ReadinessVote.promote;
  } else if (medianR >= kDemoteR &&
      (hardShare >= kHardShareForDemote || medianR >= kDemoteStrongR)) {
    vote = ReadinessVote.demote;
  } else {
    vote = ReadinessVote.hold;
  }

  return ReadinessWindow(
    samples: rs.length,
    medianR: medianR,
    slope: slope,
    hardShare: hardShare,
    projectedSeconds: projectedSeconds,
    vote: vote,
  );
}

double _median(List<num> values) {
  if (values.isEmpty) return 0;
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Slope of the least-squares line `y = a + b·x`, or 0 when `x` has no
/// variance (a single distinct cplx cannot carry a trend).
double _olsSlope(List<double> x, List<double> y) {
  if (x.length < 2) return 0;
  final n = x.length;
  var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
  for (var i = 0; i < n; i++) {
    sumX += x[i];
    sumY += y[i];
    sumXY += x[i] * y[i];
    sumXX += x[i] * x[i];
  }
  final denom = n * sumXX - sumX * sumX;
  if (denom == 0) return 0;
  return (n * sumXY - sumX * sumY) / denom;
}
