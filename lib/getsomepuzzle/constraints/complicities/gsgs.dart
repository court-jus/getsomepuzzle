import 'package:getsomepuzzle/getsomepuzzle/constraints/complicities/complicity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// GS + GS complicity: two `GroupSize` constraints anchored on
/// adjacent cells with different target sizes cannot share a group.
/// If they were both the same colour they would merge into a single
/// group of one size, violating at least one of the two constraints.
///
/// Two consequences:
///
/// 1. **Forced opposite colour** — when one of the two anchor cells
///    is already coloured and the other is empty, the empty one must
///    take the opposite colour. (Otherwise the two would share a
///    group.) `GroupSize.apply` only enforces this once its own group
///    has reached the target size; the complicity catches it the
///    moment the colours are observed, regardless of the current
///    group size.
/// 2. **Impossibility** — both anchors already coloured the same
///    colour means they share a group with two conflicting target
///    sizes. The verify side of `GS` would eventually catch this,
///    but the complicity surfaces it as an explicit impossibility
///    move at apply time.
class GSGSComplicity extends Complicity {
  @override
  String serialize() => "GSGSComplicity";

  @override
  (String, String) get slugs => ('GS', 'GS');

  @override
  bool isPresent(Puzzle puzzle) {
    final gss = puzzle.constraints.whereType<GroupSize>().toList();
    if (gss.length < 2) return false;
    for (int i = 0; i < gss.length; i++) {
      for (int j = i + 1; j < gss.length; j++) {
        if (gss[i].size == gss[j].size) continue;
        final ai = gss[i].indices.first;
        final aj = gss[j].indices.first;
        if (puzzle.getNeighbors(ai).contains(aj)) return true;
      }
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final gss = puzzle.constraints.whereType<GroupSize>().toList();
    for (int i = 0; i < gss.length; i++) {
      for (int j = i + 1; j < gss.length; j++) {
        if (gss[i].size == gss[j].size) continue;
        final ai = gss[i].indices.first;
        final aj = gss[j].indices.first;
        if (!puzzle.getNeighbors(ai).contains(aj)) continue;
        final vi = puzzle.cellValues[ai];
        final vj = puzzle.cellValues[aj];
        if (vi != CellValue.free && vj != CellValue.free) {
          if (vi == vj) {
            return Move(0, value: CellValue.free, this, isImpossible: this);
          }
          continue; // already on different colours — nothing to do
        }
        if (vi != CellValue.free && vj == CellValue.free) {
          // Tier 3: combination — two GSs reasoning jointly about an
          // adjacency that neither one alone can rule out yet. The two
          // anchors must take different colours, so aj cannot take vi.
          // If aj already excluded vi (3-colour puzzles), no useful
          // deduction here — skip to next pair.
          if (puzzle.cells[aj].options.contains(vi)) {
            return Move(aj, removeOption: vi, this, complexity: 3);
          }
          continue;
        }
        if (vj != CellValue.free && vi == CellValue.free) {
          if (puzzle.cells[ai].options.contains(vj)) {
            return Move(ai, removeOption: vj, this, complexity: 3);
          }
          continue;
        }
        // Both empty: we know they must be different colours but we
        // can't pick a value yet. A later step (other constraints
        // colouring one of them) will let this complicity fire.
      }
    }
    return null;
  }
}
