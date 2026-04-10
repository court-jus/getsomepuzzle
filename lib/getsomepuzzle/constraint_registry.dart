import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

/// Registry of all player-facing constraint types.
/// Centralizes slug, label, and factory for each constraint type.
final constraintRegistry =
    <({String slug, String label, Constraint Function(String) fromParams})>[
      (slug: 'FM', label: 'Forbidden motif', fromParams: ForbiddenMotif.new),
      (slug: 'PA', label: 'Parity', fromParams: ParityConstraint.new),
      (slug: 'GS', label: 'Group size', fromParams: GroupSize.new),
      (slug: 'LT', label: 'Letter', fromParams: LetterGroup.new),
      (slug: 'QA', label: 'Quantity', fromParams: QuantityConstraint.new),
      (slug: 'SY', label: 'Symmetry', fromParams: SymmetryConstraint.new),
      (
        slug: 'DF',
        label: 'Different from',
        fromParams: DifferentFromConstraint.new,
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
