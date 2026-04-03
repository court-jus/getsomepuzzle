import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/other_solution.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class GeneratorConfig {
  final int width;
  final int height;
  final Set<String> requiredRules;
  final Set<String> bannedRules;
  final Duration maxTime;
  final int count;

  const GeneratorConfig({
    required this.width,
    required this.height,
    this.requiredRules = const {},
    this.bannedRules = const {},
    this.maxTime = const Duration(seconds: 60),
    this.count = 1,
  });
}

class GeneratorProgress {
  final int puzzlesGenerated;
  final int totalRequested;
  final int constraintsTried;
  final int constraintsTotal;
  final double currentRatio;

  const GeneratorProgress({
    required this.puzzlesGenerated,
    required this.totalRequested,
    required this.constraintsTried,
    required this.constraintsTotal,
    required this.currentRatio,
  });
}

class PuzzleGenerator {
  static final _rng = Random();
  static const _defaultDomain = [1, 2];

  /// Attempt to generate a single puzzle. Returns the line representation or null on failure.
  static String? generateOne(
    GeneratorConfig config, {
    void Function(GeneratorProgress)? onProgress,
    bool Function()? shouldStop,
  }) {
    final width = config.width;
    final height = config.height;
    final size = width * height;
    final ratio = 0.8 + _rng.nextDouble() * 0.2; // 0.8 to 1.0

    // Build the allowed rule slugs
    final allSlugs = {'FM', 'PA', 'GS', 'LT', 'QA', 'SY', 'DF'};
    final allowedSlugs = allSlugs.difference(config.bannedRules);

    // If required rules are specified, ensure at least one of each is added
    final requiredSlugs = config.requiredRules.intersection(allowedSlugs);

    // 1. Create a random solved grid
    final solved = Puzzle.empty(width, height, _defaultDomain);
    for (int i = 0; i < size; i++) {
      solved.cells[i].setForSolver(
        _defaultDomain[_rng.nextInt(_defaultDomain.length)],
      );
    }
    final solvedValues = solved.cellValues;

    // 2. Create puzzle with some pre-filled cells
    final pu = Puzzle.empty(width, height, _defaultDomain);
    final prefilled = (size * (1 - ratio)).ceil();
    final indices = List.generate(size, (i) => i)..shuffle(_rng);
    for (int i = 0; i < prefilled && i < indices.length; i++) {
      pu.cells[indices[i]].setForSolver(solvedValues[indices[i]]);
      pu.cells[indices[i]] = pu.cells[indices[i]]..readonly = true;
    }

    // Collect readonly cell indices for DF constraint generation
    final Set<int> readonlyIndices = {};
    for (int i = 0; i < size; i++) {
      if (pu.cells[i].readonly) {
        readonlyIndices.add(i);
      }
    }

    // 3. Generate all valid constraints for the solved grid
    final List<Constraint> allConstraints = [];
    for (final slug in allowedSlugs) {
      final params = _generateParamsForSlug(
        slug,
        width,
        height,
        _defaultDomain,
        excludedIndices: slug == 'DF' ? readonlyIndices : null,
      );
      for (final param in params) {
        final constraint = _createConstraint(slug, param);
        if (constraint == null) continue;
        // Check that the constraint is satisfied by the solved grid
        if (constraint.verify(solved)) {
          allConstraints.add(constraint);
        }
      }
    }

    final total = allConstraints.length;
    allConstraints.shuffle(_rng);

    // Sort by usage priority (less common first)
    final Map<String, int> globalUsage = {
      'FM': 15379,
      'QA': 187,
      'SY': 1442,
      'LT': 1019,
      'GS': 13312,
      'PA': 15032,
      'DF': 500,
    };
    allConstraints.sort((a, b) {
      final sa = _slugOf(a);
      final sb = _slugOf(b);
      final aRequired = requiredSlugs.contains(sa) ? -1 : 0;
      final bRequired = requiredSlugs.contains(sb) ? -1 : 0;
      if (aRequired != bRequired) return aRequired.compareTo(bRequired);
      return (globalUsage[sa] ?? 0).compareTo(globalUsage[sb] ?? 0);
    });

    if (allConstraints.isEmpty) return null;
    pu.constraints.add(allConstraints.removeAt(0));

    // 4. Iteratively add constraints that improve the puzzle
    var currentRatio = pu.computeRatio();
    int tried = 0;

    while (currentRatio > 0 && allConstraints.isNotEmpty) {
      if (shouldStop?.call() == true) return null;

      bool found = false;
      while (allConstraints.isNotEmpty) {
        tried++;
        onProgress?.call(
          GeneratorProgress(
            puzzlesGenerated: 0,
            totalRequested: config.count,
            constraintsTried: tried,
            constraintsTotal: total,
            currentRatio: currentRatio,
          ),
        );

        final constraint = allConstraints.removeAt(0);
        final cloned = pu.clone();
        // Solve with existing constraints
        cloned.solve();
        final ratioBefore = cloned.computeRatio();
        // Add candidate and solve again
        cloned.constraints.add(constraint);
        cloned.solve();
        final ratioAfter = cloned.computeRatio();

        if (ratioAfter < ratioBefore) {
          pu.constraints.add(constraint);
          currentRatio = ratioAfter;
          found = true;
          break;
        }
      }

      if (!found) break;

      // Reshuffle and resort remaining constraints
      allConstraints.shuffle(_rng);
      final Map<String, int> localUsage = {};
      for (final c in pu.constraints) {
        final s = _slugOf(c);
        localUsage[s] = (localUsage[s] ?? 0) + 1;
      }
      allConstraints.sort((a, b) {
        final sa = _slugOf(a);
        final sb = _slugOf(b);
        return (localUsage[sa] ?? 0).compareTo(localUsage[sb] ?? 0);
      });
    }

    // Check required rules are present
    if (config.requiredRules.isNotEmpty) {
      final presentSlugs = pu.constraints.map((c) => _slugOf(c)).toSet();
      if (!config.requiredRules.every((r) => presentSlugs.contains(r))) {
        return null;
      }
    }

    // Compute the solved ratio (not the raw pre-filled ratio)
    final solvedPu = pu.clone();
    solvedPu.solve();
    currentRatio = solvedPu.computeRatio();
    if (currentRatio > 0.25) return null;

    if (currentRatio > 0) {
      // Fill remaining cells from solution
      final cloned = pu.clone();
      cloned.solve();
      for (final (_, idx) in cloned.freeCells()) {
        pu.setValue(idx, solvedValues[idx]);
      }
    }

    return pu.lineExport();
  }

  /// Find up to [maxSolutions] distinct solutions for a puzzle.
  static List<List<int>> findSolutions(Puzzle puzzle, {int maxSolutions = 2}) {
    final initial = puzzle.clone();
    initial.applyConstraintsPropagation();
    final solutions = <List<int>>[];

    for (int i = 0; i < maxSolutions; i++) {
      final (sol, _) = initial.solveWithBacktracking();
      if (sol == null) break;
      final foundSolution = sol.cellValues;
      solutions.add(foundSolution);
      initial.constraints.add(OtherSolutionConstraint(foundSolution));
    }
    return solutions;
  }

  static List<String> _generateParamsForSlug(
    String slug,
    int width,
    int height,
    List<int> domain, {
    Set<int>? excludedIndices,
  }) {
    switch (slug) {
      case 'FM':
        return ForbiddenMotif.generateAllParameters(width, height, domain);
      case 'PA':
        return ParityConstraint.generateAllParameters(width, height);
      case 'GS':
        return GroupSize.generateAllParameters(width, height);
      case 'LT':
        return LetterGroup.generateAllParameters(width, height);
      case 'QA':
        return QuantityConstraint.generateAllParameters(width, height, domain);
      case 'SY':
        return SymmetryConstraint.generateAllParameters(width, height);
      case 'DF':
        return DifferentFromConstraint.generateAllParameters(
          width,
          height,
          excludedIndices: excludedIndices,
        );
      default:
        return [];
    }
  }

  static Constraint? _createConstraint(String slug, String params) {
    switch (slug) {
      case 'FM':
        return ForbiddenMotif(params);
      case 'PA':
        return ParityConstraint(params);
      case 'GS':
        return GroupSize(params);
      case 'LT':
        return LetterGroup(params);
      case 'QA':
        return QuantityConstraint(params);
      case 'SY':
        return SymmetryConstraint(params);
      case 'DF':
        return DifferentFromConstraint(params);
      default:
        return null;
    }
  }

  static String _slugOf(Constraint c) {
    if (c is ForbiddenMotif) return 'FM';
    if (c is ParityConstraint) return 'PA';
    if (c is GroupSize) return 'GS';
    if (c is LetterGroup) return 'LT';
    if (c is QuantityConstraint) return 'QA';
    if (c is SymmetryConstraint) return 'SY';
    if (c is DifferentFromConstraint) return 'DF';
    return '';
  }
}
