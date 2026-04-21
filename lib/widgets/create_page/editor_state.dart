import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';

class EditorState {
  final int width;
  final int height;
  final List<Constraint> constraints;
  final Map<int, int> fixedCells;
  EditorState(this.width, this.height, this.constraints, this.fixedCells);
}
