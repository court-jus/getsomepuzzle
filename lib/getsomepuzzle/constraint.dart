import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class Constraint {
  bool isValid = true;
  bool isHighlighted = false;

  @override
  String toString() {
    return "";
  }

  String toHuman() {
    return toString();
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

  bool check(Puzzle puzzle, {bool saveResult = true}) {
    final verified = verify(puzzle);
    if (saveResult) {
      isValid = verified;
    }
    return verified;
  }

  Move? apply(Puzzle puzzle) {
    final clone = Puzzle(puzzle.lineRepresentation);
    clone.constraints = puzzle.constraints;
    for (var cell in puzzle.cellValues.indexed) {
      if (cell.$2 == 0) continue;
      clone.setValue(cell.$1, cell.$2);
    }
    for (var cell in clone.cellValues.indexed) {
      if (cell.$2 != 0) continue;
      for (var value in puzzle.domain) {
        clone.setValue(cell.$1, value);
        if (!verify(clone)) {
          // We cannot do that
          final myOpposite = clone.domain.whereNot((v) => v == value).first;
          return Move(cell.$1, myOpposite, this);
        }
        clone.resetCell(cell.$1);
      }
    }
    return null;
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
    // print("puStr $puzzleStr");
    // print("morif $motifRe");
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
