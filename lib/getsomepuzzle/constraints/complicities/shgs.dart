import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// SH + GS complicity: a `ShapeConstraint` mandates a specific shape
/// (and thus a specific cell count) for every group of its colour. A
/// `GroupSize` constraint says "the group containing this cell has
/// size N". If the two sizes disagree, the cell at the GS anchor
/// cannot be the SH's colour.
///
/// Examples:
/// - SH:111 (color 1, shapeSize 3) + GS:0.2 → cell 0 cannot be 1
///   (group size 2 would never fit shape 111) → must be the other
///   colour.
/// - SH:111 (color 1, size 3) + SH:22 (color 2, size 2) + GS:0.4 →
///   cell 0 can be neither colour → impossible.
class SHGSComplicity extends Complicity {
  @override
  String serialize() => "SHGSComplicity";

  @override
  (String, String) get slugs => ('SH', 'GS');

  @override
  bool isPresent(Puzzle puzzle) {
    final shs = puzzle.constraints.whereType<ShapeConstraint>();
    final gss = puzzle.constraints.whereType<GroupSize>();
    if (shs.isEmpty || gss.isEmpty) return false;
    // The complicity has nothing to add when every (SH, GS) pair
    // already agrees on the size — propagation by either constraint
    // alone covers that case.
    for (final gs in gss) {
      for (final sh in shs) {
        if (sh.shapeSize != gs.size) return true;
      }
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final shs = puzzle.constraints.whereType<ShapeConstraint>().toList();
    if (shs.isEmpty) return null;
    // Map color → mandated group size. In normal generation there is
    // at most one SH per colour; if more were ever added, the first
    // wins (any disagreement would already fail SH.verify on its own).
    final shapeSizeByColor = <CellValue, int>{};
    for (final sh in shs) {
      shapeSizeByColor.putIfAbsent(sh.color, () => sh.shapeSize);
    }
    for (final gs in puzzle.constraints.whereType<GroupSize>()) {
      final cellIdx = gs.indices.first;
      if (puzzle.cellValues[cellIdx] != CellValue.free) continue;
      final excluded = <CellValue>[];
      for (final entry in shapeSizeByColor.entries) {
        if (entry.value != gs.size) excluded.add(entry.key);
      }
      if (excluded.isEmpty) continue;
      // Impossibility must be judged against the cell's *current options*,
      // not the full declared domain: a 3-colour cell whose options were
      // already pruned (by another constraint) down to an all-SH-excluded
      // subset is impossible even when `excluded.length < domain.length`.
      // Counting against the domain instead would miss that, and the
      // removeOption loop below would then collapse the cell onto the last
      // remaining — excluded — option (an unsound force).
      final cell = puzzle.cells[cellIdx];
      final hasViableOption = cell.options.any((o) => !excluded.contains(o));
      if (!hasViableOption) {
        return Impossible(this);
      }
      // Combination deduction: tier 3 (see docs/dev/constraint_complicity.md).
      // Each `exColor` in `excluded` is a colour the cell cannot take. On
      // 2-colour puzzles `excluded` has one element and we can compute the
      // single survivor, but on 3-colour we emit one removeOption at a
      // time. A viable option is guaranteed to remain (checked above), so
      // pruning an excluded colour never collapses the cell onto another
      // excluded one. If every excluded colour is already gone from the
      // cell's options, this GS has no deduction left — fall through.
      for (final exColor in excluded) {
        if (cell.options.contains(exColor)) {
          return RemoveOption(cellIdx, exColor, this, complexity: 3);
        }
      }
    }
    return null;
  }
}
