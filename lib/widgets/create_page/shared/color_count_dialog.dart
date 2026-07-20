import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_dot_picker.dart';

/// Shared `AlertDialog` body used by QuantityConstraint, ColumnCountConstraint,
/// GroupCountConstraint and GroupSize. A `ColorDotPicker` (optional) + a count
/// slider, returning the chosen `(color, count)`.
Future<(CellValue color, int count)?> showColorCountDialog(
  BuildContext context, {
  required String title,
  required int initialCount,
  required int minCount,
  required int maxCount,
  required String countLabel,
  String colorLabel = '',
  CellValue initialColor = CellValue.black,
  bool showColor = true,
  required List<CellValue> domain,
}) {
  CellValue color = initialColor;
  int count = initialCount;
  return showDialog<(CellValue, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showColor)
                Row(
                  children: [
                    Text('$colorLabel: '),
                    const SizedBox(width: 8),
                    ColorDotPicker(
                      domain: domain,
                      selected: color,
                      onChanged: (v) => setDialogState(() => color = v),
                      dotSize: 28,
                    ),
                  ],
                ),
              if (showColor) const SizedBox(height: 8),
              Row(
                children: [
                  if (countLabel.isNotEmpty) Text('$countLabel: '),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: minCount.toDouble(),
                      max: maxCount.toDouble(),
                      divisions: max(1, maxCount - minCount),
                      label: '$count',
                      onChanged: (v) => setDialogState(() => count = v.round()),
                    ),
                  ),
                  SizedBox(width: 40, child: Text('$count')),
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
            onPressed: () => Navigator.pop(ctx, (color, count)),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
