import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/database.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/dialogs/playlist_name_dialog.dart';

/// Ask the player which playlist to save the current puzzle to. Returns the
/// chosen playlist's collection key (e.g. `user_in_progress`, `custom`), or
/// null if the dialog was cancelled. Defaults to a user playlist named
/// `loc.inProgressPlaylistName`, auto-creating it on first use.
Future<String?> showSaveProgressDialog({
  required BuildContext context,
  required Database database,
}) async {
  final loc = AppLocalizations.of(context)!;
  final defaultName = loc.inProgressPlaylistName;
  if (!database.userPlaylistNames.contains(defaultName)) {
    await database.createUserPlaylist(defaultName);
  }
  if (!context.mounted) return null;
  String selected = 'user_${Database.slugify(defaultName)}';

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: Text(loc.saveProgressTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: [
              for (final (key, label) in database.getWritablePlaylistOptions(
                loc.collectionMyPuzzles,
              ))
                DropdownMenuItem(value: key, child: Text(label)),
              DropdownMenuItem(
                value: '__new__',
                child: Text(
                  loc.newPlaylist,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            onChanged: (v) async {
              if (v == '__new__') {
                final name = await showPlaylistNameDialog(ctx);
                if (name == null) return;
                await database.createUserPlaylist(name);
                setLocalState(() {
                  selected = 'user_${Database.slugify(name)}';
                });
              } else if (v != null) {
                setLocalState(() => selected = v);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: Text(MaterialLocalizations.of(ctx).saveButtonLabel),
          ),
        ],
      ),
    ),
  );
}
