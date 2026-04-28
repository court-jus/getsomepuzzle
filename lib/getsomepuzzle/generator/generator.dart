import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class GeneratorConfig {
  final int width;
  final int height;
  final int? minWidth;
  final int? maxWidth;
  final int? minHeight;
  final int? maxHeight;
  final Set<String> requiredRules;

  /// Restrict candidate constraints to these slugs. `null` = every slug in
  /// the registry is allowed. Callers translate user-facing "ban" lists
  /// into this set (`registry - banned`) before constructing the config.
  final Set<String>? allowedSlugs;

  /// Slugs the equilibrium / warm-up logic would *like* to see in the final
  /// puzzle. Soft preference only — they are pushed to the front of the
  /// candidate sort, and they trigger SH prefill if SH is among them. The
  /// final puzzle is accepted regardless of which preferred slugs survived
  /// the iterative selection (cross-axis recycling: a 2-types target that
  /// only ends up using one slug still produces a valid 1-type puzzle).
  final Set<String> preferredSlugs;

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
    this.allowedSlugs,
    this.preferredSlugs = const {},
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
    // Fraction of cells left empty for the player to deduce. Randomized in
    // [0.8, 1.0] so most puzzles are fully deductive (ratio=1) but up to 20%
    // of cells may be given as prefilled hints — variety without making
    // generation trivial.
    final ratio = 0.8 + _rng.nextDouble() * 0.2;

    // Build the allowed rule slugs. Callers either pass an explicit set, or
    // let it default to the full registry.
    final allSlugs = constraintRegistry.map((entry) => entry.slug).toSet();
    final allowedSlugs = config.allowedSlugs ?? allSlugs;

    // Soft and strict slug preferences. `requiredSlugs` is what the user must
    // see in the puzzle (strictly enforced at the end). `prioritySlugs` is the
    // union with the equilibrium-pushed `preferredSlugs` — used only for
    // candidate prioritization and SH prefill, never for rejection.
    final requiredSlugs = config.requiredRules.intersection(allowedSlugs);
    final preferredSlugs = config.preferredSlugs.intersection(allowedSlugs);
    final prioritySlugs = {...requiredSlugs, ...preferredSlugs};

    // 1. Create a random solved grid. Whenever SH should be tried (required
    // by user or pushed by an equilibrium / warm-up target), the pre-fill
    // paints a valid Shape motif so the SH constraint is satisfiable.
    final hasSH = prioritySlugs.contains("SH");
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

    // Force the SH constraint in the puzzle if it was added by the preFill
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
      final params =
          generateAllParameters(
            slug,
            width,
            height,
            _defaultDomain,
            slug == 'DF' ? readonlyIndices : null,
          ) ??
          [];
      for (final param in params) {
        final constraint = createConstraint(slug, param);
        if (constraint == null) continue;
        // Check that the constraint is satisfied by the solved grid
        if (constraint.verify(solved)) {
          allConstraints.add(constraint);
        }
      }
      print("$slug : ${params.length} constraints");
    }

    final total = allConstraints.length;
    allConstraints.shuffle(_rng);
    // Sort by priority then usage. Required + preferred slugs bubble up so
    // they are tried first — this is the only mechanism by which a target
    // is "pushed" into the puzzle now that exactNTypes rejection is gone.
    final usage = usageStats ?? <String, int>{};
    allConstraints.sort((a, b) {
      final sa = a.slug;
      final sb = b.slug;
      final aPriority = prioritySlugs.contains(sa) ? -1 : 0;
      final bPriority = prioritySlugs.contains(sb) ? -1 : 0;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
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

    // Strictly enforce the user-facing required rules (CLI `--require`).
    // Target-pushed `preferredSlugs` are NOT enforced here — if the iterative
    // loop never picked them, the puzzle is still credited to whatever bin it
    // actually falls in (cross-axis recycling).
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
        pu.cells[idx].setForSolver(solvedValues[idx]);
        pu.cells[idx].readonly = true;
      }
    }

    // Project-wide validity convention: a puzzle is valid iff `solve()`
    // (propagation + force, no backtracking) reaches the unique completion
    // from its readonly cells. This guarantees the player can solve it
    // with the in-game hint system, which uses the same `solve()` engine.
    if (!pu.isDeductivelyUnique()) return null;

    return pu.lineExport();
  }

  static Puzzle _preFillSh(int width, int height) {
    final solved = Puzzle.empty(width, height, _defaultDomain);
    final chosenMotif = _pickShapeMotif(width, height);
    final sc = ShapeConstraint(chosenMotif);
    _placeInitialVariant(solved, sc);
    _fillRemainingWithOpposite(solved, sc.color);
    solved.constraints.add(sc);
    _placeAdditionalVariants(solved);
    return solved;
  }

  /// Pick one motif string via weighted random sampling, where the weight
  /// depends on the motif's bounding-box size (`rows × cols`).
  static String _pickShapeMotif(int width, int height) {
    final possibleMotifs = ShapeConstraint.generateAllParameters(
      width,
      height,
      _defaultDomain,
      null,
    );
    possibleMotifs.shuffle(_rng);
    final puzzleSize = width * height;
    // Weight candidate motifs by bounding-box size. Exponent `puzzleSize / 20`
    // scales the size preference with the grid's area:
    //   - small grid  (size≈5):  exp≈0.25, sizes stay roughly equal
    //   - medium grid (size=20): exp=1, linear in motifSize
    //   - large grid  (size≈40): exp≈2, big motifs dominate — they fit and
    //     stay visually interesting, small motifs feel trivial.
    // `base` is a per-size hand-tuned bias (see ShapeConstraint.baseWeights).
    final weights = possibleMotifs.map((m) {
      final motifSize = ShapeConstraint.motifGridSizeOf(m);
      final base = ShapeConstraint.baseWeights[motifSize] ?? 1;
      return base * pow(motifSize, puzzleSize * 0.05);
    }).toList();

    final totalWeight = weights.reduce((a, b) => a + b);
    final r = _rng.nextDouble() * totalWeight;
    double cumulative = 0;
    for (int i = 0; i < possibleMotifs.length; i++) {
      cumulative += weights[i];
      if (r <= cumulative) return possibleMotifs[i];
    }
    return possibleMotifs.last;
  }

  /// Paint one variant of [sc] onto [solved] at a random position that fits.
  static void _placeInitialVariant(Puzzle solved, ShapeConstraint sc) {
    sc.variants.shuffle();
    final variant = sc.variants
        .where((v) => v.length <= solved.height && v[0].length <= solved.width)
        .first;
    final maxRowOffset = solved.height - variant.length;
    final maxColOffset = solved.width - variant[0].length;
    final rowOffset = maxRowOffset > 0 ? _rng.nextInt(maxRowOffset) : 0;
    final colOffset = maxColOffset > 0 ? _rng.nextInt(maxColOffset) : 0;
    _paintVariant(solved, variant, rowOffset, colOffset);
  }

  /// Fill every still-free cell of [solved] with the color opposite [color].
  static void _fillRemainingWithOpposite(Puzzle solved, int color) {
    final opposite = _defaultDomain.whereNot((i) => i == color).first;
    for (int i = 0; i < solved.width * solved.height; i++) {
      if (!solved.cells[i].isFree) continue;
      solved.cells[i].setForSolver(opposite);
    }
  }

  /// Repeatedly attempt to paint additional valid variant positions onto
  /// [solved]. Each candidate position has a 50% chance of being accepted.
  static void _placeAdditionalVariants(Puzzle solved) {
    var possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
    while (possiblePositions.isNotEmpty) {
      final position =
          possiblePositions[_rng.nextInt(possiblePositions.length)];
      if (_rng.nextDouble() > 0.5) {
        final (rowOffset, colOffset) = position.$1;
        _paintVariant(solved, position.$2, rowOffset, colOffset);
        possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
      }
    }
  }

  /// Write non-zero cells of [variant] onto [solved] at (rowOffset, colOffset).
  static void _paintVariant(
    Puzzle solved,
    List<List<int>> variant,
    int rowOffset,
    int colOffset,
  ) {
    for (final (ridx, row) in variant.indexed) {
      for (final (cidx, value) in row.indexed) {
        if (value == 0) continue;
        solved.cells[(ridx + rowOffset) * solved.width + (cidx + colOffset)]
            .setForSolver(value);
      }
    }
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
}
