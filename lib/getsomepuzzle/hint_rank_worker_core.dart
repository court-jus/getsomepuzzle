import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class HintRankResult {
  final List<String> ranked;
  final int usefulCount;
  HintRankResult(this.ranked, this.usefulCount);
}

/// Reconstruct the puzzle in its current player state and compute the baseline
/// propagation move count. Returns `(puzzle, baselineMoves)` where
/// `baselineMoves` is -1 if the baseline was already contradictory (rare; any
/// candidate that makes progress still wins against -1).
(Puzzle, int) prepareRanking({
  required int width,
  required int height,
  required List<int> domain,
  required List<int> cellValues,
  required List<String> existingConstraints,
}) {
  final puzzle = Puzzle.empty(width, height, domain);
  for (int i = 0; i < cellValues.length; i++) {
    if (cellValues[i] != 0) {
      puzzle.cells[i].setForSolver(cellValues[i]);
    }
  }
  for (final cs in existingConstraints) {
    final colonIdx = cs.indexOf(':');
    if (colonIdx < 0) continue;
    final slug = cs.substring(0, colonIdx);
    final p = cs.substring(colonIdx + 1);
    final c = createConstraint(slug, p);
    if (c != null) puzzle.addConstraint(c);
  }
  final baseline = puzzle.clone();
  final baselineMoves = baseline.propagateToFixpoint() ?? -1;
  return (puzzle, baselineMoves);
}

/// Score [candidate] by the number of *additional* propagation moves it
/// unlocks over [baselineMoves]. Returns `null` for invalid candidate
/// strings, candidates that make no extra progress, or candidates that
/// make the puzzle contradictory. Otherwise returns a positive integer:
/// higher = unlocks more cells immediately = "more useful" hint.
///
/// Callers should sort candidates by descending score so the hint
/// button surfaces the most useful constraint first. A null score puts
/// the candidate in the non-useful tail.
int? scoreCandidate(Puzzle puzzle, String candidate, int baselineMoves) {
  final colonIdx = candidate.indexOf(':');
  if (colonIdx < 0) return null;
  final slug = candidate.substring(0, colonIdx);
  final p = candidate.substring(colonIdx + 1);
  final constraint = createConstraint(slug, p);
  if (constraint == null) return null;

  final test = puzzle.clone();
  test.addConstraint(constraint);
  final testMoves = test.propagateToFixpoint();
  if (testMoves == null) return null;
  final delta = testMoves - baselineMoves;
  if (delta <= 0) return null;
  return delta;
}
