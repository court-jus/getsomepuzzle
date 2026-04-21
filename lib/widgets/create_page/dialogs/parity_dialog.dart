import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

Future<ParityConstraint?> showParityDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final ridx = cellIdx ~/ width;
  final cidx = cellIdx % width;
  final leftSize = cidx;
  final rightSize = width - 1 - cidx;
  final topSize = ridx;
  final bottomSize = height - 1 - ridx;

  final validSides = <String>[];
  if (leftSize % 2 == 0 && leftSize > 0) validSides.add('left');
  if (rightSize % 2 == 0 && rightSize > 0) validSides.add('right');
  if (leftSize % 2 == 0 &&
      rightSize % 2 == 0 &&
      rightSize > 0 &&
      leftSize > 0) {
    validSides.add('horizontal');
  }
  if (topSize % 2 == 0 && topSize > 0) validSides.add('top');
  if (bottomSize % 2 == 0 && bottomSize > 0) validSides.add('bottom');
  if (topSize % 2 == 0 &&
      bottomSize % 2 == 0 &&
      bottomSize > 0 &&
      topSize > 0) {
    validSides.add('vertical');
  }

  if (validSides.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No valid parity side for this cell')),
    );
    return null;
  }

  final side = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.createChooseSide),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in validSides)
              SizedBox(
                width: double.maxFinite,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(s),
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

  return side == null ? null : ParityConstraint('$cellIdx.$side');
}
