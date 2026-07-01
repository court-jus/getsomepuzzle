import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';

Future<RowTransitionConstraint?> showRowTransitionDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final ridx = cellIdx ~/ width;
  final maxT = max(0, width - 1);
  final count = await _showCountPicker(
    context,
    title: 'Row transitions',
    initialCount: width ~/ 2,
    maxCount: maxT,
  );
  if (count == null) return null;
  return RowTransitionConstraint('$ridx.$count');
}

Future<ColumnTransitionConstraint?> showColumnTransitionDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final cidx = cellIdx % width;
  final maxT = max(0, height - 1);
  final count = await _showCountPicker(
    context,
    title: 'Column transitions',
    initialCount: height ~/ 2,
    maxCount: maxT,
  );
  if (count == null) return null;
  return ColumnTransitionConstraint('$cidx.$count');
}

Future<int?> _showCountPicker(
  BuildContext context, {
  required String title,
  required int initialCount,
  required int maxCount,
}) {
  int count = initialCount.clamp(0, maxCount);
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Row(
            children: [
              const Text('Transitions: '),
              Expanded(
                child: Slider(
                  value: count.toDouble(),
                  min: 0,
                  max: maxCount.toDouble(),
                  divisions: maxCount,
                  label: '$count',
                  onChanged: (v) => setDialogState(() => count = v.round()),
                ),
              ),
              SizedBox(width: 40, child: Text('$count')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, count),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
}
