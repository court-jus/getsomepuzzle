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
    final attributesStr = lineRepresentation.split("_");
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
      }
    }
    print("rows");
    print(getRows().map((row) => row.map((cell) => cell.value.toString()).join("")).join("\n"));
    print("columns");
    print(getColumns().map((row) => row.map((cell) => cell.value.toString()).join("")).join("\n"));
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

  int setValue(int idx, int value) {
    final cell = cells[idx];
    return cell.setValue(value);
  }

  int incrValue(int idx) {
    final currentValue = cellValues[idx];
    return setValue(idx, (currentValue + 1) % (domain.length + 1));
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
