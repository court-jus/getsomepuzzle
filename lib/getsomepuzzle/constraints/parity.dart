import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// `PA` — **balanced colour partition** of one side of an anchor cell.
///
/// Despite the legacy "parity" name and slug, the constraint requires every
/// colour of the puzzle's domain to appear the *same* number of times on the
/// targeted side: `targetCount = side.length / domain.length` cells per colour
/// (see [verify] / [apply]). The name is historical — on the original
/// 2-colour domain "balanced" collapses to "as many black as white", i.e. an
/// even side split in half, which reads as parity. On a 3-colour domain it
/// generalises to "as many black as white as purple", which is no longer a
/// parity statement; the slug is kept for backward compatibility with stored
/// puzzle lines. See `docs/dev/third_color.md` § "PA semantics on 3 colours".
class ParityConstraint extends CellsCentricConstraint {
  @override
  String get slug => 'PA';

  // Colour-agnostic: balances colours per side, references none specifically.
  @override
  Set<CellValue> get referencedColors => const {};

  String side = "";

  ParityConstraint(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
    side = strParams.split(".")[1];
  }

  @override
  String toString() {
    if (side == "left") return "⬅";
    if (side == "right") return "⮕";
    if (side == "horizontal") return "⬌";
    if (side == "vertical") return "⬍";
    if (side == "top") return "⬆";
    if (side == "bottom") return "⬇";
    return "";
  }

  @override
  String serialize() => 'PA:${indices.first}.$side';

  /// Returns the merged side when [a] and [b] lie on the same axis
  /// (vertical = top/bottom, horizontal = left/right), null otherwise.
  /// Each side of a `vertical`/`horizontal` constraint must be balanced
  /// independently, so `vertical` subsumes `top` and `bottom` (and the
  /// pair `top` + `bottom` is exactly `vertical`) — same for the
  /// horizontal axis.
  static String? mergeSides(String a, String b) {
    if (a == b) return a;
    const vertical = {'top', 'bottom', 'vertical'};
    const horizontal = {'left', 'right', 'horizontal'};
    if (vertical.contains(a) && vertical.contains(b)) return 'vertical';
    if (horizontal.contains(a) && horizontal.contains(b)) return 'horizontal';
    return null;
  }

  /// Rotation-90°-CW mapping for the `side` parameter. Cells originally to
  /// the left of the anchor end up above it in the rotated grid, etc.
  static const Map<String, String> _rotatedSide = {
    'left': 'top',
    'right': 'bottom',
    'top': 'right',
    'bottom': 'left',
    'horizontal': 'vertical',
    'vertical': 'horizontal',
  };

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIdx = rotateIdx90CW(indices.first, origWidth, origHeight);
    final newSide = _rotatedSide[side] ?? side;
    return ParityConstraint('$newIdx.$newSide');
  }

  @override
  String toHuman(Puzzle puzzle) {
    final idx = indices.first + 1;
    return "$idx = ${toString()}";
  }

  /// Generate all valid parity constraint parameters for a given grid size.
  ///
  /// A side is only emitted when its length is divisible by `domain.length`,
  /// so the per-colour target `side.length / domain.length` is an integer.
  /// On a 2-colour domain this is the classic even-side test (`size % 2`); on
  /// 3 colours it becomes `size % 3`, etc.
  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int idx = 0; idx < width * height; idx++) {
      final ridx = idx ~/ width;
      final cidx = idx % width;
      final leftSize = cidx;
      final rightSize = width - 1 - cidx;
      final topSize = ridx;
      final bottomSize = height - 1 - ridx;
      if (leftSize % domain.length == 0 && leftSize > 0) {
        result.add('$idx.left');
      }
      if (rightSize % domain.length == 0 && rightSize > 0) {
        result.add('$idx.right');
      }
      if (leftSize % domain.length == 0 &&
          rightSize % domain.length == 0 &&
          rightSize > 0 &&
          leftSize > 0) {
        result.add('$idx.horizontal');
      }
      if (topSize % domain.length == 0 && topSize > 0) {
        result.add('$idx.top');
      }
      if (bottomSize % domain.length == 0 && bottomSize > 0) {
        result.add('$idx.bottom');
      }
      if (topSize % domain.length == 0 &&
          bottomSize % domain.length == 0 &&
          bottomSize > 0 &&
          topSize > 0) {
        result.add('$idx.vertical');
      }
    }
    return result;
  }

  List<List<CellValue>> _getSideValues(Puzzle puzzle) {
    return _getSideCells(
      puzzle,
    ).map((side) => side.map((e) => e.$2.value).toList()).toList();
  }

  List<List<(int, Cell)>> _getSideCells(Puzzle puzzle) {
    final w = puzzle.width;
    final idx = indices[0];
    final ridx = idx ~/ w;
    final cidx = idx % w;
    final rows = puzzle.getRows();
    final row = rows[ridx];
    final columns = puzzle.getColumns();
    final column = columns[cidx];
    final rowValuesAndCells = row.indexed;
    final colValuesAndCells = column.indexed;
    final List<List<(int, Cell)>> sides = [];
    if (side == "left" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 < cidx).toList());
    }
    if (side == "right" || side == "horizontal") {
      sides.add(rowValuesAndCells.where((e) => e.$1 > cidx).toList());
    }
    if (side == "top" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 < ridx).toList());
    }
    if (side == "bottom" || side == "vertical") {
      sides.add(colValuesAndCells.where((e) => e.$1 > ridx).toList());
    }
    return sides;
  }

  @override
  bool verify(Puzzle puzzle) {
    // Use cells (not just values) so reachability can account for free
    // cells that have pruned a colour from their options.
    for (var side in _getSideCells(puzzle)) {
      final int targetCount = side.length ~/ puzzle.domain.length;
      final bool hasFree = side.any((e) => e.$2.value == CellValue.free);
      for (var color in puzzle.domain) {
        final int have = side.where((e) => e.$2.value == color).length;
        // Too many of one color already → target is
        // unreachable from this state
        if (have > targetCount) return false;
        // For a fully-filled side the counts must match exactly
        if (!hasFree && have != targetCount) return false;
        // Reachability: even using every free cell that still allows this
        // colour, the side can't reach its per-colour target → unreachable.
        final int reachableFree = side
            .where(
              (e) =>
                  e.$2.value == CellValue.free && e.$2.options.contains(color),
            )
            .length;
        if (have + reachableFree < targetCount) return false;
      }
    }
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final sides = _getSideCells(puzzle);
    // Weight by the largest side covered: with 2 cells per side, the second
    // cell is read directly off the first; 4 cells require parity counting;
    // 6+ cells need real bookkeeping. For 2-side variants (horizontal /
    // vertical) we take the max — the player must still scan the long side.
    final int maxSide = sides
        .map((s) => s.length)
        .reduce((a, b) => a > b ? a : b);
    final int weight = maxSide <= puzzle.domain.length
        ? 0
        : (maxSide <= (puzzle.domain.length * 2) ? 1 : 2);
    for (var side in sides) {
      final int targetCount = side.length ~/ puzzle.domain.length;
      final freeCells = side.where(
        (element) => element.$2.value == CellValue.free,
      );
      final Map<CellValue, int> perColor = {};
      for (var color in puzzle.domain) {
        perColor[color] = side
            .where((v) => v.$2.value != CellValue.free && v.$2.value == color)
            .length;
        // If we're already above the target, it's an "isImpossible" move
        if (perColor[color]! > targetCount) {
          return Impossible(this);
        }
        // If this color has reached its target, all the free cells that still
        // have that option must remove it. Removing the last remaining option
        // has the side effect of applying the only remaining color.
        if (perColor[color]! == targetCount) {
          for (var freeCell in freeCells) {
            if (freeCell.$2.options.contains(color)) {
              return RemoveOption(
                freeCell.$2.idx,
                color,
                this,
                complexity: weight,
              );
            }
          }
        }
      }
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final sides = _getSideValues(puzzle);
    for (var side in sides) {
      if (side.contains(CellValue.free)) return false;
    }
    return true;
  }
}
