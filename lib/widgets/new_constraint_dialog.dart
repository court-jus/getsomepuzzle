import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Modal shown the first time the player encounters one or more
/// constraint slugs. Body text per slug is fetched from the localised
/// strings keyed by `constraintExplain<Slug>`; the modal lists every
/// new slug in one go so the player only has to dismiss once even if
/// the puzzle introduces several constraints at the same time.
///
/// Slugs are passed as a [Set] because a single puzzle line often
/// repeats the same slug across multiple constraint entries (e.g. two
/// `FM:` rules with different params) — without the dedup we'd render
/// the same explanation twice.
///
/// The caller is responsible for calling `progress.noteSeen(slug,
/// DateTime.now())` for each slug and persisting the result after
/// dismissal — keeping the side-effect outside the widget makes it
/// trivially testable and avoids a setState cycle here.
class NewConstraintDialog extends StatelessWidget {
  final Set<String> slugs;
  final bool showSkipButton;

  const NewConstraintDialog({
    super.key,
    required this.slugs,
    this.showSkipButton = false,
  });

  /// Show the dialog with all the unseen slugs from the puzzle. The
  /// rendering preserves [Set] iteration order (insertion order for
  /// the default `LinkedHashSet`).
  ///
  /// Returns `true` iff the player chose to skip onboarding entirely
  /// (only possible when [showSkipButton] is `true` — set by the
  /// in-game first-encounter flow, not by the read-only Apprentissage
  /// page where skipping makes no sense). `false`/null means OK.
  static Future<bool> show(
    BuildContext context,
    Set<String> slugs, {
    bool showSkipButton = false,
  }) async {
    if (slugs.isEmpty) return false;
    final result = await showDialog<bool>(
      context: context,
      // Mandatory tap on a button: the modal is the only place we
      // surface this explanation, so a stray tap outside (which
      // dismisses) would mean the player never reads it.
      barrierDismissible: false,
      builder: (_) =>
          NewConstraintDialog(slugs: slugs, showSkipButton: showSkipButton),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.new_releases, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(l.newConstraintModalTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, slug) in slugs.toList().indexed) ...[
              if (i > 0) const SizedBox(height: 16),
              Text(
                _capitalise(constraintNameForSlug(l, slug)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(constraintExplanationForSlug(l, slug)),
            ],
          ],
        ),
      ),
      actions: [
        if (showSkipButton)
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

/// Localised display name for a constraint slug.
String constraintNameForSlug(AppLocalizations l, String slug) {
  switch (slug) {
    case 'FM':
      return l.constraintForbiddenPattern;
    case 'PA':
      return l.constraintParity;
    case 'RC':
      return l.constraintRowCount;
    case 'GS':
      return l.constraintGroupSize;
    case 'LT':
      return l.constraintLetterGroup;
    case 'MJ':
      return l.constraintMajority;
    case 'QA':
      return l.constraintQuantity;
    case 'SY':
      return l.constraintSymmetry;
    case 'DF':
      return l.constraintDifferentFrom;
    case 'SH':
      return l.constraintShape;
    case 'CC':
      return l.constraintColumnCount;
    case 'GC':
      return l.constraintGroupCount;
    case 'CH':
      return l.constraintChain;
    case 'NC':
      return l.constraintNeighborCount;
    case 'EY':
      return l.constraintEyes;
    default:
      return slug;
  }
}

/// Localised body text for a constraint slug. Returns the slug itself
/// as a fallback so an unknown constraint doesn't break the UI.
String constraintExplanationForSlug(AppLocalizations l, String slug) {
  switch (slug) {
    case 'FM':
      return l.constraintExplainFM;
    case 'PA':
      return l.constraintExplainPA;
    case 'RC':
      return l.constraintExplainRC;
    case 'GS':
      return l.constraintExplainGS;
    case 'LT':
      return l.constraintExplainLT;
    case 'MJ':
      return l.constraintExplainMJ;
    case 'QA':
      return l.constraintExplainQA;
    case 'SY':
      return l.constraintExplainSY;
    case 'DF':
      return l.constraintExplainDF;
    case 'SH':
      return l.constraintExplainSH;
    case 'CC':
      return l.constraintExplainCC;
    case 'GC':
      return l.constraintExplainGC;
    case 'CH':
      return l.constraintExplainCH;
    case 'NC':
      return l.constraintExplainNC;
    case 'EY':
      return l.constraintExplainEY;
    default:
      return slug;
  }
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
