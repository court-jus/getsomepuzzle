import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// LT + FM complicity: if a LetterGroup spans different rows (or columns),
/// its connecting path must include a vertical (or horizontal) step.
/// If a ForbiddenMotif blocks that step for a given color, the LT group
/// is forced to the other color.
class LTFMComplicity extends Complicity {
  @override
  String serialize() {
    return "LTFMComplicity";
  }

  @override
  bool isPresent(Puzzle puzzle) {
    final ltConstraints = puzzle.constraints.whereType<LetterGroup>();
    final fmConstraints = puzzle.constraints.whereType<ForbiddenMotif>();
    if (fmConstraints.isEmpty) return false;

    for (final lt in ltConstraints) {
      final rows = lt.indices.map((i) => i ~/ puzzle.width).toSet();
      final cols = lt.indices.map((i) => i % puzzle.width).toSet();

      for (final color in puzzle.domain) {
        if (rows.length > 1 &&
            fmConstraints.any((fm) => _blocksVertical(fm, color))) {
          return true;
        }
        if (cols.length > 1 &&
            fmConstraints.any((fm) => _blocksHorizontal(fm, color))) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final ltConstraints = puzzle.constraints.whereType<LetterGroup>();
    final fmConstraints = puzzle.constraints.whereType<ForbiddenMotif>();

    for (final lt in ltConstraints) {
      // Skip if any LT cell already has a color
      final hasKnown = lt.indices.any((i) => puzzle.cellValues[i] != 0);
      if (hasKnown) continue;

      final rows = lt.indices.map((i) => i ~/ puzzle.width).toSet();
      final cols = lt.indices.map((i) => i % puzzle.width).toSet();

      for (final color in puzzle.domain) {
        bool blocked = false;

        if (rows.length > 1) {
          blocked = fmConstraints.any((fm) => _blocksVertical(fm, color));
        }
        if (!blocked && cols.length > 1) {
          blocked = fmConstraints.any((fm) => _blocksHorizontal(fm, color));
        }

        if (blocked) {
          final forcedColor = puzzle.domain.where((c) => c != color).first;
          for (final idx in lt.indices) {
            if (puzzle.cellValues[idx] == 0) {
              return Move(idx, forcedColor, this);
            }
          }
        }
      }
    }
    return null;
  }

  /// True if the motif is exactly [[C],[C]] — the only pattern that
  /// unconditionally blocks all vertical adjacency of color [color].
  static bool _blocksVertical(ForbiddenMotif fm, int color) {
    final motif = fm.motif;
    if (motif.length != 2) return false;
    if (motif[0].length != 1) return false;
    return motif[0][0] == color && motif[1][0] == color;
  }

  /// True if the motif is exactly [[C,C]] — the only pattern that
  /// unconditionally blocks all horizontal adjacency of color [color].
  static bool _blocksHorizontal(ForbiddenMotif fm, int color) {
    final motif = fm.motif;
    if (motif.length != 1) return false;
    if (motif[0].length != 2) return false;
    return motif[0][0] == color && motif[0][1] == color;
  }
}
