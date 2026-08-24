import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/islands.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_dot_picker.dart';

/// Colour picker for the Islands (IS) constraint — no numeric fields.
/// Reuses the picker half of the shared `showColorCountDialog` body
/// (a [ColorDotPicker] over the puzzle's domain).
Future<IslandsConstraint?> showIslandsDialog(
  BuildContext context, {
  required List<CellValue> domain,
}) async {
  final loc = AppLocalizations.of(context)!;
  CellValue color = domain.first;
  return showDialog<IslandsConstraint>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.constraintIslands),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${loc.createChooseValue}:'),
              const SizedBox(height: 8),
              ColorDotPicker(
                domain: domain,
                selected: color,
                onChanged: (v) => setDialogState(() => color = v),
                dotSize: 28,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              IslandsConstraint(cellValueToString(color)),
            ),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
