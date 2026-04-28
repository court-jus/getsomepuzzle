import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/to_flutter.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/column_count.dart';
import 'package:getsomepuzzle/widgets/eyes.dart';
import 'package:getsomepuzzle/widgets/group_count.dart';
import 'package:getsomepuzzle/widgets/motif.dart';
import 'package:getsomepuzzle/widgets/neighbor_count.dart';
import 'package:getsomepuzzle/widgets/quantity.dart';

enum ConstraintType {
  forbiddenPattern,
  parity,
  groupSize,
  letterGroup,
  quantity,
  columnCount,
  groupCount,
  neighborCount,
  shape,
  symmetry,
  differentFrom,
  eyes,
  fixBlack,
  fixWhite,
}

// Preview widgets inside the picker render at the same size as a small grid
// cell so players see the actual constraint glyph they will encounter on the
// board, rather than a generic Material icon that doesn't visually match.
const _previewSize = 44.0;

Widget _previewFor(ConstraintType type, Color fgcolor) {
  switch (type) {
    case ConstraintType.forbiddenPattern:
      return MotifWidget(
        constraint: ForbiddenMotif('12.21'),
        cellSize: _previewSize,
      );
    case ConstraintType.parity:
      return constraintToFlutter(
        ParityConstraint('0.right'),
        fgcolor,
        _previewSize,
      );
    case ConstraintType.groupSize:
      return constraintToFlutter(GroupSize('0.3'), fgcolor, _previewSize);
    case ConstraintType.letterGroup:
      return constraintToFlutter(LetterGroup('A.0'), fgcolor, _previewSize);
    case ConstraintType.quantity:
      return QuantityWidget(
        constraint: QuantityConstraint('1.3'),
        actualCount: 0,
        oppositeActual: 0,
        oppositeTotal: 0,
        cellSize: _previewSize,
      );
    case ConstraintType.columnCount:
      return ColumnCountWidget(
        constraint: ColumnCountConstraint('0.1.3'),
        cellSize: _previewSize,
      );
    case ConstraintType.groupCount:
      return GroupCountWidget(
        constraint: GroupCountConstraint('1.2'),
        actualGroupCount: 0,
        cellSize: _previewSize,
      );
    case ConstraintType.neighborCount:
      return NeighborCountWidget(
        constraint: NeighborCountConstraint('0.1.2'),
        cellSize: _previewSize,
      );
    case ConstraintType.eyes:
      return EyesWidget(
        constraint: EyesConstraint('2.1.5'),
        cellSize: _previewSize,
      );
    case ConstraintType.shape:
      // A small L-tromino: visually distinct from the 2x2 checker used for
      // ForbiddenMotif so the two pattern-based types don't look identical.
      return MotifWidget(
        constraint: ShapeConstraint('11.10'),
        cellSize: _previewSize,
      );
    case ConstraintType.symmetry:
      return constraintToFlutter(
        SymmetryConstraint('0.2'),
        fgcolor,
        _previewSize,
      );
    case ConstraintType.differentFrom:
      return Text('≠', style: TextStyle(fontSize: 32, color: fgcolor));
    case ConstraintType.fixBlack:
    case ConstraintType.fixWhite:
      throw StateError('fixBlack/fixWhite are rendered as dedicated buttons');
  }
}

class _TypeEntry {
  final ConstraintType type;
  final String Function(AppLocalizations loc) label;
  const _TypeEntry(this.type, this.label);
}

const _entries = <_TypeEntry>[
  _TypeEntry(ConstraintType.forbiddenPattern, _labelForbiddenPattern),
  _TypeEntry(ConstraintType.parity, _labelParity),
  _TypeEntry(ConstraintType.groupSize, _labelGroupSize),
  _TypeEntry(ConstraintType.letterGroup, _labelLetterGroup),
  _TypeEntry(ConstraintType.quantity, _labelQuantity),
  _TypeEntry(ConstraintType.columnCount, _labelColumnCount),
  _TypeEntry(ConstraintType.groupCount, _labelGroupCount),
  _TypeEntry(ConstraintType.neighborCount, _labelNeighborCount),
  _TypeEntry(ConstraintType.shape, _labelShape),
  _TypeEntry(ConstraintType.symmetry, _labelSymmetry),
  _TypeEntry(ConstraintType.differentFrom, _labelDifferentFrom),
  _TypeEntry(ConstraintType.eyes, _labelEyes),
];

String _labelForbiddenPattern(AppLocalizations l) =>
    l.constraintForbiddenPattern;
String _labelParity(AppLocalizations l) => l.constraintParity;
String _labelGroupSize(AppLocalizations l) => l.constraintGroupSize;
String _labelLetterGroup(AppLocalizations l) => l.constraintLetterGroup;
String _labelQuantity(AppLocalizations l) => l.constraintQuantity;
String _labelColumnCount(AppLocalizations l) => l.constraintColumnCount;
String _labelGroupCount(AppLocalizations l) => l.constraintGroupCount;
String _labelNeighborCount(AppLocalizations l) => l.constraintNeighborCount;
String _labelShape(AppLocalizations l) => l.constraintShape;
String _labelSymmetry(AppLocalizations l) => l.constraintSymmetry;
String _labelDifferentFrom(AppLocalizations l) => l.constraintDifferentFrom;
String _labelEyes(AppLocalizations l) => l.constraintEyes;

Future<ConstraintType?> showConstraintTypePicker(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<ConstraintType>(
    context: context,
    builder: (ctx) {
      final fgcolor =
          IconTheme.of(ctx).color ?? Theme.of(ctx).colorScheme.onSurface;
      return AlertDialog(
        title: Text(loc.createChooseType),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `Wrap` avoids the viewport-intrinsic-dimensions crash that
              // `GridView` triggers inside an `AlertDialog`. It's wrapped in a
              // Flexible+SingleChildScrollView so the tiles scroll on short
              // viewports while the fixBlack/fixWhite row stays pinned below.
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in _entries)
                        SizedBox(
                          width: 148,
                          height: 104,
                          child: _TypeTile(
                            preview: _previewFor(e.type, fgcolor),
                            label: e.label(loc),
                            onTap: () => Navigator.pop(ctx, e.type),
                          ),
                        ),
                    ],
                  ),
                ),
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
      );
    },
  );
}

class _TypeTile extends StatelessWidget {
  final Widget preview;
  final String label;
  final VoidCallback onTap;
  const _TypeTile({
    required this.preview,
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
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: _previewSize + 4,
              child: Center(child: preview),
            ),
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
