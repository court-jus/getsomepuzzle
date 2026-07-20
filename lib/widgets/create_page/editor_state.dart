import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

class EditorState {
  final int width;
  final int height;
  final List<Constraint> constraints;
  final Map<int, CellValue> fixedCells;
  final List<CellValue> domain;
  EditorState(
    this.width,
    this.height,
    this.constraints,
    this.fixedCells,
    this.domain,
  );
}
