import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

class EndOfPlaylist extends StatelessWidget {
  final int currentLevel;
  final bool filtersBlocking;
  final int? nextLevel;
  final ValueChanged<int> onJumpToLevel;

  const EndOfPlaylist({
    super.key,
    required this.currentLevel,
    required this.filtersBlocking,
    required this.nextLevel,
    required this.onJumpToLevel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
