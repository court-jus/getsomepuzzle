import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';
import 'package:intl/intl.dart';

/// Reference page surfaced as the menu entry "Apprentissage" next to
/// Help. For each known constraint slug it shows:
///   - icon + localised name,
///   - first-seen date or "not yet encountered",
///   - count of finished, non-skipped puzzles containing the
///     constraint across every collection in the player's stats,
///   - a button that re-opens the explanation modal so the player can
///     review the rule any time without affecting their progress.
///
/// The page is rebuilt every time it is opened — counts and dates are
/// pulled from the live `Database` and `ConstraintProgress`. Because
/// the modal does not call `noteSeen` from this page, an
/// already-discovered slug stays "seen" after a refresh.
class LearningPage extends StatelessWidget {
  final Database database;
  final ConstraintProgress progress;

  const LearningPage({
    super.key,
    required this.database,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final dateFormat = DateFormat.yMMMMd(
      Localizations.localeOf(context).languageCode,
    );

    final slugs = OnboardingPhase.allKnownSlugs.toList()
      // Sort by: seen-first (so the player sees their progress at the
      // top), then alphabetical inside each bucket — matches the
      // dropdown order convention in the rest of the app.
      ..sort((a, b) {
        final seenA = progress.firstSeen[a];
        final seenB = progress.firstSeen[b];
        if ((seenA == null) != (seenB == null)) {
          return seenA == null ? 1 : -1;
        }
        if (seenA != null && seenB != null) {
          final cmp = seenA.compareTo(seenB);
          if (cmp != 0) return cmp;
        }
        return a.compareTo(b);
      });

    return Scaffold(
      appBar: AppBar(title: Text(l.learningPageTitle)),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: slugs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final slug = slugs[index];
            final firstSeen = progress.firstSeen[slug];
            final playCount = database.playCountForSlug(slug);
            final name = constraintNameForSlug(l, slug);
            final status = firstSeen == null
                ? l.learningNeverSeen
                : l.learningSeenOn(dateFormat.format(firstSeen));
            return ListTile(
              leading: Icon(
                firstSeen == null ? Icons.lock_outline : Icons.check_circle,
                color: firstSeen == null
                    ? Theme.of(context).disabledColor
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(_capitalise(name)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(status), Text(l.learningPlayCount(playCount))],
              ),
              isThreeLine: true,
              trailing: TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(l.learningRefreshButton),
                onPressed: () =>
                    NewConstraintDialog.show(context, <String>{slug}),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
