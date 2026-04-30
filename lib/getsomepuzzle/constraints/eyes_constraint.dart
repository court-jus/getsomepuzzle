import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// What an eye sees in a single direction (left, right, up or down).
class DirectionView {
  /// Number of contiguous color cells visible from the eye in this direction.
  final int seen;

  /// Total cells from the eye until (but not including) the first opposite-color
  /// cell or the grid edge. This is the maximum [seen] could ever become.
  final int max;

  /// Puzzle indices of the empty cells in this direction, ordered from closest
  /// to farthest from the eye.
  final List<int> empties;

  /// Position in the line of sight of each empty cell (0-indexed: 0 is the cell
  /// immediately adjacent to the eye). Parallel array to [empties].
  /// `emptyPositions[0] == seen`.
  final List<int> emptyPositions;

  const DirectionView({
    required this.seen,
    required this.max,
    required this.empties,
    required this.emptyPositions,
  });
}

class WhatIsSeen {
  final DirectionView left;
  final DirectionView right;
  final DirectionView up;
  final DirectionView down;

  WhatIsSeen({
    required this.left,
    required this.right,
    required this.up,
    required this.down,
  });

  Iterable<DirectionView> get directions => [left, right, up, down];

  int get totalSeen => directions.fold(0, (s, d) => s + d.seen);
  int get totalMax => directions.fold(0, (s, d) => s + d.max);
  bool get hasEmpty => directions.any((d) => d.empties.isNotEmpty);
}

class EyesConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'EY';

  int color = 0;
  int count = 0;

  EyesConstraint(String strParams) {
    final params = strParams.split(".");
    indices = [int.parse(params[0])];
    color = int.parse(params[1]);
    count = int.parse(params[2]);
  }

  @override
  String serialize() => '$slug:${indices.first}.$color.$count';

  @override
  String toString() => '$count';

  @override
  String toHuman(Puzzle puzzle) => '${indices.first + 1} sees $count $color';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    final minCount = 0;
    final maxCount = (width - 1) + (height - 1);
    for (int col = 0; col < width; col++) {
      for (int row = 0; row < height; row++) {
        final idx = row * width + col;
        for (int count = minCount; count < maxCount; count++) {
          for (final c in domain) {
            result.add('$idx.$c.$count');
          }
        }
      }
    }
    return result;
  }

  WhatIsSeen whatDoIsee(Puzzle puzzle) {
    final idx = indices.first;
    final width = puzzle.width;
    final size = width * puzzle.height;
    final eyeRow = idx ~/ width;
    return WhatIsSeen(
      left: _scan(puzzle, idx - 1, -1, (i) => i >= 0 && i ~/ width == eyeRow),
      right: _scan(puzzle, idx + 1, 1, (i) => i < size && i ~/ width == eyeRow),
      up: _scan(puzzle, idx - width, -width, (i) => i >= 0),
      down: _scan(puzzle, idx + width, width, (i) => i < size),
    );
  }

  DirectionView _scan(
    Puzzle puzzle,
    int start,
    int step,
    bool Function(int) inBounds,
  ) {
    int seen = 0;
    bool stillSeeing = true;
    final empties = <int>[];
    final emptyPositions = <int>[];
    int max = 0;
    for (var i = start; inBounds(i); i += step) {
      final v = puzzle.cellValues[i];
      if (v != color && v != 0) break;
      if (v == color && stillSeeing) seen++;
      if (v == 0) {
        stillSeeing = false;
        empties.add(i);
        emptyPositions.add(max);
      }
      max++;
    }
    return DirectionView(
      seen: seen,
      max: max,
      empties: empties,
      emptyPositions: emptyPositions,
    );
  }

  @override
  bool verify(Puzzle puzzle) {
    final view = whatDoIsee(puzzle);
    return view.totalSeen <= count && view.totalMax >= count;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final view = whatDoIsee(puzzle);
    final opposite = puzzle.domain.firstWhereOrNull((v) => v != color) ?? 0;

    if (view.totalSeen > count) {
      // Already seeing more than required.
      return Move(0, 0, this, isImpossible: this);
    }
    if (view.totalMax < count) {
      // Even filling every reachable empty with the target color is not enough.
      return Move(0, 0, this, isImpossible: this);
    }

    for (final d in view.directions) {
      final othersMax = view.totalMax - d.max;
      final othersSeen = view.totalSeen - d.seen;
      // Range of feasible final counts in this direction.
      final minD = math.max(d.seen, count - othersMax);
      final maxD = math.min(d.max, count - othersSeen);

      // Lower bound: cells at positions 0..minD-1 must all hold the target
      // color in the final state. Force the first empty in that range.
      if (minD > d.seen) {
        for (int i = 0; i < d.empties.length; i++) {
          if (d.emptyPositions[i] < minD) {
            return Move(d.empties[i], color, this, complexity: 2);
          }
        }
      }

      // Upper bound: cells 0..maxD cannot all be color, otherwise count_d would
      // exceed maxD. If exactly one empty is at position <= maxD, that empty
      // must take the opposite color to break line of sight in time.
      if (maxD < d.max) {
        int? unique;
        bool multiple = false;
        for (int i = 0; i < d.empties.length; i++) {
          if (d.emptyPositions[i] <= maxD) {
            if (unique == null) {
              unique = d.empties[i];
            } else {
              multiple = true;
              break;
            }
          }
        }
        if (unique != null && !multiple) {
          // When the eye already sees the target count (which includes the
          // count == 0 case), the upper bound is just "stop seeing more" —
          // a trivial close-the-line move. Otherwise the player needs to
          // juggle per-direction budgets across the four directions.
          final int weight = view.totalSeen == count ? 0 : 3;
          return Move(unique, opposite, this, complexity: weight);
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final view = whatDoIsee(puzzle);
    // Complete when the count is reached and no empty cell remains in any line
    // of sight (no future fill can move the constraint).
    return view.totalSeen == count && !view.hasEmpty;
  }
}
