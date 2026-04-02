import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

const _allowBigMotifs = false;

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
  String serialize() {
    return 'FM:${motif.map((row) => row.map((v) => v.toString()).join("")).join(".")}';
  }

  @override
  bool verify(Puzzle puzzle) {
    return !isPresent(puzzle);
  }

  /// Generate all possible ForbiddenMotif parameter strings for a given grid.
  static List<String> generateAllParameters(int width, int height, List<int> domain) {
    final all11 = ['0', ...domain.map((v) => v.toString())];
    final all12 = [for (var i in all11) for (var j in all11) '$i$j'];
    final all21 = [for (var i in all11) for (var j in all11) [i, j]];
    final all22 = [for (var i in all12) for (var j in all12) [i, j]];

    // Build list of motifs as List<String> (each string is a row)
    final List<List<String>> allMotifs = [];
    // 1x1
    for (var m in all11) { allMotifs.add([m]); }
    // 1x2
    for (var m in all12) { allMotifs.add([m]); }
    // 2x1
    for (var m in all21) { allMotifs.add(m); }
    // 2x2
    for (var m in all22) { allMotifs.add(m); }

    if (width > 2) {
      // 1x3
      final all13 = [for (var i in all11) for (var j in all12) '$i$j'];
      for (var m in all13) { allMotifs.add([m]); }
      if (_allowBigMotifs) {
        final all23 = [for (var i in all13) for (var j in all13) [i, j]];
        allMotifs.addAll(all23);
      }
    }
    if (height > 2) {
      // 3x1
      final all31 = [for (var i in all11) for (var j in all11) for (var k in all11) [i, j, k]];
      allMotifs.addAll(all31);
      if (_allowBigMotifs && width > 2) {
        final all13 = [for (var i in all11) for (var j in all12) '$i$j'];
        final all33 = [for (var i in all13) for (var j in all13) for (var k in all13) [i, j, k]];
        allMotifs.addAll(all33);
      }
    }

    final List<String> result = [];
    for (final motif in allMotifs) {
      // Filter out motifs with empty edges
      if (motif.first.split('').every((c) => c == '0')) continue;
      if (motif.last.split('').every((c) => c == '0')) continue;
      if (motif.every((r) => r[0] == '0')) continue;
      if (motif.every((r) => r[r.length - 1] == '0')) continue;
      result.add(motif.join('.'));
    }
    return result;
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
