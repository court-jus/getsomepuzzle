import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

/// Bounding Box (BB): every connected group of [color] must occupy a bounding
/// box of exactly [width] × [height] cells in the solved state. The bounding
/// box is the smallest axis-aligned rectangle containing the group's cells;
/// the group need not fill it (a hollow shape spanning the extent satisfies
/// the rule). Global scope — applies to every group of the colour, like `GC`.
///
/// See `docs/dev/constraints/bounding_box.md`. The field order is **width then
/// height**, consistent across [serialize] (`.width.height`) and [rotated]
/// (swaps to `.height.width`).
class BoundingBoxConstraint extends Constraint {
  @override
  String get slug => 'BB';

  CellValue color = CellValue.free;
  int width = 0;
  int height = 0;

  @override
  Set<CellValue> get referencedColors => {color};

  BoundingBoxConstraint(String strParams) {
    final params = strParams.split(".");
    color = cellRepresentationToValue(params[0]);
    width = int.parse(params[1]);
    height = int.parse(params[2]);
  }

  @override
  String serialize() => 'BB:${cellValueToString(color)}.$width.$height';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      BoundingBoxConstraint('${cellValueToString(color)}.$height.$width');

  @override
  String toString() => "${cellValueToString(color)} BB $width×$height";

  @override
  String toHuman(Puzzle puzzle) =>
      "Groups of color ${cellValueToString(color)} must have bounding box "
      "$width×$height";

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final result = <String>[];
    for (final value in domain) {
      // A box must sit strictly inside the grid: a 1-wide/1-tall box is a
      // no-adjacency rule rather than a bounding box, and a box spanning a
      // full grid dimension (w == width or h == height) is a weak rule. So
      // each extent is bounded to [2, dim - 1].
      for (int w = 2; w <= width - 1; w++) {
        for (int h = 2; h <= height - 1; h++) {
          result.add('${cellValueToString(value)}.$w.$h');
        }
      }
    }
    return result;
  }

  /// Bounding box of [group] as `(height, width)` — row span first, the matrix
  /// convention (note the class fields are width-first; this helper is the one
  /// place that returns row-span-first).
  (int, int) _bbHW(List<int> group, int gridWidth) {
    int minR = group.first ~/ gridWidth, maxR = minR;
    int minC = group.first % gridWidth, maxC = minC;
    for (final idx in group.skip(1)) {
      final r = idx ~/ gridWidth;
      final c = idx % gridWidth;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
    }
    return (maxR - minR + 1, maxC - minC + 1);
  }

  /// Bounds `(minR, maxR, minC, maxC)` of [group].
  (int, int, int, int) _bounds(List<int> group, int gridWidth) {
    int minR = group.first ~/ gridWidth, maxR = minR;
    int minC = group.first % gridWidth, maxC = minC;
    for (final idx in group.skip(1)) {
      final r = idx ~/ gridWidth;
      final c = idx % gridWidth;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
    }
    return (minR, maxR, minC, maxC);
  }

  /// Bounding box `(height, width)` of the option-aware region reachable from
  /// [group] through cells that are `color` or still have `color` in their
  /// options. This is an *upper bound* on the extent the group can ever reach,
  /// so a region narrower/shorter than the target proves the target is
  /// unreachable.
  (int, int) _reachableBBHW(Puzzle puzzle, List<int> group) {
    final reach = floodFill(
      puzzle,
      group,
      (i) =>
          puzzle.cellValues[i] == color ||
          puzzle.cells[i].options.contains(color),
    );
    return _bbHW(reach.toList(), puzzle.width);
  }

  @override
  bool verify(Puzzle puzzle) {
    final groups = getColorGroups(puzzle, color);
    for (final group in groups) {
      final (h, w) = _bbHW(group, puzzle.width);
      if (puzzle.complete) {
        // Finished: the box must equal the target exactly.
        if (h != height || w != width) return false;
        continue;
      }
      // Over-large is broken now and monotone-sound: a box only ever grows, so
      // it can never shrink back under the target.
      if (h > height || w > width) return false;
      // Too small in at least one dimension: still valid only if the group's
      // reachable region can still span the full W×H extent.
      if (h < height || w < width) {
        final (rh, rw) = _reachableBBHW(puzzle, group);
        if (rh < height || rw < width) return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final groups = getColorGroups(puzzle, color);

    // Pass 1: contradictions. An over-large box, or a too-small box whose
    // reachable region can no longer span W×H, makes the target unreachable.
    for (final group in groups) {
      final (h, w) = _bbHW(group, puzzle.width);
      if (h > height || w > width) return Impossible(this);
      if (h < height || w < width) {
        final (rh, rw) = _reachableBBHW(puzzle, group);
        if (rh < height || rw < width) return Impossible(this);
      }
    }

    // Pass 2: pruning. A free, still-`color`-capable cell orthogonally adjacent
    // to a group cell and lying just outside the box would, if coloured, extend
    // the box by one in that direction. Prune `color` from it only when that
    // dimension is already at the target (so growing it overshoots). A cell
    // outside in a dimension that is still below target may legally be needed
    // to grow, so it is left alone.
    for (final group in groups) {
      final (minR, maxR, minC, maxC) = _bounds(group, puzzle.width);
      final h = maxR - minR + 1;
      final w = maxC - minC + 1;
      for (final cell in group) {
        for (final nei in puzzle.getNeighbors(cell)) {
          if (puzzle.cellValues[nei] != CellValue.free) continue;
          if (!puzzle.cells[nei].options.contains(color)) continue;
          final r = nei ~/ puzzle.width;
          final c = nei % puzzle.width;
          final extendsVert = r < minR || r > maxR;
          final extendsHoriz = c < minC || c > maxC;
          if (extendsVert && h == height) {
            return RemoveOption(nei, color, this, complexity: 2);
          }
          if (extendsHoriz && w == width) {
            return RemoveOption(nei, color, this, complexity: 2);
          }
        }
      }
    }

    // Pass 3: forced growth. When the W×H box position is uniquely pinned by
    // the group's current extent and the grid borders, the group must reach
    // all four sides of that box. If a side it does not yet occupy has exactly
    // one `color`-capable cell, that cell is forced; if it has none, the box is
    // unreachable.
    for (final group in groups) {
      final (minR, maxR, minC, maxC) = _bounds(group, puzzle.width);
      final h = maxR - minR + 1;
      final w = maxC - minC + 1;
      // Box already at target extent ⇒ pass 2 guards overflow, nothing to grow.
      if (h == height && w == width) continue;
      // Candidate top-left corners of the final box: it must contain the
      // current extent and fit inside the grid.
      final r0lo = max(0, maxR - height + 1);
      final r0hi = min(minR, puzzle.height - height);
      final c0lo = max(0, maxC - width + 1);
      final c0hi = min(minC, puzzle.width - width);
      // Box position not yet pinned in both axes — can't force an edge.
      if (r0lo != r0hi || c0lo != c0hi) continue;
      final r0 = r0lo;
      final c0 = c0lo;
      final boxMaxR = r0 + height - 1;
      final boxMaxC = c0 + width - 1;
      final groupSet = group.toSet();
      final edges = <List<int>>[
        [for (int c = c0; c <= boxMaxC; c++) r0 * puzzle.width + c], // top
        [for (int c = c0; c <= boxMaxC; c++) boxMaxR * puzzle.width + c], // bot
        [for (int r = r0; r <= boxMaxR; r++) r * puzzle.width + c0], // left
        [for (int r = r0; r <= boxMaxR; r++) r * puzzle.width + boxMaxC], // rgt
      ];
      for (final edge in edges) {
        // Already touching this side: nothing to force here.
        if (edge.any(groupSet.contains)) continue;
        final capable = edge
            .where(
              (i) =>
                  puzzle.cellValues[i] == color ||
                  (puzzle.cellValues[i] == CellValue.free &&
                      puzzle.cells[i].options.contains(color)),
            )
            .toList();
        if (capable.isEmpty) return Impossible(this);
        if (capable.length == 1 &&
            puzzle.cellValues[capable.first] == CellValue.free) {
          return SetValue(capable.first, color, this, complexity: 3);
        }
      }
    }

    // Pass 4: pinned-box connectivity. Within a pinned box the group must be a
    // single connected run of `color`-capable cells touching all four sides. A
    // free capable cell whose removal would sever a still-needed side from the
    // group (the only link to a lone edge cell) is forced — the connectivity
    // counterpart of pass 3's edge forcing.
    for (final group in groups) {
      final (minR, maxR, minC, maxC) = _bounds(group, puzzle.width);
      final h = maxR - minR + 1;
      final w = maxC - minC + 1;
      if (h == height && w == width) continue;
      final r0lo = max(0, maxR - height + 1);
      final r0hi = min(minR, puzzle.height - height);
      final c0lo = max(0, maxC - width + 1);
      final c0hi = min(minC, puzzle.width - width);
      if (r0lo != r0hi || c0lo != c0hi) continue;
      final r0 = r0lo;
      final c0 = c0lo;
      final boxMaxR = r0 + height - 1;
      final boxMaxC = c0 + width - 1;
      // `color`-capable cells inside the box (already `color`, or free with
      // `color` still in options).
      final capable = <int>{};
      for (int r = r0; r <= boxMaxR; r++) {
        for (int c = c0; c <= boxMaxC; c++) {
          final i = r * puzzle.width + c;
          if (puzzle.cellValues[i] == color ||
              (puzzle.cellValues[i] == CellValue.free &&
                  puzzle.cells[i].options.contains(color))) {
            capable.add(i);
          }
        }
      }
      // Does the capable component containing the group (minus [removed]) still
      // reach all four sides of the box?
      bool spans(Set<int> removed) {
        final allowed = capable.difference(removed);
        if (!allowed.contains(group.first)) return false;
        final comp = floodFill(puzzle, [
          group.first,
        ], (i) => allowed.contains(i));
        bool top = false, bot = false, lft = false, rgt = false;
        for (final i in comp) {
          final r = i ~/ puzzle.width;
          final c = i % puzzle.width;
          if (r == r0) top = true;
          if (r == boxMaxR) bot = true;
          if (c == c0) lft = true;
          if (c == boxMaxC) rgt = true;
        }
        return top && bot && lft && rgt;
      }

      if (!spans(<int>{})) return Impossible(this);
      for (final p in capable) {
        if (puzzle.cellValues[p] != CellValue.free) continue;
        if (!spans({p})) {
          return SetValue(p, color, this, complexity: 4);
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final groups = getColorGroups(puzzle, color);
    // Every existing group must already be at the exact target extent.
    for (final group in groups) {
      final (h, w) = _bbHW(group, puzzle.width);
      if (h != height || w != width) return false;
    }
    // Conservative grey-out: any free, still-`color`-capable cell adjacent to a
    // group cell could grow or merge a box, and any new-group candidate could
    // spawn a fresh under-target group — either keeps apply() alive.
    for (final group in groups) {
      for (final cell in group) {
        for (final nei in puzzle.getNeighbors(cell)) {
          if (puzzle.cellValues[nei] == CellValue.free &&
              puzzle.cells[nei].options.contains(color)) {
            return false;
          }
        }
      }
    }
    if (getFreeCellsThatCanStartNewColorGroup(puzzle, color).isNotEmpty) {
      return false;
    }
    return true;
  }
}
