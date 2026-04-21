import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<GroupCountConstraint?> showGroupCountDialog(
  BuildContext context, {
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final maxCount = (width * height / 2).ceil();
  final result = await showColorCountDialog(
    context,
    title: loc.constraintGroupCount,
    initialCount: maxCount,
    minCount: 1,
    maxCount: maxCount,
    colorLabel: loc.createChooseValue,
    countLabel: loc.createChooseCount,
  );
  if (result == null) return null;
  return GroupCountConstraint('${result.$1}.${result.$2}');
}
