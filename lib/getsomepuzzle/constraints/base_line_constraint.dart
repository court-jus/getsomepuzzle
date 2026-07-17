import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

base class LineCentricConstraint extends Constraint {
  // A common class for Row/Column constraints
  CellValue color = CellValue.free;
  int count = 0;

  // Covers CC/RC (count of `color`) and RT/CT (transitions carry a nominal
  // `color`, kept conservatively so auto-shrink never drops it).
  @override
  Set<CellValue> get referencedColors => {color};

  @override
  String serialize() => '$slug:${getIdx()}.${cellValueToString(color)}.$count';

  @override
  String toString() => '$count';

  int getIdx() => 0;

  List<Cell> getLine(Puzzle puzzle) => [];

  @override
  bool verify(Puzzle puzzle) {
    final line = getLine(puzzle);
    final have = line.where((cell) => cell.value == color).length;
    if (puzzle.complete) return have == count;
    if (have > count) return false;
    // Only free cells that can still take `color` count toward reachability.
    final free = line
        .where(
          (cell) =>
              cell.value == CellValue.free && cell.options.contains(color),
        )
        .length;
    if (have + free < count) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final line = getLine(puzzle);
    final colorCount = line.where((cell) => cell.value == color).length;
    final freeCells = line.where((cell) => cell.value == CellValue.free);
    if (freeCells.isEmpty) return null;

    if (colorCount > count) {
      return Impossible(this);
    }
    if (colorCount == count) {
      // All color cells placed — remaining free cells get an opposite color
      for (var freeCell in freeCells) {
        if (freeCell.options.contains(color)) {
          return RemoveOption(freeCell.idx, color, this, complexity: 1);
        }
      }
      // No free cell still has `color` in options — the line is already
      // closed. The constraint is satisfied; nothing more to do. (Reporting
      // `isImpossible` here was the same domain-3 trap as in SH Level 2:
      // domain-2 auto-sets when only one option remains, so free cells
      // disappear after one round of removeOption; domain-3+ leaves the
      // cell free with two options and we loop back here with nothing to do.)
      return null;
    }
    if (count - colorCount == freeCells.length) {
      // Exactly as many free cells as needed — they must all be color.
      // The cell may have lost the option earlier (3-colour puzzles): in
      // that case the target is no longer reachable.
      final target = freeCells.first;
      if (!target.options.contains(color)) {
        return Impossible(this);
      }
      return SetValue(target.idx, color, this, complexity: 0);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final line = getLine(puzzle);
    // RT/CT keep `color == CellValue.free` (they count transitions, not
    // a specific colour), so the option filter doesn't apply.
    if (color == CellValue.free) {
      return line.every((cell) => cell.value != CellValue.free);
    }
    return line.every(
      (cell) =>
          cell.value != CellValue.free ||
          (cell.value == CellValue.free && !cell.options.contains(color)),
    );
  }
}

base class JRCConstraint extends LineCentricConstraint {
  List<CellValue> colorOrder = [];

  Map<CellValue, int> _countsPerColor(List<Cell> line) {
    final counts = {for (final c in colorOrder) c: 0};
    for (final cell in line) {
      if (cell.value != CellValue.free && counts.containsKey(cell.value)) {
        counts[cell.value] = counts[cell.value]! + 1;
      }
    }
    return counts;
  }

  /// Bottom-up minimums: each colour must beat the next.
  Map<CellValue, int> _computeMins(int n, Map<CellValue, int> counts) {
    final k = colorOrder.length;
    final mins = {for (final c in colorOrder) c: counts[c]!};

    for (var i = k - 2; i >= 0; i--) {
      final c = colorOrder[i];
      final nextC = colorOrder[i + 1];
      if (mins[c]! <= mins[nextC]!) {
        mins[c] = mins[nextC]! + 1;
      }
    }

    final tightFirst = (n / k + (k - 1) / 2).ceil();
    if (mins[colorOrder.first]! < tightFirst) {
      mins[colorOrder.first] = tightFirst;
    }

    return mins;
  }

  /// Maximum counts given the minimums.
  Map<CellValue, int> _computeMaxs(int n, Map<CellValue, int> mins) {
    final k = colorOrder.length;
    final maxs = <CellValue, int>{};

    if (k == 2) {
      final a = colorOrder[0];
      final b = colorOrder[1];
      maxs[a] = n - mins[b]!;
      maxs[b] = (n - 1) ~/ 2;
    } else if (k == 3) {
      final a = colorOrder[0];
      final b = colorOrder[1];
      final c = colorOrder[2];
      maxs[a] = n - mins[b]! - mins[c]!;
      maxs[b] = min(n - mins[a]! - mins[c]!, mins[a]! - 1);
      maxs[c] = min(n - mins[a]! - mins[b]!, maxs[b]! - 1);
    } else {
      for (final color in colorOrder) {
        maxs[color] = n - 1;
      }
    }

    return maxs;
  }

  (Map<CellValue, int>, Map<CellValue, int>) _computeBounds(List<Cell> line) {
    final n = line.length;
    final counts = _countsPerColor(line);
    final mins = _computeMins(n, counts);
    final maxs = _computeMaxs(n, mins);
    return (mins, maxs);
  }

  @override
  bool verify(Puzzle puzzle) {
    final line = getLine(puzzle);
    final counts = _countsPerColor(line);
    final freeCells = line.where((c) => c.value == CellValue.free).toList();

    if (freeCells.isEmpty) {
      for (var i = 0; i < colorOrder.length - 1; i++) {
        if (counts[colorOrder[i]]! <= counts[colorOrder[i + 1]]!) return false;
      }
      return true;
    }

    final (mins, maxs) = _computeBounds(line);

    for (final color in colorOrder) {
      final count = counts[color]!;
      final free = freeCells.where((c) => c.options.contains(color)).length;
      if (count + free < mins[color]!) return false;
      if (count > maxs[color]!) return false;
    }

    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final line = getLine(puzzle);
    final freeCells = line.where((c) => c.value == CellValue.free).toList();
    if (freeCells.isEmpty) return null;

    final counts = _countsPerColor(line);
    final (mins, maxs) = _computeBounds(line);

    for (final color in colorOrder) {
      final count = counts[color]!;
      final free = freeCells.where((c) => c.options.contains(color)).length;
      if (count > maxs[color]!) return Impossible(this);
      if (count + free < mins[color]!) return Impossible(this);
    }

    for (final color in colorOrder) {
      final count = counts[color]!;
      final free = freeCells.where((c) => c.options.contains(color)).length;
      final needed = mins[color]! - count;
      if (needed == free && needed > 0) {
        final cell = freeCells.firstWhere((c) => c.options.contains(color));
        return SetValue(cell.idx, color, this, complexity: 1);
      }
    }

    for (final color in colorOrder) {
      if (counts[color]! == maxs[color]!) {
        for (final cell in freeCells) {
          if (cell.options.contains(color)) {
            return RemoveOption(cell.idx, color, this, complexity: 2);
          }
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final line = getLine(puzzle);
    final freeCells = line.where((c) => c.value == CellValue.free).toList();
    if (freeCells.isEmpty) return true;
    final counts = _countsPerColor(line);
    for (var i = 0; i < colorOrder.length - 1; i++) {
      final upper = colorOrder[i];
      final lower = colorOrder[i + 1];
      final lowerReachable = freeCells
          .where((c) => c.options.contains(lower))
          .length;
      if (counts[upper]! <= counts[lower]! + lowerReachable) {
        return false;
      }
    }
    return true;
  }
}
