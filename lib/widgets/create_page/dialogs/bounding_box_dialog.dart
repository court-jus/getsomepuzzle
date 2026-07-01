import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

/// Color + width + height picker for the global Bounding Box (BB) constraint.
/// Mirrors the layout of [showColorCountDialog] but exposes two dimension
/// sliders (width, height) instead of a single count.
Future<BoundingBoxConstraint?> showBoundingBoxDialog(
  BuildContext context, {
  required int width,
  required int height,
}) {
  final loc = AppLocalizations.of(context)!;
  int color = 1;
  int w = min(3, width);
  int h = min(3, height);

  Widget dimRow(
    String label,
    int value,
    int maxv,
    ValueChanged<int> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text('$label: ')),
        Expanded(
          child: maxv <= 1
              ? Align(alignment: Alignment.centerLeft, child: Text('$value'))
              : Slider(
                  value: value.toDouble(),
                  min: 1,
                  max: maxv.toDouble(),
                  divisions: maxv - 1,
                  label: '$value',
                  onChanged: (v) => onChanged(v.round()),
                ),
        ),
        SizedBox(width: 40, child: Text('$value')),
      ],
    );
  }

  return showDialog<BoundingBoxConstraint>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(loc.constraintBoundingBox),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${loc.createChooseValue}: '),
                  DropdownButton<int>(
                    value: color,
                    items: [1, 2]
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() => color = v!),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              dimRow(
                loc.generateWidth,
                w,
                width,
                (v) => setDialogState(() => w = v),
              ),
              dimRow(
                loc.generateHeight,
                h,
                height,
                (v) => setDialogState(() => h = v),
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
            onPressed: () =>
                Navigator.pop(ctx, BoundingBoxConstraint('$color.$w.$h')),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
