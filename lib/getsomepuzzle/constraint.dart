import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class Constraint {
  bool isValid = true;

  @override
  String toString() {
    return "";
  }

  Widget toWidget(Color defaultColor, double cellSize, {int count = 1}) {
    return SizedBox(
      width: cellSize / count,
      height: cellSize / count,
      child: Center(
        child: Text(toString(), style: TextStyle(fontSize: cellSize * cellSizeToFontSize / count)),
      ),
    );
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
    final int mow = motif[0].length;
    final int pta = puzzle.width - mow;
    final RegExp motifRe = RegExp(
      motif
          .map(
            (line) =>
                line.map((c) => c.toString()).join("").replaceAll("0", "."),
          )
          .join("." * pta),
    );
    final puzzleStr = puzzle.cellValues.map((c) => c.toString()).join("");
    for (var idx = 0; idx < puzzleStr.length; idx++) {
      if ((puzzle.width - (idx % puzzle.width)) < mow) {
        continue;
      }
      if (motifRe.matchAsPrefix(puzzleStr, idx) != null) {
        return true;
      }
    }
    return false;
  }
}

class CellsCentricConstraint extends Constraint {
  List<int> indices = [];
}
