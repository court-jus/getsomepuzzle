import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

/// Registry of all player-facing constraint types.
/// Centralizes slug, label, and factory for each constraint type.
final constraintRegistry =
    <
      ({
        String slug,
        String label,
        Constraint Function(String) fromParams,
        List<String> Function(
          int width,
          int height,
          List<int> domain,
          Set<int>? excludedIndices,
        )
        generateAllParameters,
      })
    >[
      (
        slug: 'FM',
        label: 'Forbidden motif',
        fromParams: ForbiddenMotif.new,
        generateAllParameters: ForbiddenMotif.generateAllParameters,
      ),
      (
        slug: 'PA',
        label: 'Parity',
        fromParams: ParityConstraint.new,
        generateAllParameters: ParityConstraint.generateAllParameters,
      ),
      (
        slug: 'GS',
        label: 'Group size',
        fromParams: GroupSize.new,
        generateAllParameters: GroupSize.generateAllParameters,
      ),
      (
        slug: 'LT',
        label: 'Letter',
        fromParams: LetterGroup.new,
        generateAllParameters: LetterGroup.generateAllParameters,
      ),
      (
        slug: 'QA',
        label: 'Quantity',
        fromParams: QuantityConstraint.new,
        generateAllParameters: QuantityConstraint.generateAllParameters,
      ),
      (
        slug: 'SY',
        label: 'Symmetry',
        fromParams: SymmetryConstraint.new,
        generateAllParameters: SymmetryConstraint.generateAllParameters,
      ),
      (
        slug: 'DF',
        label: 'Different from',
        fromParams: DifferentFromConstraint.new,
        generateAllParameters: DifferentFromConstraint.generateAllParameters,
      ),
      (
        slug: 'SH',
        label: 'Shape',
        fromParams: ShapeConstraint.new,
        generateAllParameters: ShapeConstraint.generateAllParameters,
      ),
      (
        slug: 'CC',
        label: 'Column count',
        fromParams: ColumnCountConstraint.new,
        generateAllParameters: ColumnCountConstraint.generateAllParameters,
      ),
      (
        slug: 'GC',
        label: 'Group count',
        fromParams: GroupCountConstraint.new,
        generateAllParameters: GroupCountConstraint.generateAllParameters,
      ),
    ];

/// All player-facing constraint slugs.
List<String> get constraintSlugs =>
    constraintRegistry.map((r) => r.slug).toList();

/// Lookup: slug → label.
Map<String, String> get constraintLabels => {
  for (final r in constraintRegistry) r.slug: r.label,
};

/// Create a constraint from its slug and params string. Returns null if slug unknown.
Constraint? createConstraint(String slug, String params) {
  for (final r in constraintRegistry) {
    if (r.slug == slug) return r.fromParams(params);
  }
  return null;
}

List<String>? generateAllParameters(
  String slug,
  int width,
  int height,
  List<int> domain,
  Set<int>? excludedIndices,
) {
  for (final r in constraintRegistry) {
    if (r.slug == slug) {
      return r.generateAllParameters(width, height, domain, excludedIndices);
    }
  }
  return null;
}
