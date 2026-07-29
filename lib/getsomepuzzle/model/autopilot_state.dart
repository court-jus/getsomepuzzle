import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

/// A single parsed action from a scenario file.
sealed class AutopilotAction {
  const AutopilotAction();
}

/// Load a puzzle from a full v2 line.
class LoadStateAction extends AutopilotAction {
  final String v2Line;
  const LoadStateAction(this.v2Line);
}

/// Pause execution for [milliseconds].
class WaitAction extends AutopilotAction {
  final int milliseconds;
  const WaitAction(this.milliseconds);
}

/// Move the fake cursor to the centre of cell at grid (col, row).
class MouseAction extends AutopilotAction {
  final int col;
  final int row;
  const MouseAction(this.col, this.row);
}

/// Move the fake cursor to a named UI widget.
///
/// Target is either a special name (`hint`) or a constraint reference in
/// `SLUG:PARAMS` form (e.g. `FM:1.2`, `RC:0.1.3`).
class MouseToAction extends AutopilotAction {
  final String target;
  const MouseToAction(this.target);
}

/// Assign an exact colour to a cell.
class SetValueAction extends AutopilotAction {
  final int col;
  final int row;

  /// The colour to assign. Parsed from a name by [parseScenario].
  final CellValue value;
  const SetValueAction(this.col, this.row, this.value);
}

/// One click on the hint button — advances the hint stage.
class HintAction extends AutopilotAction {
  const HintAction();
}

/// Show or close an informational dialog.
///
/// When both [title] and [text] are non-null a new dialog is shown (matching
/// the onboarding-dialog style, no buttons). When both are null any open
/// dialog is dismissed.
class DialogAction extends AutopilotAction {
  final String? title;
  final String? text;
  const DialogAction({this.title, this.text});
}
