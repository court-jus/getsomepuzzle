import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class HelpText extends Constraint {
  String text = "";

  HelpText(String strParams) {
    text = strParams.replaceAll("∅", " ");
  }

  @override
  String serialize() => 'TX:${text.replaceAll(" ", "∅")}';

  @override
  String toString() {
    return text;
  }

  @override
  bool verify(Puzzle puzzle) {
    return true;
  }
}
