import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Modal that suggests the player try the 3-colour mode. Fires at most
/// once, gated by [Database.shouldSuggestThirdColor]: after onboarding
/// graduation plus 50 plays, and only if the player has never played
/// a 3-colour puzzle.
///
/// Two outcomes:
/// - "Try it" → resolves to `true`; the caller is expected to enable
///   3-colour puzzles in the player's domain filters and reload the
///   playlist so the next puzzle is drawn from the wider pool.
/// - "Maybe later" → resolves to `false`; the caller just dismisses
///   the suggestion. In both cases the modal is marked as shown so it
///   never reappears.
class ThirdColorSuggestionDialog extends StatelessWidget {
  const ThirdColorSuggestionDialog({super.key});

  /// Returns `true` iff the player chose to opt in to 3-colour
  /// puzzles. `false` means "maybe later" / dismissed.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      // Mandatory tap on a button — same rationale as
      // NewConstraintDialog: a stray tap outside would silently
      // dismiss a once-in-a-lifetime suggestion the player should
      // consciously act on.
      barrierDismissible: false,
      builder: (_) => const ThirdColorSuggestionDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.palette, color: Colors.purple),
          const SizedBox(width: 8),
          Expanded(child: Text(l.thirdColorSuggestionTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.thirdColorSuggestionBody),
            const SizedBox(height: 16),
            Text(
              l.thirdColorSuggestionFiltersReminder,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.thirdColorSuggestionLaterLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.thirdColorSuggestionTryLabel),
        ),
      ],
    );
  }
}
