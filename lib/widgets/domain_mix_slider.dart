import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Colour-mix control shared by the Open-page advanced filters and the
/// "Ready for 3 colors?" suggestion dialog.
///
/// A five-step slider from "Only 2 colors" (left, value `0`) to
/// "Only 3 colors" (right, value `1`). Intermediate stops keep both
/// domains admissible; `Database.getPuzzlesByLevel` weights the playlist
/// so ≈ the slider value of the served puzzles is 3-colour.
class DomainMixSlider extends StatelessWidget {
  /// Current mix in `[0, 1]` — the share of 3-colour puzzles.
  final double value;

  /// Called with the new mix while the player drags.
  final ValueChanged<double> onChanged;

  const DomainMixSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Slider(
          value: value.clamp(0.0, 1.0),
          // Five steps (0, ⅕ … 1): the same grid the onboarding
          // suggestion starts from.
          divisions: 5,
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.labelDomainTwoColors),
              Text(l.labelDomainThreeColors),
            ],
          ),
        ),
      ],
    );
  }
}
