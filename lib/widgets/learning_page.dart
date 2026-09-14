import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constraint_progress.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/new_constraint_dialog.dart';
import 'package:getsomepuzzle/widgets/constraints/registry.dart';
import 'package:intl/intl.dart';

/// Reference page surfaced as the menu entry "Apprentissage" next to
/// Help. For each known constraint it shows:
///   - icon + localised name,
///   - first-seen date or "not yet encountered",
///   - count of finished, non-skipped puzzles containing the
///     constraint across every collection in the player's stats,
///   - a button that re-opens the explanation modal so the player can
///     review the rule any time without affecting their progress.
///
/// Rows are per *concept*, not per slug: the row/column pairs
/// (CC↔RC, JC↔JR, RT↔CT) share one explanation line, so they are
/// collapsed to their display slug and their progress is merged across
/// the family — otherwise the same rule would be listed twice.
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

    // One row per concept: collapsing the row/column pairs leaves the
    // display slug (CC, JC, RT) as the row's identity, and the family's
    // progress is merged into it.
    final rows =
        [
            for (final slug in collapseMergedRules(
              OnboardingPhase.allKnownSlugs,
            ))
              (
                slug: slug,
                firstSeen: _firstSeenOf(slug),
                playCount: _playCountOf(slug),
              ),
          ]
          // Sort by: seen-first (so the player sees their progress at the
          // top), then chronological, then alphabetical inside each bucket —
          // matches the dropdown order convention in the rest of the app.
          ..sort((a, b) {
            final seenA = a.firstSeen;
            final seenB = b.firstSeen;
            if ((seenA == null) != (seenB == null)) {
              return seenA == null ? 1 : -1;
            }
            if (seenA != null && seenB != null) {
              final cmp = seenA.compareTo(seenB);
              if (cmp != 0) return cmp;
            }
            return a.slug.compareTo(b.slug);
          });

    return Scaffold(
      appBar: AppBar(title: Text(l.learningPageTitle)),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final slug = rows[index].slug;
            final firstSeen = rows[index].firstSeen;
            final playCount = rows[index].playCount;
            final name = constraintNameForSlug(l, slug);
            final status = firstSeen == null
                ? l.learningNeverSeen
                : l.learningSeenOn(dateFormat.format(firstSeen));
            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    opacity: firstSeen == null ? 0.35 : 1.0,
                    child: ConstraintIcon(slug: slug, size: 36),
                  ),
                  if (firstSeen == null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                ],
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
                // Disabled until the player has actually encountered the
                // constraint in play (same `firstSeen` gate as the lock
                // icon), so the explanation modal can't spoil a rule early.
                onPressed: firstSeen == null
                    ? null
                    : () => NewConstraintDialog.show(context, <String>{slug}),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Earliest encounter date across the merged family of [displaySlug].
  /// The members of a row/column pair are the same rule to the player,
  /// so the row reports the first time either orientation was met.
  DateTime? _firstSeenOf(String displaySlug) {
    DateTime? earliest;
    for (final slug in expandMergedRules({displaySlug})) {
      final seen = progress.firstSeen[slug];
      if (seen != null && (earliest == null || seen.isBefore(earliest))) {
        earliest = seen;
      }
    }
    return earliest;
  }

  /// Finished, non-skipped plays across the merged family of
  /// [displaySlug], so a row counts both orientations of the rule.
  int _playCountOf(String displaySlug) => expandMergedRules({
    displaySlug,
  }).fold(0, (sum, slug) => sum + database.playCountForSlug(slug));
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
