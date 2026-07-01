import 'package:flutter/material.dart';
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
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.celebration, color: Colors.amber),
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
