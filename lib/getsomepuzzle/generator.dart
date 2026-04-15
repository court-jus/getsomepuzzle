import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraint_registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/other_solution.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/parity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';
import 'package:getsomepuzzle/getsomepuzzle/puzzle.dart';

class GeneratorConfig {
  final int width;
  final int height;
  final int? minWidth;
  final int? maxWidth;
  final int? minHeight;
  final int? maxHeight;
  final Set<String> requiredRules;
  final Set<String> bannedRules;
  final Duration maxTime;
  final int count;

  const GeneratorConfig({
    required this.width,
    required this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
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

  /// Count how many puzzles use each constraint type in a collection.
  /// Each type is counted at most once per puzzle.
  static Map<String, int> computeUsageStats(List<String> puzzleLines) {
    final stats = {for (final s in constraintSlugs) s: 0};
    for (final line in puzzleLines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields = line.split('_');
      if (fields.length < 5) continue;
      final slugs = fields[4]
          .split(';')
          .map((c) => c.split(':').first)
          .where((s) => s.isNotEmpty)
          .toSet();
      for (final slug in slugs) {
        stats[slug] = (stats[slug] ?? 0) + 1;
      }
    }
    return stats;
  }

  /// Attempt to generate a single puzzle. Returns the line representation or null on failure.
  static String? generateOne(
    GeneratorConfig config, {
    void Function(GeneratorProgress)? onProgress,
    bool Function()? shouldStop,
    Map<String, int>? usageStats,
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
    // In case we want a "SH" constraint, this step is different
    bool hasSH = config.requiredRules.contains("SH");
    if (!hasSH && usageStats != null && usageStats.containsKey("SH")) {
      final lowestUsage = usageStats.values.reduce(min);
      if (usageStats["SH"] == lowestUsage) {
        hasSH = true;
      }
    }
    final solved = hasSH
        ? _preFillSh(width, height)
        : _preFillRegular(width, height);
    final solvedValues = solved.cellValues;

    // 2. Create puzzle with some pre-filled cells
    final pu = Puzzle.empty(width, height, _defaultDomain);
    pu.cachedSolution = solvedValues;
    final prefilled = (size * (1 - ratio)).ceil();
    final indices = List.generate(size, (i) => i)..shuffle(_rng);
    for (int i = 0; i < prefilled && i < indices.length; i++) {
      pu.cells[indices[i]].setForSolver(solvedValues[indices[i]]);
      pu.cells[indices[i]] = pu.cells[indices[i]]..readonly = true;
    }

    // Force the SH constraint in the puzzle
    pu.constraints.addAll(solved.constraints);

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
        final constraint = createConstraint(slug, param);
        if (constraint == null) continue;
        // Check that the constraint is satisfied by the solved grid
        if (constraint.verify(solved)) {
          allConstraints.add(constraint);
        }
      }
    }

    final total = allConstraints.length;
    allConstraints.shuffle(_rng);
    // Sort by usage priority (less common types first)
    final usage = usageStats ?? <String, int>{};
    allConstraints.sort((a, b) {
      final sa = a.slug;
      final sb = b.slug;
      final aRequired = requiredSlugs.contains(sa) ? -1 : 0;
      final bRequired = requiredSlugs.contains(sb) ? -1 : 0;
      if (aRequired != bRequired) return aRequired.compareTo(bRequired);
      return (usage[sa] ?? 0).compareTo(usage[sb] ?? 0);
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
        final s = c.slug;
        localUsage[s] = (localUsage[s] ?? 0) + 1;
      }
      allConstraints.sort((a, b) {
        final sa = a.slug;
        final sb = b.slug;
        return (localUsage[sa] ?? 0).compareTo(localUsage[sb] ?? 0);
      });
    }

    // Check required rules are present
    if (config.requiredRules.isNotEmpty) {
      final presentSlugs = pu.constraints.map((c) => c.slug).toSet();
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

  static Puzzle _preFillSh(int width, int height) {
    final solved = Puzzle.empty(width, height, _defaultDomain);
    final possibleMotifs = ShapeConstraint.generateAllParameters(width, height);
    possibleMotifs.shuffle(_rng);
    final puzzleSize = width * height;
    final weights = possibleMotifs.map((m) {
      final sc = ShapeConstraint(m);
      final motifSize = sc.motifGridSize;
      final base = ShapeConstraint.baseWeights[motifSize] ?? 1;
      return base * pow(motifSize, puzzleSize * 0.05) * 0.2;
    }).toList();

    double totalWeight = weights.reduce((a, b) => a + b);
    double r = _rng.nextDouble() * totalWeight;
    double cumulative = 0;
    String chosenMotif = '';
    for (int i = 0; i < possibleMotifs.length; i++) {
      cumulative += weights[i];
      if (r <= cumulative) {
        chosenMotif = possibleMotifs[i];
        break;
      }
    }
    final chosenConstraint = ShapeConstraint(chosenMotif);
    chosenConstraint.variants.shuffle();
    final chosenVariant = chosenConstraint.variants
        .where(
          (variant) => variant.length <= height && variant[0].length <= width,
        )
        .first;
    int motifValue = 0;
    final maxRowOffset = height - chosenVariant.length;
    final maxColOffset = width - chosenVariant[0].length;
    final rowOffset = maxRowOffset > 0 ? _rng.nextInt(maxRowOffset) : 0;
    final colOffset = maxColOffset > 0 ? _rng.nextInt(maxColOffset) : 0;
    for (var (ridx, row) in chosenVariant.indexed) {
      for (var (cidx, value) in row.indexed) {
        if (value != 0) {
          solved.cells[(ridx + rowOffset) * width + (cidx + colOffset)]
              .setForSolver(value);
          motifValue = value;
        }
      }
    }
    final size = solved.width * solved.height;
    final opposite = _defaultDomain.whereNot((i) => i == motifValue).first;
    for (int i = 0; i < size; i++) {
      if (!solved.cells[i].isFree) continue;
      solved.cells[i].setForSolver(opposite);
    }
    solved.constraints.add(chosenConstraint);
    var possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
    while (possiblePositions.isNotEmpty) {
      final position =
          possiblePositions[_rng.nextInt(possiblePositions.length)];
      // 50% chance to add this position to the solved puzzle
      if (_rng.nextDouble() > 0.5) {
        final rowOffset = position.$1.$1;
        final colOffset = position.$1.$2;
        final variant = position.$2;
        for (var (ridx, row) in variant.indexed) {
          for (var (cidx, value) in row.indexed) {
            if (value != 0) {
              solved.cells[(ridx + rowOffset) * width + (cidx + colOffset)]
                  .setForSolver(value);
              motifValue = value;
            }
          }
        }
        // Recompute valid positions after grid changed
        possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
      }
    }
    return solved;
  }

  static Puzzle _preFillRegular(int width, int height) {
    final solved = Puzzle.empty(width, height, _defaultDomain);
    final size = solved.width * solved.height;
    for (int i = 0; i < size; i++) {
      solved.cells[i].setForSolver(
        _defaultDomain[_rng.nextInt(_defaultDomain.length)],
      );
    }
    return solved;
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
}
