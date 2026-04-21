import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/symmetry.dart';

Future<SymmetryConstraint?> showSymmetryDialog(
  BuildContext context, {
  required int cellIdx,
}) async {
  final loc = AppLocalizations.of(context)!;
  final axis = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.createChooseAxis),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var a = 1; a <= 5; a++)
              SizedBox(
                width: double.maxFinite,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, a),
                  icon: SizedBox(
                    width: 32,
                    height: 32,
                    child: SymmetryWidget(
                      fgcolor: Colors.black,
                      constraint: SymmetryConstraint('0.$a'),
                      cellSize: 32,
                    ),
                  ),
                  label: Text('Axis $a'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
      ],
    ),
  );
  return axis == null ? null : SymmetryConstraint('$cellIdx.$axis');
}
