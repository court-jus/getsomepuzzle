import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/islands.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_size.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_row.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/transition_column.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

/// Registry of all player-facing constraint types.
/// Centralizes slug and factory for each constraint type.
final constraintRegistry =
    <
      ({
        String slug,
        Constraint Function(String) fromParams,
        List<String> Function(
          int width,
          int height,
          List<CellValue> domain,
          Set<int>? excludedIndices,
        )
        generateAllParameters,
      })
    >[
      (
        slug: 'FM',
        fromParams: ForbiddenMotif.new,
        generateAllParameters: ForbiddenMotif.generateAllParameters,
      ),
      (
        slug: 'PA',
        fromParams: ParityConstraint.new,
        generateAllParameters: ParityConstraint.generateAllParameters,
      ),
      (
        slug: 'RC',
        fromParams: RowCountConstraint.new,
        generateAllParameters: RowCountConstraint.generateAllParameters,
      ),
      (
        slug: 'RT',
        fromParams: RowTransitionConstraint.new,
        generateAllParameters: RowTransitionConstraint.generateAllParameters,
      ),
      (
        slug: 'GS',
        fromParams: GroupSize.new,
        generateAllParameters: GroupSize.generateAllParameters,
      ),
      (
        slug: 'LT',
        fromParams: LetterGroup.new,
        generateAllParameters: LetterGroup.generateAllParameters,
      ),
      (
        slug: 'QA',
        fromParams: QuantityConstraint.new,
        generateAllParameters: QuantityConstraint.generateAllParameters,
      ),
      (
        slug: 'SY',
        fromParams: SymmetryConstraint.new,
        generateAllParameters: SymmetryConstraint.generateAllParameters,
      ),
      (
        slug: 'DF',
        fromParams: DifferentFromConstraint.new,
        generateAllParameters: DifferentFromConstraint.generateAllParameters,
      ),
      (
        slug: 'SH',
        fromParams: ShapeConstraint.new,
        generateAllParameters: ShapeConstraint.generateAllParameters,
      ),
      (
        slug: 'CC',
        fromParams: ColumnCountConstraint.new,
        generateAllParameters: ColumnCountConstraint.generateAllParameters,
      ),
      (
        slug: 'JC',
        fromParams: ColumnMajorityConstraint.new,
        generateAllParameters: ColumnMajorityConstraint.generateAllParameters,
      ),
      (
        slug: 'CH',
        fromParams: ChainConstraint.new,
        generateAllParameters: ChainConstraint.generateAllParameters,
      ),
      (
        slug: 'CT',
        fromParams: ColumnTransitionConstraint.new,
        generateAllParameters: ColumnTransitionConstraint.generateAllParameters,
      ),
      (
        slug: 'GC',
        fromParams: GroupCountConstraint.new,
        generateAllParameters: GroupCountConstraint.generateAllParameters,
      ),
      (
        slug: 'MJ',
        fromParams: MajorityConstraint.new,
        generateAllParameters: MajorityConstraint.generateAllParameters,
      ),
      (
        slug: 'NC',
        fromParams: NeighborCountConstraint.new,
        generateAllParameters: NeighborCountConstraint.generateAllParameters,
      ),
      (
        slug: 'EY',
        fromParams: EyesConstraint.new,
        generateAllParameters: EyesConstraint.generateAllParameters,
      ),
      (
        slug: 'IM',
        fromParams: ImplicationConstraint.new,
        generateAllParameters: ImplicationConstraint.generateAllParameters,
      ),
      (
        slug: 'IS',
        fromParams: IslandsConstraint.new,
        generateAllParameters: IslandsConstraint.generateAllParameters,
      ),
      (
        slug: 'JR',
        fromParams: RowMajorityConstraint.new,
        generateAllParameters: RowMajorityConstraint.generateAllParameters,
      ),
      (
        slug: 'BB',
        fromParams: BoundingBoxConstraint.new,
        generateAllParameters: BoundingBoxConstraint.generateAllParameters,
      ),
    ];

/// All player-facing constraint slugs.
List<String> get constraintSlugs =>
    constraintRegistry.map((r) => r.slug).toList();

/// Create a constraint from its slug and params string. Returns null if slug unknown.
Constraint? createConstraint(String slug, String params) {
  for (final r in constraintRegistry) {
    if (r.slug == slug) return r.fromParams(params);
  }
  return null;
}

/// Row/column pairs that are functionally equivalent for user-facing
/// filtering and generation. The key is the "display" slug (always the
/// column variant); the value is the full set of slugs in the pair.
const mergedRuleGroups = {
  'CC': {'CC', 'RC'},
  'JC': {'JC', 'JR'},
  'RT': {'RT', 'CT'},
};

/// Slugs hidden from the UI because they are covered by a merged group.
/// The user only sees the column-variant slug (CC, JC, RT).
final hiddenSlugs = {'RC', 'JR', 'CT'};

/// Expand a set of user-facing slugs to the full set of real slugs
/// they cover (handling merged pairs transparently).
Set<String> expandMergedRules(Set<String> rules) {
  final expanded = <String>{};
  for (final r in rules) {
    expanded.addAll(mergedRuleGroups[r] ?? {r});
  }
  return expanded;
}

/// Collapse real slugs to their user-facing display slug (the reverse
/// of [expandMergedRules]): RC→CC, JR→JC, CT→RT. Used whenever the UI
/// renders one concept per row/column pair (help modal, catalogues).
Set<String> collapseMergedRules(Iterable<String> slugs) {
  final collapsed = <String>{};
  for (final slug in slugs) {
    var display = slug;
    for (final entry in mergedRuleGroups.entries) {
      if (entry.value.contains(slug)) {
        display = entry.key;
        break;
      }
    }
    collapsed.add(display);
  }
  return collapsed;
}

List<String>? generateAllParameters(
  String slug,
  int width,
  int height,
  List<CellValue> domain,
  Set<int>? excludedIndices,
) {
  for (final r in constraintRegistry) {
    if (r.slug == slug) {
      return r.generateAllParameters(width, height, domain, excludedIndices);
    }
  }
  return null;
}
