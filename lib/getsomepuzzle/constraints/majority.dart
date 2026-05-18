import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class MajorityConstraint extends Constraint {
  @override
  String get slug => 'MJ';

  int r0 = 0;
  int c0 = 0;
  int r1 = 0;
  int c1 = 0;
  int targetColor = 0;

  List<int>? _zoneIndices;

  MajorityConstraint(String strParams) {
    final parts = strParams.split(".");
    r0 = int.parse(parts[0]);
    c0 = int.parse(parts[1]);
    r1 = int.parse(parts[2]);
    c1 = int.parse(parts[3]);
    targetColor = int.parse(parts[4]);
  }

  /// Absolute cell indices contained in the zone for a grid of given [width].
  /// Cached on first call — callers must not invoke with two different widths
  /// on the same instance (in practice an instance is tied to one puzzle).
  List<int> indicesFor(int width) {
    _zoneIndices ??= () {
      final indices = <int>[];
      for (int r = r0; r <= r1; r++) {
        for (int c = c0; c <= c1; c++) {
          indices.add(r * width + c);
        }
      }
      return indices;
    }();
    return _zoneIndices!;
  }

  int get zoneSize => (r1 - r0 + 1) * (c1 - c0 + 1);

  /// Minimum target-color cells needed for strict majority:
  /// floor(N/2) + 1 = (N ~/ 2) + 1
  int get target => (zoneSize ~/ 2) + 1;

  @override
  String toString() => 'MJ';

  @override
  String toHuman(Puzzle puzzle) =>
      'Zone (${r0 + 1},${c0 + 1})-(${r1 + 1},${c1 + 1}) : majority of $targetColor';

  @override
  String serialize() => 'MJ:$r0.$c0.$r1.$c1.$targetColor';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    return MajorityConstraint(
      '$c0.${origHeight - 1 - r1}.$c1.${origHeight - 1 - r0}.$targetColor',
    );
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final List<String> result = [];
    for (int r0 = 0; r0 < height; r0++) {
      for (int r1 = r0; r1 < height; r1++) {
        for (int c0 = 0; c0 < width; c0++) {
          for (int c1 = c0; c1 < width; c1++) {
            final h = r1 - r0 + 1;
            final w = c1 - c0 + 1;
            final zs = h * w;
            if (zs < 3) continue;
            if (h == 1 || w == 1) continue;
            if (zs > (width * height) * 0.6) continue;
            for (final color in domain) {
              result.add('$r0.$c0.$r1.$c1.$color');
            }
          }
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final indices = indicesFor(puzzle.width);
    final currentCount = indices
        .where((i) => puzzle.cellValues[i] == targetColor)
        .length;
    final opposite = puzzle.domain.firstWhere((v) => v != targetColor);
    final oppositeCount = indices
        .where((i) => puzzle.cellValues[i] == opposite)
        .length;
    final freeCount = indices.where((i) => puzzle.cellValues[i] == 0).length;

    if (freeCount == 0) {
      return currentCount >= target;
    }

    if (currentCount + freeCount < target) return false;
    if (oppositeCount > zoneSize - target) return false;
    return true;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final indices = indicesFor(puzzle.width);
    final opposite = puzzle.domain.firstWhere((v) => v != targetColor);
    final freeCells = indices.where((i) => puzzle.cellValues[i] == 0).toList();
    if (freeCells.isEmpty) return null;

    final currentCount = indices
        .where((i) => puzzle.cellValues[i] == targetColor)
        .length;
    final oppositeCount = indices
        .where((i) => puzzle.cellValues[i] == opposite)
        .length;
    final firstFree = freeCells.first;

    /// Too much opposite
    if (oppositeCount > zoneSize - target) {
      return Move(0, 0, this, isImpossible: this);
    }

    /// Not enough space to grow
    if (currentCount + freeCells.length < target) {
      return Move(0, 0, this, isImpossible: this);
    }

    /// Just enough space to grow
    if (currentCount + freeCells.length == target) {
      return Move(firstFree, targetColor, this, complexity: 0);
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    final indices = indicesFor(puzzle.width);
    return indices.every((i) => puzzle.cellValues[i] != 0);
  }
}
