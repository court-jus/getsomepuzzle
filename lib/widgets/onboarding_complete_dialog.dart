import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class OnboardingCompleteDialog extends StatelessWidget {
  const OnboardingCompleteDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const OnboardingCompleteDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.celebration, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(l.onboardingCompleteTitle)),
        ],
      ),
      content: Text(l.onboardingCompleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
