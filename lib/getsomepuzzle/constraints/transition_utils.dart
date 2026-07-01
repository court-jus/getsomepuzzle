import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Count adjacent transitions in [line] where both cells are filled
/// and have different values. A transition is any adjacent pair of
/// different-filled cells, regardless of which color they are.
int countTransitions(List<Cell> line) {
  int t = 0;
  for (int i = 0; i < line.length - 1; i++) {
    final a = line[i].value;
    final b = line[i + 1].value;
    if (a != CellValue.free && b != CellValue.free && a != b) {
      t++;
    }
  }
  return t;
}

/// Count adjacent pairs in [line] where at least one cell is free (value == 0).
int countFreePairs(List<Cell> line) {
  int fp = 0;
  for (int i = 0; i < line.length - 1; i++) {
    if (line[i].value == CellValue.free ||
        line[i + 1].value == CellValue.free) {
      fp++;
    }
  }
  return fp;
}

/// Shared [verify] logic for row/column transition constraints.
bool verifyTransitionLine(Puzzle puzzle, List<Cell> line, int count) {
  final t = countTransitions(line);
  if (puzzle.complete) return t == count;
  if (t > count) return false;
  final fp = countFreePairs(line);
  if (t + fp < count) return false;

  // Endpoint parity: for binary domains, the parity of the transition
  // count must match the endpoint color relationship. Same ends → even
  // transitions; different ends → odd transitions.
  if (puzzle.domain.length == 2) {
    final firstVal = line.first.value;
    final lastVal = line.last.value;
    if (firstVal != CellValue.free && lastVal != CellValue.free) {
      final endsMatch = firstVal == lastVal;
      if (endsMatch && count.isOdd) return false;
      if (!endsMatch && count.isEven) return false;
    }
  } else if (count == 1) {
    // 3+ colours: a single transition means exactly two runs, so the two
    // endpoints must differ. Both endpoints coloured and equal is unreachable.
    // (For count >= 2 the endpoints can be equal or not — no deduction.)
    final firstVal = line.first.value;
    final lastVal = line.last.value;
    if (firstVal != CellValue.free &&
        lastVal != CellValue.free &&
        firstVal == lastVal) {
      return false;
    }
  }

  return true;
}

/// Shared [apply] logic for row/column transition constraints.
Move? applyTransitionLine(
  Puzzle puzzle,
  List<Cell> line,
  int count,
  CanApply constraint,
) {
  final t = countTransitions(line);
  final fp = countFreePairs(line);

  if (t > count) {
    return Impossible(constraint);
  }

  if (t + fp < count) {
    return Impossible(constraint);
  }

  // Endpoint parity deduction (binary domain only): when exactly one
  // endpoint is known, the transition count parity determines the other.
  // Even count → same color; odd count → opposite color.
  if (puzzle.domain.length == 2) {
    final firstVal = line.first.value;
    final lastVal = line.last.value;
    if (firstVal == CellValue.free && lastVal != CellValue.free) {
      final opposite = puzzle.domain.firstWhere((v) => v != lastVal);
      final forced = count.isEven ? lastVal : opposite;
      return SetValue(line.first.idx, forced, constraint, complexity: 3);
    }
    if (firstVal != CellValue.free && lastVal == CellValue.free) {
      final opposite = puzzle.domain.firstWhere((v) => v != firstVal);
      final forced = count.isEven ? firstVal : opposite;
      return SetValue(line.last.idx, forced, constraint, complexity: 3);
    }
  } else if (count == 1) {
    // 3+ colours: exactly one transition → two runs → the endpoints differ.
    // We can't force a unique colour (two remain), but we can prune the known
    // end's colour from the free end, or flag the contradiction.
    final first = line.first;
    final last = line.last;
    final fv = first.value;
    final lv = last.value;
    if (fv != CellValue.free && lv != CellValue.free) {
      if (fv == lv) return Impossible(constraint);
    } else if (fv != CellValue.free && last.options.contains(fv)) {
      return RemoveOption(last.idx, fv, constraint, complexity: 3);
    } else if (lv != CellValue.free && first.options.contains(lv)) {
      return RemoveOption(first.idx, lv, constraint, complexity: 3);
    }
  }

  // Saturated: no more transitions allowed. Valid for any domain size —
  // forcing a free cell to match its filled neighbour avoids any new
  // transition regardless of how many colours exist.
  if (t == count) {
    for (int i = 0; i < line.length; i++) {
      if (line[i].value != CellValue.free) continue;
      CellValue? forced;
      if (i > 0 && line[i - 1].value != CellValue.free) {
        forced = line[i - 1].value;
      }
      if (i < line.length - 1 && line[i + 1].value != CellValue.free) {
        final nv = line[i + 1].value;
        if (forced == null) {
          forced = nv;
        } else if (forced != nv) {
          return Impossible(constraint);
        }
      }
      if (forced != null) {
        // The cell must match its filled neighbour to avoid a new transition.
        // If that colour has been pruned from its options (3+-colour domain),
        // no allowed value keeps the transition count within budget.
        if (!line[i].options.contains(forced)) {
          return Impossible(constraint);
        }
        return SetValue(line[i].idx, forced, constraint, complexity: 1);
      }
    }
    return null;
  }

  // Full need: every free pair must produce a transition. Only yields a
  // unique replacement value when the domain has exactly two colours —
  // for larger domains, "differ from the neighbour" leaves multiple
  // candidates and no forcing is possible.
  if (t + fp == count) {
    final domain = puzzle.domain;
    if (domain.length == 2) {
      for (int i = 0; i < line.length; i++) {
        if (line[i].value != CellValue.free) continue;
        CellValue? forced;
        if (i > 0 && line[i - 1].value != CellValue.free) {
          final nv = line[i - 1].value;
          forced = domain.firstWhere((v) => v != nv);
        }
        if (i < line.length - 1 && line[i + 1].value != CellValue.free) {
          final nv = line[i + 1].value;
          final mustBe = domain.firstWhere((v) => v != nv);
          if (forced == null) {
            forced = mustBe;
          } else if (forced != mustBe) {
            return Impossible(constraint);
          }
        }
        if (forced != null) {
          return SetValue(line[i].idx, forced, constraint, complexity: 2);
        }
      }
      return null;
    }
    // 3+ colours: every free pair must become a transition, so a free cell
    // adjacent to a coloured neighbour must differ from it. We can only prune
    // the neighbour colour(s) (multiple candidates remain), not force a value.
    for (int i = 0; i < line.length; i++) {
      final cell = line[i];
      if (cell.value != CellValue.free) continue;
      final neighbourColors = <CellValue>{};
      if (i > 0 && line[i - 1].value != CellValue.free) {
        neighbourColors.add(line[i - 1].value);
      }
      if (i < line.length - 1 && line[i + 1].value != CellValue.free) {
        neighbourColors.add(line[i + 1].value);
      }
      if (neighbourColors.isEmpty) continue;
      // Must differ from every coloured neighbour: if nothing survives, the
      // cell is unsatisfiable.
      final survives = cell.options.any((o) => !neighbourColors.contains(o));
      if (!survives) {
        return Impossible(constraint);
      }
      for (final nv in neighbourColors) {
        if (cell.options.contains(nv)) {
          return RemoveOption(cell.idx, nv, constraint, complexity: 2);
        }
      }
    }
    return null;
  }

  // Lower-bound probing fallback (3+ colours): prune any colour whose
  // assignment to a free cell would make the whole line infeasible — e.g. a
  // cell wedged between two different colours where a third colour forces two
  // transitions and overshoots the budget. `_lineFeasibleWith` is the
  // soundness oracle: infeasible ⇒ that colour is genuinely impossible here.
  if (puzzle.domain.length > 2) {
    for (final cell in line) {
      if (cell.value != CellValue.free) continue;
      for (final c in cell.options) {
        if (!_lineFeasibleWith(line, count, cell.idx, c)) {
          return RemoveOption(cell.idx, c, constraint, complexity: 4);
        }
      }
    }
  }

  return null;
}

/// Necessary-condition feasibility check for a [line] expected to hold exactly
/// [count] transitions, assuming the cell at [probeIdx] takes [probeVal].
/// Returns `false` only when that assignment is provably impossible (the
/// transition bounds are violated, or the `count == 1` endpoint rule fails).
/// Used purely as a sound pruning oracle — it never asserts feasibility.
bool _lineFeasibleWith(
  List<Cell> line,
  int count,
  int probeIdx,
  CellValue probeVal,
) {
  CellValue valAt(int i) => line[i].idx == probeIdx ? probeVal : line[i].value;
  int t = 0;
  int fp = 0;
  for (int i = 0; i < line.length - 1; i++) {
    final a = valAt(i);
    final b = valAt(i + 1);
    if (a != CellValue.free && b != CellValue.free) {
      if (a != b) t++;
    } else {
      fp++;
    }
  }
  if (t > count) return false;
  if (t + fp < count) return false;
  if (count == 1) {
    final fv = valAt(0);
    final lv = valAt(line.length - 1);
    if (fv != CellValue.free && lv != CellValue.free && fv == lv) return false;
  }
  return true;
}

/// Shared parameter generation for row/column transition constraints.
/// [numLines] is the number of rows (for RT) or columns (for CT).
/// [maxT] is the maximum transition count per line.
List<String> generateAllTransitionParams(int numLines, int maxT) {
  final List<String> result = [];
  for (int idx = 0; idx < numLines; idx++) {
    for (int t = 0; t <= maxT; t++) {
      result.add('$idx.$t');
    }
  }
  return result;
}
