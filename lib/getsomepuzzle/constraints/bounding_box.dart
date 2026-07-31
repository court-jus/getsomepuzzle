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

    // Pass A: merge-prevention. A free `color`-capable cell inside this
    // group's current bounding box that, if coloured, would orthogonally
    // connect this group to another same-colour group must lose `color` when
    // the merged bounding box would exceed the target. Runs even for groups
    // already at the target extent — an at-target box can still be broken by
    // a bridging cell.
    for (final group in groups) {
      final (minR, maxR, minC, maxC) = _bounds(group, puzzle.width);
      for (int r = minR; r <= maxR; r++) {
        for (int c = minC; c <= maxC; c++) {
          final i = r * puzzle.width + c;
          if (puzzle.cellValues[i] != CellValue.free) continue;
          if (!puzzle.cells[i].options.contains(color)) continue;
          if (!puzzle.getNeighbors(i).any(group.contains)) continue;
          for (final other in groups) {
            if (identical(other, group)) continue;
            if (!puzzle.getNeighbors(i).any(other.contains)) continue;
            final otherMinR = other
                .map((idx) => idx ~/ puzzle.width)
                .reduce(min);
            final otherMaxR = other
                .map((idx) => idx ~/ puzzle.width)
                .reduce(max);
            final otherMinC = other
                .map((idx) => idx % puzzle.width)
                .reduce(min);
            final otherMaxC = other
                .map((idx) => idx % puzzle.width)
                .reduce(max);
            if (max(maxR, otherMaxR) - min(minR, otherMinR) + 1 > height ||
                max(maxC, otherMaxC) - min(minC, otherMinC) + 1 > width) {
              return RemoveOption(i, color, this, complexity: 2);
            }
          }
        }
      }
    }

    // Pass 3: candidate-box analysis. Enumerate every W×H box position that
    // can contain the group's current extent, keep only those the group can
    // actually span as a single connected component touching all four sides,
    // then force the cells every surviving candidate needs.
    for (final group in groups) {
      final (minR, maxR, minC, maxC) = _bounds(group, puzzle.width);
      if (maxR - minR + 1 == height && maxC - minC + 1 == width) continue;
      final candidates = <_CandidateBox>[];
      for (
        int r0 = max(0, maxR - height + 1);
        r0 <= min(minR, puzzle.height - height);
        r0++
      ) {
        final boxMaxR = r0 + height - 1;
        for (
          int c0 = max(0, maxC - width + 1);
          c0 <= min(minC, puzzle.width - width);
          c0++
        ) {
          final boxMaxC = c0 + width - 1;
          final needed = _analyzeCandidateBox(
            puzzle,
            group,
            r0,
            boxMaxR,
            c0,
            boxMaxC,
          );
          if (needed != null) candidates.add(_CandidateBox(r0, c0, needed));
        }
      }
      if (candidates.isEmpty) return Impossible(this);
      if (candidates.length == 1) {
        final needed = candidates.first.needed;
        if (needed.isNotEmpty) {
          return SetValue(needed.first, color, this, complexity: 3);
        }
      }
      final common = candidates
          .map((c) => c.needed)
          .reduce((a, b) => a.intersection(b));
      if (common.isNotEmpty) {
        return SetValue(common.first, color, this, complexity: 3);
      }
    }

    return null;
  }

  /// Analyses whether [group] can complete the W×H box with top-left corner
  /// (r0,c0) (rows r0..[boxMaxR], columns c0..[boxMaxC]) as its final bounding
  /// box. Returns `null` when the box is unreachable, otherwise the set of
  /// free cells forced by choosing this box.
  Set<int>? _analyzeCandidateBox(
    Puzzle puzzle,
    List<int> group,
    int r0,
    int boxMaxR,
    int c0,
    int boxMaxC,
  ) {
    // 1. Reachable: the connected region inside the box the group could ever
    //    occupy — its own cells plus every free `color`-capable cell reachable
    //    through `color`-capable cells. Already-`color` cells of other groups
    //    are traversable: merging keeps the box valid as long as it still fits
    //    the target.
    final reachable = floodFill(puzzle, group, (i) {
      if (puzzle.cellValues[i] != color &&
          !puzzle.cells[i].options.contains(color)) {
        return false;
      }
      final r = i ~/ puzzle.width;
      final c = i % puzzle.width;
      return r >= r0 && r <= boxMaxR && c >= c0 && c <= boxMaxC;
    });

    // 2. Reachable cells touching a `color` cell outside this box can never be
    //    used — they would merge the group with an external group and overshoot
    //    the target. They are pruned from the per-candidate `possible` set (no
    //    global RemoveOption needed).
    final excluded = reachable.where((i) {
      return puzzle.getNeighbors(i).any((n) {
        if (puzzle.cellValues[n] != color) return false;
        final r = n ~/ puzzle.width;
        final c = n % puzzle.width;
        return r < r0 || r > boxMaxR || c < c0 || c > boxMaxC;
      });
    }).toSet();
    final possible = reachable.difference(excluded);
    final groupSet = group.toSet();

    // 3. Edge coverage: every box side needs at least one cell the group can
    //    occupy. A side with exactly one free possible cell forces it.
    final edges = <List<int>>[
      [for (int c = c0; c <= boxMaxC; c++) r0 * puzzle.width + c], // top
      [for (int c = c0; c <= boxMaxC; c++) boxMaxR * puzzle.width + c], // bot
      [for (int r = r0; r <= boxMaxR; r++) r * puzzle.width + c0], // left
      [for (int r = r0; r <= boxMaxR; r++) r * puzzle.width + boxMaxC], // rgt
    ];
    final needed = <int>{};
    for (final edge in edges) {
      final (feasible, forced) = _analyzeBoxEdge(
        edge,
        groupSet,
        possible,
        puzzle,
      );
      if (!feasible) return null;
      if (forced != null) needed.add(forced);
    }

    // 4. Connectivity: the group must end up as ONE component spanning all four
    //    sides. A free possible cell whose removal severs a side (an
    //    articulation point of the spanning property) is forced — e.g. a
    //    connector cell that keeps two diagonally-adjacent parts in the same
    //    group.
    bool spans(Set<int> removed) {
      final allowed = possible.difference(removed);
      final comp = floodFill(puzzle, group, allowed.contains);
      if (!comp.contains(group.first)) return false;
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

    if (!spans(const <int>{})) return null;
    for (final p in possible) {
      if (puzzle.cellValues[p] != CellValue.free) continue;
      if (!spans({p})) needed.add(p);
    }

    return needed;
  }

  /// Checks whether [edge] has at least one cell the group can occupy.
  /// Returns `(feasible, forced)`:
  /// - `feasible = false` — no cell lies on this side, the box is unreachable.
  /// - `feasible = true, forced != null` — exactly one free possible cell on
  ///   this side; it is forced.
  /// - `feasible = true, forced == null` — side covered, nothing forced.
  (bool, int?) _analyzeBoxEdge(
    List<int> edge,
    Set<int> groupSet,
    Set<int> possible,
    Puzzle puzzle,
  ) {
    final covered = edge
        .where((i) => possible.contains(i) || groupSet.contains(i))
        .toList();
    if (covered.isEmpty) return (false, null);
    if (covered.length == 1 &&
        puzzle.cellValues[covered.first] == CellValue.free) {
      return (true, covered.first);
    }
    return (true, null);
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

/// One candidate box position for a group's final bounding box, together with
/// the free cells forced by choosing it.
class _CandidateBox {
  final int r0;
  final int c0;
  final Set<int> needed;
  const _CandidateBox(this.r0, this.c0, this.needed);
}
