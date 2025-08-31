import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';


class Constraint {
  bool isValid = true;

  @override
  String toString() {
    return "";
  }

  Widget toWidget(Color defaultColor) {
    return Text(toString());
  }

  bool verify(Puzzle puzzle) {
    return true;
  }

  bool check(Puzzle puzzle) {
    isValid = verify(puzzle);
    return isValid;
  }
}

class Motif extends Constraint {
  List<List<int>> motif = [];

  bool isPresent(Puzzle puzzle) {
    final Map<int, Map<int, List<int>>> findings = {};
    final rows = puzzle.getRows();
    for (var (midx, motifline) in motif.indexed) {
      final motiflineStr = motifline.map((e) => e.toString()).join("");
      final motifRe = RegExp(motiflineStr);
      for (var (ridx, row) in rows.indexed) {
        final List<int> rowFindings = findings
            .putIfAbsent(midx - 1, () => {})
            .putIfAbsent(ridx - 1, () => []);
        final rowStr = row.map((e) => e.value.toString()).join("");
        final List<int> matchingIdx = [
          for (var idx in Iterable.generate(rowStr.length))
            if (motifRe.matchAsPrefix(rowStr, idx) != null &&
                (midx == 0 || rowFindings.contains(idx)))
              idx,
        ];
        if (matchingIdx.isNotEmpty) {
          if (midx == motif.length - 1) {
            return true;
          }
          findings.putIfAbsent(midx, () => {})[ridx] = matchingIdx;
        }
      }
    }
    return false;
  }
}

class ForbiddenMotif extends Motif {
  ForbiddenMotif(String strMotif) {
    final strRows = strMotif.split(".");
    motif = strRows
        .map((row) => row.split("").map((cel) => int.parse(cel)).toList())
        .toList();
  }

  @override
  String toString() {
    final strMotif = motif
        .map((row) => row.map((v) => v.toString()).join(""))
        .join(".");
    return strMotif;
  }

  @override
  bool verify(Puzzle puzzle) {
    return !isPresent(puzzle);
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
    if (side == "left") return "⬅";
    if (side == "right") return "⮕";
    if (side == "horizontal") return "⬌";
    if (side == "vertical") return "⬍";
    if (side == "top") return "⬆";
    if (side == "bottom") return "⬇";
    return "";
  }

  @override
  Widget toWidget(Color defaultColor) {
    final Map<String, IconData> icons = {
      "left": Icons.arrow_circle_left_outlined,
      "right": Icons.arrow_circle_right_outlined,
      "horizontal": Icons.swap_horizontal_circle_outlined,
      "vertical": Icons.swap_vert_circle_outlined,
      "top": Icons.arrow_circle_up_outlined,
      "bottom": Icons.arrow_circle_down_outlined,
    };
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
    if (icons.containsKey(side)) {
      return Icon(
        icons[side],
        size: 40,
        color: fgcolor,
      );
    }
    return Text("");
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
      if (even != odd) {
        return false;
      }
    }
    return true;
  }
}

class GroupSize extends CellCentricConstraint {
  int size = 0;

  GroupSize(String strParams) {
    idx = int.parse(strParams.split(".")[0]);
    size = int.parse(strParams.split(".")[1]);
  }

  @override
  String toString() {
    return size.toString();
  }

  @override
  Widget toWidget(Color defaultColor) {
    final fgcolor = isValid ? defaultColor : Colors.redAccent;
    return Text(toString(), style: TextStyle(fontSize: 36, color: fgcolor));
  }

  @override
  bool verify(Puzzle puzzle) {
    final groups = puzzle.getGroups();
    final myGroup = groups.firstWhereOrNull((grp) => grp.contains(idx));
    if (myGroup == null) return false;
    return myGroup.length == size;
  }
}
