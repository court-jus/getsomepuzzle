import 'dart:math';

import 'package:flutter/material.dart';

/// Shared `AlertDialog` body used by QuantityConstraint, ColumnCountConstraint,
/// GroupCountConstraint and GroupSize. A color dropdown (optional) + a count
/// slider, returning the chosen `(color, count)`.
Future<(int color, int count)?> showColorCountDialog(
  BuildContext context, {
  required String title,
  required int initialCount,
  required int minCount,
  required int maxCount,
  required String countLabel,
  String colorLabel = '',
  int initialColor = 1,
  bool showColor = true,
}) {
  int color = initialColor;
  int count = initialCount;
  return showDialog<(int, int)>(
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
                    DropdownButton<int>(
                      value: color,
                      items: [1, 2]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => color = v!),
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
