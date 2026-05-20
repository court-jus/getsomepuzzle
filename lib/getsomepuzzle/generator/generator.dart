import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/path.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/regular.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sh.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sy.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
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

  /// When set, only puzzles classified at this exact level are emitted.
  /// Easier puzzles are dropped; harder puzzles enter an "easing" loop
  /// (add more constraints to reduce trace complexity) bounded by
  /// [easingBudget]. `null` = no target filter (default behavior).
  final PuzzleLevel? targetLevel;

  /// Per-puzzle wall-clock budget for the easing loop. Once exceeded,
  /// the candidate is dropped and the worker moves on. Ignored when
  /// [targetLevel] is `null`.
  final Duration easingBudget;

  /// When true, every `generateOne` invocation routes through
  /// `preFillPath` (the path-based pre-fill, cf. `docs/dev/path_based.md`).
  /// LT becomes the structural backbone; other constraints are added via
  /// the internal bipartite desambiguation, not the regular greedy.
  final bool pathBasedScenario;

  /// When true, every `generateOne` invocation routes through
  /// `preFillSy` (the SY-based pre-fill, cf. `docs/dev/prefill_sy.md`).
  /// Symmetric islands become the structural backbone; other constraints
  /// are added via the internal bipartite cascade.
  final bool syBasedScenario;

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
    this.targetLevel,
    this.easingBudget = const Duration(seconds: 30),
    this.pathBasedScenario = false,
    this.syBasedScenario = false,
  });
}

/// Why a `generateOne` attempt was abandoned. Surfaced via the
/// `onReject` callback so callers (the worker logger, the dashboard)
/// can attribute failure modes precisely instead of staring at a
/// generic "FAILURE in 4856ms".
enum GenerationRejectReason {
  /// No candidate constraint was even valid for the chosen
  /// solution — the constraint pool started empty. Very rare; only
  /// happens with extreme `--allow`/`--ban` filters.
  noCandidates,

  /// Iterative loop finished but `solve()` still leaves more than 25 %
  /// of cells free → too many would have to be filled "for free", so
  /// we reject. This is the most common failure mode on tight
  /// `--require` configs where the required slug doesn't push hard
  /// enough.
  ratioTooHigh,

  /// One of the user-required (`--require RULES`) slugs never made
  /// it into the iterative-loop-accepted constraint set.
  requiredMissing,

  /// `solveExplained`/replay didn't reach a clean completion — the
  /// puzzle isn't deductively solvable as-is. Defensive: should be
  /// unreachable after the ratio check passes, but kept as a separate
  /// reason so the rare false-negative is visible in logs.
  notUnique,

  /// `--target-collection` set and the puzzle classified into an
  /// out-of-cascade bucket (`overfilled`, `overfilledEasy`,
  /// `undetermined`). Prefill ratio is structural, so we can't ease
  /// it away.
  targetOutOfCascade,

  /// `--target-collection` set and the puzzle classified strictly
  /// easier than the target. Lower-level puzzles can't be made
  /// harder by adding constraints, so we drop.
  targetTooEasy,

  /// `--target-collection` set and `Puzzle.simplify` couldn't reach
  /// the target within its budget (`--easing-budget`). The puzzle
  /// was too hard and easing plateaued or timed out.
  targetEasingFailed,

  /// `shouldStop` callback returned true (worker wide max-time
  /// reached, SIGINT, etc.). Distinct from the other reasons because
  /// it's not a property of the candidate puzzle.
  cancelled,

  /// Path-based pre-fill (`preFillPath`) exhausted its retry budget
  /// without producing a deductively-unique puzzle. Symptom: random
  /// topology + colors + DPLL routing + bipartite desambiguation
  /// couldn't converge for this size.
  pathPrefillFailed,

  /// SY-based pre-fill (`preFillSy`) exhausted its retry budget without
  /// producing a deductively-unique puzzle. Symptom: random seeds +
  /// axes + island growth + bipartite cascade couldn't converge.
  syPrefillFailed,
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

  /// Attempt to generate a single puzzle.
  ///
  /// Returns `(line, level)` on success, `null` on failure.
  ///
  /// The classification is computed from the same `solveExplained()`
  /// trace that validates deductive uniqueness — no extra solve.
  static ({String line, PuzzleLevel level})? generateOne(
    GeneratorConfig config, {
    void Function(GeneratorProgress)? onProgress,
    bool Function()? shouldStop,
    void Function(GenerationRejectReason, Puzzle)? onReject,
    Map<String, int>? usageStats,
  }) {
    final width = config.width;
    final height = config.height;

    // Path-based pre-fill is a complete pipeline of its own (topology +
    // routing + bipartite desambiguation). It bypasses the regular
    // grid-first / greedy flow and produces a ready-to-finalize puzzle.
    if (config.pathBasedScenario) {
      final result = preFillPath(width, height, _rng);
      if (result == null) {
        onReject?.call(
          GenerationRejectReason.pathPrefillFailed,
          Puzzle.empty(width, height, _defaultDomain),
        );
        return null;
      }
      final pu = result.puzzle;
      pu.cachedSolution = result.solution;
      pu.generationScenario = 'pathBased';
      return _finalize(pu, config, onReject: onReject, shouldStop: shouldStop);
    }

    if (config.syBasedScenario) {
      final result = preFillSy(width, height, _rng);
      if (result == null) {
        onReject?.call(
          GenerationRejectReason.syPrefillFailed,
          Puzzle.empty(width, height, _defaultDomain),
        );
        return null;
      }
      final pu = result.puzzle;
      pu.cachedSolution = result.solution;
      pu.generationScenario = 'syBased';
      return _finalize(pu, config, onReject: onReject, shouldStop: shouldStop);
    }

    final size = width * height;
    // Fraction of cells left empty for the player to deduce. Randomized in
    // [0.75, 1.0] so most puzzles are fully deductive (ratio=1) but up to 25%
    // of cells may be given as prefilled hints — variety without making
    // generation trivial.
    final ratio = 0.75 + _rng.nextDouble() * 0.25;

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
        ? preFillSh(width, height, _defaultDomain, _rng)
        : preFillRegular(width, height, _defaultDomain, _rng);
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
    pu.addAllConstraints(solved.constraints);

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

    if (allConstraints.isEmpty) {
      onReject?.call(GenerationRejectReason.noCandidates, pu);
      return null;
    }
    pu.addConstraint(allConstraints.removeAt(0));

    // 4. Iteratively add constraints that improve the puzzle
    var currentRatio = pu.computeRatio();
    int tried = 0;

    while (currentRatio > 0 && allConstraints.isNotEmpty) {
      if (shouldStop?.call() == true) {
        onReject?.call(GenerationRejectReason.cancelled, pu);
        return null;
      }

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
        cloned.addConstraint(constraint);
        cloned.solve();
        final ratioAfter = cloned.computeRatio();

        if (ratioAfter < ratioBefore) {
          pu.addConstraint(constraint);
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
        onReject?.call(GenerationRejectReason.requiredMissing, pu);
        return null;
      }
    }

    // Compute the solved ratio (not the raw pre-filled ratio)
    final solvedPu = pu.clone();
    solvedPu.solve();
    currentRatio = solvedPu.computeRatio();
    if (currentRatio > 0.25) {
      onReject?.call(GenerationRejectReason.ratioTooHigh, pu);
      return null;
    }

    if (currentRatio > 0) {
      // Fill remaining cells from solution
      final cloned = pu.clone();
      cloned.solve();
      for (final (_, idx) in cloned.freeCells()) {
        pu.cells[idx].setForSolver(solvedValues[idx]);
        pu.cells[idx].readonly = true;
      }
    }

    // Stamp the generation scenario. `sh` requires that `preFillSh`
    // actually planted a Shape motif (detected by the SH constraint
    // being attached to the solved grid). When SH was requested but the
    // pre-fill didn't find a valid motif, the flow falls back to
    // classic.
    final shAttached = pu.constraints.any((c) => c.slug == 'SH');
    pu.generationScenario = (hasSH && shAttached) ? 'sh' : 'classic';

    return _finalize(pu, config, onReject: onReject, shouldStop: shouldStop);
  }

  /// Shared post-build pipeline: validity gate via `solveExplained`,
  /// `classifyTrace`, optional target-collection routing / easing, and
  /// the "easier-first" constraint sort. Used by both the regular/SH
  /// flow and the path-based flow.
  static ({String line, PuzzleLevel level})? _finalize(
    Puzzle pu,
    GeneratorConfig config, {
    void Function(GenerationRejectReason, Puzzle)? onReject,
    bool Function()? shouldStop,
  }) {
    // Project-wide validity convention: a puzzle is valid iff `solve()`
    // (propagation + force, no backtracking) reaches the unique completion
    // from its readonly cells. This guarantees the player can solve it
    // with the in-game hint system, which uses the same `solve()` engine.
    //
    // We use `solveExplained` rather than `isDeductivelyUnique`/`solve`
    // because the trace it produces is also what the level classifier
    // needs — running both would mean two solves for the same answer.
    final steps = pu.solveExplained();
    final replay = pu.clone();
    for (final s in steps) {
      replay.setValue(s.cellIdx, s.value);
    }
    final isUnique = replay.complete && replay.check(saveResult: false).isEmpty;
    if (!isUnique) {
      onReject?.call(GenerationRejectReason.notUnique, pu);
      return null;
    }

    final prefill = pu.cells.where((c) => c.readonly).length / pu.cells.length;
    var level = classifyTrace(
      steps: steps,
      prefillRatio: prefill,
      solved: true,
    );

    // Target-collection filter. When set, classify-and-route the puzzle:
    //   - exact match → emit;
    //   - too easy (lower index) → drop, caller will retry;
    //   - too hard (higher index) → delegate to `Puzzle.simplify`,
    //     which runs the indispensable-by-exploration pass under the
    //     `easingBudget` wall-clock cap.
    //   - out-of-cascade buckets (overfilled / undetermined) → drop:
    //     prefill ratio doesn't change with more constraints, so they
    //     cannot be eased into a playable collection.
    // Important: `simplify` never invokes `removeUselessRules` — its
    // job is to strip redundant constraints, which is exactly the
    // opposite of what easing builds up.
    if (config.targetLevel != null) {
      final target = config.targetLevel!;
      if (level == PuzzleLevel.overfilled ||
          level == PuzzleLevel.overfilledEasy ||
          level == PuzzleLevel.undetermined) {
        onReject?.call(GenerationRejectReason.targetOutOfCascade, pu);
        return null;
      }
      if (level.index < target.index) {
        onReject?.call(GenerationRejectReason.targetTooEasy, pu);
        return null;
      }
      SimplifyResult? simplifyResult;
      if (level.index > target.index) {
        // Path-based mode bans LT from easing: adding more letters would
        // dilute the puzzle's identity (the bipartite already placed the
        // intended LT set). SY-based mode bans SY for the same reason —
        // the islands are already placed and adding more anchors would
        // muddy the player's shape-recovery intent.
        final easingAllowed = config.pathBasedScenario
            ? (config.allowedSlugs ?? <String>{})
                  .where((s) => s != 'LT')
                  .toSet()
            : config.syBasedScenario
            ? (config.allowedSlugs ?? <String>{})
                  .where((s) => s != 'SY')
                  .toSet()
            : config.allowedSlugs;
        simplifyResult = pu.simplify(
          targetLevel: target,
          maxTime: config.easingBudget,
          allowedSlugs: easingAllowed,
          shouldStop: shouldStop,
        );
        if (!simplifyResult.reachedTarget) {
          onReject?.call(GenerationRejectReason.targetEasingFailed, pu);
          return null;
        }
        level = simplifyResult.finalLevel;
      }
      // Reuse simplify's final trace for sort if it ran — it's a
      // fresher signal than `steps` (which predates any graft).
      if (simplifyResult != null) {
        pu.sortConstraintsByDifficulty(simplifyResult.finalSteps);
        return (line: pu.lineExport(), level: level);
      }
    }

    // Final pass: enforce the project-wide "easier-first" constraint
    // order on the persisted line, reusing the trace `steps` we
    // already computed for the classification above. No extra solve.
    //
    // Skipping the post-sort re-classification is deliberate: sorting
    // can only lower `maxPropCx` (never raise anything in the
    // cascade), so `level` remains an honest upper bound of what a
    // fresh parse would see. The asset-routing may sit one tier high
    // for borderline puzzles — acceptable trade-off vs paying a full
    // re-solve here.
    pu.sortConstraintsByDifficulty(steps);

    return (line: pu.lineExport(), level: level);
  }
}
