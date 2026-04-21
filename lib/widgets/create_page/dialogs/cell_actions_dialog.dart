import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

enum CellAction { addNew, deleteConstraint, removeFixed, fixBlack, fixWhite }

Future<CellAction?> showCellActionsDialog(
  BuildContext context, {
  required bool hasConstraints,
  required bool isFixed,
}) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<CellAction>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionTile(
              icon: Icons.add,
              label: loc.createAddNew,
              onTap: () => Navigator.pop(ctx, CellAction.addNew),
            ),
            if (hasConstraints)
              _ActionTile(
                icon: Icons.delete,
                label: loc.createDeleteConstraint,
                onTap: () => Navigator.pop(ctx, CellAction.deleteConstraint),
              ),
            if (isFixed)
              _ActionTile(
                icon: Icons.lock_open,
                label: loc.createRemoveFixed,
                onTap: () => Navigator.pop(ctx, CellAction.removeFixed),
              ),
            if (isFixed)
              _ActionTile(
                icon: Icons.circle,
                iconColor: Colors.black,
                label: loc.createFixBlack,
                onTap: () => Navigator.pop(ctx, CellAction.fixBlack),
              ),
            if (isFixed)
              _ActionTile(
                icon: Icons.circle,
                iconColor: Colors.white,
                label: loc.createFixWhite,
                onTap: () => Navigator.pop(ctx, CellAction.fixWhite),
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
}

Future<Constraint?> showDeleteConstraintPicker(
  BuildContext context, {
  required List<Constraint> constraints,
}) {
  return showDialog<Constraint>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in constraints)
              _ActionTile(
                icon: Icons.delete,
                iconColor: Colors.red,
                label: c.serialize(),
                onTap: () => Navigator.pop(ctx, c),
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
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: iconColor),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
    );
  }
}
