import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Returns the chosen letter. Multi-select mode is then owned by the caller.
Future<String?> showLetterGroupDialog(
  BuildContext context, {
  required Set<String> usedLetters,
}) {
  final loc = AppLocalizations.of(context)!;
  String nextLetter = 'A';
  while (usedLetters.contains(nextLetter)) {
    nextLetter = String.fromCharCode(nextLetter.codeUnitAt(0) + 1);
  }

  String letter = nextLetter;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.createChooseLetter),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButton<String>(
            value: letter,
            items: List.generate(
              26,
              (i) => String.fromCharCode('A'.codeUnitAt(0) + i),
            ).map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => setDialogState(() => letter = v!),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, letter),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
