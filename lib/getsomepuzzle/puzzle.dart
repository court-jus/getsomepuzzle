import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/helptext.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

class Stats {
  int failures = 0;
  int duration = 0;
  Stopwatch timer = Stopwatch();

  @override
  String toString() {
    // 2025-08-23T22:59:42 8s - 0f 3x3_000001020_GS:5.1;PA:6.top;PA:0.right;PA:2.left;FM:222_1:212121122
    return "${(timer.elapsedMilliseconds / 1000).round()}s - ${failures}f";
  }

  void begin() {
    timer.start();
    failures = 0;
  }

  void pause() {
    timer.stop();
  }

  void resume() {
    timer.start();
  }

  void stop(String puzzleRepresentation) {
    timer.stop();
    duration = (timer.elapsedMilliseconds / 1000).round();
    timer.reset();
  }
}

class Puzzle {
  String lineRepresentation;
  List<int> domain = [];
  int width = 0;
  int height = 0;
  List<Cell> cells = [];
  List<Constraint> constraints = [];

  Puzzle(this.lineRepresentation) {
    var attributesStr = lineRepresentation.split("_");
    final dimensions = attributesStr[1].split("x");
    domain = attributesStr[0].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    cells = attributesStr[2]
        .split("")
        .map((e) => int.parse(e))
        .indexed
        .map((e) => Cell(e.$2, e.$1, domain, e.$2 > 0))
        .toList();
    final strConstraints = attributesStr[3].split(";");
    for (var strConstraint in strConstraints) {
      final constraintAttr = strConstraint.split(":");
      if (constraintAttr[0] == "FM") {
        constraints.add(ForbiddenMotif(constraintAttr[1]));
      } else if (constraintAttr[0] == "PA") {
        constraints.add(ParityConstraint(constraintAttr[1]));
      } else if (constraintAttr[0] == "GS") {
        constraints.add(GroupSize(constraintAttr[1]));
      } else if (constraintAttr[0] == "LT") {
        constraints.add(LetterGroup(constraintAttr[1]));
      } else if (constraintAttr[0] == "QA") {
        constraints.add(QuantityConstraint(constraintAttr[1]));
      } else if (constraintAttr[0] == "SY") {
        constraints.add(SymmetryConstraint(constraintAttr[1]));
      } else if (constraintAttr[0] == "TX") {
        constraints.add(HelpText(constraintAttr[1]));
      }
    }
  }

  void restart() {
    for (var cell in cells) {
      if (!cell.readonly) {
        cell.value = 0;
        cell.options = cell.domain;
      }
    }
  }

  List<int> get cellValues => cells.map((cell) => cell.value).toList();
  Map<int, List<Constraint>> get cellConstraints {
    final Map<int, List<Constraint>> result = {};
    for (var constraint in constraints.whereType<CellsCentricConstraint>()) {
      for (var idx in constraint.indices) {
        if (!result.keys.contains(idx)) {
          result[idx] = [];
        }
        result[idx]!.add(constraint);
      }
    }
    return result;
  }

  int getValue(int idx) {
    return cells[idx].value;
  }

  List<List<Cell>> getRows() {
    // 12_4x5_00020210200022001201_FM:1.2;PA:10.top;PA:19.top_1:22222212221122111211
    return cells.slices(width).toList();
  }

  List<List<Cell>> getColumns() {
    final rows = getRows();
    final List<List<Cell>> result = [];
    for (var i = 0; i < rows[0].length; i++) {
      result.add([]);
      for (var row in rows) {
        result[i].add(row[i]);
      }
    }
    return result;
  }

  List<List<int>> getGroups() {
    final List<Set<int>> sameValues = [
      for (var idx in Iterable.generate(cellValues.length))
        getNeighborsSameValue(idx).toSet(),
    ];
    final Map<int, Set<int>> groups = {};
    var groupCount = 0;
    for (var others in sameValues) {
      if (others.isEmpty) continue;
      final existing = {
        for (var item in groups.entries)
          if (others.intersection(item.value).isNotEmpty) item.key: item.value,
      };
      if (existing.isEmpty) {
        groupCount += 1;
        groups[groupCount] = others;
        continue;
      }
      // Merge the groups
      final newIdx = existing.keys.toList()[0];
      var newGrp = existing[newIdx]!.union(others);
      final indicesRemove = existing.keys.where((i) => i != newIdx);
      for (var indexRemove in indicesRemove) {
        final removeGrp = existing[indexRemove];
        if (removeGrp != null) {
          groups.remove(indexRemove);
          newGrp = newGrp.union(removeGrp);
        }
      }
      groups[newIdx] = groups[newIdx]!.union(newGrp);
    }
    final List<List<int>> result = groups.values.map((grp) {
      final indices = grp.toList();
      indices.sort();
      return indices;
    }).toList();
    return result;
  }

  List<int> getNeighbors(int idx) {
    final maxidx = width * height - 1;
    final minidx = 0;
    final ridx = idx ~/ width;
    final abv = idx - width;
    final bel = idx + width;
    final lft = idx - 1;
    final rgt = idx + 1;
    final List<int> result = [];
    if (abv >= minidx) result.add(abv);
    if (bel <= maxidx) result.add(bel);
    if (lft >= minidx && lft ~/ width == ridx) result.add(lft);
    if (rgt <= maxidx && rgt ~/ width == ridx) result.add(rgt);
    return result;
  }

  List<int> getNeighborsSameValue(int idx) {
    final myValue = cellValues[idx];
    if (myValue == 0) return [];
    final List<int> result = [idx];
    result.addAll(getNeighbors(idx).where((e) => cellValues[e] == myValue));
    return result;
  }

  List<int> getNeighborsSameValueOrEmpty(int idx, int myValue) {
    final List<int> result = [idx];
    result.addAll(
      getNeighbors(
        idx,
      ).where((e) => cellValues[e] == myValue || cellValues[e] == 0),
    );
    return result;
  }

  bool setValue(int idx, int value) {
    final cell = cells[idx];
    return cell.setValue(value);
  }

  void resetCell(int idx) {
    final cell = cells[idx];
    cell.reset();
  }

  void incrValue(int idx) {
    final currentValue = cellValues[idx];
    setValue(idx, (currentValue + 1) % (domain.length + 1));
  }

  bool get complete {
    return !cellValues.any((val) => val == 0);
  }

  List<Constraint> check({bool saveResult = true}) {
    final List<Constraint> result = [];
    for (var constraint in constraints) {
      if (!constraint.check(this, saveResult: saveResult)) {
        result.add(constraint);
      }
    }
    return result;
  }

  Move? apply() {
    for (var c in constraints) {
      final move = c.apply(this);
      if (move != null) return move;
    }
    return null;
  }

  Move? applyAll() {
    bool finished = false;
    while (!finished) {
      final move = apply();
      if (move == null) return null;
      if (move.isImpossible != null) {
        finished = true;
        return Move(0, 0, move.givenBy, isImpossible: move.isImpossible);
      }
      setValue(move.idx, move.value);
      if (complete) {
        finished = true;
        return Move(
          0,
          0,
          move.givenBy,
          isImpossible: check(saveResult: false).isNotEmpty
              ? move.givenBy
              : null,
        );
      }
    }
    return null;
  }

  Move? findAMove() {
    // First find broken constraints
    final hasErrors = check(saveResult: false);
    if (hasErrors.isNotEmpty) {
      final firstError = hasErrors.first;
      final errorMove = firstError.apply(this);
      if (errorMove != null) {
        return errorMove;
      }
    }
    // Then try by directly applying the constraint
    final easyMove = apply();
    if (easyMove != null) return easyMove;
    // Nothing was found, we will now try on a cloned puzzle
    // to randomly set a cell's value and see if that leads to
    // an impossible to solve puzzle. It would mean that this
    // value is forbidden.
    final clone = Puzzle(lineRepresentation);
    clone.constraints = constraints;
    for (var cell in cellValues.indexed) {
      clone.setValue(cell.$1, cell.$2);
    }
    for (var freeCell in clone.cells.indexed.where(
      (entry) => entry.$2.value == 0,
    )) {
      for (var value in clone.domain) {
        clone.setValue(freeCell.$1, value);
        Move? result = clone.applyAll();
        if (result != null && result.isImpossible != null) {
          final opposite = clone.domain.whereNot((v) => v == value).first;
          return Move(freeCell.$1, opposite, result.givenBy);
        } else if (result != null && result.isImpossible == null) {
          return Move(freeCell.$1, value, result.givenBy);
        } else {
          for (var cell in cellValues.indexed) {
            clone.setValue(cell.$1, cell.$2);
          }
        }
      }
    }
    return null;
  }

  void clearConstraintsValidity() {
    for (var constraint in constraints) {
      constraint.isValid = true;
    }
  }

  void clearHighlights() {
    for (var constraint in constraints) {
      constraint.isHighlighted = false;
    }
    for (var cell in cells) {
      cell.isHighlighted = false;
    }
  }

  List<List<int>> toVirtualGroups() {
    final idxToExplore = cellValues.indexed.toList();
    final Map<int, List<int>> explored = {};
    final Map<int, Map<int, List<int>>> groupsPerValuePerCell = {};
    while (idxToExplore.isNotEmpty) {
      final exploring = idxToExplore.removeAt(0);
      final exploreIdx = exploring.$1;
      final value = exploring.$2;
      final others = explored[value] ?? [];
      if (others.contains(exploreIdx)) {
        continue;
      }
      others.add(exploreIdx);
      explored[value] = others;
      final sameOrEmpty = getNeighborsSameValueOrEmpty(exploreIdx, value);
      if (groupsPerValuePerCell[value] == null) {
        groupsPerValuePerCell[value] = {};
      }
      if (groupsPerValuePerCell[value]![exploreIdx] == null) {
        groupsPerValuePerCell[value]![exploreIdx] = [];
      }
      groupsPerValuePerCell[value]![exploreIdx]!.addAll(sameOrEmpty);
      for (var neighbor in sameOrEmpty) {
        if (neighbor != exploreIdx) {
          idxToExplore.add((neighbor, value));
        }
      }
    } // while
    final Map<int, List<Set<int>>> setsPerValue = {};
    for (var valueEntry in groupsPerValuePerCell.entries) {
      final value = valueEntry.key;
      final valueData = valueEntry.value;
      for (var dataEntry in valueData.entries) {
        final idx = dataEntry.key;
        final newGroup = dataEntry.value.toSet();
        if (setsPerValue[value] == null) {
          setsPerValue[value] = [];
        }
        for (var existing in findAndPop(setsPerValue[value]!, idx)) {
          newGroup.addAll(existing);
        }
        setsPerValue[value]!.add(newGroup);
      }
    }
    return setsPerValue.values.flattenedToList
        .map((grp) => grp.toList())
        .toList();
  }
}

List<Set<int>> findAndPop(List<Set<int>> setlist, int value) {
  /*
    Pops the sets in setlist that contains value.
    */
  final Set<int> indices = {};
  for (var setEntry in setlist.indexed) {
    final idx = setEntry.$1;
    final candidate = setEntry.$2;
    if (candidate.contains(value)) {
      indices.add(idx);
    }
  }
  final List<Set<int>> result = [];
  for (var idx in indices.sorted((a, b) => a - b).reversed) {
    result.add(setlist.removeAt(idx));
  }
  return result;
}
