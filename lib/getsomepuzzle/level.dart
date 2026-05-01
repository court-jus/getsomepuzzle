// Difficulty-level classification for puzzles, computed from a
// `solveExplained()` trace plus the prefill ratio of the initial grid.
//
// The cascading rules are documented in `docs/dev/levels.md`. This
// file is the single source of truth for the cascade — both the
// generator (live classification) and `bin/classify_difficulty.dart`
// (offline re-classification) call into `classifyTrace`.

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Difficulty palier. The numeric ordering is meaningful only inside
/// the "valid" range (debutant → fouFurieux); `preRempli` and
/// `indetermine` are out-of-cascade buckets.
enum PuzzleLevel {
  debutant,
  joueur,
  avance,
  balaise,
  expert,
  fouFurieux,
  preRempli,
  indetermine,
}

/// Default playlist filename associated with each level. Used by both
/// the generator's auto-split mode and `--split-out`.
const Map<PuzzleLevel, String> levelFilenames = {
  PuzzleLevel.debutant: '1-easy.txt',
  PuzzleLevel.joueur: '2-player.txt',
  PuzzleLevel.avance: '3-advanced.txt',
  PuzzleLevel.balaise: '4-strong.txt',
  PuzzleLevel.expert: '5-expert.txt',
  PuzzleLevel.fouFurieux: '6-mad.txt',
  PuzzleLevel.preRempli: 'overfilled.txt',
  PuzzleLevel.indetermine: 'undetermined.txt',
};

/// Maps the slug of a built-in playable level collection (the asset
/// filename without the `.txt` suffix) to its [PuzzleLevel]. Excludes
/// the out-of-cascade buckets `preRempli` and `indetermine`, which are
/// not surfaced as playable collections.
const Map<String, PuzzleLevel> playableCollectionKeyToLevel = {
  '1-easy': PuzzleLevel.debutant,
  '2-player': PuzzleLevel.joueur,
  '3-advanced': PuzzleLevel.avance,
  '4-strong': PuzzleLevel.balaise,
  '5-expert': PuzzleLevel.expert,
  '6-mad': PuzzleLevel.fouFurieux,
};

/// Inverse of [playableCollectionKeyToLevel].
const Map<PuzzleLevel, String> levelToPlayableCollectionKey = {
  PuzzleLevel.debutant: '1-easy',
  PuzzleLevel.joueur: '2-player',
  PuzzleLevel.avance: '3-advanced',
  PuzzleLevel.balaise: '4-strong',
  PuzzleLevel.expert: '5-expert',
  PuzzleLevel.fouFurieux: '6-mad',
};

/// Human-readable label for tables and CLI output.
const Map<PuzzleLevel, String> levelLabels = {
  PuzzleLevel.debutant: 'Debutant',
  PuzzleLevel.joueur: 'Joueur',
  PuzzleLevel.avance: 'Avance',
  PuzzleLevel.balaise: 'Balaise',
  PuzzleLevel.expert: 'Expert',
  PuzzleLevel.fouFurieux: 'Fou furieux',
  PuzzleLevel.preRempli: 'Pre-rempli',
  PuzzleLevel.indetermine: 'Indetermine',
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
/// [maxPrefill] the puzzle is bucketed in [PuzzleLevel.preRempli]
/// regardless of the trace.
///
/// [solved] indicates whether the trace actually completed the puzzle
/// — if false we return [PuzzleLevel.indetermine] (timeout, partial
/// trace, or solver got stuck on a contradiction).
PuzzleLevel classifyTrace({
  required List<SolveStep> steps,
  required double prefillRatio,
  required bool solved,
  double maxPrefill = defaultMaxPrefill,
}) {
  if (prefillRatio > maxPrefill) return PuzzleLevel.preRempli;
  if (!solved) return PuzzleLevel.indetermine;

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

  if (forceMoves >= 2 || (forceMoves == 1 && maxForceDepth > 5)) {
    return PuzzleLevel.fouFurieux;
  }
  if (forceMoves == 0 && maxComplCx >= 4) return PuzzleLevel.balaise;
  if (forceMoves == 0 && maxComplCx > 0) return PuzzleLevel.avance;
  if (forceMoves == 1) return PuzzleLevel.expert;
  if (maxPropCx >= 3) return PuzzleLevel.joueur;
  return PuzzleLevel.debutant;
}

/// Recommend a playable [PuzzleLevel] from a `playerLevel` (cplx scale,
/// anchored at 50 = cohort average — see `docs/dev/adapt_to_player.md`).
///
/// Thresholds are deliberately hand-picked rather than derived from the
/// corpus medians: those medians (`debutant`=7, `joueur`=18, `avance`=36,
/// `balaise`=39, `expert`=37, `fouFurieux`=67) are not monotonic between
/// `avance`/`balaise`/`expert`, because cplx tracks predicted duration
/// while the cascade tracks cognitive type — they don't align in the
/// 35-45 zone. A "closest median" rule would flip the recommendation
/// erratically there. Explicit thresholds are stable and easy to test.
///
/// The cohort anchor at 50 means an average-paced player lands on the
/// boundary between `avance` and `balaise` — feels right.
PuzzleLevel recommendedLevelFor(int playerLevel) {
  if (playerLevel < 25) return PuzzleLevel.debutant;
  if (playerLevel < 40) return PuzzleLevel.joueur;
  if (playerLevel < 50) return PuzzleLevel.avance;
  if (playerLevel < 65) return PuzzleLevel.balaise;
  if (playerLevel < 80) return PuzzleLevel.expert;
  return PuzzleLevel.fouFurieux;
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
  if (prefill > maxPrefill) return PuzzleLevel.preRempli;

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
