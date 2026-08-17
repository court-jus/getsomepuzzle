import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';

/// Modal reminder of the constraints used by the current puzzle,
/// opened from the top-bar help button (next to the hint button).
///
/// Players coming back to the game after a while don't remember every
/// rule; this modal lists the distinct constraint types of the puzzle
/// currently on screen, reusing the exact per-constraint sections of
/// the onboarding modal ([ConstraintExplanationList]) so the two
/// surfaces stay in sync.
///
/// The caller is responsible for passing the already-deduped, merged
/// slug set (row/column pairs RC/CC, JR/JC, RT/CT collapsed to their
/// display slug, e.g. via `collapseMergedRules`) — the widget itself
/// is a dumb renderer.
class ConstraintHelpDialog extends StatelessWidget {
  final Set<String> slugs;

  const ConstraintHelpDialog({super.key, required this.slugs});

  /// Show the modal. No-op when [slugs] is empty.
  static Future<void> show(BuildContext context, Set<String> slugs) async {
    if (slugs.isEmpty) return;
    await showDialog<void>(
      context: context,
      // Optional reference material: a stray tap outside dismisses it
      // harmlessly (unlike NewConstraintDialog, whose explanation is
      // mandatory-read during onboarding).
      builder: (_) => ConstraintHelpDialog(slugs: slugs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.help_outline, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(l.puzzleHelpTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.puzzleHelpIntro(slugs.length)),
            const SizedBox(height: 16),
            ConstraintExplanationList(slugs: slugs.toList()),
          ],
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
