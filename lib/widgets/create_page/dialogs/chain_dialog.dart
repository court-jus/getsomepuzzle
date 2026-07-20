import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';

Future<ChainConstraint?> showChainDialog(
  BuildContext context, {
  required List<CellValue> domain,
}) async {
  final loc = AppLocalizations.of(context)!;
  final options = <(CellValue color, String fromSide, String toSide)>[
    for (final color in domain) ...[
      (color, 'top', 'bottom'),
      (color, 'left', 'right'),
    ],
  ];
  return showDialog<ChainConstraint>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.constraintChain),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in options)
              SizedBox(
                width: double.maxFinite,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(
                    ctx,
                    ChainConstraint(
                      '${cellValueToString(opt.$1)}.${opt.$2}.${opt.$3}',
                    ),
                  ),
                  icon: SizedBox(
                    width: 40,
                    height: 40,
                    child: ChainWidget(
                      constraint: ChainConstraint(
                        '${cellValueToString(opt.$1)}.${opt.$2}.${opt.$3}',
                      ),
                      cellSize: 40,
                    ),
                  ),
                  label: Text('${opt.$2} → ${opt.$3}'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
      ],
    ),
  );
}
