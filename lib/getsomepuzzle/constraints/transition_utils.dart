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
    if (a != 0 && b != 0 && a != b) {
      t++;
    }
  }
  return t;
}

/// Count adjacent pairs in [line] where at least one cell is free (value == 0).
int countFreePairs(List<Cell> line) {
  int fp = 0;
  for (int i = 0; i < line.length - 1; i++) {
    if (line[i].value == 0 || line[i + 1].value == 0) {
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
    return Move(0, 0, constraint, isImpossible: constraint);
  }

  if (t + fp < count) {
    return Move(0, 0, constraint, isImpossible: constraint);
  }

  // Saturated: no more transitions allowed. Valid for any domain size —
  // forcing a free cell to match its filled neighbour avoids any new
  // transition regardless of how many colours exist.
  if (t == count) {
    for (int i = 0; i < line.length; i++) {
      if (line[i].value != 0) continue;
      int? forced;
      if (i > 0 && line[i - 1].value != 0) {
        forced = line[i - 1].value;
      }
      if (i < line.length - 1 && line[i + 1].value != 0) {
        final nv = line[i + 1].value;
        if (forced == null) {
          forced = nv;
        } else if (forced != nv) {
          return Move(line[i].idx, 0, constraint, isImpossible: constraint);
        }
      }
      if (forced != null) {
        return Move(line[i].idx, forced, constraint, complexity: 1);
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
    if (domain.length != 2) return null;
    for (int i = 0; i < line.length; i++) {
      if (line[i].value != 0) continue;
      int? forced;
      if (i > 0 && line[i - 1].value != 0) {
        final nv = line[i - 1].value;
        forced = domain.firstWhere((v) => v != nv);
      }
      if (i < line.length - 1 && line[i + 1].value != 0) {
        final nv = line[i + 1].value;
        final mustBe = domain.firstWhere((v) => v != nv);
        if (forced == null) {
          forced = mustBe;
        } else if (forced != mustBe) {
          return Move(line[i].idx, 0, constraint, isImpossible: constraint);
        }
      }
      if (forced != null) {
        return Move(line[i].idx, forced, constraint, complexity: 2);
      }
    }
    return null;
  }

  return null;
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
