import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<RowCountConstraint?> showRowCountDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final ridx = cellIdx ~/ width;
  final result = await showColorCountDialog(
    context,
    title: loc.constraintRowCount,
    initialCount: width,
    minCount: 1,
    maxCount: width,
    colorLabel: loc.createChooseValue,
    countLabel: loc.createChooseCount,
  );
  if (result == null) return null;
  return RowCountConstraint('$ridx.${result.$1}.${result.$2}');
}
