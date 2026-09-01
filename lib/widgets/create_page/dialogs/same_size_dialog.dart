import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/same_size.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Chooses the suit symbol for a multi-cell Same Size constraint. Cell
/// selection remains owned by the editor, just like the Letter Group flow.
Future<String?> showSameSizeDialog(
  BuildContext context, {
  required Set<String> usedSymbols,
}) {
  final loc = AppLocalizations.of(context)!;
  final nextSymbol = kSameSizeSymbols.keys.firstWhere(
    (symbol) => !usedSymbols.contains(symbol),
    orElse: () => kSameSizeSymbols.keys.first,
  );
  String symbol = nextSymbol;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.createChooseSymbol),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DropdownButton<String>(
            value: symbol,
            items: kSameSizeSymbols.entries
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setDialogState(() => symbol = value);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, symbol),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
