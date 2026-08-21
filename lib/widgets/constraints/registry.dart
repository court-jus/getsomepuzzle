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
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/onboarding.dart';
import 'package:getsomepuzzle/l10n/app_localizations.dart';
import 'package:getsomepuzzle/widgets/constraints/bounding_box.dart';
import 'package:getsomepuzzle/widgets/constraints/chain.dart';
import 'package:getsomepuzzle/widgets/constraints/column_count.dart';
import 'package:getsomepuzzle/widgets/constraints/column_majority.dart';
import 'package:getsomepuzzle/widgets/constraints/different_from.dart';
import 'package:getsomepuzzle/widgets/constraints/implication.dart';
import 'package:getsomepuzzle/widgets/constraints/eyes.dart';
import 'package:getsomepuzzle/widgets/constraints/group_count.dart';
import 'package:getsomepuzzle/widgets/constraints/group_size.dart';
import 'package:getsomepuzzle/widgets/constraints/majority.dart';
import 'package:getsomepuzzle/widgets/constraints/motif.dart';
import 'package:getsomepuzzle/widgets/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/widgets/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/constraints/row_count.dart';
import 'package:getsomepuzzle/widgets/constraints/symmetry.dart';
import 'package:getsomepuzzle/widgets/constraints/transition.dart';

final constraintUIRegistry =
    <({String slug, Widget Function(Color fgcolor, double size) buildPreview})>[
      (
        slug: 'FM',
        buildPreview: (fg, size) =>
            MotifWidget(constraint: ForbiddenMotif('12.21'), cellSize: size),
      ),
      (
        slug: 'PA',
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: Icon(
            Icons.arrow_circle_right_outlined,
            color: fg,
            size: size * 0.8,
          ),
        ),
      ),
      (
        slug: 'RC',
        buildPreview: (fg, size) => RowCountWidget(
          constraint: RowCountConstraint('0.1.3'),
          cellSize: size,
        ),
      ),
      (
        slug: 'RT',
        buildPreview: (fg, size) => TransitionWidget(
          constraint: RowTransitionConstraint('0.3'),
          cellSize: size,
          axis: Axis.horizontal,
        ),
      ),
      (
        slug: 'GS',
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: GroupSizeWidget(
            constraint: GroupSize('0.3'),
            actualGroupSize: 0,
            fgcolor: fg,
            cellSize: size,
          ),
        ),
      ),
      (
        slug: 'LT',
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: Text(
            'A',
            style: TextStyle(fontSize: size * 0.7, color: fg),
          ),
        ),
      ),
      (
        slug: 'QA',
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
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: SymmetryWidget(
            constraint: SymmetryConstraint('0.2'),
            fgcolor: fg,
            cellSize: size,
          ),
        ),
      ),
      (
        slug: 'DF',
        buildPreview: (fg, size) =>
            DifferentFromPreview(color: fg, cellSize: size),
      ),
      (
        slug: 'SH',
        buildPreview: (fg, size) =>
            MotifWidget(constraint: ShapeConstraint('11.10'), cellSize: size),
      ),
      (
        slug: 'CC',
        buildPreview: (fg, size) => ColumnCountWidget(
          constraint: ColumnCountConstraint('0.1.3'),
          cellSize: size,
        ),
      ),
      (
        slug: 'JC',
        buildPreview: (fg, size) => MajorityIndicatorWidget(
          constraint: ColumnMajorityConstraint('0.21'),
          cellSize: size,
        ),
      ),
      (
        slug: 'CH',
        buildPreview: (fg, size) => ChainWidget(
          constraint: ChainConstraint('1.top.bottom'),
          fgcolor: fg,
          cellSize: size,
        ),
      ),
      (
        slug: 'CT',
        buildPreview: (fg, size) => TransitionWidget(
          constraint: ColumnTransitionConstraint('0.3'),
          cellSize: size,
          axis: Axis.vertical,
        ),
      ),
      (
        slug: 'GC',
        buildPreview: (fg, size) => GroupCountWidget(
          constraint: GroupCountConstraint('1.2'),
          actualGroupCount: 0,
          cellSize: size,
        ),
      ),
      (
        slug: 'MJ',
        buildPreview: (fg, size) =>
            MajorityZonePreview(color: fg, cellSize: size),
      ),
      (
        slug: 'NC',
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: NeighborCountWidget(
            constraint: NeighborCountConstraint('0.1.2'),
            cellSize: size,
          ),
        ),
      ),
      (
        slug: 'EY',
        buildPreview: (fg, size) => _CellBorder(
          size: size,
          child: EyesWidget(
            constraint: EyesConstraint('2.1.5'),
            cellSize: size,
          ),
        ),
      ),
      (
        slug: 'IM',
        buildPreview: (fg, size) =>
            ImplicationWidget(fgcolor: fg, cellSize: size),
      ),
      (
        slug: 'JR',
        buildPreview: (fg, size) => MajorityIndicatorWidget(
          constraint: RowMajorityConstraint('0.21'),
          cellSize: size,
        ),
      ),
      (
        slug: 'BB',
        buildPreview: (fg, size) => BoundingBoxWidget(
          constraint: BoundingBoxConstraint('1.3.3'),
          cellSize: size,
        ),
      ),
    ];

/// Frames an in-cell constraint glyph with a cell border in the readonly
/// cell's border color, so the picker / onboarding / catalogue previews and
/// the exported website icons read as "a glyph inside a cell" — the way
/// these constraints appear on the board.
class _CellBorder extends StatelessWidget {
  const _CellBorder({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: pc.cellFgReadonly, width: 2.0),
      ),
      child: Center(child: child),
    );
  }
}

Widget previewForSlug(String slug, Color fgcolor, double size) {
  for (final r in constraintUIRegistry) {
    if (r.slug == slug) return r.buildPreview(fgcolor, size);
  }
  throw ArgumentError('Unknown slug: $slug');
}

/// Icon for a constraint slug, rendered with the registry's preview
/// builders at a fixed square footprint.
///
/// Resolves the foreground color from the ambient theme so the glyph
/// adapts to light/dark themes, and centers the preview inside a
/// [size]-sized box so every slug renders at the same footprint
/// regardless of the preview's intrinsic size.
class ConstraintIcon extends StatelessWidget {
  const ConstraintIcon({super.key, required this.slug, this.size = 40});

  /// Slug of the constraint to render; must exist in [constraintUIRegistry].
  final String slug;

  /// Side of the square box the icon is rendered into.
  final double size;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: previewForSlug(slug, fg, size)),
    );
  }
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
    case 'JR':
      return l.constraintLineMajority;
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

/// Localised body text for a constraint slug. Returns the slug itself
/// as a fallback so an unknown constraint doesn't break the UI.
///
/// Shared by the onboarding dialogs (`NewConstraintDialog`) and the
/// constraints catalogue on the help page, so both surfaces stay in sync.
String constraintExplanationForSlug(AppLocalizations l, String slug) {
  switch (slug) {
    case 'FM':
      return l.constraintExplainFM;
    case 'PA':
      return l.constraintExplainPA;
    case 'RC':
    case 'CC':
      return l.constraintExplainLineCount;
    case 'GS':
      return l.constraintExplainGS;
    case 'LT':
      return l.constraintExplainLT;
    case 'MJ':
      return l.constraintExplainMJ;
    case 'JC':
    case 'JR':
      return l.constraintExplainLineMajority;
    case 'QA':
      return l.constraintExplainQA;
    case 'SY':
      return l.constraintExplainSY;
    case 'DF':
      return l.constraintExplainDF;
    case 'SH':
      return l.constraintExplainSH;
    case 'GC':
      return l.constraintExplainGC;
    case 'CH':
      return l.constraintExplainCH;
    case 'NC':
      return l.constraintExplainNC;
    case 'EY':
      return l.constraintExplainEY;
    case 'IM':
      return l.constraintExplainIM;
    case 'BB':
      return l.constraintExplainBB;
    case 'RT':
    case 'CT':
      return l.constraintExplainTransition;
    default:
      return slug;
  }
}

/// Slugs shown by the help-page constraints catalogue, in teaching
/// order: the strict-onboarding phase introducers first (the order the
/// player learns them), then every remaining slug in registry order.
/// Adding a new constraint to the registries extends this list for free.
///
/// Row/column pairs that share one explanation (RC/CC, JC/JR, RT/CT)
/// are collapsed to their display slug (CC, JC, RT) — the same pairing
/// as the model registry's `mergedRuleGroups` — so each catalogue row
/// covers both orientations instead of duplicating identical text.
List<String> get constraintCatalogueSlugs {
  final ordered = <String>[];
  final seen = <String>{};
  for (final phase in OnboardingPhase.phases) {
    if (seen.add(phase.introducing)) ordered.add(phase.introducing);
  }
  for (final entry in constraintUIRegistry) {
    if (hiddenSlugs.contains(entry.slug)) continue;
    if (seen.add(entry.slug)) ordered.add(entry.slug);
  }
  return List.unmodifiable(ordered);
}
