// ignore_for_file: avoid_print
import 'package:collection/collection.dart';
import 'package:getsomepuzzle_ng/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle_ng/getsomepuzzle/constraint.dart';

class Puzzle {
  String lineRepresentation;
  List<int> domain = [];
  int width = 0;
  int height = 0;
  List<Cell> cells = [];
  List<Constraint> constraints = [];

  Puzzle(this.lineRepresentation) {
    var attributesStr = lineRepresentation.split("_");
    if (attributesStr.length == 4) {
      // Default domain
      attributesStr.insert(0, "12");
    }
    final dimensions = attributesStr[1].split("x");
    domain = attributesStr[0].split("").map((e) => int.parse(e)).toList();
    width = int.parse(dimensions[0]);
    height = int.parse(dimensions[1]);
    cells = attributesStr[2]
        .split("")
        .map((e) => int.parse(e))
        .map((e) => Cell(e, domain, e > 0))
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

  List<int> get cellValues => cells.map((e) => e.value).toList();
  Map<int, Constraint> get cellConstraints => {
    for (var e in constraints.whereType<CellCentricConstraint>()) e.idx: e,
  };

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

  int setValue(int idx, int value) {
    final cell = cells[idx];
    return cell.setValue(value);
  }

  int incrValue(int idx) {
    final currentValue = cellValues[idx];
    return setValue(idx, (currentValue + 1) % (domain.length + 1));
  }

  bool get complete {
    return !cellValues.any((val) => val == 0);
  }

  List<Constraint> check() {
    final List<Constraint> result = [];
    for (var constraint in constraints) {
      if (!constraint.check(this)) {
        result.add(constraint);
      }
    }
    return result;
  }
}
