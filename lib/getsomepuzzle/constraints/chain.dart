import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

class ChainConstraint extends Constraint {
  @override
  String get slug => 'CH';

  CellValue color = CellValue.free;
  String fromSide = '';
  String toSide = '';

  @override
  Set<CellValue> get referencedColors => {color};

  ChainConstraint(String strParams) {
    final params = strParams.split(".");
    color = cellRepresentationToValue(params[0]);
    fromSide = params[1];
    toSide = params[2];
  }

  @override
  String serialize() => 'CH:${cellValueToString(color)}.$fromSide.$toSide';

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
    return 'Path from $fromSide to $toSide in color ${cellValueToString(color)}';
  }

  @override
  Constraint rotated(int origWidth, int origHeight) {
    const next = {
      'top': 'right',
      'right': 'bottom',
      'bottom': 'left',
      'left': 'top',
    };
    String newFrom = next[fromSide] ?? fromSide;
    String newTo = next[toSide] ?? toSide;
    // Canonicalize opposite-side pairs to (top, bottom) / (left, right) order
    // so rotated outputs match the forms produced by generateAllParameters.
    if (newFrom == 'bottom' || newFrom == 'right') {
      final tmp = newFrom;
      newFrom = newTo;
      newTo = tmp;
    }
    return ChainConstraint('${cellValueToString(color)}.$newFrom.$newTo');
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (final value in domain) {
      result.add('${cellValueToString(value)}.top.bottom');
      result.add('${cellValueToString(value)}.left.right');
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

  /// A cell is passable for a `color` chain iff it can still become `color`:
  /// already `color`, or still free *and* with `color` among its remaining
  /// options. A free cell whose `color` option has been pruned (only possible
  /// on a 3+-colour puzzle) can never join the path, so it blocks just like a
  /// committed cell of a different colour.
  bool _passable(Puzzle puzzle, int idx) {
    final v = puzzle.cellValues[idx];
    if (v == color) return true;
    return v == CellValue.free && puzzle.cells[idx].options.contains(color);
  }

  bool _isBlocked(Puzzle puzzle) {
    final fromCells = _borderCells(
      fromSide,
      puzzle.width,
      puzzle.height,
    ).where((i) => _passable(puzzle, i));
    final toCellSet = _borderCells(toSide, puzzle.width, puzzle.height).toSet();
    return !canReach(
      puzzle,
      fromCells,
      toCellSet.contains,
      (i) => _passable(puzzle, i),
    );
  }

  @override
  bool verify(Puzzle puzzle) => !_isBlocked(puzzle);

  @override
  Move? apply(Puzzle puzzle) {
    if (_isBlocked(puzzle)) {
      return Impossible(this);
    }

    final fromCells = _borderCells(fromSide, puzzle.width, puzzle.height);
    final toCells = _borderCells(toSide, puzzle.width, puzzle.height);

    // Border saturation (weight 1): only one free cell remains on a side
    // and every other cell on that side is blocking (committed, non-`color`).
    final fromFree = fromCells
        .where((i) => puzzle.cellValues[i] == CellValue.free)
        .toList();
    final fromBlocked = fromCells.where((i) => !_passable(puzzle, i)).length;
    if (fromFree.length == 1 &&
        fromBlocked == fromCells.length - 1 &&
        puzzle.cells[fromFree.first].options.contains(color)) {
      // The lone free cell is the only possible path start *and* it can still
      // take `color`. If `color` were pruned from it, the saturation premise
      // would be false (some committed `color` cell is the real start), so we
      // fall through rather than force an impossible value.
      return SetValue(fromFree.first, color, this, complexity: 1);
    }
    final toFree = toCells
        .where((i) => puzzle.cellValues[i] == CellValue.free)
        .toList();
    final toBlocked = toCells.where((i) => !_passable(puzzle, i)).length;
    if (toFree.length == 1 &&
        toBlocked == toCells.length - 1 &&
        puzzle.cells[toFree.first].options.contains(color)) {
      // Symmetric to the fromSide saturation above: only force when the lone
      // free endpoint can actually take `color`.
      return SetValue(toFree.first, color, this, complexity: 1);
    }

    // Forced bridge (weight 2): blocking a free cell (committing it to any
    // non-`color` colour) cuts every possible path → it must be `color`.
    // Any non-`color` colour is equivalent for the blocking test (it makes
    // the cell non-passable), so a single representative suffices — but it
    // has to be a colour the cell can actually take. Picking from the
    // cell's own options rather than the whole domain avoids assigning a
    // value the option set has already excluded, which threw a RangeError
    // on 3-colour grids where the first non-`color` domain entry was pruned.
    for (int i = 0; i < puzzle.cellValues.length; i++) {
      if (puzzle.cellValues[i] != CellValue.free) continue;
      final options = puzzle.cells[i].options;
      CellValue? blocker;
      for (final v in options) {
        if (v != color) {
          blocker = v;
          break;
        }
      }
      // No non-`color` option: the cell can only be `color`, so it can't be
      // blocked — nothing to probe here.
      if (blocker == null) continue;
      final clone = puzzle.clone();
      clone.setValue(i, blocker);
      if (_isBlocked(clone)) {
        // Every non-`color` choice for this cell severs the chain. If
        // `color` is still an option it must take it; otherwise no colour
        // keeps a path open and the chain is unsatisfiable.
        if (options.contains(color)) {
          return SetValue(i, color, this, complexity: 2);
        }
        return Impossible(this);
      }
    }

    return null;
  }

  // True when a path of already-coloured target cells connects fromSide to
  // toSide. Traversal restricted to cells whose value is exactly `color`
  // (free cells do NOT count, unlike _isBlocked).
  bool _hasCompletePath(Puzzle puzzle) {
    final fromCells = _borderCells(
      fromSide,
      puzzle.width,
      puzzle.height,
    ).where((i) => puzzle.cellValues[i] == color);
    final toCellSet = _borderCells(toSide, puzzle.width, puzzle.height).toSet();
    return canReach(
      puzzle,
      fromCells,
      toCellSet.contains,
      (i) => puzzle.cellValues[i] == color,
    );
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    // Once a path of target-coloured cells connects the two sides, no future
    // move can break it (placed cells are immutable): verify stays true and
    // no apply branch can ever fire again → the constraint is complete.
    return _hasCompletePath(puzzle);
  }
}
