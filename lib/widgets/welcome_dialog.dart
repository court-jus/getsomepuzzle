import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Intro modal shown once at the very first puzzle of a fresh
/// onboarding (i.e. when `ConstraintProgress.firstSeen` is empty).
/// Sets the scene before the per-rule explanations start firing — the
/// new player otherwise lands on a NewConstraintDialog without any
/// context on what the game is about.
///
/// Two outcomes:
/// - OK → resolves to `false`; the caller chains the regular
///   NewConstraintDialog right after.
/// - Skip → resolves to `true`; the caller short-circuits the rule
///   modal and applies the same skip-onboarding side effects (mark
///   every slug seen, push the phase counter past every phase).
class WelcomeDialog extends StatelessWidget {
  const WelcomeDialog({super.key});

  /// Returns `true` iff the player chose to skip onboarding entirely
  /// from this welcome screen. `false` means OK / proceed.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      // Mandatory tap on a button — same rationale as NewConstraintDialog.
      barrierDismissible: false,
      builder: (_) => const WelcomeDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.celebration, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(l.welcomeModalTitle)),
        ],
      ),
      content: SingleChildScrollView(child: Text(l.welcomeModalBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.newConstraintModalSkip),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}
