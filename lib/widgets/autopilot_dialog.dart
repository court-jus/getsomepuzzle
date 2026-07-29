import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// An informational dialog displayed by the autopilot's `dialog` action.
///
/// Matches the onboarding-dialog visual style (same icon + title row,
/// [SingleChildScrollView] body, [AlertDialog] base) but has **no buttons**
/// and [barrierDismissible] is `false`. The only way to dismiss it is a
/// subsequent `dialog` action with no arguments from the scenario.
class AutopilotDialog extends StatelessWidget {
  const AutopilotDialog({super.key, this.title, required this.text});

  /// Optional title shown in the dialog header. When null or empty the
  /// title row still appears with the icon (no title text).
  final String? title;

  /// Body text. `\n` escapes are already converted to real newlines by the
  /// scenario parser.
  final String text;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (title != null && title!.isNotEmpty) ? title! : '',
              style: title != null && title!.isNotEmpty
                  ? null
                  : const TextStyle(fontSize: 0),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(child: Text(text)),
    );
  }
}
