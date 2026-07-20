import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<QuantityConstraint?> showQuantityDialog(
  BuildContext context, {
  required int width,
  required int height,
  required List<CellValue> domain,
}) async {
  final loc = AppLocalizations.of(context)!;
  final result = await showColorCountDialog(
    context,
    title: loc.constraintQuantity,
    initialCount: (width * height) ~/ 2,
    minCount: 1,
    maxCount: width * height - 1,
    colorLabel: loc.createChooseValue,
    countLabel: loc.createChooseCount,
    domain: domain,
  );
  if (result == null) return null;
  return QuantityConstraint('${cellValueToString(result.$1)}.${result.$2}');
}
