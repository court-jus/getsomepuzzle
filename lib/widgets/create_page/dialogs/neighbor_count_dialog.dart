import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<NeighborCountConstraint?> showNeighborCountDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final row = cellIdx ~/ width;
  final col = cellIdx % width;
  final maxCount =
      (col > 0 ? 1 : 0) +
      (col < width - 1 ? 1 : 0) +
      (row > 0 ? 1 : 0) +
      (row < height - 1 ? 1 : 0);
  final result = await showColorCountDialog(
    context,
    title: loc.constraintNeighborCount,
    initialCount: maxCount > 1 ? maxCount - 1 : maxCount,
    minCount: 0,
    maxCount: maxCount,
    colorLabel: loc.createChooseValue,
    countLabel: loc.createChooseCount,
  );
  if (result == null) return null;
  return NeighborCountConstraint('$cellIdx.${result.$1}.${result.$2}');
}
