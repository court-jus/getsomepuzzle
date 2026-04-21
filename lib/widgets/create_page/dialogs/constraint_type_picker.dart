import 'package:flutter/material.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';

enum ConstraintType {
  forbiddenPattern,
  parity,
  groupSize,
  letterGroup,
  quantity,
  columnCount,
  groupCount,
  shape,
  symmetry,
  differentFrom,
  fixBlack,
  fixWhite,
}

class _TypeEntry {
  final ConstraintType type;
  final IconData? icon;
  final Widget? leading;
  final String Function(AppLocalizations loc) label;
  const _TypeEntry(this.type, this.label, {this.icon, this.leading});
}

final _entries = <_TypeEntry>[
  _TypeEntry(
    ConstraintType.forbiddenPattern,
    (l) => l.constraintForbiddenPattern,
    icon: Icons.block,
  ),
  _TypeEntry(
    ConstraintType.parity,
    (l) => l.constraintParity,
    icon: Icons.swap_horiz,
  ),
  _TypeEntry(
    ConstraintType.groupSize,
    (l) => l.constraintGroupSize,
    icon: Icons.group_work,
  ),
  _TypeEntry(
    ConstraintType.letterGroup,
    (l) => l.constraintLetterGroup,
    icon: Icons.text_fields,
  ),
  _TypeEntry(
    ConstraintType.quantity,
    (l) => l.constraintQuantity,
    icon: Icons.tag,
  ),
  _TypeEntry(
    ConstraintType.columnCount,
    (l) => l.constraintColumnCount,
    icon: Icons.circle_outlined,
  ),
  _TypeEntry(
    ConstraintType.groupCount,
    (l) => l.constraintGroupCount,
    icon: Icons.link,
  ),
  _TypeEntry(
    ConstraintType.shape,
    (l) => l.constraintShape,
    icon: Icons.rotate_90_degrees_ccw,
  ),
  _TypeEntry(
    ConstraintType.symmetry,
    (l) => l.constraintSymmetry,
    icon: Icons.flip,
  ),
  _TypeEntry(
    ConstraintType.differentFrom,
    (l) => l.constraintDifferentFrom,
    leading: const Text('≠', style: TextStyle(fontSize: 28)),
  ),
];

Future<ConstraintType?> showConstraintTypePicker(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<ConstraintType>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.createChooseType),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `Wrap` avoids the viewport-intrinsic-dimensions crash that
            // `GridView` triggers inside an `AlertDialog`.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _entries)
                  SizedBox(
                    width: 148,
                    height: 90,
                    child: _TypeTile(
                      leading: e.leading ?? Icon(e.icon, size: 32),
                      label: e.label(loc),
                      onTap: () => Navigator.pop(ctx, e.type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, ConstraintType.fixBlack),
                    icon: const Icon(Icons.circle, color: Colors.black),
                    label: Text(loc.createFixBlack),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(ctx, ConstraintType.fixWhite),
                    icon: const Icon(Icons.circle, color: Colors.white),
                    label: Text(loc.createFixWhite),
                  ),
                ),
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
      ],
    ),
  );
}

class _TypeTile extends StatelessWidget {
  final Widget leading;
  final String label;
  final VoidCallback onTap;
  const _TypeTile({
    required this.leading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 32, child: Center(child: leading)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
