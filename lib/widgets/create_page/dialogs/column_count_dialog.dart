import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<ColumnCountConstraint?> showColumnCountDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final cidx = cellIdx % width;
  final result = await showColorCountDialog(
    context,
    title: loc.constraintColumnCount,
    initialCount: height,
    minCount: 1,
    maxCount: height,
    colorLabel: loc.createChooseValue,
    countLabel: loc.createChooseCount,
  );
  if (result == null) return null;
  return ColumnCountConstraint('$cidx.${result.$1}.${result.$2}');
}
