// Difficulty-level classification for puzzles, computed from a
// `solveExplained()` trace plus the prefill ratio of the initial grid.
//
// The cascading rules are documented in `docs/dev/levels.md`. This
// file is the single source of truth for the cascade — both the
// generator (live classification) and `bin/classify_difficulty.dart`
// (offline re-classification) call into `classifyTrace`.

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Difficulty tier. The numeric ordering is meaningful only inside
/// the "valid" range (beginner → mad); `overfilledEasy`,
/// `overfilled` and `undetermined` are out-of-cascade buckets.
///
/// `overfilledEasy` is the prefill-bucketed sibling of `beginner`:
/// puzzles whose prefill ratio exceeds the cap but whose trace shape
/// would otherwise put them in `beginner`. We split them out so the
/// onboarding system can mix them into the entry-level catalog
/// without pulling in genuinely-hard overfilled puzzles.
enum PuzzleLevel {
  beginner,
  player,
  advanced,
  strong,
  expert,
  mad,
  overfilledEasy,
  overfilled,
  undetermined,
}

/// Default playlist filename associated with each level. Used by both
/// the generator's auto-split mode and `--split-out`.
const Map<PuzzleLevel, String> levelFilenames = {
  PuzzleLevel.beginner: '1-easy.txt',
  PuzzleLevel.player: '2-player.txt',
  PuzzleLevel.advanced: '3-advanced.txt',
  PuzzleLevel.strong: '4-strong.txt',
  PuzzleLevel.expert: '5-expert.txt',
  PuzzleLevel.mad: '6-mad.txt',
  PuzzleLevel.overfilledEasy: 'overfilled-easy.txt',
  PuzzleLevel.overfilled: 'overfilled.txt',
  PuzzleLevel.undetermined: 'undetermined.txt',
};

/// Maps the slug of a built-in playable level collection (the asset
/// filename without the `.txt` suffix) to its [PuzzleLevel]. Excludes
/// the out-of-cascade buckets `overfilled*` and `undetermined`, which
/// are not surfaced as playable collections.
const Map<String, PuzzleLevel> playableCollectionKeyToLevel = {
  '1-easy': PuzzleLevel.beginner,
  '2-player': PuzzleLevel.player,
  '3-advanced': PuzzleLevel.advanced,
  '4-strong': PuzzleLevel.strong,
  '5-expert': PuzzleLevel.expert,
  '6-mad': PuzzleLevel.mad,
};

/// Inverse of [playableCollectionKeyToLevel].
const Map<PuzzleLevel, String> levelToPlayableCollectionKey = {
  PuzzleLevel.beginner: '1-easy',
  PuzzleLevel.player: '2-player',
  PuzzleLevel.advanced: '3-advanced',
  PuzzleLevel.strong: '4-strong',
  PuzzleLevel.expert: '5-expert',
  PuzzleLevel.mad: '6-mad',
};

/// Human-readable label for tables and CLI output.
const Map<PuzzleLevel, String> levelLabels = {
  PuzzleLevel.beginner: 'Beginner',
  PuzzleLevel.player: 'Player',
  PuzzleLevel.advanced: 'Advanced',
  PuzzleLevel.strong: 'Strong',
  PuzzleLevel.expert: 'Expert',
  PuzzleLevel.mad: 'Mad',
  PuzzleLevel.overfilledEasy: 'Overfilled (beginner)',
  PuzzleLevel.overfilled: 'Overfilled',
  PuzzleLevel.undetermined: 'Undetermined',
};

/// Default upper bound on the prefill ratio. Slightly more permissive
/// than the current generator contract (0.25) to retain legacy
/// puzzles. See docs/dev/levels.md for the histogram-based rationale.
const double defaultMaxPrefill = 0.30;

/// Classify a puzzle from its solving trace.
///
/// [steps] must come from `Puzzle.solveExplained()` on the puzzle in
/// its initial state (not after partial play). [prefillRatio] is the
/// fraction of cells already given as readonly; if it exceeds
/// [maxPrefill] the puzzle is bucketed in [PuzzleLevel.overfilled]
/// (or [PuzzleLevel.overfilledEasy] for trace-easy puzzles)
/// regardless of the trace.
///
/// [solved] indicates whether the trace actually completed the puzzle
/// — if false we return [PuzzleLevel.undetermined] (timeout, partial
/// trace, or solver got stuck on a contradiction).
PuzzleLevel classifyTrace({
  required List<SolveStep> steps,
  required double prefillRatio,
  required bool solved,
  double maxPrefill = defaultMaxPrefill,
}) {
  if (!solved) return PuzzleLevel.undetermined;

  int forceMoves = 0;
  int maxForceDepth = 0;
  int maxPropCx = 0;
  int maxComplCx = 0;
  for (final s in steps) {
    if (s.method == SolveMethod.force) {
      forceMoves++;
      if (s.forceDepth > maxForceDepth) maxForceDepth = s.forceDepth;
    } else if (s.isComplicity) {
      if (s.complexity > maxComplCx) maxComplCx = s.complexity;
    } else {
      if (s.complexity > maxPropCx) maxPropCx = s.complexity;
    }
  }

  // First pass: classify purely by trace shape, as if prefill were
  // unlimited. This tells us whether the puzzle is pedagogically
  // simple regardless of how much it's been pre-filled.
  final PuzzleLevel traceLevel;
  if (forceMoves >= 2 || (forceMoves == 1 && maxForceDepth > 5)) {
    traceLevel = PuzzleLevel.mad;
  } else if (forceMoves == 0 && maxComplCx >= 4) {
    traceLevel = PuzzleLevel.strong;
  } else if (forceMoves == 0 && maxComplCx > 0) {
    traceLevel = PuzzleLevel.advanced;
  } else if (forceMoves == 1) {
    traceLevel = PuzzleLevel.expert;
  } else if (maxPropCx >= 3) {
    traceLevel = PuzzleLevel.player;
  } else {
    traceLevel = PuzzleLevel.beginner;
  }

  // Second pass: route puzzles past the prefill cap to the appropriate
  // out-of-cascade bucket. Beginner-by-trace puzzles end up in
  // `overfilledEasy` (mixed into onboarding); everything else ends up
  // in plain `overfilled`.
  if (prefillRatio > maxPrefill) {
    return traceLevel == PuzzleLevel.beginner
        ? PuzzleLevel.overfilledEasy
        : PuzzleLevel.overfilled;
  }
  return traceLevel;
}

/// Recommend a playable [PuzzleLevel] from a `playerLevel` (cplx scale,
/// anchored at 50 = cohort average — see `docs/dev/adapt_to_player.md`).
///
/// Thresholds are deliberately hand-picked rather than derived from the
/// corpus medians: those medians (`beginner`=7, `player`=18, `advanced`=36,
/// `strong`=39, `expert`=37, `mad`=67) are not monotonic between
/// `advanced`/`strong`/`expert`, because cplx tracks predicted duration
/// while the cascade tracks cognitive type — they don't align in the
/// 35-45 zone. A "closest median" rule would flip the recommendation
/// erratically there. Explicit thresholds are stable and easy to test.
///
/// The cohort anchor at 50 means an average-paced player lands on the
/// boundary between `advanced` and `strong` — feels right.
PuzzleLevel recommendedLevelFor(int playerLevel) {
  if (playerLevel < 25) return PuzzleLevel.beginner;
  if (playerLevel < 40) return PuzzleLevel.player;
  if (playerLevel < 50) return PuzzleLevel.advanced;
  if (playerLevel < 65) return PuzzleLevel.strong;
  if (playerLevel < 80) return PuzzleLevel.expert;
  return PuzzleLevel.mad;
}

/// Convenience over [classifyTrace] when you have a [Puzzle] in its
/// initial state and want a one-shot classification. Runs
/// `solveExplained()` itself; useful for offline tools. The generator
/// already has the trace in hand and should call [classifyTrace]
/// directly to avoid the double solve.
PuzzleLevel classifyPuzzle(
  Puzzle puzzle, {
  double maxPrefill = defaultMaxPrefill,
  int? timeoutMs = 30000,
}) {
  final prefill =
      puzzle.cells.where((c) => c.readonly).length / puzzle.cells.length;
  // No early prefill short-circuit any more: classifyTrace itself now
  // routes high-prefill puzzles to `overfilledEasy` or `overfilled`
  // depending on their underlying trace shape. We always run the trace
  // so the routing is correct.
  final steps = puzzle.solveExplained(timeoutMs: timeoutMs);
  // Replay on a clone to verify the trace actually completes the puzzle.
  final replay = puzzle.clone();
  for (final s in steps) {
    replay.setValue(s.cellIdx, s.value);
  }
  final solved = replay.complete && replay.check(saveResult: false).isEmpty;

  return classifyTrace(
    steps: steps,
    prefillRatio: prefill,
    solved: solved,
    maxPrefill: maxPrefill,
  );
}
