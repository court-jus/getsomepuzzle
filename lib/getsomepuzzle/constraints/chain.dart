import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class ChainConstraint extends Constraint {
  @override
  String get slug => 'CH';

  int color = 0;
  String fromSide = '';
  String toSide = '';

  ChainConstraint(String strParams) {
    final params = strParams.split(".");
    color = int.parse(params[0]);
    fromSide = params[1];
    toSide = params[2];
  }

  @override
  String serialize() => 'CH:$color.$fromSide.$toSide';

  @override
  String toString() {
    String abbrev(String s) {
      switch (s) {
        case 'left':
          return 'L';
        case 'right':
          return 'R';
        case 'top':
          return 'T';
        case 'bottom':
          return 'B';
        default:
          return s;
      }
    }

    return '${abbrev(fromSide)}-${abbrev(toSide)}';
  }

  @override
  String toHuman(Puzzle puzzle) {
    return 'Path from $fromSide to $toSide in color $color';
  }

  @override
  Constraint rotated(int origWidth, int origHeight) {
    String rotateSide(String side) {
      switch (side) {
        case 'top':
          return 'right';
        case 'right':
          return 'bottom';
        case 'bottom':
          return 'left';
        case 'left':
          return 'top';
        default:
          return side;
      }
    }

    return ChainConstraint(
      '$color.${rotateSide(fromSide)}.${rotateSide(toSide)}',
    );
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (final value in domain) {
      result.add('$value.top.bottom');
      result.add('$value.left.right');
    }
    return result;
  }

  List<int> _borderCells(String side, int width, int height) {
    switch (side) {
      case 'left':
        return [for (int r = 0; r < height; r++) r * width];
      case 'right':
        return [for (int r = 0; r < height; r++) r * width + (width - 1)];
      case 'top':
        return [for (int c = 0; c < width; c++) c];
      case 'bottom':
        final start = (height - 1) * width;
        return [for (int c = 0; c < width; c++) start + c];
      default:
        return [];
    }
  }

  bool _hasPath(Puzzle puzzle) {
    final fromCells = _borderCells(
      fromSide,
      puzzle.width,
      puzzle.height,
    ).where((i) => puzzle.cellValues[i] == color);
    if (fromCells.isEmpty) return false;

    final visited = <int>{};
    final queue = List<int>.from(fromCells);
    for (final c in fromCells) {
      visited.add(c);
    }

    final toCellSet = _borderCells(toSide, puzzle.width, puzzle.height).toSet();

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (toCellSet.contains(current)) return true;

      for (final nei in puzzle.getNeighbors(current)) {
        if (!visited.contains(nei) && puzzle.cellValues[nei] == color) {
          visited.add(nei);
          queue.add(nei);
        }
      }
    }
    return false;
  }

  bool _isBlocked(Puzzle puzzle) {
    final oppositeColor = puzzle.domain.whereNot((v) => v == color).first;
    final fromCells = _borderCells(
      fromSide,
      puzzle.width,
      puzzle.height,
    ).where((i) => puzzle.cellValues[i] != oppositeColor);
    if (fromCells.isEmpty) return true;

    final visited = <int>{};
    final queue = List<int>.from(fromCells);
    for (final c in fromCells) {
      visited.add(c);
    }

    final toCellSet = _borderCells(toSide, puzzle.width, puzzle.height).toSet();

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (toCellSet.contains(current)) return false;

      for (final nei in puzzle.getNeighbors(current)) {
        if (!visited.contains(nei) && puzzle.cellValues[nei] != oppositeColor) {
          visited.add(nei);
          queue.add(nei);
        }
      }
    }
    return true;
  }

  @override
  bool verify(Puzzle puzzle) {
    if (_isBlocked(puzzle)) return false;
    if (puzzle.complete) return _hasPath(puzzle);
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    if (_isBlocked(puzzle)) {
      return Move(0, 0, this, isImpossible: this);
    }

    final oppositeColor = puzzle.domain.whereNot((v) => v == color).first;

    // Source/target side completely opposite-coloured → impossible
    final fromCells = _borderCells(fromSide, puzzle.width, puzzle.height);
    final toCells = _borderCells(toSide, puzzle.width, puzzle.height);
    if (fromCells.every((i) => puzzle.cellValues[i] == oppositeColor)) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (toCells.every((i) => puzzle.cellValues[i] == oppositeColor)) {
      return Move(0, 0, this, isImpossible: this);
    }

    // Border saturation (weight 1): only one free cell remains on a side
    // and all other cells on that side are opposite colour.
    final fromFree = fromCells.where((i) => puzzle.cellValues[i] == 0).toList();
    final fromOpposite = fromCells
        .where((i) => puzzle.cellValues[i] == oppositeColor)
        .length;
    if (fromFree.length == 1 && fromOpposite == fromCells.length - 1) {
      return Move(fromFree.first, color, this, complexity: 1);
    }
    final toFree = toCells.where((i) => puzzle.cellValues[i] == 0).toList();
    final toOpposite = toCells
        .where((i) => puzzle.cellValues[i] == oppositeColor)
        .length;
    if (toFree.length == 1 && toOpposite == toCells.length - 1) {
      return Move(toFree.first, color, this, complexity: 1);
    }

    // Forced bridge (weight 2): setting a free cell to opposite blocks
    // every possible path → it must be the target colour.
    for (int i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] != 0) continue;
      final clone = puzzle.clone();
      clone.setValue(i, oppositeColor);
      if (_isBlocked(clone)) {
        return Move(i, color, this, complexity: 2);
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    return puzzle.cellValues.every((v) => v != 0);
  }
}
