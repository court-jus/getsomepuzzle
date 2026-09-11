import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/domain_mix_slider.dart';

/// Modal that suggests the player try the 3-colour mode. Fires at most
/// once, gated by [Database.shouldSuggestThirdColor]: after onboarding
/// graduation plus 50 plays, and only if the player has never played
/// a 3-colour puzzle.
///
/// The player picks the colour mix with the same [DomainMixSlider] the
/// Open-page advanced filters use; the dialog seeds it at
/// [kThirdColorSuggestionShare] (≈ one 3-colour puzzle in five).
///
/// Two outcomes:
/// - "Try it" → resolves to the chosen share; the caller writes it to
///   `Filters.threeColorShare` and reloads the playlist so the next
///   puzzle is drawn from the wider pool.
/// - "Maybe later" → resolves to `null`; the caller leaves the filters
///   untouched. In both cases the modal is marked as shown so it never
///   reappears.
class ThirdColorSuggestionDialog extends StatefulWidget {
  const ThirdColorSuggestionDialog({super.key});

  /// Returns the chosen 3-colour share, or `null` when the player chose
  /// "maybe later" / dismissed.
  static Future<double?> show(BuildContext context) async {
    return showDialog<double>(
      context: context,
      // Mandatory tap on a button — same rationale as
      // NewConstraintDialog: a stray tap outside would silently
      // dismiss a once-in-a-lifetime suggestion the player should
      // consciously act on.
      barrierDismissible: false,
      builder: (_) => const ThirdColorSuggestionDialog(),
    );
  }

  @override
  State<ThirdColorSuggestionDialog> createState() =>
      _ThirdColorSuggestionDialogState();
}

class _ThirdColorSuggestionDialogState
    extends State<ThirdColorSuggestionDialog> {
  double _share = kThirdColorSuggestionShare;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.palette, color: Color(0xFF2AA198)),
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
            Text(l.thirdColorSuggestionMixLabel),
            DomainMixSlider(
              value: _share,
              onChanged: (value) => setState(() => _share = value),
            ),
            const SizedBox(height: 8),
            Text(
              l.thirdColorSuggestionFiltersReminder,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.thirdColorSuggestionLaterLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_share),
          child: Text(l.thirdColorSuggestionTryLabel),
        ),
      ],
    );
  }
}
