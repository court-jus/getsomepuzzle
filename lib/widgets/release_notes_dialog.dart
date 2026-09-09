import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Release-notes intro dialog for returning players (intro dialog #1,
/// shipped with 2.0.0). Shown once to players upgrading from an older
/// version — new installs never see it (they are marked up-to-date
/// after the #0 welcome).
///
/// The intro-dialog family is numbered so future releases can append
/// their own dialog (2, 3, …) and only need to remember the number of
/// the last dialog the player has seen (`introDialogSeen` pref, see
/// `main.dart` `_maybeShowNextIntroDialog`).
class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    // Mandatory tap on the button — same rationale as WelcomeDialog.
    barrierDismissible: false,
    builder: (_) => const ReleaseNotesDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.new_releases, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(l.releaseNotesTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(
          l.releaseNotesBody,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
