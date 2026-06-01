import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

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

    final feasible = <CellValue>[];
    for (final color in puzzle.domain) {
      if (_colorIsFeasible(gs, color, qas, puzzle)) {
        feasible.add(color);
      }
    }

    if (feasible.isEmpty) {
      return Impossible(this);
    }

    // Anchor already committed: a contradiction iff its colour is one
    // the QA arithmetic ruled out. Otherwise nothing to add.
    if (anchorColor != CellValue.free) {
      if (!feasible.contains(anchorColor)) {
        return Impossible(this);
      }
      return null;
    }

    // Anchor free with a single feasible colour: force it — unless that
    // colour has been pruned from the anchor's options (3+-colour domain),
    // in which case no in-options colour is QA-feasible and the state is
    // unsatisfiable.
    if (feasible.length == 1) {
      if (puzzle.cells[anchor].options.contains(feasible.first)) {
        return SetValue(anchor, feasible.first, this, complexity: 3);
      }
      return Impossible(this);
    }

    // Several colours still feasible — only reachable on domain ≥ 3.
    // Prune any infeasible colour still sitting in the anchor's option
    // set. On a 2-colour domain this loop never fires (both colours are
    // either feasible or the single-feasible branch above already ran).
    final anchorCell = puzzle.cells[anchor];
    for (final color in puzzle.domain) {
      if (!feasible.contains(color) && anchorCell.options.contains(color)) {
        return RemoveOption(anchor, color, this, complexity: 3);
      }
    }
    return null;
  }

  /// `true` when colouring the anchor's group `color` is compatible
  /// with the QA bounds on `color`. Considers the merged cluster the
  /// anchor would form with already-coloured `color` neighbours.
  bool _colorIsFeasible(
    GroupSize gs,
    CellValue color,
    List<QuantityConstraint> qas,
    Puzzle puzzle,
  ) {
    final qa = qas.firstWhereOrNull((q) => q.color == color);
    if (qa == null) return true;

    final anchor = gs.indices.first;
    final mergedSize = _hypotheticalMergedSize(puzzle, anchor, color);
    if (mergedSize > gs.size) {
      // Existing same-colour merge already overshoots the GS target.
      // That's a GS-level contradiction, not the QA arithmetic we
      // model here — let GroupSize.verify / apply surface it.
      return false;
    }

    // Lower bound on the grid's total `color` count if the anchor takes
    // `color`: the `gs.size` cells of its group, plus every already-placed
    // `color` cell that *cannot* belong to that group.
    //
    // A placed cell is only "definitely outside" the group when no
    // connected run of ≤ `gs.size` cells could ever link it to the
    // anchor — i.e. its 4-connected distance over {`color` ∪ free} cells
    // is ≥ `gs.size` (a connected subgraph containing both would need
    // more than `gs.size` cells), or it is wholly unreachable that way.
    // Cells closer than that might still join the group as the free
    // intermediates get coloured, so counting them as "outside" would be
    // unsound: the old `placedSameColor - placedInsideGroup` heuristic
    // counted every cell outside the *immediate* committed cluster as
    // outside, which wrongly forced cells on valid puzzles whenever a
    // future group member was still free (e.g. once SY's weaker 3-colour
    // port stopped colouring the connecting cells early).
    final dist = _distancesOverPassable(puzzle, anchor, color);
    var definitelyOutside = 0;
    for (int i = 0; i < puzzle.cellValues.length; i++) {
      if (i == anchor || puzzle.cellValues[i] != color) continue;
      final d = dist[i];
      if (d == null || d >= gs.size) definitelyOutside++;
    }
    return gs.size + definitelyOutside <= qa.count;
  }

  /// 4-connected BFS edge-distances from [anchor], traversing only cells
  /// that are either [color] or free — the cells that could end up part
  /// of a `color` group containing the anchor. Cells unreachable this way
  /// are absent from the returned map.
  static Map<int, int> _distancesOverPassable(
    Puzzle puzzle,
    int anchor,
    CellValue color,
  ) {
    final dist = <int, int>{anchor: 0};
    final queue = <int>[anchor];
    var head = 0;
    while (head < queue.length) {
      final cur = queue[head++];
      final d = dist[cur]!;
      for (final nei in puzzle.getNeighbors(cur)) {
        if (dist.containsKey(nei)) continue;
        final v = puzzle.cellValues[nei];
        if (v != color && v != CellValue.free) continue;
        dist[nei] = d + 1;
        queue.add(nei);
      }
    }
    return dist;
  }

  /// Size of the cluster that would contain the anchor if it were
  /// coloured `color`, i.e. 4-connected flood-fill from the anchor
  /// over cells of `color` (treating the anchor as `color`).
  static int _hypotheticalMergedSize(
    Puzzle puzzle,
    int anchor,
    CellValue color,
  ) {
    return floodFill(puzzle, [
      anchor,
    ], (i) => puzzle.cellValues[i] == color).length;
  }
}
