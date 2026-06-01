import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/rotation.dart';

class LetterGroup extends CellsCentricConstraint {
  @override
  String get slug => 'LT';

  // Colour-agnostic: groups same-letter cells, independent of colour.
  @override
  Set<CellValue> get referencedColors => const {};

  String letter = "";

  LetterGroup(String strParams) {
    final params = strParams.split(".");
    letter = params.removeAt(0);
    indices = params.map((e) => int.parse(e)).toList();
  }

  @override
  String serialize() => 'LT:$letter.${indices.join(".")}';

  @override
  Constraint rotated(int origWidth, int origHeight) {
    final newIndices = indices
        .map((i) => rotateIdx90CW(i, origWidth, origHeight))
        .toList();
    return LetterGroup('$letter.${newIndices.join(".")}');
  }

  @override
  String toHuman(Puzzle puzzle) {
    final hIndices = indices.map((i) => i + 1);
    return "$hIndices = $letter";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final size = width * height;
    final maxLetters = max(1, size ~/ 5);
    final List<String> result = [];
    for (int idx1 = 0; idx1 < size; idx1++) {
      for (int idx2 = 0; idx2 < size; idx2++) {
        if (idx1 == idx2) continue;
        for (int l = 0; l < maxLetters; l++) {
          // Skip 'I' (charCode 73): rendered in a cell it is visually
          // confusable with the vertical-symmetry (SY) glyph.
          if (l == 8) continue;
          result.add('${String.fromCharCode(65 + l)}.$idx1.$idx2');
        }
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    // Aggregation in `Puzzle` guarantees a single LetterGroup per letter, so
    // `indices` already lists every cell sharing this letter.
    //
    // Two LT cells with already-fixed but different colours can never end up
    // in a single same-colour group regardless of future play — the
    // constraint is unreachable, so return false immediately. This early
    // check runs before the "any cell still empty" short-circuit so the
    // detection fires even on partial states.
    CellValue? seenColor;
    for (final idx in indices) {
      final v = puzzle.cellValues[idx];
      if (v == CellValue.free) continue;
      if (seenColor == null) {
        seenColor = v;
      } else if (seenColor != v) {
        return false;
      }
    }
    if (indices.any((i) => puzzle.cellValues[i] == CellValue.free)) return true;
    final groups = getGroups(puzzle);
    final myIndicesSet = indices.toSet();
    final myGroups = groups
        .where((g) => g.toSet().intersection(myIndicesSet).isNotEmpty)
        .toList();
    if (myGroups.isEmpty) return false;
    // No cell carrying a different letter may share my group(s).
    for (final group in myGroups) {
      for (final idx in group) {
        if (myIndicesSet.contains(idx)) continue;
        final constraintsAtIdx = puzzle.cellConstraints[idx];
        if (constraintsAtIdx == null) continue;
        for (final constraint in constraintsAtIdx) {
          if (constraint is LetterGroup && constraint.letter != letter) {
            return false;
          }
        }
      }
    }
    if (!puzzle.complete) return true;
    // Complete state: a single connected group must cover all my indices.
    return myGroups.length == 1;
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myColors = indices
        .map((idx) => puzzle.getValue(idx))
        .where((value) => value != CellValue.free);
    if (myColors.isEmpty) return null;
    final myColor = myColors.first;
    final otherLetters = puzzle.constraints
        .whereType<LetterGroup>()
        .where((c) => c.letter != letter)
        .map((c) => c.indices)
        .flattenedToList;
    // 1. Every member must take myColor; any other coloured value is an error
    //    (on 3+ colours that includes the third colour, not just the single
    //    "opposite"), and a free member with myColor pruned from its options
    //    can no longer satisfy the group.
    for (var member in indices) {
      final memberValue = puzzle.getValue(member);
      if (memberValue == CellValue.free) {
        if (!puzzle.cells[member].options.contains(myColor)) {
          return Impossible(this);
        }
        return SetValue(member, myColor, this, complexity: 0);
      }
      if (memberValue != myColor) {
        return Impossible(this);
      }
    }
    final allGroups = getGroups(puzzle);
    final myIndicesSet = indices.toSet();
    final myGroupsJoined = allGroups
        .where((grp) => grp.toSet().intersection(myIndicesSet).isNotEmpty)
        .flattened;
    // 2. Cells of another letter touching my group cannot be the same colour
    //    (would merge two distinct letters).
    final neighborWithLetters = myGroupsJoined
        .map((idx) => puzzle.getNeighbors(idx))
        .flattened
        .where((nei) => otherLetters.contains(nei));
    for (var nei in neighborWithLetters) {
      final neiValue = puzzle.getValue(nei);
      if (neiValue == myColor) {
        return Impossible(this);
      }
      // The neighbour just can't be myColor (it would merge two letters); on
      // 3+ colours that's a removeOption, not a force to one specific opposite.
      // On a 2-colour domain removeOption collapses to the other colour, so
      // the historical behaviour is preserved.
      if (neiValue == CellValue.free &&
          puzzle.cells[nei].options.contains(myColor)) {
        return RemoveOption(nei, myColor, this, complexity: 1);
      }
    }

    // 3. Feasibility: my members must all share one virtual group anchored
    //    on myColor (i.e. there must be SOME path of myColor + empty cells
    //    connecting them).
    final canConnect = toVirtualGroups(
      puzzle,
    ).any((vg) => indices.every((m) => vg.contains(m)));
    if (!canConnect) {
      return Impossible(this);
    }

    final sameGroup = allGroups.any(
      (grp) => grp.toSet().intersection(myIndicesSet).length == indices.length,
    );

    // 4. Articulation: any empty cell whose blocking would disconnect the
    //    members must take myColor — it lies on every possible merge path.
    //    Subsumes the per-group "single exit" rule (a sealed-but-one group
    //    has its lone exit as articulation point).
    if (!sameGroup && indices.length > 1) {
      for (var idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (puzzle.getValue(idx) != CellValue.free) continue;
        if (blockingDisconnectsMembers(puzzle, idx, myColor, indices)) {
          return SetValue(idx, myColor, this, complexity: 4);
        }
      }
    }

    // 5. Free neighbours of my group that also touch another letter's
    //    same-colour cells cannot take myColor (would merge two letters).
    final otherSameColor = otherLetters.where(
      (idx) => puzzle.cellValues[idx] == myColor,
    );
    if (otherSameColor.isNotEmpty) {
      final otherGroups = allGroups
          .where(
            (grp) =>
                grp.toSet().intersection(otherSameColor.toSet()).isNotEmpty,
          )
          .flattened;
      final Set<int> groupFreeNeighbors = {};
      for (var member in indices) {
        final memberGroup = allGroups
            .where((grp) => grp.contains(member))
            .first;
        for (var groupCell in memberGroup) {
          groupFreeNeighbors.addAll(
            puzzle
                .getNeighbors(groupCell)
                .where((idx) => puzzle.getValue(idx) == CellValue.free),
          );
        }
      }
      for (final groupFreeNeighbor in groupFreeNeighbors) {
        final neighborsWithOther = puzzle
            .getNeighbors(groupFreeNeighbor)
            .where((nei) => otherGroups.contains(nei));
        // Taking myColor here would bridge my group to another letter's
        // same-colour group → forbidden. Prune myColor rather than forcing a
        // specific opposite (collapses to the other colour on a 2-colour
        // domain; leaves the remaining options on 3+).
        if (neighborsWithOther.isNotEmpty &&
            puzzle.cells[groupFreeNeighbor].options.contains(myColor)) {
          return RemoveOption(groupFreeNeighbor, myColor, this, complexity: 2);
        }
      }
    }

    return null;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    if (indices.any((i) => i >= puzzle.cellValues.length)) return false;
    final myCellValues = indices.map((i) => puzzle.cellValues[i]).toList();
    if (myCellValues.contains(CellValue.free)) return false;
    final groups = getGroups(puzzle);
    final myGroup = groups.firstWhereOrNull(
      (grp) =>
          grp.toSet().intersection(indices.toSet()).length == indices.length,
    );
    if (myGroup == null) return false;
    for (final member in myGroup) {
      final freeNeighbors = puzzle
          .getNeighbors(member)
          .where((nei) => puzzle.cellValues[nei] == CellValue.free);
      if (freeNeighbors.isNotEmpty) return false;
    }
    return true;
  }
}
