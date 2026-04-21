import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/create_page/shared/color_count_dialog.dart';

Future<GroupSize?> showGroupSizeDialog(
  BuildContext context, {
  required int cellIdx,
  required int width,
  required int height,
}) async {
  final loc = AppLocalizations.of(context)!;
  final maxSize = min(15, (width * height) ~/ 2);
  final result = await showColorCountDialog(
    context,
    title: loc.createChooseSize,
    initialCount: 2,
    minCount: 1,
    maxCount: maxSize,
    countLabel: '',
    showColor: false,
  );
  if (result == null) return null;
  return GroupSize('$cellIdx.${result.$2}');
}
