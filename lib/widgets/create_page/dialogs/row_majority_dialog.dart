import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Dialog for creating a [RowMajorityConstraint]. Lets the user pick
/// a row index and a colour ordering (permutation of the domain).
Future<RowMajorityConstraint?> showRowMajorityDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
  required List<CellValue> domain,
}) async {
  final loc = AppLocalizations.of(context)!;
  final ridx = cellIdx ~/ width;
  List<CellValue> order = domain.toList();
  return showDialog<RowMajorityConstraint>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.constraintRowMajority),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Row: ${ridx + 1}'),
              const SizedBox(height: 12),
              const Text('Colour order (most → least):'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < order.length; i++)
                    _colorChip(
                      ctx,
                      order[i],
                      onUp: i > 0
                          ? () => setDialogState(() {
                              final tmp = order[i - 1];
                              order[i - 1] = order[i];
                              order[i] = tmp;
                            })
                          : null,
                      onDown: i < order.length - 1
                          ? () => setDialogState(() {
                              final tmp = order[i + 1];
                              order[i + 1] = order[i];
                              order[i] = tmp;
                            })
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
            onPressed: () {
              final params = '$ridx.${order.map(cellValueToString).join()}';
              Navigator.pop(ctx, RowMajorityConstraint(params));
            },
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}

Widget _colorChip(
  BuildContext ctx,
  CellValue color, {
  VoidCallback? onUp,
  VoidCallback? onDown,
}) {
  final pc = Theme.of(ctx).extension<PuzzleColors>()!;
  final bg = pc.constraintColors[color] ?? Colors.grey;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onUp != null)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_upward, size: 16),
            onPressed: onUp,
          )
        else
          const SizedBox(width: 16),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        ),
        if (onDown != null)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_downward, size: 16),
            onPressed: onDown,
          )
        else
          const SizedBox(width: 16),
      ],
    ),
  );
}
