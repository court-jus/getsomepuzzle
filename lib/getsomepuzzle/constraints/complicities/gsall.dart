import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// GS + (anything) complicity. For each `GroupSize` constraint we
/// enumerate every way to seal off a connected group of exactly
/// `gs.size` cells around the anchor (including merges with
/// same-colour cells reached via the added cells), drop the
/// sealings that violate **any** constraint of the puzzle (FMs,
/// other GSs, parity, symmetry, …), and force every cell whose
/// role (in-group / sealed) is identical across all surviving
/// sealings.
///
/// Anchor handling has two branches:
/// 1. **Coloured anchor** — usual case. Survivors are sealings of
///    the anchor's group; partial determination forces unanimous
///    cells.
/// 2. **Empty anchor** — try each domain colour. If only one
///    colour admits any surviving sealing, the anchor is forced to
///    that colour. (Other deductions cascade once the anchor is
///    coloured.)
class GSAllComplicity extends Complicity {
  /// Cap on `gs.size - |currentGroup|` — limits combinatorial cost.
  /// With merges the real number of decisions is often much smaller.
  static const int _maxGap = 6;

  /// Slug of the constraint that explains this particular deduction
  /// alongside `GS`. Set when [apply] returns a move whose sealings
  /// were all rejected by the same single constraint type. Falls back
  /// to `'*'` (any) when blockers are heterogeneous or absent.
  final String _secondSlug;

  GSAllComplicity([this._secondSlug = '*']);

  @override
  String serialize() => "GSAllComplicity";

  @override
  (String, String) get slugs => ('GS', _secondSlug);

  @override
  bool isPresent(Puzzle puzzle) {
    return puzzle.constraints.whereType<GroupSize>().isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    for (final gs in puzzle.constraints.whereType<GroupSize>()) {
      final move = _solveGS(gs, puzzle);
      if (move != null) return move;
    }
    return null;
  }

  /// Wrap [move] so its `contributors` lists the [gs] constraint and
  /// every specific constraint instance in [blockers]. Also retag
  /// `givenBy` to a `GSAllComplicity` with the unique blocker slug
  /// when all blockers share the same slug, so the hint UI can render
  /// "GS + FM" instead of "GS + other".
  Move _tagContributors(Move move, Set<Constraint> blockers, GroupSize gs) {
    final involved = <CanApply>[gs, ...blockers];
    final withContribs = switch (move) {
      SetValue(:final idx, :final value, :final complexity) => SetValue(
        idx,
        value,
        this,
        complexity: complexity,
        contributors: involved,
      ),
      RemoveOption(
        :final idx,
        :final option,
        :final complexity,
        :final isForce,
        :final forceDepth,
      ) =>
        RemoveOption(
          idx,
          option,
          this,
          complexity: complexity,
          isForce: isForce,
          forceDepth: forceDepth,
          contributors: involved,
        ),
      Impossible() => Impossible(this, contributors: involved),
    };
    final slugs = blockers.map((c) => c.slug).toSet();
    if (slugs.length != 1) return withContribs;
    return withContribs.retag(GSAllComplicity(slugs.first));
  }

  Move? _solveGS(GroupSize gs, Puzzle puzzle) {
    final anchor = gs.indices.first;
    final c = puzzle.cellValues[anchor];
    if (c != CellValue.free) {
      final blockers = <Constraint>{};
      final survivors = _enumerateForColor(puzzle, gs, anchor, c, blockers);
      if (survivors == null) return null;
      if (survivors.isEmpty) {
        return _tagContributors(Impossible(this), blockers, gs);
      }
      final move = _forceFromSurvivors(puzzle, survivors, c);
      return move == null ? null : _tagContributors(move, blockers, gs);
    }

    // Empty anchor: try each domain colour. Track blockers across
    // both hypotheses so the hint surfaces a single rejecting
    // constraint when one is responsible for collapsing the choice.
    final feasible = <CellValue>[];
    final blockers = <Constraint>{};
    for (final color in puzzle.domain) {
      final hyp = puzzle.clone();
      hyp.cells[anchor].setForSolver(color);
      final survivors = _enumerateForColor(hyp, gs, anchor, color, blockers);
      if (survivors == null) {
        // Gap too big to enumerate — assume feasible (don't risk a
        // false force).
        feasible.add(color);
      } else if (survivors.isNotEmpty) {
        feasible.add(color);
      }
    }
    if (feasible.isEmpty) {
      return _tagContributors(Impossible(this), blockers, gs);
    }
    if (feasible.length == 1) {
      // Tier 4: trying both colours and concluding only one works
      // is a step harder than the coloured-anchor case (per
      // docs/dev/constraint_complicity.md). Force the survivor colour —
      // unless it has been pruned from the anchor's options (3+-colour
      // domain), in which case no allowed colour is feasible → impossible.
      if (puzzle.cells[anchor].options.contains(feasible.first)) {
        return _tagContributors(
          SetValue(anchor, feasible.first, this, complexity: 4),
          blockers,
          gs,
        );
      }
      return _tagContributors(Impossible(this), blockers, gs);
    }
    return null;
  }

  /// Returns the list of surviving sealings for the given anchor
  /// colour, or null when the gap is too large to enumerate. Every
  /// constraint instance that rejected at least one sealing is added
  /// to [blockers] so the caller can surface a meaningful hint.
  List<_Survivor>? _enumerateForColor(
    Puzzle puzzle,
    GroupSize gs,
    int anchor,
    CellValue color,
    Set<Constraint> blockers,
  ) {
    // All cells of `color` connected (4-adjacency) to the anchor.
    final group = floodFill(puzzle, [
      anchor,
    ], (i) => puzzle.cellValues[i] == color);
    if (group.length > gs.size) return [];
    if (group.length == gs.size) {
      return _checkSealedTarget(puzzle, group, color, blockers);
    }
    final gap = gs.size - group.length;
    if (gap > _maxGap) return null;

    final survivors = <_Survivor>[];
    _enumerate(puzzle, group, <int>{}, gs.size, color, (g, s) {
      final clone = puzzle.clone();
      for (final idx in g) {
        if (puzzle.cellValues[idx] == CellValue.free) {
          clone.cells[idx].setForSolver(color);
        }
      }
      for (final idx in s) {
        if (puzzle.cellValues[idx] == CellValue.free) {
          // Sealing means "not `color`", not "a specific opposite colour".
          // On a 2-colour domain pruning `color` collapses to the unique
          // opposite (exact, unchanged). On 3+ colours the cell stays free
          // with its remaining options, so a colour-counting constraint
          // can't reject a sealing that another opposite would have
          // satisfied — which would discard a valid sealing and produce a
          // false force / false impossibility.
          clone.cells[idx].removeOptionForSolver(color);
        }
      }
      for (final cst in puzzle.constraints) {
        if (!cst.verify(clone)) {
          blockers.add(cst);
          return;
        }
      }
      survivors.add(_Survivor(g, s));
    });
    return survivors;
  }

  /// Group already at target size — verify that sealing the frontier
  /// is consistent. Returns a single survivor or empty. Records the
  /// specific rejecting constraint in [blockers] when sealing fails.
  List<_Survivor> _checkSealedTarget(
    Puzzle puzzle,
    Set<int> group,
    CellValue color,
    Set<Constraint> blockers,
  ) {
    final sealed = <int>{};
    for (final m in group) {
      for (final nei in puzzle.getNeighbors(m)) {
        if (group.contains(nei)) continue;
        if (puzzle.cellValues[nei] != CellValue.free) continue;
        sealed.add(nei);
      }
    }
    final clone = puzzle.clone();
    for (final idx in sealed) {
      // "Not `color`" — see _enumerateForColor. Collapses to the unique
      // opposite on a 2-colour domain, stays free on 3+ colours.
      clone.cells[idx].removeOptionForSolver(color);
    }
    for (final cst in puzzle.constraints) {
      if (!cst.verify(clone)) {
        blockers.add(cst);
        return [];
      }
    }
    return [_Survivor(group, sealed)];
  }

  Move? _forceFromSurvivors(
    Puzzle puzzle,
    List<_Survivor> survivors,
    CellValue c,
  ) {
    final candidates = <int>{};
    for (final s in survivors) {
      for (final idx in s.group) {
        if (puzzle.cellValues[idx] == CellValue.free) candidates.add(idx);
      }
      for (final idx in s.sealed) {
        if (puzzle.cellValues[idx] == CellValue.free) candidates.add(idx);
      }
    }
    // We pass through every candidate looking for an emittable deduction;
    // a candidate that's "allInGroup but c was already pruned" or
    // "allInSealed but c was already pruned" simply doesn't yield a move
    // (the deduction would target an option that has already been removed).
    for (final idx in candidates) {
      bool allInGroup = true;
      bool allInSealed = true;
      for (final s in survivors) {
        if (!s.group.contains(idx)) allInGroup = false;
        if (!s.sealed.contains(idx)) allInSealed = false;
        if (!allInGroup && !allInSealed) break;
      }
      if (allInGroup && puzzle.cells[idx].options.contains(c)) {
        return SetValue(idx, c, this, complexity: 3);
      }
      // "allInSealed" means the cell is OUTSIDE the gs group in every
      // surviving sealing → the cell cannot take `c`. On 2-colour
      // puzzles the original code forced the unique opposite value; on
      // 3+ colours we express the same fact as `removeOption: c`.
      if (allInSealed && puzzle.cells[idx].options.contains(c)) {
        return RemoveOption(idx, c, this, complexity: 3);
      }
    }
    return null;
  }

  /// Recursive sealing enumeration: at each step, pick the canonical
  /// (lowest-indexed) free cell adjacent to the current `group` and
  /// not yet sealed, then branch on whether it joins the group
  /// (with same-colour merges flooded in) or gets sealed. A branch
  /// terminates as soon as the group reaches the target size — every
  /// remaining frontier cell is auto-sealed.
  static void _enumerate(
    Puzzle puzzle,
    Set<int> group,
    Set<int> sealed,
    int target,
    CellValue c,
    void Function(Set<int>, Set<int>) callback,
  ) {
    if (group.length > target) return;

    final frontier = <int>{};
    for (final m in group) {
      for (final nei in puzzle.getNeighbors(m)) {
        if (group.contains(nei)) continue;
        if (puzzle.cellValues[nei] != CellValue.free) continue;
        if (sealed.contains(nei)) continue;
        frontier.add(nei);
      }
    }

    if (group.length == target) {
      callback(group, {...sealed, ...frontier});
      return;
    }

    if (frontier.isEmpty) return;

    int pick = frontier.first;
    for (final f in frontier) {
      if (f < pick) pick = f;
    }

    // Only branch on outcomes the cell can actually take: a frontier cell
    // that has had `c` pruned can't join the group, and one whose only
    // remaining option is `c` can't be sealed. Exploring an infeasible
    // branch would build an impossible clone and add a bogus survivor.
    final options = puzzle.cells[pick].options;
    if (options.contains(c)) {
      final newGroup = _addWithMerges(puzzle, group, pick, c);
      _enumerate(puzzle, newGroup, sealed, target, c, callback);
    }
    if (options.any((v) => v != c)) {
      final newSealed = {...sealed, pick};
      _enumerate(puzzle, group, newSealed, target, c, callback);
    }
  }

  /// Add [newCell] to [group], then flood-fill through every
  /// already-coloured `c`-cell reachable from [newCell] (merging
  /// previously-disconnected same-colour groups into one). The fill does
  /// not propagate through cells already in [group]: only the merges
  /// triggered by [newCell] itself are picked up.
  static Set<int> _addWithMerges(
    Puzzle puzzle,
    Set<int> group,
    int newCell,
    CellValue c,
  ) {
    final merged = floodFill(puzzle, [
      newCell,
    ], (i) => puzzle.cellValues[i] == c && !group.contains(i));
    return {...group, ...merged};
  }
}

class _Survivor {
  final Set<int> group;
  final Set<int> sealed;
  _Survivor(this.group, this.sealed);
}
