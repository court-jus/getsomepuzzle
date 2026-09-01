import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

/// The four card-suit symbols a [SameSize] constraint can carry.
/// [symbol] is the serialised key; [glyph] is the rendered character.
const Map<String, String> kSameSizeSymbols = {
  'H': '♥', // heart
  'D': '♦', // diamond
  'S': '♠', // spade
  'C': '♣', // club
};

/// The Same Size constraint (`SZ`) marks several cells with the same symbol
/// and requires them to belong to distinct groups that all have the same size
/// in the solved puzzle.
///
/// It is **colour-agnostic** — it constrains group *sizes*, not a specific
/// colour — so `referencedColors` returns the empty set (same as `GS`, `LT`,
/// `DF`, `SY`). Like `LT`, two `SameSize` constraints sharing a symbol are
/// merged into a single constraint listing every marked cell; `Puzzle`
/// enforces that invariant in `addConstraint` / `prependConstraint`.
class SameSize extends CellsCentricConstraint {
  @override
  String get slug => 'SZ';

  // Colour-agnostic: constrains group sizes, not a specific colour.
  @override
  Set<CellValue> get referencedColors => const {};

  /// Serialised symbol key: one of `H`, `D`, `S`, `C`.
  String symbol = '';

  /// Rendered suit glyph (e.g. `♥` for `H`).
  String get glyph => kSameSizeSymbols[symbol] ?? symbol;

  SameSize(String strParams) {
    final params = strParams.split('.');
    symbol = params.removeAt(0);
    indices = params.map((e) => int.parse(e)).toList();
  }

  @override
  String serialize() => 'SZ:$symbol.${indices.join('.')}';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIndices = indices
        .map((i) => rotateIdx90CW(i, origWidth, origHeight))
        .toList();
    return SameSize('$symbol.${newIndices.join('.')}');
  }

  @override
  String toString() => glyph;

  @override
  String toHuman(Puzzle puzzle) {
    final hIndices = indices.map((i) => i + 1);
    return "$hIndices = $glyph";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final size = width * height;
    final List<String> result = [];
    for (final symbol in kSameSizeSymbols.keys) {
      for (int idx1 = 0; idx1 < size; idx1++) {
        for (int idx2 = idx1 + 1; idx2 < size; idx2++) {
          result.add('$symbol.$idx1.$idx2');
        }
      }
    }
    return result;
  }

  /// Distinct existing groups that contain at least one marked cell. Cells
  /// that are still free are skipped (they are not part of any group yet).
  List<List<int>> _relevantGroups(Puzzle puzzle) {
    final groups = getGroups(puzzle);
    final relevant = <List<int>>[];
    for (final idx in indices) {
      if (puzzle.cellValues[idx] == CellValue.free) continue;
      final group = groups.firstWhereOrNull((g) => g.contains(idx));
      if (group == null) continue;
      // Groups never share cells, so `group.first` uniquely identifies one.
      if (!relevant.any((g) => g.first == group.first)) relevant.add(group);
    }
    return relevant;
  }

  /// True when no two marked cells already belong to the same group.
  bool _markedGroupsAreIndependent(Puzzle puzzle) {
    final marked = indices.toSet();
    return getGroups(
      puzzle,
    ).every((group) => group.where(marked.contains).length < 2);
  }

  /// Prevent a free cell from merging two marked groups of the same colour.
  /// A free marked cell must also avoid merging into an existing marked group.
  Move? _preventMarkedGroupMerge(Puzzle puzzle, List<List<int>> relevant) {
    for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
      if (puzzle.cellValues[idx] != CellValue.free) continue;
      final adjacentGroups = <CellValue, Set<int>>{};
      for (final group in relevant) {
        if (!puzzle.getNeighbors(idx).any(group.contains)) continue;
        final color = puzzle.cellValues[group.first];
        adjacentGroups.putIfAbsent(color, () => <int>{}).add(group.first);
      }
      for (final entry in adjacentGroups.entries) {
        final mergesMarkedGroups = entry.value.length > 1;
        final mergesMarkedCell =
            indices.contains(idx) && entry.value.isNotEmpty;
        if ((mergesMarkedGroups || mergesMarkedCell) &&
            puzzle.cells[idx].options.contains(entry.key)) {
          return RemoveOption(idx, entry.key, this, complexity: 1);
        }
      }
    }
    return null;
  }

  @override
  bool verify(Puzzle puzzle) {
    if (!_markedGroupsAreIndependent(puzzle)) return false;
    final relevant = _relevantGroups(puzzle);
    if (relevant.isEmpty) return !puzzle.complete;

    final firstSize = relevant.first.length;
    final allEqual = relevant.every((g) => g.length == firstSize);
    if (allEqual) return true;
    // Sizes differ. A completed puzzle can never repair that.
    if (puzzle.complete) return false;
    // Partial: a smaller group is still satisfiable iff it can grow (or
    // merge) toward the larger size. A smaller enclosed group is stuck.
    final target = relevant.fold<int>(0, (m, g) => max(m, g.length));
    for (final group in relevant) {
      if (group.length == target) continue;
      if (!_canGrow(puzzle, group)) return false;
    }
    return true;
  }

  /// True when [group] can still grow: some member has a free neighbour that
  /// still has the group's colour in its options. Mirrors the growable check
  /// in `GroupSize.verify`.
  bool _canGrow(Puzzle puzzle, List<int> group) {
    final color = puzzle.cellValues[group.first];
    for (final member in group) {
      for (final nei in puzzle.getNeighbors(member)) {
        if (puzzle.cellValues[nei] == CellValue.free &&
            puzzle.cells[nei].options.contains(color)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Move? apply(Puzzle puzzle) {
    if (!_markedGroupsAreIndependent(puzzle)) return Impossible(this);
    final relevant = _relevantGroups(puzzle);
    if (relevant.isEmpty) return null;
    final separationMove = _preventMarkedGroupMerge(puzzle, relevant);
    if (separationMove != null) return separationMove;
    // Take the largest group as the common target, then reuse the GroupSize
    // growth mechanism to grow every smaller group up to it. The target is a
    // *floor*: the largest marked group can still grow, so the equal sizes
    // may be reached above it — exact-size pruning would wrongly cut growth
    // paths that overshoot the current maximum (they are the puzzle's valid
    // completions). Forced growth deductions (single exit, articulation,
    // unreachable floor) still apply.
    final target = relevant.fold<int>(0, (m, g) => max(m, g.length));
    for (final group in relevant) {
      if (group.length >= target) continue;
      final move = GroupSize(
        '${group.first}.$target',
        atLeast: true,
      ).apply(puzzle);
      if (move != null) return move.retag(this);
    }
    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    if (indices.any((i) => puzzle.cellValues[i] == CellValue.free)) {
      return false;
    }
    final relevant = _relevantGroups(puzzle);
    if (relevant.isEmpty) return false;
    final firstSize = relevant.first.length;
    for (final group in relevant) {
      if (group.length != firstSize) return false;
      if (_canGrow(puzzle, group)) return false;
    }
    return true;
  }
}
