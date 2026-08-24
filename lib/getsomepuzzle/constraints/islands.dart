import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// The Islands constraint (`IS`): in the solved puzzle, every connected
/// group of a given colour must be isolated from every other group of that
/// colour — including diagonally. No two distinct groups may touch, even at
/// a corner.
///
/// Orthogonal contact is not expressible: two 4-adjacent cells of the same
/// colour are by definition the same group. The operative content of the
/// rule is therefore exclusively **diagonal contact** between *final*
/// distinct groups.
///
/// Open states are judged on **mergeability**: diagonal contact between two
/// current groups is only a violation if the groups can never grow
/// together. Two groups can merge iff some path of capable cells (coloured,
/// or free with `color` still in options) joins them; the capable-component
/// partition only refines under forward play, so "different component
/// today" proves permanent separation while "same component" correctly
/// leaves the state undecided.
///
/// Pure avoidance constraint (like `FM`/`CH`): `apply` forbids placements
/// (`RemoveOption`) and never emits `SetValue` — the positive forcing is
/// left to the counting constraints (`QA`, `GC`, `RC`).
class IslandsConstraint extends Constraint {
  @override
  String get slug => 'IS';

  CellValue color = CellValue.free;

  @override
  Set<CellValue> get referencedColors => {color};

  IslandsConstraint(String strParams) {
    color = cellRepresentationToValue(strParams);
  }

  @override
  String serialize() => 'IS:${cellValueToString(color)}';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      IslandsConstraint(cellValueToString(color));

  @override
  String toString() {
    return '${cellValueToString(color)} islands';
  }

  @override
  String toHuman(Puzzle puzzle) {
    return 'Islands of colour ${cellValueToString(color)}: groups never '
        'touch, even diagonally';
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    return [for (final value in domain) cellValueToString(value)];
  }

  /// A cell can host [color] now or in any future state: already coloured,
  /// or free with [color] still among its options (a pruned option can
  /// never come back).
  bool _capable(Puzzle puzzle, int i) =>
      puzzle.cellValues[i] == color ||
      (puzzle.cellValues[i] == CellValue.free &&
          puzzle.cells[i].options.contains(color));

  /// Connected components of the capable set, as a component id per cell
  /// (-1 for non-capable cells).
  ///
  /// Two colour groups end up merged in some completion iff they share a
  /// component here. The partition only ever refines under forward play: a
  /// cell leaves the capable set when coloured another colour or when an
  /// option is pruned, and nothing ever joins it — so cells in different
  /// components today stay separated forever.
  List<int> _capableComponents(Puzzle puzzle) {
    final n = puzzle.cellValues.length;
    final comps = List<int>.filled(n, -1);
    var next = 0;
    for (var start = 0; start < n; start++) {
      if (comps[start] != -1 || !_capable(puzzle, start)) continue;
      comps[start] = next;
      final stack = <int>[start];
      while (stack.isNotEmpty) {
        for (final nb in puzzle.getNeighbors(stack.removeLast())) {
          if (comps[nb] == -1 && _capable(puzzle, nb)) {
            comps[nb] = next;
            stack.add(nb);
          }
        }
      }
      next++;
    }
    return comps;
  }

  /// Violated iff two **coloured** cells of [color] share a corner while
  /// lying in different capable components — a diagonal contact that no
  /// future growth can merge away. Contact between groups that are still
  /// connectable through capable cells is not a violation: colouring the
  /// bridge merges them into one group.
  ///
  /// On a complete puzzle there are no free cells, so components collapse
  /// to the actual colour groups and this degenerates to the exact final
  /// check.
  @override
  bool verify(Puzzle puzzle) {
    final comps = _capableComponents(puzzle);
    for (var i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] != color) continue;
      for (final d in diagonalNeighbors(puzzle, i)) {
        if (puzzle.cellValues[d] == color && comps[d] != comps[i]) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    // Branch 1: permanently violated state (diagonal contact across
    // incapable-of-merging groups).
    if (!verify(puzzle)) {
      return Impossible(this);
    }
    // Branch 2: diagonal-contact prune. Colouring `f` creates a permanent
    // violation iff some coloured diagonal neighbour `d` of `f` sits in a
    // different capable component: after colouring, `(f, d)` is a
    // coloured diagonal pair that no future growth can merge. Components
    // only refine over time, so the cross-component relation is stable and
    // the prune is sound without any simulation.
    //
    // No-op guard (same convention as DF/GS): only emit the RemoveOption
    // while `color` is still present in `f`'s options, otherwise a 3-colour
    // propagation loop would re-emit the same prune forever.
    final comps = _capableComponents(puzzle);
    for (var f = 0; f < puzzle.cellValues.length; f++) {
      if (puzzle.cellValues[f] != CellValue.free) continue;
      if (!puzzle.cells[f].options.contains(color)) continue;
      var prunes = false;
      for (final d in diagonalNeighbors(puzzle, f)) {
        if (puzzle.cellValues[d] == color && comps[d] != comps[f]) {
          prunes = true;
          break;
        }
      }
      if (prunes) {
        return RemoveOption(f, color, this, complexity: 1);
      }
    }
    // Branch 3: mandatory-merge articulation. A diagonally-connected pair
    // of `color` groups must end up merged (branch 1 condemns them
    // otherwise). If a single free capable cell lies on every capable path
    // between such a pair, that cell is unavoidable and must take `color`
    // — same articulation logic as LT's step 4.
    final merge = _forcedMerge(puzzle);
    if (merge != null) return merge;
    return null;
  }

  /// Branch 3 helper — for each pair of distinct [color] groups that share
  /// a corner, find a free capable cell whose removal disconnects the two
  /// groups in the capable graph (`blockingDisconnectsMembers`, the LT/GS
  /// articulation test). Such a cell lies on every possible merge path, so
  /// the mandatory merge pins it to [color].
  ///
  /// Reachability precondition: reaching this point means `verify` passed,
  /// so every diagonally-touching pair is already same-component — the
  /// vacuously-true trap of the helper cannot fire.
  Move? _forcedMerge(Puzzle puzzle) {
    final groups = getColorGroups(puzzle, color);
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        var touches = false;
        for (final a in groups[i]) {
          if (touches) break;
          for (final d in diagonalNeighbors(puzzle, a)) {
            if (groups[j].contains(d)) {
              touches = true;
              break;
            }
          }
        }
        if (!touches) continue;
        for (var x = 0; x < puzzle.cellValues.length; x++) {
          if (puzzle.cellValues[x] != CellValue.free) continue;
          if (!puzzle.cells[x].options.contains(color)) continue;
          if (blockingDisconnectsMembers(
            puzzle,
            x,
            color,
            [groups[i].first, groups[j].first],
          )) {
            return SetValue(x, color, this, complexity: 3);
          }
        }
      }
    }
    return null;
  }

  /// Grayout: conservative, like SH. `verify` holds and no free cell still
  /// has [color] as an option.
  ///
  /// An early grayout ("branch 2 saturated ∧ no free-free capable diagonal
  /// pair") is unsound: the capable-component partition keeps refining
  /// while free capable cells remain — a bridge cell painted the opposite
  /// colour splits components and can legitimately revive branch 2 or even
  /// create a branch-1 impossibility later. Only a fully resolved capable
  /// set guarantees `apply` can never fire again.
  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    for (var i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] == CellValue.free &&
          puzzle.cells[i].options.contains(color)) {
        return false;
      }
    }
    return true;
  }
}
