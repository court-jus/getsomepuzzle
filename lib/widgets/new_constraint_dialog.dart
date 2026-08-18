import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.new_releases, color: pc.dialogAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(l.newConstraintModalTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstraintExplanationList(
          slugs: slugs.toList(),
          showLearnMore: true,
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

/// Localised body text for a constraint slug lives in
/// `widgets/constraints/registry.dart` (`constraintExplanationForSlug`),
/// shared with the help-page catalogue so the two surfaces stay in sync.
String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// One section per constraint slug: the localised name (with its icon)
/// as a header, then the localised explanation paragraph. Shared by the
/// onboarding modal (`NewConstraintDialog`) and the puzzle-help modal
/// (`ConstraintHelpDialog`) so both surfaces render identically.
class ConstraintExplanationList extends StatelessWidget {
  const ConstraintExplanationList({
    super.key,
    required this.slugs,
    this.showLearnMore = false,
  });

  /// Constraint slugs to explain, in display order. A [Set] passed by
  /// callers is converted to a list preserving iteration order.
  final List<String> slugs;

  /// When true, each section gets a "Learn more" button linking to the
  /// detailed online explanation page for that slug. On by the
  /// onboarding modal, off by the puzzle-help modal (which stays a
  /// pure in-app reminder).
  final bool showLearnMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, slug) in slugs.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstraintIcon(slug: slug, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _capitalise(constraintNameForSlug(l, slug)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(constraintExplanationForSlug(l, slug)),
          if (showLearnMore) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.learnMore),
                onPressed: () {
                  final languageCode = Localizations.localeOf(
                    context,
                  ).languageCode;
                  final locale = (languageCode == 'fr' || languageCode == 'es')
                      ? languageCode
                      : 'en';
                  final url = Uri.parse('$kDocBaseUrl/$locale/$slug.html');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ),
          ],
        ],
      ],
    );
  }
}
