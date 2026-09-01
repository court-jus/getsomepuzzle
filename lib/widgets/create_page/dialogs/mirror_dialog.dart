import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/mirror.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_dot_picker.dart';

/// Picker for the Mirror (MI) constraint: a colour and a direction.
///
/// All domain colours are selectable (no once-per-colour limit), and the
/// direction chips are gated on the grid dimensions — `H` (horizontal mirror,
/// balances top/bottom halves) requires an even height, `V` (vertical mirror,
/// balances left/right halves) an even width.
Future<MirrorConstraint?> showMirrorDialog(
  BuildContext context, {
  required int width,
  required int height,
  required List<CellValue> domain,
}) async {
  final loc = AppLocalizations.of(context)!;
  CellValue color = domain.first;
  String direction = height.isEven ? 'H' : 'V';
  return showDialog<MirrorConstraint>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.constraintMirror),
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(loc.mirrorHorizontal),
                    selected: direction == 'H',
                    onSelected: height.isEven
                        ? (sel) => setDialogState(() => direction = 'H')
                        : null,
                  ),
                  ChoiceChip(
                    label: Text(loc.mirrorVertical),
                    selected: direction == 'V',
                    onSelected: width.isEven
                        ? (sel) => setDialogState(() => direction = 'V')
                        : null,
                  ),
                ],
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
              MirrorConstraint('${cellValueToString(color)}.$direction'),
            ),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
