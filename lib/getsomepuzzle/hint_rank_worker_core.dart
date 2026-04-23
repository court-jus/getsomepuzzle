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
    if (c != null) puzzle.constraints.add(c);
  }
  final baseline = puzzle.clone();
  final baselineMoves = baseline.propagateToFixpoint() ?? -1;
  return (puzzle, baselineMoves);
}

/// Whether adding [candidate] to [puzzle] unlocks more deductions than the
/// baseline. Returns false for invalid candidate strings, candidates that
/// make no extra progress, or candidates that make the puzzle contradictory.
bool classifyCandidate(Puzzle puzzle, String candidate, int baselineMoves) {
  final colonIdx = candidate.indexOf(':');
  if (colonIdx < 0) return false;
  final slug = candidate.substring(0, colonIdx);
  final p = candidate.substring(colonIdx + 1);
  final constraint = createConstraint(slug, p);
  if (constraint == null) return false;

  final test = puzzle.clone();
  test.constraints.add(constraint);
  final testMoves = test.propagateToFixpoint();
  return testMoves != null && testMoves > baselineMoves;
}
