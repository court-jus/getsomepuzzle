import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class EndOfPlaylist extends StatelessWidget {
  final int currentLevel;
  final bool filtersBlocking;

  /// When true, the widget shows a tutorial-specific congratulatory message
  /// and drops everything that would mention the player level / catalog
  /// ceiling — these concepts don't apply to the tutorial collection.
  final bool isTutorial;

  /// Primary call-to-action shown only in tutorial mode: sets up the player
  /// for the main catalog (level 0, auto-level on) and switches to the
  /// default collection. Ignored when [isTutorial] is false.
  final VoidCallback? onStartPlaying;

  /// True when the current collection still has unplayed candidates that
  /// were not in the just-finished batch. Drives whether we offer
  /// "Continue" as an option.
  final bool hasMoreInCurrent;

  /// Localised label of the current collection (e.g. "Joueur"). Used by
  /// the "Continue with X" button. Pass null on non-playable collections.
  final String? currentCollectionLabel;

  /// Localised label of the suggested collection (e.g. "Avancé"). Pass
  /// null when no suggestion is available.
  final String? recommendedCollectionLabel;

  /// Action: load another batch from the current collection.
  final VoidCallback? onContinueCurrent;

  /// Action: switch to the recommended collection and load its first
  /// batch.
  final VoidCallback? onSwitchToRecommended;

  /// Action: send the player to the open page so they can pick another
  /// collection manually.
  final VoidCallback? onPickAnother;

  /// Number of puzzles the player has played (regardless of skip/like
  /// state) in the currently loaded collection. Surfaced as a tally in
  /// the headline message — better fits the new batch-based UX than
  /// the legacy "you exhausted everything" message, which is no
  /// longer accurate at every batch boundary.
  final int playedCount;

  const EndOfPlaylist({
    super.key,
    required this.currentLevel,
    required this.filtersBlocking,
    this.isTutorial = false,
    this.onStartPlaying,
    this.hasMoreInCurrent = false,
    this.currentCollectionLabel,
    this.recommendedCollectionLabel,
    this.onContinueCurrent,
    this.onSwitchToRecommended,
    this.onPickAnother,
    this.playedCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (isTutorial) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.endOfPlaylistTutorialFinished,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          if (onStartPlaying != null)
            FilledButton.icon(
              onPressed: onStartPlaying,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.endOfPlaylistTutorialStartPlaying),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              l.endOfPlaylistTutorialAutoLevelNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l.endOfPlaylistTutorialHaveFun,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      );
    }
    final hasRecommendation =
        recommendedCollectionLabel != null && onSwitchToRecommended != null;
    // "Continue" is meaningless when filters block the current
    // collection: re-preparing the playlist would just hit the same
    // empty result. The recommendation still applies — different
    // collections have different distributions and the user's filters
    // may be permissive enough there, so it's a real escape hatch.
    final canContinue =
        !filtersBlocking &&
        hasMoreInCurrent &&
        onContinueCurrent != null &&
        currentCollectionLabel != null;

    final headlineMessage = filtersBlocking
        ? l.endOfPlaylistFiltersBlocking
        : l.endOfPlaylistCongrats(playedCount);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headlineMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(l.endOfPlaylistCurrentLevel(currentLevel)),
        const SizedBox(height: 16),
        if (hasRecommendation) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              l.endOfPlaylistSuggestedHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            if (canContinue)
              FilledButton.tonal(
                onPressed: onContinueCurrent,
                child: Text(l.endOfPlaylistContinueIn(currentCollectionLabel!)),
              ),
            if (hasRecommendation)
              FilledButton(
                onPressed: onSwitchToRecommended,
                child: Text(
                  l.endOfPlaylistTrySuggested(recommendedCollectionLabel!),
                ),
              ),
          ],
        ),
        if (onPickAnother != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onPickAnother,
            child: Text(l.endOfPlaylistPickAnother),
          ),
        ],
      ],
    );
  }
}
