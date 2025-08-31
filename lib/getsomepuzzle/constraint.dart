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

class CellsCentricConstraint extends Constraint {
  List<int> indices = [];
}
