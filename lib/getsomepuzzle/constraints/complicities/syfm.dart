import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// SY + FM complicity. Two branches:
///
/// 1. **Coloured anchor** — joining a free neighbour A to the
///    anchor's group forces A's symmetric A' (under the SY axis) to
///    the same colour by `SY.apply`. If the resulting configuration
///    `{anchor, A, A'}` (plus the rest of the grid) violates any
///    `ForbiddenMotif`, A cannot be the anchor's colour. Restricted
///    to free cells adjacent to the anchor's current group: only
///    those automatically join the group when coloured `c`, which is
///    what makes the SY symmetry argument bind.
///
/// 2. **Empty anchor** — try each domain colour as a hypothesis for
///    the anchor, run constraint-only propagation in each, and
///    intersect the resulting states. A free cell determined to the
///    same value across **every** feasible hypothesis is forced. If
///    one colour is infeasible, the anchor itself is forced to the
///    other. The SY constraint binds together with the rest of the
///    grid via the in-hypothesis propagation, which surfaces
///    deductions force-by-cell would miss.
class SYFMComplicity extends Complicity {
  /// Cap on propagation steps in each hypothetical run.
  static const int _maxHypothesisSteps = 200;

  @override
  String serialize() => "SYFMComplicity";

  @override
  bool isPresent(Puzzle puzzle) {
    return puzzle.constraints.whereType<SymmetryConstraint>().isNotEmpty &&
        puzzle.constraints.whereType<ForbiddenMotif>().isNotEmpty;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final fms = puzzle.constraints.whereType<ForbiddenMotif>().toList();
    if (fms.isEmpty) return null;

    for (final sy in puzzle.constraints.whereType<SymmetryConstraint>()) {
      final anchor = sy.indices.first;
      final c = puzzle.cellValues[anchor];
      Move? move;
      if (c != 0) {
        move = _solveColouredAnchor(sy, puzzle, fms, anchor, c);
      } else {
        move = _solveEmptyAnchor(sy, puzzle, anchor);
      }
      if (move != null) return move;
    }
    return null;
  }

  Move? _solveColouredAnchor(
    SymmetryConstraint sy,
    Puzzle puzzle,
    List<ForbiddenMotif> fms,
    int anchor,
    int c,
  ) {
    final opposite = puzzle.domain.firstWhere((v) => v != c);

    final anchorGroup = getGroups(
      puzzle,
    ).firstWhereOrNull((g) => g.contains(anchor));
    if (anchorGroup == null) return null;

    final frontier = <int>{};
    for (final m in anchorGroup) {
      for (final nei in puzzle.getNeighbors(m)) {
        if (puzzle.cellValues[nei] == 0) frontier.add(nei);
      }
    }

    for (final a in frontier) {
      final mirror = sy.computeSymmetry(puzzle, a);
      if (mirror == null || mirror == a) continue;
      if (puzzle.cellValues[mirror] == opposite) continue;

      final clone = puzzle.clone();
      clone.cells[a].setForSolver(c);
      if (puzzle.cellValues[mirror] == 0) {
        clone.cells[mirror].setForSolver(c);
      }

      for (final fm in fms) {
        if (!fm.verify(clone)) {
          return Move(a, opposite, this, complexity: 4);
        }
      }
    }
    return null;
  }

  Move? _solveEmptyAnchor(SymmetryConstraint sy, Puzzle puzzle, int anchor) {
    final feasible = <int>[];
    final colorStates = <int, List<int>>{};

    for (final color in puzzle.domain) {
      final hyp = puzzle.clone();
      // Disable complicities in the hypothetical to avoid recursive
      // calls of this very complicity (and others). Plain constraint
      // propagation is enough for the SY × FM interactions we want
      // to capture here.
      hyp.complicities = [];
      hyp.cells[anchor].setForSolver(color);

      bool failed = false;
      for (int step = 0; step < _maxHypothesisSteps; step++) {
        final m = hyp.findAMove(checkErrors: false, tryForce: false);
        if (m == null) break;
        if (m.isImpossible != null) {
          failed = true;
          break;
        }
        hyp.setValue(m.idx, m.value);
        if (hyp.complete) break;
      }
      // A hypothesis that ends with at least one constraint failing
      // is also infeasible — propagation may simply have stopped
      // before noticing.
      if (!failed) {
        for (final cst in hyp.constraints) {
          if (!cst.verify(hyp)) {
            failed = true;
            break;
          }
        }
      }

      if (failed) continue;
      feasible.add(color);
      colorStates[color] = hyp.cellValues;
    }

    if (feasible.isEmpty) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (feasible.length == 1) {
      // Only one colour for the anchor leads to a feasible state.
      return Move(anchor, feasible.first, this, complexity: 4);
    }
    // Both colours feasible — find a free cell whose value is the
    // same across every feasible hypothesis.
    for (int i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] != 0) continue;
      final v = colorStates[feasible.first]![i];
      if (v == 0) continue;
      bool unanimous = true;
      for (final color in feasible.skip(1)) {
        if (colorStates[color]![i] != v) {
          unanimous = false;
          break;
        }
      }
      if (unanimous) {
        return Move(i, v, this, complexity: 4);
      }
    }
    return null;
  }
}
