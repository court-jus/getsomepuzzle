import 'package:getsomepuzzle_ng/getsomepuzzle/puzzle.dart';

class Constraint {
  bool isValid = true;

  @override
  String toString() {
    return "";
  }

  bool verify(Puzzle puzzle) {
    return true;
  }

  bool check(Puzzle puzzle) {
    isValid = verify(puzzle);
    return isValid;
  }
}

class Motif extends Constraint {}

class ForbiddenMotif extends Motif {
  List<List<int>> motif = [];

  ForbiddenMotif(String strMotif) {
    final strRows = strMotif.split(".");
    motif = strRows
        .map((row) => row.split("").map((cel) => int.parse(cel)).toList())
        .toList();
  }
}

class CellCentricConstraint extends Constraint {
  int idx = 0;
}

class ParityConstraint extends CellCentricConstraint {
  String side = "";

  ParityConstraint(String strParams) {
    idx = int.parse(strParams.split(".")[0]);
    side = strParams.split(".")[1];
  }

  @override
  String toString() {
    final flag = isValid ? "V" : "X";
    if (side == "left") return "$flag $idx ⬅";
    if (side == "right") return "$flag $idx ⮕";
    if (side == "horizontal") return "$flag $idx ⬌";
    if (side == "vertical") return "$flag $idx ⬍";
    if (side == "top") return "$flag $idx ⬆";
    if (side == "bottom") return "$flag $idx ⬇";
    return "";
  }

  @override
  bool verify(Puzzle puzzle) {
    final w = puzzle.width;
    final ridx = idx ~/ w;
    final cidx = idx % w;
    final rows = puzzle.getRows();
    final row = rows[ridx];
    final columns = puzzle.getColumns();
    final column = columns[cidx];
    print("$isValid Check $idx $side $ridx $cidx");
    final rowStr = row.map((cell) => cell.value.toString()).join("");
    final colStr = column.map((cell) => cell.value.toString()).join("");
    print("Row $rowStr col $colStr");
    final rowValuesAndIndices = row.indexed.map((e) => (e.$1, e.$2.value));
    final colValuesAndIndices = column.indexed.map((e) => (e.$1, e.$2.value));
    final List<Iterable<int>> sides = [];
    if (side == "left" || side == "horizontal") {
      sides.add(rowValuesAndIndices.where((e) => e.$1 < cidx).map((e) => e.$2));
    }
    if (side == "right" || side == "horizontal") {
      sides.add(rowValuesAndIndices.where((e) => e.$1 > cidx).map((e) => e.$2));
    }
    if (side == "top" || side == "vertical") {
      sides.add(colValuesAndIndices.where((e) => e.$1 < ridx).map((e) => e.$2));
    }
    if (side == "bottom" || side == "vertical") {
      sides.add(colValuesAndIndices.where((e) => e.$1 > ridx).map((e) => e.$2));
    }
    for (var side in sides) {
      if (side.contains(0)) {
        continue;
      }
      final int even = side.where((v) => v % 2 == 0).length;
      final int odd = side.where((v) => v % 2 != 0).length;
      print("$side $even $odd");
      if (even != odd) {
        return false;
      }
    }
    return true;
  }
}
