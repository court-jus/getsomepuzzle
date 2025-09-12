import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class QuantityConstraint extends Constraint {
  int value = 0;
  int count = 0;

  QuantityConstraint(String strParams) {
    final params = strParams.split(".");
    value = int.parse(params[0]);
    count = int.parse(params[1]);
  }

  @override
  String toString() {
    return "$value = $count";
  }

  @override
  bool verify(Puzzle puzzle) {
    final myValues = puzzle.cellValues.where((val) => val == value);
    return myValues.length == count;
  }
}
