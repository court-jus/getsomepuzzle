import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// LT + GS complicity: when a `GroupSize` constraint is anchored on a
/// cell that also belongs to a `LetterGroup`, the GS size must
/// accommodate every LT cell *plus* the path cells needed to connect
/// them. The lower bound on the group size is therefore
/// `max_pairwise_manhattan(LT cells) + 1`.
///
/// Two deductions:
///
/// 1. **Impossibility** — when `gs.size < lower_bound`, the puzzle
///    cannot satisfy both constraints.
/// 2. **Force the path** — for an *aligned* 2-cell LT (cells on the
///    same row or column) with `gs.size == manhattan + 1`, the path
///    between the LT cells is the unique minimum-length connector.
///    Every cell on that path must take the LT colour. The colour
///    must be already known (any line cell coloured) — otherwise we
///    only know the cells share a colour, not which one.
class LTGSComplicity extends Complicity {
  @override
  String serialize() => "LTGSComplicity";

  @override
  bool isPresent(Puzzle puzzle) {
    final lts = puzzle.constraints.whereType<LetterGroup>().toList();
    final gss = puzzle.constraints.whereType<GroupSize>().toList();
    if (lts.isEmpty || gss.isEmpty) return false;
    for (final gs in gss) {
      final cell = gs.indices.first;
      for (final lt in lts) {
        if (lt.indices.length < 2) continue;
        if (!lt.indices.contains(cell)) continue;
        final lower = _minGroupSize(lt.indices, puzzle.width);
        if (gs.size < lower) return true;
        if (_isAligned(lt.indices, puzzle.width) && lower == gs.size) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    for (final gs in puzzle.constraints.whereType<GroupSize>()) {
      final cell = gs.indices.first;
      for (final lt in puzzle.constraints.whereType<LetterGroup>()) {
        if (lt.indices.length < 2) continue;
        if (!lt.indices.contains(cell)) continue;

        // 1. Impossibility — too far apart for the requested size.
        final lower = _minGroupSize(lt.indices, puzzle.width);
        if (gs.size < lower) {
          return Move(0, 0, this, isImpossible: this);
        }

        // 2. Collinear LT (all cells on one row or column) with exact
        // size fit — the entire row/column segment from the smallest
        // to the largest LT cell IS the unique minimum tree, so every
        // cell on it must take the LT colour.
        if (_isAligned(lt.indices, puzzle.width) && gs.size == lower) {
          final move = _forceLineCells(lt, puzzle);
          if (move != null) return move;
        }
      }
    }
    return null;
  }

  /// For a collinear LT (all cells on one row or one column), the
  /// minimum tree is the contiguous row/column segment from the
  /// smallest to the largest LT cell. When the segment colour is
  /// already known (any line cell coloured), force the first empty
  /// cell on the segment to that colour.
  Move? _forceLineCells(LetterGroup lt, Puzzle puzzle) {
    final w = puzzle.width;
    final firstR = lt.indices[0] ~/ w;
    final firstC = lt.indices[0] % w;
    final sameRow = lt.indices.every((i) => i ~/ w == firstR);
    final sameCol = lt.indices.every((i) => i % w == firstC);
    if (!sameRow && !sameCol) return null;

    final lineCells = <int>[];
    if (sameRow) {
      int cMin = w, cMax = 0;
      for (final i in lt.indices) {
        final c = i % w;
        if (c < cMin) cMin = c;
        if (c > cMax) cMax = c;
      }
      for (int c = cMin; c <= cMax; c++) {
        lineCells.add(firstR * w + c);
      }
    } else {
      int rMin = puzzle.height, rMax = 0;
      for (final i in lt.indices) {
        final r = i ~/ w;
        if (r < rMin) rMin = r;
        if (r > rMax) rMax = r;
      }
      for (int r = rMin; r <= rMax; r++) {
        lineCells.add(r * w + firstC);
      }
    }

    int? color;
    for (final idx in lineCells) {
      final v = puzzle.cellValues[idx];
      if (v != 0) {
        color = v;
        break;
      }
    }
    if (color == null) return null;

    // Skip cells already in lt.indices: LT.apply handles those on its
    // own as soon as the LT colour is known (no need for the complicity
    // to compete with it). The new contribution is the path cells
    // *between* the LT cells.
    final ltSet = lt.indices.toSet();
    for (final idx in lineCells) {
      if (ltSet.contains(idx)) continue;
      if (puzzle.cellValues[idx] == 0) {
        // Tier 4: combine LT (path-must-form) + GS (size-bounded path)
        // to force every cell on the unique minimum line.
        return Move(idx, color, this, complexity: 4);
      }
    }
    return null;
  }

  /// Lower bound on the size of any group containing all of [indices]:
  /// the maximum pairwise Manhattan distance plus 1. Tight for aligned
  /// 2-cell LTs; conservative for general k-cell or non-aligned LTs.
  static int _minGroupSize(List<int> indices, int width) {
    if (indices.length < 2) return indices.length;
    int maxD = 0;
    for (int i = 0; i < indices.length; i++) {
      for (int j = i + 1; j < indices.length; j++) {
        final d = _manhattan(indices[i], indices[j], width);
        if (d > maxD) maxD = d;
      }
    }
    return maxD + 1;
  }

  static int _manhattan(int a, int b, int width) {
    final ar = a ~/ width, ac = a % width;
    final br = b ~/ width, bc = b % width;
    return (ar - br).abs() + (ac - bc).abs();
  }

  /// True iff every index shares a row or every index shares a column.
  static bool _isAligned(List<int> indices, int width) {
    if (indices.length < 2) return true;
    final firstR = indices[0] ~/ width;
    final firstC = indices[0] % width;
    bool sameRow = true, sameCol = true;
    for (final idx in indices) {
      if (idx ~/ width != firstR) sameRow = false;
      if (idx % width != firstC) sameCol = false;
    }
    return sameRow || sameCol;
  }
}
