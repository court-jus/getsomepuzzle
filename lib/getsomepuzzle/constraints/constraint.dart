import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Common contract for any object that can drive deductions on a Puzzle.
/// Both regular [Constraint]s and cross-constraint [Complicity]s implement
/// this — the propagation loop only needs `apply` and a way to identify
/// the source of a [Move].
abstract class CanApply {
  Move? apply(Puzzle puzzle);
  String serialize();
}

class Constraint extends CanApply {
  bool isValid = true;
  bool isHighlighted = false;
  bool isComplete = false;

  @override
  String toString() {
    return "";
  }

  String get slug => '';

  String toHuman(Puzzle puzzle) {
    return toString();
  }

  @override
  String serialize() {
    return '';
  }

  bool verify(Puzzle puzzle) {
    return true;
  }

  bool check(Puzzle puzzle, {bool saveResult = true}) {
    final verified = verify(puzzle);
    if (saveResult) {
      isValid = verified;
    }
    return verified;
  }

  bool isCompleteFor(Puzzle puzzle) => false;

  /// True when this constraint cannot coexist with [other] (an unresolvable
  /// conflict, e.g. visually overlapping borders). Default: no conflict.
  /// Only [MajorityConstraint] overrides this.
  bool conflictsWith(Constraint other) => false;

  /// Return a fresh constraint instance equivalent to this one applied to a
  /// puzzle rotated 90° clockwise. The arguments are the dimensions of the
  /// **original** puzzle (before rotation). All positional data — cell
  /// indices, line indices, sides, axes, 2D motifs — must be remapped so the
  /// returned constraint validates the rotated grid identically.
  ///
  /// Constraints whose data is purely global (no position) may return a
  /// fresh clone of self. Constraints that swap their slug under rotation
  /// (e.g. `ColumnCount` ↔ `RowCount`) must return an instance of the
  /// other class.
  Constraint rotated(int origWidth, int origHeight) {
    throw UnimplementedError(
      '$runtimeType does not implement rotated(); '
      'every Constraint subclass must override this for the puzzle '
      'rotation feature to work.',
    );
  }

  @override
  Move? apply(Puzzle puzzle) {
    throw UnimplementedError(
      '$runtimeType does not implement apply(); '
      'every Constraint subclass must override apply() with a deduction '
      'rule appropriate to its semantics — there is no generic fallback '
      'that is correct on a 3-colour domain.',
    );
  }

  /// The colours this constraint depends on — explicitly (a quantity/count
  /// target colour) or implicitly (the non-free values in an FM/SH motif).
  /// The auto-shrink pass uses this to decide whether a colour absent from
  /// the solution can also be dropped from the puzzle's declared domain
  /// without orphaning a constraint. Colour-agnostic constraints (`PA`,
  /// `GS`, `LT`, `DF`, `SY`) return the empty set.
  ///
  /// No generic fallback: like [apply] and [rotated], every subclass must
  /// declare its own colours so a new constraint can't silently drop a
  /// referenced colour from the export.
  Set<CellValue> get referencedColors {
    throw UnimplementedError(
      '$runtimeType does not implement referencedColors; '
      'every Constraint subclass must declare the colours it references '
      '(or the empty set) so the domain auto-shrink stays sound.',
    );
  }
}

class Motif extends Constraint {
  List<List<CellValue>> motif = [];

  @override
  Set<CellValue> get referencedColors => {
    for (final row in motif)
      for (final v in row)
        if (v != CellValue.free) v,
  };

  bool isPresent(Puzzle puzzle) {
    final int mow = motif[0].length;
    final int pta = puzzle.width - mow;
    final RegExp motifRe = RegExp(
      motif
          .map(
            (line) => line.map(cellValueToString).join("").replaceAll("0", "."),
          )
          .join("." * pta),
    );
    final puzzleStr = puzzle.cellValues.map(cellValueToString).join("");
    // print("puStr $puzzleStr");
    // print("morif $motifRe");
    for (var idx = 0; idx < puzzleStr.length; idx++) {
      if ((puzzle.width - (idx % puzzle.width)) < mow) {
        continue;
      }
      if (motifRe.matchAsPrefix(puzzleStr, idx) != null) {
        return true;
      }
    }
    return false;
  }

  static List<int> findMotifPositions(
    List<List<CellValue>> searchMotif,
    Puzzle puzzle,
  ) {
    final int mow = searchMotif[0].length;
    final int pta = puzzle.width - mow;
    final RegExp motifRe = RegExp(
      searchMotif
          .map(
            (line) => line.map(cellValueToString).join("").replaceAll("0", "."),
          )
          .join("." * pta),
    );
    final puzzleStr = puzzle.cellValues.map(cellValueToString).join("");
    final List<int> positions = [];
    for (var idx = 0; idx < puzzleStr.length; idx++) {
      if ((puzzle.width - (idx % puzzle.width)) < mow) {
        continue;
      }
      if (motifRe.matchAsPrefix(puzzleStr, idx) != null) {
        positions.add(idx);
      }
    }
    return positions;
  }
}

class CellsCentricConstraint extends Constraint {
  List<int> indices = [];
}
