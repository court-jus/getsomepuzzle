import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

Future<String?> showPlaylistNameDialog(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.createPlaylist),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: loc.playlistName),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}
