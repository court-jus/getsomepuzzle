import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

// Arrows for the parity constraint appear smaller so we add a zoom factor
const fontSizeRatio = 40.0 / 36.0;

class ParityConstraint extends CellsCentricConstraint {
  String side = "";

  ParityConstraint(String strParams) {
    indices.add(int.parse(strParams.split(".")[0]));
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
  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
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
      return SizedBox(
        width: cellSize / count,
        height: cellSize / count,
        child: Center(
          child: Icon(icons[side], size: cellSize * cellSizeToFontSize * fontSizeRatio / count, color: fgcolor),
        ),
      );
    }
    return Text("");
  }

  @override
  bool verify(Puzzle puzzle) {
    final w = puzzle.width;
    final idx = indices[0];
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
