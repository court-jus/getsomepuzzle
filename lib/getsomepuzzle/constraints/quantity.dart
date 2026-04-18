import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class QuantityConstraint extends Constraint {
  @override
  String get slug => 'QA';

  int value = 0;
  int count = 0;

  QuantityConstraint(String strParams) {
    final params = strParams.split(".");
    value = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String serialize() => 'QA:$value.$count';

  @override
  String toString() {
    return "$value = $count";
  }

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
    Set<int>? excludedIndices,
  ) {
    final maxCount = width * height - 1;
    final List<String> result = [];
    for (int count = 1; count < maxCount; count++) {
      for (final value in domain) {
        result.add('$value.$count');
      }
    }
    return result;
  }

  @override
  bool verify(Puzzle puzzle) {
    final myValues = puzzle.cellValues.where((val) => val == value);
    if (puzzle.complete) {
      return myValues.length == count;
    } else {
      return myValues.length <= count;
    }
  }

  @override
  Move? apply(Puzzle puzzle) {
    final myValues = puzzle.cellValues.where((val) => val == value);
    final myOpposite = puzzle.domain.whereNot((val) => val == value).first;
    final freeCells = puzzle.cellValues.indexed.where((val) => val.$2 == 0);
    if (freeCells.isEmpty) return null;
    final firstFreeCell = freeCells.first.$1;
    if (myValues.length > count) {
      return Move(0, 0, this, isImpossible: this);
    }
    if (myValues.length == count) {
      // I'm already complete, all the rest of the puzzle should be myOpposite
      return Move(firstFreeCell, myOpposite, this);
    } else if (count - myValues.length == freeCells.length) {
      // The number of free cells match what I need, I take all them
      return Move(firstFreeCell, value, this);
    }
    return null;
  }
}
