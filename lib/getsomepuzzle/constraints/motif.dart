import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

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

  @override
  Move? apply(Puzzle puzzle) {
    for (var row = 0; row < motif.length; row++) {
      for (var col = 0; col < motif[0].length; col++) {
        final car = motif[row][col];
        if (car == 0) continue;
        // Create submotif with this cell as wildcard
        final submotif = motif.map((r) => List<int>.from(r)).toList();
        submotif[row][col] = 0;
        // Search for submotif in puzzle
        final positions = Motif.findMotifPositions(submotif, puzzle);
        for (var pos in positions) {
          final posRow = pos ~/ puzzle.width;
          final posCol = pos % puzzle.width;
          final targetIdx = (posRow + row) * puzzle.width + (posCol + col);
          if (puzzle.cellValues[targetIdx] == 0) {
            final opposite = puzzle.domain.whereNot((v) => v == car).first;
            return Move(targetIdx, opposite, this);
          }
          if (puzzle.cellValues[targetIdx] == car) {
            return Move(0, 0, this, isImpossible: this);
          }
        }
      }
    }
    return null;
  }
}
