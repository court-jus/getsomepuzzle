import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// GS + QA complicity: a `GroupSize` constraint anchored on cell `i`
/// with target size `s`, combined with a `QuantityConstraint` capping
/// colour `c` at `n` cells in the whole grid, rules out colour `c`
/// for the group of `i` whenever the group plus the `c`-cells already
/// placed outside it cannot fit under `n`.
///
/// Example: `GS:15.9` + `QA:1.8`. If cell 15 were colour 1, the group
/// would need 9 connected 1-cells, while at most 8 are allowed in the
/// grid. So cell 15 must take the opposite colour.
///
/// `GSAllComplicity` doesn't catch this case because its sealing
/// enumeration is gated by `_maxGap` (6): for a gap of 9 it bails out
/// without checking feasibility. The deduction here is arithmetic and
/// runs in O(constraints × colors).
class GSQAComplicity extends Complicity {
  @override
  String serialize() => 'GSQAComplicity';

  @override
  (String, String) get slugs => ('GS', 'QA');

  @override
  bool isPresent(Puzzle puzzle) {
    return puzzle.constraints.whereType<GroupSize>().isNotEmpty &&
        puzzle.constraints.whereType<QuantityConstraint>().isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final qas = puzzle.constraints.whereType<QuantityConstraint>().toList();
    for (final gs in puzzle.constraints.whereType<GroupSize>()) {
      final move = _solveGS(gs, qas, puzzle);
      if (move != null) return move;
    }
    return null;
  }

  Move? _solveGS(GroupSize gs, List<QuantityConstraint> qas, Puzzle puzzle) {
    final anchor = gs.indices.first;
    final anchorColor = puzzle.cellValues[anchor];

    final feasible = <int>[];
    for (final color in puzzle.domain) {
      if (_colorIsFeasible(gs, color, qas, puzzle)) {
        feasible.add(color);
      }
    }

    if (feasible.isEmpty) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (feasible.length != 1) return null;

    final forced = feasible.first;
    if (anchorColor == 0) {
      return Move(anchor, forced, this, complexity: 3);
    }
    if (anchorColor != forced) {
      return Move(0, 0, this, isImpossible: this);
    }
    return null;
  }

  /// `true` when colouring the anchor's group `color` is compatible
  /// with the QA bounds on `color`. Considers the merged cluster the
  /// anchor would form with already-coloured `color` neighbours.
  bool _colorIsFeasible(
    GroupSize gs,
    int color,
    List<QuantityConstraint> qas,
    Puzzle puzzle,
  ) {
    final qa = qas.firstWhereOrNull((q) => q.value == color);
    if (qa == null) return true;

    final anchor = gs.indices.first;
    final mergedSize = _hypotheticalMergedSize(puzzle, anchor, color);
    if (mergedSize > gs.size) {
      // Existing same-colour merge already overshoots the GS target.
      // That's a GS-level contradiction, not the QA arithmetic we
      // model here — let GroupSize.verify / apply surface it.
      return false;
    }

    final placedSameColor = puzzle.cellValues.where((v) => v == color).length;
    // `mergedSize` counts the would-be cluster including the anchor.
    // The anchor itself only contributes to `placedSameColor` if it is
    // already coloured `color`; otherwise (empty or different colour)
    // the cluster size overcounts by 1 versus currently-placed cells.
    final anchorMatches = puzzle.cellValues[anchor] == color;
    final placedInsideGroup = anchorMatches ? mergedSize : mergedSize - 1;
    final placedOutsideGroup = placedSameColor - placedInsideGroup;
    // Once the group is grown to `gs.size`, the grid has at least
    // `gs.size + placedOutsideGroup` cells of `color`. Compare against
    // the QA cap.
    return gs.size + placedOutsideGroup <= qa.count;
  }

  /// Size of the cluster that would contain the anchor if it were
  /// coloured `color`, i.e. 4-connected flood-fill from the anchor
  /// over cells of `color` (treating the anchor as `color`).
  static int _hypotheticalMergedSize(Puzzle puzzle, int anchor, int color) {
    final visited = <int>{anchor};
    final queue = <int>[anchor];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final nei in puzzle.getNeighbors(cur)) {
        if (visited.contains(nei)) continue;
        if (puzzle.cellValues[nei] != color) continue;
        visited.add(nei);
        queue.add(nei);
      }
    }
    return visited.length;
  }
}
