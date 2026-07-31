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

/// Show or close a subtitle overlay on top of the puzzle.
///
/// When both [title] and [text] are non-null a subtitle overlay is shown
/// (light-green text with thin black outline, transparent background,
/// centered on screen like movie subtitles). When both are null the
/// overlay is removed.
class DialogAction extends AutopilotAction {
  final String? title;
  final String? text;
  const DialogAction({this.title, this.text});
}

/// Change the colors used by subsequent [DialogAction] subtitle overlays.
///
/// Each field holds a raw colour token — either:
/// - A [PuzzleColors] semantic name (e.g. `dialogAccent`, `highlight`)
/// - A hex code (`#RRGGBB` or `#AARRGGBB`)
/// - `default` to reset that slot to its original value
///
/// All three fields are always provided by the action; the execution engine
/// resolves each token to a [Color] at runtime.
class TextColorAction extends AutopilotAction {
  final String textColor;
  final String fillColor;
  final String borderColor;

  const TextColorAction({
    required this.textColor,
    required this.fillColor,
    required this.borderColor,
  });
}

/// Set a full-screen background colour for subsequent [DialogAction] overlays.
///
/// Holds a single raw colour token — either:
/// - A [PuzzleColors] semantic name (e.g. `dialogAccent`, `highlight`)
/// - A hex code (`#RRGGBB` or `#AARRGGBB`)
/// - `default` to reset the background to transparent
///
/// The rectangle is drawn behind the dialog text so the text stays legible
/// on top of it. The execution engine resolves the token to a [Color] at
/// runtime.
class BackgroundAction extends AutopilotAction {
  final String color;

  const BackgroundAction({required this.color});
}
