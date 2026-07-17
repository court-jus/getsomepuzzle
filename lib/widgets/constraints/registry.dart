import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/bounding_box.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/column_count.dart';
import 'package:getsomepuzzle/widgets/constraints/column_majority.dart';
import 'package:getsomepuzzle/widgets/constraints/implication.dart';
import 'package:getsomepuzzle/widgets/constraints/eyes.dart';
import 'package:getsomepuzzle/widgets/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/constraints/group_size.dart';
import 'package:getsomepuzzle/widgets/constraints/motif.dart';
import 'package:getsomepuzzle/widgets/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/widgets/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/symmetry.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';

final constraintUIRegistry =
    <
      ({
        String slug,
        String label,
        Widget Function(Color fgcolor, double size) buildPreview,
      })
    >[
      (
        slug: 'FM',
        label: 'Forbidden motif',
        buildPreview: (fg, size) =>
            MotifWidget(constraint: ForbiddenMotif('12.21'), cellSize: size),
      ),
      (
        slug: 'PA',
        label: 'Parity',
        buildPreview: (fg, size) => Icon(
          Icons.arrow_circle_right_outlined,
          color: fg,
          size: size * 0.8,
        ),
      ),
      (
        slug: 'RC',
        label: 'Row count',
        buildPreview: (fg, size) => RowCountWidget(
          constraint: RowCountConstraint('0.1.3'),
          cellSize: size,
        ),
      ),
      (
        slug: 'RT',
        label: 'Row transition',
        buildPreview: (fg, size) => TransitionWidget(
          constraint: RowTransitionConstraint('0.3'),
          cellSize: size,
          axis: Axis.horizontal,
        ),
      ),
      (
        slug: 'GS',
        label: 'Group size',
        buildPreview: (fg, size) => GroupSizeWidget(
          constraint: GroupSize('0.3'),
          actualGroupSize: 0,
          fgcolor: fg,
          cellSize: size,
        ),
      ),
      (
        slug: 'LT',
        label: 'Letter',
        buildPreview: (fg, size) => Text(
          'A',
          style: TextStyle(fontSize: size * 0.7, color: fg),
        ),
      ),
      (
        slug: 'QA',
        label: 'Quantity',
        buildPreview: (fg, size) => QuantityWidget(
          constraint: QuantityConstraint('1.3'),
          actualCount: 0,
          oppositeActual: 0,
          oppositeTotal: 0,
          cellSize: size,
        ),
      ),
      (
        slug: 'SY',
        label: 'Symmetry',
        buildPreview: (fg, size) => SymmetryWidget(
          constraint: SymmetryConstraint('0.2'),
          fgcolor: fg,
          cellSize: size,
        ),
      ),
      (
        slug: 'DF',
        label: 'Different from',
        buildPreview: (fg, size) => Text(
          '≠',
          style: TextStyle(fontSize: size * 0.7, color: fg),
        ),
      ),
      (
        slug: 'SH',
        label: 'Shape',
        buildPreview: (fg, size) =>
            MotifWidget(constraint: ShapeConstraint('11.10'), cellSize: size),
      ),
      (
        slug: 'CC',
        label: 'Column count',
        buildPreview: (fg, size) => ColumnCountWidget(
          constraint: ColumnCountConstraint('0.1.3'),
          cellSize: size,
        ),
      ),
      (
        slug: 'JC',
        label: 'Column majority',
        buildPreview: (fg, size) => MajorityIndicatorWidget(
          constraint: ColumnMajorityConstraint('0.21'),
          cellSize: size,
        ),
      ),
      (
        slug: 'CH',
        label: 'Chain',
        buildPreview: (fg, size) => ChainWidget(
          constraint: ChainConstraint('1.top.bottom'),
          fgcolor: fg,
          cellSize: size,
        ),
      ),
      (
        slug: 'CT',
        label: 'Column transition',
        buildPreview: (fg, size) => TransitionWidget(
          constraint: ColumnTransitionConstraint('0.3'),
          cellSize: size,
          axis: Axis.vertical,
        ),
      ),
      (
        slug: 'GC',
        label: 'Group count',
        buildPreview: (fg, size) => GroupCountWidget(
          constraint: GroupCountConstraint('1.2'),
          actualGroupCount: 0,
          cellSize: size,
        ),
      ),
      (
        slug: 'MJ',
        label: 'Majority',
        buildPreview: (fg, size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: fg, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      (
        slug: 'NC',
        label: 'Neighbor count',
        buildPreview: (fg, size) => NeighborCountWidget(
          constraint: NeighborCountConstraint('0.1.2'),
          cellSize: size,
        ),
      ),
      (
        slug: 'EY',
        label: 'Eyes',
        buildPreview: (fg, size) =>
            EyesWidget(constraint: EyesConstraint('2.1.5'), cellSize: size),
      ),
      (
        slug: 'IM',
        label: 'Implication',
        buildPreview: (fg, size) =>
            ImplicationWidget(fgcolor: fg, cellSize: size),
      ),
      (
        slug: 'JR',
        label: 'Row majority',
        buildPreview: (fg, size) => MajorityIndicatorWidget(
          constraint: RowMajorityConstraint('0.21'),
          cellSize: size,
        ),
      ),
      (
        slug: 'BB',
        label: 'Bounding box',
        buildPreview: (fg, size) => BoundingBoxWidget(
          constraint: BoundingBoxConstraint('1.3.3'),
          cellSize: size,
        ),
      ),
    ];

Widget previewForSlug(String slug, Color fgcolor, double size) {
  for (final r in constraintUIRegistry) {
    if (r.slug == slug) return r.buildPreview(fgcolor, size);
  }
  throw ArgumentError('Unknown slug: $slug');
}

String constraintNameForSlug(AppLocalizations l, String slug) {
  switch (slug) {
    case 'FM':
      return l.constraintForbiddenPattern;
    case 'PA':
      return l.constraintParity;
    case 'RC':
    case 'CC':
      return l.constraintLineCount;
    case 'GS':
      return l.constraintGroupSize;
    case 'LT':
      return l.constraintLetterGroup;
    case 'MJ':
      return l.constraintMajority;
    case 'JC':
      return l.constraintColumnMajority;
    case 'JR':
      return l.constraintRowMajority;
    case 'QA':
      return l.constraintQuantity;
    case 'SY':
      return l.constraintSymmetry;
    case 'DF':
      return l.constraintDifferentFrom;
    case 'SH':
      return l.constraintShape;
    case 'GC':
      return l.constraintGroupCount;
    case 'CH':
      return l.constraintChain;
    case 'NC':
      return l.constraintNeighborCount;
    case 'EY':
      return l.constraintEyes;
    case 'IM':
      return l.constraintImplication;
    case 'BB':
      return l.constraintBoundingBox;
    case 'RT':
    case 'CT':
      return l.constraintTransition;
    case '*':
      return l.complicityOtherConstraint;
    default:
      assert(false, 'Unmapped constraint slug "$slug"');
      return slug;
  }
}
