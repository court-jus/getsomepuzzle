import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String detail,
}) async {
  final loc = AppLocalizations.of(context)!;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.createConfirmDelete),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Text(detail),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            MaterialLocalizations.of(ctx).deleteButtonTooltip,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
