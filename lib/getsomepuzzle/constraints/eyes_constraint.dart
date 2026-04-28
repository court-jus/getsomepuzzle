import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class WhatIsSeen {
  // Describe what can be seen by a cell
  late int count; // The number of cells of that color that are seen by the cell
  late List<int> candidates; //Empty cells that are seen and can be filled

  WhatIsSeen({required this.count, required this.candidates});
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
    final result = WhatIsSeen(count: 0, candidates: []);
    final idx = indices.first;
    final size = puzzle.width * puzzle.height;
    for (
      var left = idx - 1;
      left >= 0 && (left ~/ puzzle.width) == (idx ~/ puzzle.width);
      left--
    ) {
      if (puzzle.cellValues[left] == color) {
        result.count += 1;
        continue;
      }
      if (puzzle.cellValues[left] == 0) {
        result.candidates.add(left);
      }
      break;
    }
    for (
      var right = idx + 1;
      right < size && (right ~/ puzzle.width) == (idx ~/ puzzle.width);
      right++
    ) {
      if (puzzle.cellValues[right] == color) {
        result.count += 1;
        continue;
      }
      if (puzzle.cellValues[right] == 0) {
        result.candidates.add(right);
      }
      break;
    }
    for (var top = idx - puzzle.width; top >= 0; top -= puzzle.width) {
      if (puzzle.cellValues[top] == color) {
        result.count += 1;
        continue;
      }
      if (puzzle.cellValues[top] == 0) {
        result.candidates.add(top);
      }
      break;
    }
    for (
      var bottom = idx + puzzle.width;
      bottom < size;
      bottom += puzzle.width
    ) {
      if (puzzle.cellValues[bottom] == color) {
        result.count += 1;
        continue;
      }
      if (puzzle.cellValues[bottom] == 0) {
        result.candidates.add(bottom);
      }
      break;
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final whatDoISee = whatDoIsee(puzzle);
    final int matches = whatDoISee.count;
    final int? candidate = whatDoISee.candidates.firstOrNull;
    return matches == count || (matches < count && candidate != null);
  }

  @override
  Move? apply(Puzzle puzzle) {
    final whatDoISee = whatDoIsee(puzzle);
    final int matches = whatDoISee.count;
    final int? candidate = whatDoISee.candidates.firstOrNull;
    final int opposite = puzzle.domain.firstWhereOrNull((v) => v != color) ?? 0;
    if (matches > count) {
      // There is an error, I see too many colored cells
      return Move(0, 0, this, isImpossible: this);
    }
    if (matches == count && candidate != null) {
      // I'm complete and have a free candidate,
      // I can say that no more cells can be added to my "sides"
      // so this candidate must be my opposite color
      return Move(candidate, opposite, this);
    }
    if (matches < count && whatDoISee.candidates.length == 1) {
      // I don't see enough colored cells and have only one free candidate,
      // I can say that this candidate must by my color
      return Move(candidate!, color, this);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final whatDoISee = whatDoIsee(puzzle);
    final int matches = whatDoISee.count;
    final int? candidate = whatDoISee.candidates.firstOrNull;
    // I'm complete if I have the correct number of matches and no free candidate
    return matches == count && candidate == null;
  }
}
