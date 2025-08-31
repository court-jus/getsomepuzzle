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
}
