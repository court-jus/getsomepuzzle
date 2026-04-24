import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class EndOfPlaylist extends StatelessWidget {
  final int currentLevel;
  final bool filtersBlocking;
  final int? nextLevel;
  final ValueChanged<int> onJumpToLevel;

  /// When true, the widget shows a tutorial-specific congratulatory message
  /// and drops everything that would mention the player level / catalog
  /// ceiling — these concepts don't apply to the tutorial collection.
  final bool isTutorial;

  /// Primary call-to-action shown only in tutorial mode: sets up the player
  /// for the main catalog (level 0, auto-level on) and switches to the
  /// default collection. Ignored when [isTutorial] is false.
  final VoidCallback? onStartPlaying;

  const EndOfPlaylist({
    super.key,
    required this.currentLevel,
    required this.filtersBlocking,
    required this.nextLevel,
    required this.onJumpToLevel,
    this.isTutorial = false,
    this.onStartPlaying,
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
    final message = filtersBlocking
        ? l.endOfPlaylistFiltersBlocking
        : l.endOfPlaylistCongrats;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(l.endOfPlaylistCurrentLevel(currentLevel)),
        const SizedBox(height: 16),
        if (nextLevel != null)
          FilledButton.icon(
            onPressed: () => onJumpToLevel(nextLevel!),
            icon: const Icon(Icons.trending_up),
            label: Text(
              l.endOfPlaylistJumpTo(nextLevel!, nextLevel! - currentLevel),
            ),
          )
        else
          Text(
            l.endOfPlaylistMaxLevel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }
}
