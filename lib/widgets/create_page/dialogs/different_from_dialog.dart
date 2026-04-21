import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';

Future<DifferentFromConstraint?> showDifferentFromDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final cidx = cellIdx % width;
  final ridx = cellIdx ~/ width;
  final validDirs = <String>[];
  if (cidx < width - 1) validDirs.add('right');
  if (ridx < height - 1) validDirs.add('down');

  if (validDirs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No valid direction for this cell')),
    );
    return null;
  }

  if (validDirs.length == 1) {
    return DifferentFromConstraint('$cellIdx.${validDirs.first}');
  }

  final dir = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in validDirs)
              SizedBox(
                width: double.maxFinite,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Text(
                    d == 'right' ? '→' : '↓',
                    style: const TextStyle(fontSize: 24),
                  ),
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

  return dir == null ? null : DifferentFromConstraint('$cellIdx.$dir');
}
