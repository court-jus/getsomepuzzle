import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/letter_group.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/bb.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/boss.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/path.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/regular.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sh.dart';
import 'package:getsomepuzzle/getsomepuzzle/generator/prefill/sy.dart';
import 'package:getsomepuzzle/getsomepuzzle/level.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart' as utils_groups;

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

  /// Wall-clock cap for a single `generateOne` call. Once exceeded, the
  /// worker's `shouldStop` returns true and the attempt is aborted with
  /// `GenerationRejectReason.attemptTimeout`. Prevents one slow combo
  /// (e.g. CH-alone on a medium grid) from burning the entire [maxTime]
  /// budget across a single attempt.
  final Duration maxAttemptTime;

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
  /// `preFillPath` (the path-based pre-fill, cf. `docs/dev/path_based.md`):
  /// LT regions are built feasibly-by-construction, seeded as the backbone,
  /// then the classic greedy adds garde-fous.
  final bool pathBasedScenario;

  /// When true, every `generateOne` invocation routes through
  /// `preFillSy` (the SY-based pre-fill, cf. `docs/dev/prefill_sy.md`).
  /// Symmetric islands become the structural backbone; other constraints
  /// are added via the internal bipartite cascade.
  final bool syBasedScenario;

  /// Max retries inside `preFillPath` before it gives up. Tunable via
  /// `--path-retries`.
  final int pathMaxRetries;

  /// Path sinuosity for `preFillPath` (0..1). 0 ≈ shortest path (easy),
  /// higher ≈ winding snakes (harder LT deductions). Tunable via `--winding`.
  final double pathWindingProb;

  /// Per-slug deficit derived from the corpus equilibrium stats (the same
  /// gap that `pickTarget` uses on the slug axis). Higher = more
  /// under-represented in the corpus. Used as a soft secondary sort key
  /// between `prioritySlugs` and local-usage in `generateOne`, so puzzles
  /// pull in other under-represented slugs alongside the one forced by the
  /// target — not just the target itself. `null` or empty = no bias
  /// (warm-up, equilibrium disabled, or balanced corpus).
  final Map<String, double>? slugDeficitScores;

  /// Colour domain used by both the random pre-fill and the generated
  /// puzzle's declared domain. `defaultDomain` (2 colours) keeps the
  /// historical CLI behaviour; pass `fullDomain` to enable 3-colour
  /// generation.
  final List<CellValue> domain;

  /// Which candidate-acceptance strategy `generateOne` uses. Defaults
  /// to the shipped `phaseGate`; the other values are for A/B
  /// benchmarking.
  final GenerationStrategy strategy;

  /// No-progress watchdog window. If the iterative loop spends this
  /// long without accepting a new candidate, the attempt is aborted
  /// with `GenerationRejectReason.attemptStalled` so the worker can
  /// move on. `Duration.zero` disables the watchdog. Default 15 s —
  /// roughly an order of magnitude above the typical inter-accept gap
  /// on the configurations we've benched, leaving plenty of slack for
  /// legitimately slow successes.
  final Duration maxStall;

  /// Use the experimental "seed-and-grow" prefill instead of the
  /// default random/SH/BB prefill. Targets large grids ("Boss" levels):
  /// plants seeds weighted toward the grid centre, grows each one into
  /// a group of 15–25 cells, then random-fills the remaining ~30 % and
  /// posts a GS constraint per seeded group with its final size.
  /// See `docs/dev/boss.md`.
  final bool useBossPrefill;

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
    this.maxAttemptTime = const Duration(seconds: 120),
    this.count = 1,
    this.targetLevel,
    this.easingBudget = const Duration(seconds: 30),
    this.pathBasedScenario = false,
    this.syBasedScenario = false,
    this.pathMaxRetries = 30,
    this.pathWindingProb = 0.5,
    this.slugDeficitScores,
    this.domain = defaultDomain,
    this.strategy = GenerationStrategy.phaseGate,
    this.maxStall = const Duration(seconds: 15),
    this.useBossPrefill = false,
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

  /// Per-attempt time budget exhausted (cf. `GeneratorConfig.maxAttemptTime`).
  /// Workers cap a single `generateOne` call so one pathological combo
  /// can't monopolize the total `maxTime` budget. Distinct from
  /// `cancelled` so post-run analysis can tell apart "global timeout"
  /// from "this combo was slow".
  attemptTimeout,

  /// Path-based pre-fill (`preFillPath`) exhausted its retry budget
  /// without producing a deductively-unique puzzle. Symptom: constructive
  /// backbone build + DPLL completion couldn't converge for this size.
  pathPrefillFailed,

  /// Refinement of [pathPrefillFailed]: retries failed predominantly at
  /// backbone placement (no reachable region — e.g. too many letters
  /// for the grid).
  pathPlacementFailed,

  /// Refinement of [pathPrefillFailed]: retries failed predominantly because
  /// the DPLL background completion hit its timeout.
  pathRoutingTimeout,

  /// Refinement of [pathPrefillFailed]: retries failed predominantly because
  /// the DPLL background completion proved infeasible.
  pathRoutingInfeasible,

  /// SY-based pre-fill (`preFillSy`) exhausted its retry budget without
  /// producing a deductively-unique puzzle. Symptom: random seeds +
  /// axes + island growth + bipartite cascade couldn't converge.
  syPrefillFailed,

  /// No-progress watchdog tripped: the iterative loop went `maxStall`
  /// without an acceptance, so the attempt was abandoned to free the
  /// worker for fresher attempts. Observed empirically on hard
  /// equilibrium targets where one attempt would otherwise eat
  /// minutes of CPU at a plateau ratio. See `GeneratorConfig.maxStall`.
  attemptStalled,
}

/// Map a failed `preFillPath` attempt to its dominant reject
/// reason, reusing the existing path reject taxonomy (no bipartite phase
/// here). `null` cause → the generic prefill-failed bucket.
GenerationRejectReason _pathRejectReason(PathPrefillStats stats) {
  return switch (stats.dominantCause) {
    PathFailCause.placement => GenerationRejectReason.pathPlacementFailed,
    PathFailCause.routingTimeout => GenerationRejectReason.pathRoutingTimeout,
    PathFailCause.routingInfeasible =>
      GenerationRejectReason.pathRoutingInfeasible,
    PathFailCause.bipartite => GenerationRejectReason.pathPrefillFailed,
    null => GenerationRejectReason.pathPrefillFailed,
  };
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

/// Candidate-acceptance strategy used by `generateOne`'s iterative
/// loop. Exposed as a CLI knob so benches can compare strategies
/// head-to-head; the default `phaseGate` matches the production
/// path. See `docs/dev/third_color.md` for the design history.
enum GenerationStrategy {
  /// Pre-everything baseline. Every candidate gets a full
  /// `cloned.solve()` (propagation + force) and is accepted iff
  /// the post-solve ratio strictly drops. No prop-only phase, no
  /// `removeUselessRules` cleanup. The reference point for the
  /// other strategies.
  singleTier,

  /// Production default: phase 1 (cheap prop-only accepts) until
  /// plateau, then phase 2 (single-tier full solve) for the
  /// remaining force-enablers. `removeUselessRules` runs post-loop.
  phaseGate,

  /// Phase 1 limited to a single sweep. After the first sweep
  /// (with or without accepts) we transition to phase 2
  /// unconditionally, skipping the `secondChance` retest cycles
  /// in phase 1 that thrash on sparse-cheap-accept configurations.
  /// Hypothesis: peer-synergy across phase 1 sweeps is rare enough
  /// that one sweep captures most cheap accepts.
  phase1Oneshot,

  /// Phase 1 only — no transition to phase 2. By construction the
  /// loop accepts only constraints whose propagation alone advances
  /// the prop fixpoint. Force-enabler constraints (those that don't
  /// propagate directly but unlock a force step) are *never*
  /// accepted; if `solve()` needs them to close the puzzle, the
  /// attempt is rejected as `ratioTooHigh`. Two interpretations:
  ///   * As a generator throughput experiment: validates whether
  ///     the cheap signal alone is enough on a given config (vs
  ///     paying phase 2's full-solve cost).
  ///   * As a difficulty filter: every puzzle produced is
  ///     solvable by pure propagation, no force needed → "pure
  ///     beginner" tier.
  propOnly,
}

/// Per-stage wall-time accumulator paired with an invocation counter.
/// `loop_*` stages run many times per attempt while one-shot stages
/// (`prefill`, `export`, …) run at most once — counting calls lets a
/// caller compute the average time per call, which is what actually
/// drives "is this stage worth optimising next?". `enter`/`exit`
/// mirror `Stopwatch.start`/`stop` and additionally bump `calls`.
class _StageTimer {
  final Stopwatch sw = Stopwatch();
  int calls = 0;
  void enter() {
    calls++;
    sw.start();
  }

  void exit() {
    sw.stop();
  }
}

class PuzzleGenerator {
  static final _rng = Random();

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
  ///
  /// [onTimings] fires once before every return (success *or* failure)
  /// with two `stage → int` breakdowns of the attempt: cumulative
  /// microseconds and invocation counts. Stage keys are stable; the
  /// loop stages (`loop_probe`, `loop_candidate`, `loop_sort`) run many
  /// times per attempt — the count map lets callers compute an average
  /// time per call.
  static ({String line, PuzzleLevel level})? generateOne(
    GeneratorConfig config, {
    void Function(GeneratorProgress)? onProgress,
    void Function(GenerationRejectReason, Puzzle)? onReject,
    bool Function()? shouldStop,
    Map<String, int>? usageStats,
    void Function(Map<String, int> micros, Map<String, int> calls)? onTimings,
    void Function(PathPrefillStats)? onPathStats,
    void Function(int maxAcceptGapMs)? onStallStats,
  }) {
    // Per-stage timer + invocation counter. Each can be entered/exited
    // multiple times to accumulate (loop stages are entered many times
    // per attempt, one-shot stages exactly once).
    final tPrefill = _StageTimer();
    final tInitConstraints = _StageTimer();
    final tLoopProbe = _StageTimer();
    final tLoopCandidateProp = _StageTimer();
    final tLoopCandidateFull = _StageTimer();
    final tLoopSort = _StageTimer();
    final tPostSolve = _StageTimer();
    final tFill = _StageTimer();
    final tCleanup = _StageTimer();
    final tSolveExplained = _StageTimer();
    final tClassify = _StageTimer();
    final tShrink = _StageTimer();
    final tExport = _StageTimer();

    try {
      return _generateOneTimed(
        config,
        onProgress: onProgress,
        onReject: onReject,
        shouldStop: shouldStop,
        usageStats: usageStats,
        onPathStats: onPathStats,
        onStallStats: onStallStats,
        tPrefill: tPrefill,
        tInitConstraints: tInitConstraints,
        tLoopProbe: tLoopProbe,
        tLoopCandidateProp: tLoopCandidateProp,
        tLoopCandidateFull: tLoopCandidateFull,
        tLoopSort: tLoopSort,
        tPostSolve: tPostSolve,
        tFill: tFill,
        tCleanup: tCleanup,
        tSolveExplained: tSolveExplained,
        tClassify: tClassify,
        tShrink: tShrink,
        tExport: tExport,
      );
    } finally {
      if (onTimings != null) {
        onTimings(
          {
            'prefill': tPrefill.sw.elapsedMicroseconds,
            'init_constraints': tInitConstraints.sw.elapsedMicroseconds,
            'loop_probe': tLoopProbe.sw.elapsedMicroseconds,
            'loop_candidate_prop': tLoopCandidateProp.sw.elapsedMicroseconds,
            'loop_candidate_full': tLoopCandidateFull.sw.elapsedMicroseconds,
            'loop_sort': tLoopSort.sw.elapsedMicroseconds,
            'post_solve': tPostSolve.sw.elapsedMicroseconds,
            'fill': tFill.sw.elapsedMicroseconds,
            'cleanup': tCleanup.sw.elapsedMicroseconds,
            'solve_explained': tSolveExplained.sw.elapsedMicroseconds,
            'classify': tClassify.sw.elapsedMicroseconds,
            'shrink': tShrink.sw.elapsedMicroseconds,
            'export': tExport.sw.elapsedMicroseconds,
          },
          {
            'prefill': tPrefill.calls,
            'init_constraints': tInitConstraints.calls,
            'loop_probe': tLoopProbe.calls,
            'loop_candidate_prop': tLoopCandidateProp.calls,
            'loop_candidate_full': tLoopCandidateFull.calls,
            'loop_sort': tLoopSort.calls,
            'post_solve': tPostSolve.calls,
            'fill': tFill.calls,
            'cleanup': tCleanup.calls,
            'solve_explained': tSolveExplained.calls,
            'classify': tClassify.calls,
            'shrink': tShrink.calls,
            'export': tExport.calls,
          },
        );
      }
    }
  }

  /// Body of [generateOne]. Split out so the public entry can wrap
  /// it in a `try/finally` that fires the timings callback even for
  /// early returns (rejections, `shouldStop`, exceptions).
  static ({String line, PuzzleLevel level})? _generateOneTimed(
    GeneratorConfig config, {
    void Function(GeneratorProgress)? onProgress,
    void Function(GenerationRejectReason, Puzzle)? onReject,
    bool Function()? shouldStop,
    Map<String, int>? usageStats,
    void Function(PathPrefillStats)? onPathStats,
    void Function(int maxAcceptGapMs)? onStallStats,
    required _StageTimer tPrefill,
    required _StageTimer tInitConstraints,
    required _StageTimer tLoopProbe,
    required _StageTimer tLoopCandidateProp,
    required _StageTimer tLoopCandidateFull,
    required _StageTimer tLoopSort,
    required _StageTimer tPostSolve,
    required _StageTimer tFill,
    required _StageTimer tCleanup,
    required _StageTimer tSolveExplained,
    required _StageTimer tClassify,
    required _StageTimer tShrink,
    required _StageTimer tExport,
  }) {
    final phaseSw = Stopwatch()..start();
    int lastPhaseMs = 0;
    int phaseDelta() {
      final now = phaseSw.elapsedMilliseconds;
      final d = now - lastPhaseMs;
      lastPhaseMs = now;
      return d;
    }

    final width = config.width;
    final height = config.height;

    if (config.syBasedScenario) {
      final result = preFillSy(
        width,
        height,
        config.domain,
        _rng,
        shouldStop: shouldStop,
      );
      if (result == null) {
        onReject?.call(
          GenerationRejectReason.syPrefillFailed,
          Puzzle.empty(width, height, config.domain),
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

    final domain = config.domain;
    tPrefill.enter();
    // 1. Create a random solved grid. Whenever SH should be tried (required
    // by user or pushed by an equilibrium / warm-up target), the pre-fill
    // paints a valid Shape motif so the SH constraint is satisfiable. The
    // experimental "Boss" prefill (seed-and-grow) takes precedence when the
    // caller requested it via `useBossPrefill` — it produces large coherent
    // blobs instead of white-noise random fill, which matters at 30×20+
    // grid sizes.
    final hasSH = prioritySlugs.contains("SH");
    // BB mirrors SH's lightweight wiring: when BB is prioritised and SH is not,
    // the pre-fill builds islands whose colour groups all share one W×H extent
    // so a BB constraint is satisfiable (a random grid almost never survives
    // the candidate `verify` filter for BB). SH keeps priority over BB.
    final hasBB = prioritySlugs.contains("BB");
    List<LetterGroup> constructiveLts = const [];
    final Puzzle solved;
    if (config.pathBasedScenario) {
      final stats = PathPrefillStats();
      final result = preFillPath(
        width,
        height,
        domain,
        _rng,
        windingProb: config.pathWindingProb,
        maxRetries: config.pathMaxRetries,
        stats: stats,
        shouldStop: shouldStop,
      );
      onPathStats?.call(stats);
      if (result == null) {
        tPrefill.exit();
        onReject?.call(
          _pathRejectReason(stats),
          Puzzle.empty(width, height, domain),
        );
        return null;
      }
      solved = result.solved;
      constructiveLts = result.letterGroups;
    } else {
      // Boss prefill (seed-and-grow) takes precedence over the other
      // prefills when explicitly requested via config flag.
      solved = config.useBossPrefill
          ? preFillBoss(width, height, domain, _rng)
          : hasSH
          ? preFillSh(width, height, domain, _rng)
          : hasBB
          ? preFillBB(width, height, domain, _rng)
          : preFillRegular(width, height, domain, _rng);
    }
    final solvedValues = solved.cellValues;

    // 2. Create puzzle with some pre-filled cells
    final pu = Puzzle.empty(width, height, domain);
    pu.cachedSolution = solvedValues;
    final prefilled = (size * (1 - ratio)).ceil();
    final indices = List.generate(size, (i) => i)..shuffle(_rng);
    for (int i = 0; i < prefilled && i < indices.length; i++) {
      pu.cells[indices[i]].setForSolver(solvedValues[indices[i]]);
      pu.cells[indices[i]] = pu.cells[indices[i]]..readonly = true;
    }

    // Force the SH constraint in the puzzle if it was added by the preFill
    pu.addAllConstraints(solved.constraints);
    // Seed the constructive LT backbone explicitly. `solved` is kept pure (no
    // constraints) so candidate enumeration reads a neutral grid; the backbone
    // is injected here, into the player puzzle only.
    for (final lt in constructiveLts) {
      pu.addConstraint(lt);
    }
    tPrefill.exit();

    tInitConstraints.enter();
    // Collect readonly cell indices for DF constraint generation
    final Set<int> readonlyIndices = {};
    for (int i = 0; i < size; i++) {
      if (pu.cells[i].readonly) {
        readonlyIndices.add(i);
      }
    }
    onLog?.call(
      'phase2 prefilled=$prefilled readonly=${readonlyIndices.length} '
      'done in ${phaseDelta()}ms',
    );

    // 3. Generate all valid constraints for the solved grid.
    //
    // On big grids (30×20+), some slugs produce huge candidate lists
    // (GS alone yields ~8400). Verifying them all up front is what
    // makes phase 3 dominate the wall-clock. So we cap the *kept*
    // candidates per slug at [maxConstraintParameters], stash the
    // un-tried tail of each slug's shuffled params list as a
    // per-slug "reserve", and only consume the reserve later (see
    // `refillFromReserve` below) if phase 4 burns through the
    // initial batch without solving the puzzle.
    const maxConstraintParameters = 1000;
    onLog?.call('phase3 start: ${allowedSlugs.length} slug(s)');
    final List<Constraint> allConstraints = [];
    // Per-slug reserve: shuffled params list + cursor into it (next
    // index to try). Entry is removed when the cursor hits the end.
    final reserveParams = <String, ({List<String> params, int next})>{};
    final slugSw = Stopwatch();
    for (final slug in allowedSlugs) {
      slugSw
        ..reset()
        ..start();
      final params =
          generateAllParameters(
            slug,
            width,
            height,
            domain,
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
        final constraint = createConstraint(slug, params[i]);
        if (constraint != null && constraint.verify(solved)) {
          allConstraints.add(constraint);
          kept++;
        }
        i++;
      }
      if (i < paramCount) {
        reserveParams[slug] = (params: params, next: i);
        onLog?.call(
          '  [$slug] capped: kept=$kept reserve=${paramCount - i} '
          '(scanned $i/$paramCount in ${slugSw.elapsedMilliseconds}ms)',
        );
      } else {
        onLog?.call(
          '  [$slug] exhausted: kept=$kept/$paramCount '
          'in ${slugSw.elapsedMilliseconds}ms',
        );
      }
    }
    onLog?.call(
      'phase3 done: ${allConstraints.length} initial candidates, '
      'reserves=${reserveParams.length} slug(s) in ${phaseDelta()}ms',
    );

    // Helper: when phase 4 empties allConstraints with the puzzle still
    // unsolved, pull another batch from each remaining reserve. Returns
    // `true` iff at least one new candidate was added. Mutates
    // `allConstraints` and `reserveParams` in place; the caller is
    // responsible for re-shuffling / re-sorting after the call.
    bool refillFromReserve() {
      if (reserveParams.isEmpty) return false;
      bool added = false;
      final emptied = <String>[];
      for (final entry in reserveParams.entries) {
        final slug = entry.key;
        final list = entry.value.params;
        int i = entry.value.next;
        int kept = 0;
        while (i < list.length && kept < maxConstraintParameters) {
          final c = createConstraint(slug, list[i]);
          if (c != null && c.verify(solved)) {
            allConstraints.add(c);
            kept++;
            added = true;
          }
          i++;
        }
        if (i >= list.length) {
          emptied.add(slug);
        } else {
          reserveParams[slug] = (params: list, next: i);
        }
        onLog?.call('  [$slug] refill: kept=$kept cursor=$i/${list.length}');
      }
      for (final slug in emptied) {
        reserveParams.remove(slug);
      }
      return added;
    }

    // Per-letter LT pre-filter. An LT pair satisfies `verify(solved)`
    // iff its two cells share a *connected* same-colour component in
    // `solved` — but `Puzzle.addConstraint` silently merges same-letter
    // LTs, and two individually-valid pairs that land in *different*
    // components (whether of different colours or two disjoint groups
    // of the same colour) merge into an LT whose union spans several
    // components. That merged constraint then fails on `solved`, and
    // the whole generation attempt gets rejected late at
    // `!isUnique`. We pre-filter so the iterative loop never even
    // considers a pair that would corrupt a letter once merged: for
    // each letter, we pick a single component (the one with the most
    // surviving pairs — likely the most generative) and drop pairs
    // that sit on any other component. `LetterGroup.generateAllParameters`
    // cannot do this itself: it doesn't see `solvedValues`.
    final solvedGroups = utils_groups.getGroups(solved);
    final cellToComponent = <int, int>{};
    for (int gi = 0; gi < solvedGroups.length; gi++) {
      for (final cellIdx in solvedGroups[gi]) {
        cellToComponent[cellIdx] = gi;
      }
    }
    final ltByLetterComponent = <String, List<LetterGroup>>{};
    final keptNonLt = <Constraint>[];
    for (final c in allConstraints) {
      if (c is LetterGroup) {
        // verify(solved) guarantees both indices are in the same component,
        // so we can read it off any index.
        final comp = cellToComponent[c.indices.first];
        ltByLetterComponent.putIfAbsent('${c.letter}-c$comp', () => []).add(c);
      } else {
        keptNonLt.add(c);
      }
    }
    final perLetterChosenKey = <String, String>{};
    for (final key in ltByLetterComponent.keys) {
      final letter = key.substring(0, key.indexOf('-'));
      final current = perLetterChosenKey[letter];
      if (current == null ||
          ltByLetterComponent[key]!.length >
              ltByLetterComponent[current]!.length) {
        perLetterChosenKey[letter] = key;
      }
    }
    allConstraints
      ..clear()
      ..addAll(keptNonLt);
    for (final key in perLetterChosenKey.values) {
      allConstraints.addAll(ltByLetterComponent[key]!);
    }

    final total = allConstraints.length;
    allConstraints.shuffle(_rng);
    // Sort by priority, then by corpus-level deficit, then by local usage.
    // - Required + preferred slugs bubble up first (the target push).
    // - Among the rest, slugs that are under-represented in the corpus
    //   (highest deficit) come next, so a puzzle doesn't just satisfy its
    //   target slug but also pulls in other slugs lagging behind globally.
    // - Local-usage tie-break keeps a single puzzle from over-loading the
    //   same slug repeatedly.
    final usage = usageStats ?? <String, int>{};
    final deficits = config.slugDeficitScores ?? const <String, double>{};
    // `path-constructive`: relegate counting garde-fous (QA/GC) to the tail of
    // every candidate sort. They pin the background *count*, closing the puzzle
    // by counting once the paths are deduced — the "= background" degeneracy we
    // want to avoid. Kept available (never banned), chosen only when no local
    // garde-fou closes the puzzle. Dominant criterion (ahead of priority).
    final deprioritizedSlugs = config.pathBasedScenario
        ? const {'QA', 'GC'}
        : const <String>{};
    allConstraints.sort((a, b) {
      final sa = a.slug;
      final sb = b.slug;
      final aDep = deprioritizedSlugs.contains(sa) ? 1 : 0;
      final bDep = deprioritizedSlugs.contains(sb) ? 1 : 0;
      if (aDep != bDep) return aDep.compareTo(bDep);
      final aPriority = prioritySlugs.contains(sa) ? -1 : 0;
      final bPriority = prioritySlugs.contains(sb) ? -1 : 0;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      final aDeficit = deficits[sa] ?? 0.0;
      final bDeficit = deficits[sb] ?? 0.0;
      if (aDeficit != bDeficit) return bDeficit.compareTo(aDeficit);
      return (usage[sa] ?? 0).compareTo(usage[sb] ?? 0);
    });

    if (allConstraints.isEmpty) {
      tInitConstraints.exit();
      onReject?.call(GenerationRejectReason.noCandidates, pu);
      return null;
    }
    pu.addConstraint(allConstraints.removeAt(0));
    tInitConstraints.exit();

    // 4. Iteratively add constraints that improve the puzzle.
    //
    // Per-candidate signal: `cloned.solve()` (propagation + force, no
    // backtracking) — same engine used at the final validity check, so
    // a constraint that helps `solve()` close more cells is the
    // unambiguous "good candidate" signal. The cost is high
    // (`_forceOneCell` runs O(free × domain × propagation) on every
    // candidate, twice for before/after) but the signal is correct.
    //
    // Optimisation: `ratioBefore` only changes when we accept a
    // candidate, so we cache it across candidates within an outer
    // iteration. That cuts the inner loop's solve() count in half.
    //
    // Earlier experiments:
    //   * Propagation-only signal — 100% `ratioTooHigh` rejections
    //     (force-enabler constraints got dropped).
    //   * Hybrid (prop-only + occasional force on `pu`) — still high
    //     `ratioTooHigh` rate. The force decisions baked into `pu`
    //     during the loop weren't reproducible by `solve()` from the
    //     restarted state, because `solve()`'s force sees the full
    //     final constraint set and can pick a different cell.
    // Both reverted; see `docs/dev/third_color.md`.
    //
    // The current implementation is phase-gated:
    //
    //   Phase 1 (cheap-only): each candidate is tested via
    //     `cloned.propagateToFixpoint()` and accepted iff its
    //     prop-fixpoint free-cell count drops below `pu`'s. ~5 ms /
    //     call. Force-enablers (constraints that don't propagate
    //     directly but unlock a force step) silently fail this test
    //     and get parked in `secondChance`. Phase 1 closes "easy"
    //     puzzles via a propagation cascade in very few candidate
    //     tests.
    //
    //   Phase 2 (single-tier baseline): triggered when phase 1
    //     plateaus (inner sweep exhausts without acceptance) and
    //     `secondChance` is non-empty. Phase 2 runs the strict
    //     full-solve criterion `fullRatio < cachedRatioBefore` —
    //     ~55 ms / call — and picks up the force-enablers phase 1
    //     dropped. No cheap probe in phase 2: each candidate test
    //     pays one full solve, like the pre-phase baseline.
    //
    // The earlier "every candidate tries cheap then full" two-tier
    // was reverted because on 3-colour grids the cheap path almost
    // never fires (~0.4 % hit rate), so the 5 ms cheap probe became
    // pure overhead on every test. Worse, cheap-accept set
    // `currentRatio = cloned.computeRatio()` (a prop-fixpoint ratio,
    // ≥ full-solve ratio), and the outer loop's `currentRatio > 0`
    // exit condition then never fired — the loop kept accepting weak
    // prop-only constraints past the point where the puzzle was
    // full-solve-closeable, blowing up the candidate count and the
    // failure rate. The phase-gate keeps the cheap path's "fast win"
    // on easy puzzles while avoiding both issues: cheap probe runs
    // only in phase 1, and `currentRatio` is only updated in phase 2
    // (where it correctly reflects full-solve progress).
    //
    // `removeUselessRules` runs post-loop to prune any over-accepts
    // from phase 1 — its cheap signal is laxer than the strict full
    // criterion, so some phase-1-accepted constraints may turn out
    // subsumed by phase 2 picks or by fill-from-solution hints.
    var currentRatio = pu.computeRatio();
    int tried = 0;
    double? cachedRatioBefore;
    int? cachedPropFreeCells;
    List<int>? cachedUndetermined;
    // No-progress watchdog: track wall-clock elapsed since the last
    // accept. When it crosses `config.maxStall`, abandon the attempt.
    // Initialised with a fresh stopwatch so the watchdog window
    // includes attempt-start setup (init_constraints etc.) — a
    // pathological attempt that never accepts anything still bails
    // out within maxStall, not maxStall + setup.
    final attemptSw = Stopwatch()..start();
    int lastAcceptMs = 0;
    // Largest wall-clock gap between two consecutive accepts (counting the
    // setup-to-first-accept window). This is exactly the peak the no-progress
    // watchdog counter reaches before each reset — so for an attempt that
    // succeeded, `maxStall` must be ≥ this value or the attempt would have
    // been killed. Surfaced via `onStallStats` to calibrate `maxStall`.
    int maxAcceptGapMs = 0;
    final maxStallMs = config.maxStall.inMilliseconds;
    final watchdogEnabled = maxStallMs > 0;
    // Candidates that didn't improve against the *current* `pu` state.
    // In phase 1 these are force-enabler candidates (no prop progress).
    // In phase 2 these are candidates that don't improve the full-solve
    // ratio. Re-pooled into `allConstraints` after every accept (state
    // changed → previously useless may now propagate or unlock force).
    final secondChance = <Constraint>[];
    // `singleTier` starts directly in phase 2 (full-solve criterion
    // for every candidate, no prop-only pre-pass). The other two
    // strategies enter phase 1 first.
    int phase = config.strategy == GenerationStrategy.singleTier ? 2 : 1;

    while (true) {
      if (shouldStop?.call() == true) {
        onReject?.call(GenerationRejectReason.cancelled, pu);
        return null;
      }

      // Phase-specific exit: phase 1 ends when propagation alone
      // closes the puzzle; phase 2 ends when full solve does.
      if (phase == 1 && cachedPropFreeCells == 0) break;
      if (phase == 2 && currentRatio == 0) break;
      // Common exit: nothing left to try.
      if (allConstraints.isEmpty && secondChance.isEmpty) break;

      bool found = false;
      while (allConstraints.isNotEmpty) {
        // Each candidate triggers two `solve()` calls which can be expensive
        // (CH especially: BFS on every free cell, multiplied across solve
        // iterations). Without this check the worker can chew through 50+
        // candidates without ever re-asking the deadline, blowing past
        // `maxAttemptTime` by tens of seconds. Particularly important for
        // 3-colour grids where a candidate sweep can run hundreds of solve()
        // calls.
        if (shouldStop?.call() == true) {
          onReject?.call(GenerationRejectReason.cancelled, pu);
          return null;
        }
        // No-progress watchdog. Checked before incrementing `tried` so
        // a single super-slow candidate test (e.g. a 30 s full solve
        // on a hard 3-colour grid) can't single-handedly trip it; the
        // window is consumed by lack-of-progress, not by a slow tick.
        if (watchdogEnabled &&
            attemptSw.elapsedMilliseconds - lastAcceptMs > maxStallMs) {
          onReject?.call(GenerationRejectReason.attemptStalled, pu);
          return null;
        }
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
        // Throttle phase-4 progress logs to one per 50 tried candidates,
        // so heavy attempts where many candidates fail to improve the
        // ratio still emit liveness signal.
        if (tried - lastLoggedTried >= 50) {
          onLog?.call(
            '  phase4 tried=$tried accepted=${pu.constraints.length} '
            'ratio=${currentRatio.toStringAsFixed(3)} '
            'remaining=${allConstraints.length}',
          );
          lastLoggedTried = tried;
        }

        // Phase-specific cold probe of `pu`'s baseline.
        //
        // Phase 1 needs `cachedPropFreeCells` (free count after
        // propagateToFixpoint). Phase 2 needs `cachedRatioBefore`
        // (free ratio after a full solve). Both probe a clone so
        // `pu.cells` stays untouched — otherwise propagation-deduced
        // values would leak into `lineExport()` and be marked
        // readonly when the puzzle is reloaded (puzzle.dart:188).
        if (phase == 1 && cachedPropFreeCells == null) {
          tLoopProbe.enter();
          final probe = pu.clone();
          probe.propagateToFixpoint();
          cachedPropFreeCells = probe.freeCells().length;
          cachedUndetermined ??= [
            for (final (_, idx) in probe.freeCells()) idx,
          ];
          tLoopProbe.exit();
        }
        if (phase == 2 && cachedRatioBefore == null) {
          tLoopProbe.enter();
          final probe = pu.clone();
          probe.solve();
          cachedRatioBefore = probe.computeRatio();
          cachedUndetermined = [for (final (_, idx) in probe.freeCells()) idx];
          tLoopProbe.exit();
        }

        final constraint = allConstraints.removeAt(0);
        // Reject candidates that visually conflict with an already-placed
        // constraint (e.g. two MJ zones with overlapping borders). Placed
        // constraints never leave this loop, so the conflict is monotone and
        // the candidate can be dropped permanently.
        if (pu.constraints.any((c) => constraint.conflictsWith(c))) {
          continue;
        }
        final cloned = pu.clone();
        cloned.addConstraint(constraint);
        // Invariant guard: `Puzzle.addConstraint` silently merges
        // same-letter `LetterGroup`s. Two LT:A.x.y pairs that
        // *individually* verify against `solved` (each pair shares a
        // colour group) can merge into an LT:A whose union spans
        // multiple colour groups — that merged constraint no longer
        // satisfies `solved`. We drop the candidate when the merge
        // breaks the invariant. Not requeued in `secondChance`: the
        // merge would still break next time.
        if (constraint is LetterGroup) {
          final merged = cloned.constraints.whereType<LetterGroup>().firstWhere(
            (lt) => lt.letter == constraint.letter,
          );
          if (!merged.verify(solved)) continue;
        }

        bool accepted = false;
        if (phase == 1) {
          tLoopCandidateProp.enter();
          cloned.propagateToFixpoint();
          final propFree = cloned.freeCells().length;
          tLoopCandidateProp.exit();

          if (propFree < cachedPropFreeCells!) {
            // Cheap accept. We deliberately do NOT update
            // `currentRatio` here: `cloned.computeRatio()` would be
            // the prop-fixpoint ratio (≥ true full-solve ratio), and
            // setting `currentRatio` to that overestimate would break
            // the outer loop's `currentRatio == 0` exit signal in
            // phase 2 (it would never reach 0 from a phase-1
            // overshoot). Phase 1's own exit signal is
            // `cachedPropFreeCells == 0`.
            cachedPropFreeCells = propFree;
            cachedUndetermined = [
              for (final (_, idx) in cloned.freeCells()) idx,
            ];
            accepted = true;
          }
        } else {
          // Phase 2: strict full-solve criterion (single-tier
          // baseline). No cheap probe — `cloned.solve(shouldStop)`
          // does propagation + force from scratch.
          tLoopCandidateFull.enter();
          cloned.solve(shouldStop: shouldStop);
          final fullRatio = cloned.computeRatio();
          tLoopCandidateFull.exit();

          if (fullRatio < cachedRatioBefore!) {
            cachedRatioBefore = fullRatio;
            currentRatio = fullRatio;
            cachedUndetermined = [
              for (final (_, idx) in cloned.freeCells()) idx,
            ];
            accepted = true;
          }
        }

        if (accepted) {
          // Reset the watchdog: an accept counts as forward progress
          // regardless of which phase produced it (a cheap phase-1
          // accept that doesn't move `currentRatio` still proves the
          // loop is finding useful constraints).
          final gap = attemptSw.elapsedMilliseconds - lastAcceptMs;
          if (gap > maxAcceptGapMs) {
            maxAcceptGapMs = gap;
            onStallStats?.call(maxAcceptGapMs);
          }
          lastAcceptMs = attemptSw.elapsedMilliseconds;
          pu.addConstraint(constraint);
          // Per-line uniqueness: at most one CC per column and one RC
          // per row. Two CC:<col>.<colour>.<count> candidates targeting
          // the same column add no information on a 2-colour domain
          // and are at best partially redundant on 3-colour (see
          // `docs/dev/third_color.md`).
          if (constraint is ColumnCountConstraint) {
            allConstraints.removeWhere(
              (c) =>
                  c is ColumnCountConstraint &&
                  c.columnIdx == constraint.columnIdx,
            );
            secondChance.removeWhere(
              (c) =>
                  c is ColumnCountConstraint &&
                  c.columnIdx == constraint.columnIdx,
            );
          } else if (constraint is RowCountConstraint) {
            allConstraints.removeWhere(
              (c) => c is RowCountConstraint && c.rowIdx == constraint.rowIdx,
            );
            secondChance.removeWhere(
              (c) => c is RowCountConstraint && c.rowIdx == constraint.rowIdx,
            );
          }
          found = true;
          onLog?.call(
            '  phase4 ACCEPT slug=${constraint.slug} '
            'tried=$tried accepted=${pu.constraints.length} '
            'ratio=${currentRatio.toStringAsFixed(3)} '
            'remaining=${allConstraints.length}',
          );
          lastLoggedTried = tried;
          break;
        } else {
          // No help against the current state — park it. After we
          // accept some other candidate (or switch phases), the state
          // changes and this one may now contribute.
          secondChance.add(constraint);
        }
      }

      if (!found) {
        // Inner sweep exhausted without an accept.
        if (phase == 1 &&
            secondChance.isNotEmpty &&
            config.strategy != GenerationStrategy.propOnly) {
          // Phase 1 plateau → switch to phase 2 and retry the parked
          // candidates with the strict full-solve criterion. This is
          // where force-enabler constraints get a chance.
          // `propOnly` deliberately skips this transition: it only
          // accepts propagation-helpers, so any puzzle that needs
          // force is rejected as `ratioTooHigh` at the post-loop
          // check.
          phase = 2;
          allConstraints.addAll(secondChance);
          secondChance.clear();
          continue;
        }
        break;
      }

      // `phase1Oneshot`: after the first phase-1 sweep (whatever its
      // outcome) we transition to phase 2 unconditionally — no more
      // phase 1 retests of the parked candidates. This caps phase 1's
      // total cost at one sweep regardless of how thinly cheap accepts
      // are spread.
      if (phase == 1 && config.strategy == GenerationStrategy.phase1Oneshot) {
        phase = 2;
      }

      // We accepted a candidate → state changed → previously-rejected
      // candidates get another shot. Re-pool them, then resort with
      // targeted priority: constraints that touch one of the still-
      // undetermined cells are tried first. The targeted set covers
      // DF/NC/CC/RC — the slugs whose per-cell effect is enumerable
      // in closed form. `cachedUndetermined` was just populated from
      // the accept's `cloned.freeCells()` (above), so the sort below
      // sees an up-to-date mask without paying a fresh probe solve.
      allConstraints.addAll(secondChance);
      secondChance.clear();
      allConstraints.shuffle(_rng);

      tLoopSort.enter();
      // Non-null by construction: the accept branch above always sets
      // `cachedUndetermined`, and we only reach here when `found` is
      // true (i.e. an accept happened in this outer iteration).
      final targetedKeys = _generateTargetedKeys(
        undetermined: cachedUndetermined!,
        solvedValues: solvedValues,
        width: width,
        height: height,
        domain: domain,
      );
      final Map<String, int> localUsage = {};
      for (final c in pu.constraints) {
        final s = c.slug;
        localUsage[s] = (localUsage[s] ?? 0) + 1;
      }
      allConstraints.sort((a, b) {
        final aDep = deprioritizedSlugs.contains(a.slug) ? 1 : 0;
        final bDep = deprioritizedSlugs.contains(b.slug) ? 1 : 0;
        if (aDep != bDep) return aDep.compareTo(bDep);
        final aTargeted = targetedKeys.contains(a.serialize()) ? -1 : 0;
        final bTargeted = targetedKeys.contains(b.serialize()) ? -1 : 0;
        if (aTargeted != bTargeted) return aTargeted.compareTo(bTargeted);
        final sa = a.slug;
        final sb = b.slug;
        final aDeficit = deficits[sa] ?? 0.0;
        final bDeficit = deficits[sb] ?? 0.0;
        if (aDeficit != bDeficit) return bDeficit.compareTo(aDeficit);
        return (localUsage[sa] ?? 0).compareTo(localUsage[sb] ?? 0);
      });
      tLoopSort.exit();
    }

    onLog?.call(
      'phase4 done: tried=$tried accepted=${pu.constraints.length} '
      'final ratio=${currentRatio.toStringAsFixed(3)} '
      'in ${phaseDelta()}ms',
    );

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

    // Validity is determined by `solve()`'s post-loop ratio:
    //   * ratio == 0 → solve reaches completion from the readonly cells
    //     alone → puzzle is unique under the project-wide convention.
    //   * 0 < ratio ≤ 0.25 → fill the still-free cells with their
    //     solved values, making them readonly. After fill, solve() is
    //     guaranteed to complete (the previously-free cells now act as
    //     hints) → puzzle is unique.
    //   * ratio > 0.25 → too many cells would need to be given for
    //     free → reject as `ratioTooHigh`.
    //
    // We previously also did a `solveExplained`-then-replay pass to
    // check `replay.complete`. That was redundant: `solveExplained`
    // uses the same `findAMove` engine as `solve()`, so once `solve()`
    // reaches completion, the replay can only fail if the two engines
    // disagree — which would be a bug to fix in the engine, not a
    // rejection criterion. Dropping the check eliminates one solve
    // pass and one rejection category (`notUnique`).
    tPostSolve.enter();
    final solvedPu = pu.clone();
    solvedPu.solve();
    currentRatio = solvedPu.computeRatio();
    tPostSolve.exit();
    if (currentRatio > 0.25) {
      onReject?.call(GenerationRejectReason.ratioTooHigh, pu);
      return null;
    }

    if (currentRatio > 0) {
      tFill.enter();
      // `solvedPu` is already solved; reuse it rather than running a
      // third solve on a fresh clone.
      for (final (_, idx) in solvedPu.freeCells()) {
        pu.cells[idx].setForSolver(solvedValues[idx]);
        pu.cells[idx].readonly = true;
      }
      tFill.exit();
    }

    // Stamp the generation scenario. `sh` requires that `preFillSh`
    // actually planted a Shape motif (detected by the SH constraint
    // being attached to the solved grid). When SH was requested but the
    // pre-fill didn't find a valid motif, the flow falls back to
    // classic.
    final shAttached = pu.constraints.any((c) => c.slug == 'SH');
    // `bb` requires that `preFillBB` actually attached a BB constraint; when
    // BB was requested but nothing attached, the flow falls back to classic.
    final bbAttached = pu.constraints.any((c) => c.slug == 'BB');
    pu.generationScenario = config.pathBasedScenario
        ? 'pathBased'
        : (hasSH && shAttached)
        ? 'sh'
        : (hasBB && bbAttached)
        ? 'bb'
        : 'classic';

    // Post-loop cleanup: the cheap-tier accept signal in phase 1 is
    // laxer than the strict `ratioAfter < ratioBefore` check, so the
    // loop may have accepted constraints whose contribution is
    // subsumed by peers accepted later (or by the fill-from-solution
    // hints we just placed). `removeUselessRules` walks the
    // constraints last-to-first and drops any whose absence still
    // leaves `isDeductivelyUnique()` true.
    //
    // Skipped for `singleTier`: that strategy uses the strict accept
    // criterion throughout, so over-accept is structurally impossible
    // and the N-solves cleanup would be pure overhead.
    if (config.strategy != GenerationStrategy.singleTier) {
      // Preserve the constructive LT backbone: those LTs are the puzzle's
      // structural identity and must survive even when made redundant by
      // greedy-added garde-fous.
      pu.removeUselessRules(
        preserveSlugs: config.pathBasedScenario ? const {'LT'} : const {},
        shouldStop: shouldStop,
      );
    }

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
    // `shouldStop` is propagated so the finalisation trace can be cut
    // short on a budget hit instead of letting one pathological trace
    // burn through the per-attempt deadline.
    final steps = pu.solveExplained(shouldStop: shouldStop);
    if (steps.isEmpty && shouldStop?.call() == true) {
      onReject?.call(GenerationRejectReason.cancelled, pu);
      return null;
    }
    final replay = pu.clone();
    for (final s in steps) {
      if (s.value != null) {
        replay.setValue(s.cellIdx, s.value!);
      } else if (s.removeOption != null) {
        replay.removeOption(s.cellIdx, s.removeOption!);
      }
    }
    final isUnique = replay.complete && replay.check(saveResult: false).isEmpty;
    onLog?.call(
      'phase8 solveExplained: steps=${steps.length} unique=$isUnique '
      'solveExplained=${solveExplainedMs}ms phaseTotal=${phaseDelta()}ms',
    );
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
          level == PuzzleLevel.overfilledPlayer ||
          level == PuzzleLevel.overfilledAdvanced ||
          level == PuzzleLevel.overfilledStrong ||
          level == PuzzleLevel.overfilledExpert ||
          level == PuzzleLevel.overfilledMad ||
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
      // Skipped in boss mode: large grids accept verbose constraint
      // sets, and the sort cost is non-negligible on 30×20+.
      if (simplifyResult != null) {
        pu.sortConstraintsByDifficulty(simplifyResult.finalSteps);
        autoShrinkDomain(pu, replay);
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
    autoShrinkDomain(pu, replay);

    return (line: pu.lineExport(), level: level);
  }

  /// Auto-shrink the declared domain. When the validated solution never
  /// uses a colour, and no constraint references it explicitly, the
  /// puzzle is functionally a smaller-domain puzzle — saving it with
  /// the original (larger) domain would expose a never-used colour to
  /// the play UI (option dots, incrValue cycle). For `--domain 3` runs
  /// this auto-promotes purely-2-colour outcomes back to `12`.
  ///
  /// [pu] is the puzzle about to be exported; [replay] is the solved
  /// puzzle whose `cellValues` give the validated solution. Public so the
  /// shrink logic can be unit-tested in isolation; [generateOne] calls it
  /// on both export paths just before `lineExport`.
  static void autoShrinkDomain(Puzzle pu, Puzzle replay) {
    final usedColours = <CellValue>{};
    for (final v in replay.cellValues) {
      if (v != CellValue.free) usedColours.add(v);
    }
    final referencedColours = <CellValue>{};
    for (final c in pu.constraints) {
      referencedColours.addAll(c.referencedColors);
    }
    final keep = {...usedColours, ...referencedColours};
    final shrunkDomain = pu.domain.where(keep.contains).toList();
    if (shrunkDomain.length < pu.domain.length) {
      pu.domain = shrunkDomain;
      for (final cell in pu.cells) {
        cell.domain = shrunkDomain;
      }
      // Reset the complexity cache: the shrunken domain gives slightly
      // different propagation behaviour and the cache would otherwise
      // reflect the wrong domain.
      pu.cachedComplexity = null;
    }
  }

  /// Serialised-key set of constraint candidates that, when added,
  /// touch (and are therefore likely to determine) one of the
  /// [undetermined] cells. Covers the four slugs whose per-cell effect
  /// is enumerable in closed form from the solved grid:
  ///   * DF — pairs anchored on or adjacent to the cell.
  ///   * NC — anchored at a neighbour of the cell, so the cell is in
  ///     the anchor's neighbourhood and the NC count enforces it.
  ///   * CC / RC — the unique line constraint for the cell's column
  ///     or row.
  /// Other slugs (FM, PA, GS, LT, SH, GC, SY, QA, EY) have effects
  /// that depend on global state in ways `solvedValues` alone can't
  /// score; they fall back to the usage-based ordering. The returned
  /// strings are matched against `Constraint.serialize()` — only
  /// candidates that are already in `allConstraints` benefit, but the
  /// initial enumeration is exhaustive so every targeted key has a
  /// matching candidate (modulo prior accept-time pruning of CC/RC).
  static Set<String> _generateTargetedKeys({
    required List<int> undetermined,
    required List<CellValue> solvedValues,
    required int width,
    required int height,
    required List<CellValue> domain,
  }) {
    final result = <String>{};
    for (final cellIdx in undetermined) {
      final col = cellIdx % width;
      final row = cellIdx ~/ width;

      // DF: pairs anchored on cellIdx (right/down) or whose right/down
      // neighbour IS cellIdx. Each is valid only when the pair's two
      // solved values differ.
      if (col < width - 1 &&
          solvedValues[cellIdx] != solvedValues[cellIdx + 1]) {
        result.add('DF:$cellIdx.right');
      }
      if (row < height - 1 &&
          solvedValues[cellIdx] != solvedValues[cellIdx + width]) {
        result.add('DF:$cellIdx.down');
      }
      if (col > 0 && solvedValues[cellIdx - 1] != solvedValues[cellIdx]) {
        result.add('DF:${cellIdx - 1}.right');
      }
      if (row > 0 && solvedValues[cellIdx - width] != solvedValues[cellIdx]) {
        result.add('DF:${cellIdx - width}.down');
      }

      // NC anchored at each orthogonal neighbour Y of cellIdx: the
      // constraint reads "Y has N <colour> neighbours" and cellIdx is
      // one of those neighbours, so the count directly constrains
      // cellIdx's value (jointly with Y's other neighbours).
      final ncAnchors = <int>[];
      if (col > 0) ncAnchors.add(cellIdx - 1);
      if (col < width - 1) ncAnchors.add(cellIdx + 1);
      if (row > 0) ncAnchors.add(cellIdx - width);
      if (row < height - 1) ncAnchors.add(cellIdx + width);
      for (final y in ncAnchors) {
        final yCol = y % width;
        final yRow = y ~/ width;
        final yNeighbours = <int>[];
        if (yCol > 0) yNeighbours.add(y - 1);
        if (yCol < width - 1) yNeighbours.add(y + 1);
        if (yRow > 0) yNeighbours.add(y - width);
        if (yRow < height - 1) yNeighbours.add(y + width);
        for (final c in domain) {
          final count = yNeighbours.where((n) => solvedValues[n] == c).length;
          result.add('NC:$y.${cellValueToString(c)}.$count');
        }
      }

      // CC for cellIdx's column. Compute the per-colour count from
      // the solved grid; only that count is consistent with the
      // solution (any other count would fail `verify`).
      for (final c in domain) {
        var count = 0;
        for (int rIter = 0; rIter < height; rIter++) {
          if (solvedValues[rIter * width + col] == c) count++;
        }
        result.add('CC:$col.${cellValueToString(c)}.$count');
      }

      // RC mirror for cellIdx's row.
      for (final c in domain) {
        var count = 0;
        for (int cIter = 0; cIter < width; cIter++) {
          if (solvedValues[row * width + cIter] == c) count++;
        }
        result.add('RC:$row.${cellValueToString(c)}.$count');
      }
    }
    return result;
  }

  /// Experimental "seed-and-grow" prefill used for large "Boss" grids.
  ///
  /// Phase 1 (until ~70% of cells are filled): plant seeds — choose an
  /// empty cell weighted by Chebyshev distance to the nearest edge AND to
  /// the nearest already-filled cell (so seeds spread away from borders
  /// and from each other). Assign a random color and a target group size
  /// in [_bossMinGroupSize, _bossMaxGroupSize], then grow the seed by
  /// painting random free neighbours until the target is reached (or the
  /// group runs out of free neighbours).
  ///
  /// Phase 2 (remaining ~30%): paint every still-empty cell with a random
  /// colour. This can grow some of the seeded groups (when the random
  /// colour matches a neighbouring seeded group's colour). Then, for each
  /// seeded pivot, recompute the actual final group size and post a
  /// `GroupSize` constraint reflecting reality — so the player still has
  /// the deductive pressure of a known group size, just with the
  /// final-after-fill value.
  ///
  /// Phase 3 (in `generateOne`, unchanged): the standard iterative loop
  /// adds more constraints until the puzzle is uniquely deductive.
  ///
  /// Debug: dumps the post-prefill state to `/tmp/boss_prefill_<ts>.txt`
  /// so we can inspect blob shapes visually before phase 3 runs. To be
  /// removed (or gated behind a debug flag) once the algorithm is
  /// validated — see plan "Hors scope".
  static Puzzle _preFillBoss(int width, int height) {
    const fillRatio = 0.70;
    const minGroupSize = 15;
    const maxGroupSize = 25;
    // After phase 2a's random fill, many seeds end up sharing the same
    // connected component (their identical-colour blobs merge through the
    // random fill). Posting one GS per seed in that case yields N copies
    // of the same "this component has size K" statement. We cap the
    // number of GS constraints that can target the same component to
    // [maxSameGroup] to keep the constraint set lean.
    const maxSameGroup = 3;

    final solved = Puzzle.empty(width, height, _defaultDomain);
    final size = width * height;
    final targetFilled = (size * fillRatio).round();

    // Distance to the nearest edge in Chebyshev metric: 0 on the border,
    // grows toward the centre. Used as the seed-weight floor.
    int distToEdge(int idx) {
      final x = idx % width;
      final y = idx ~/ width;
      return min(min(x, width - 1 - x), min(y, height - 1 - y));
    }

    // BFS-based Chebyshev distance from every cell to the nearest filled
    // cell. Recomputed before each seed (cheap: O(size)). Empty grid →
    // returns -1 everywhere, signaling "no constraint from this term".
    List<int> distToFilled() {
      final dist = List<int>.filled(size, -1);
      final queue = <int>[];
      for (int i = 0; i < size; i++) {
        if (solved.cells[i].value != 0) {
          dist[i] = 0;
          queue.add(i);
        }
      }
      if (queue.isEmpty) return dist;
      // BFS in Chebyshev metric: include the 4 axis neighbours plus the 4
      // diagonals so the metric matches `distToEdge`.
      int head = 0;
      while (head < queue.length) {
        final cur = queue[head++];
        final cx = cur % width;
        final cy = cur ~/ width;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx;
            final ny = cy + dy;
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            final nIdx = ny * width + nx;
            if (dist[nIdx] != -1) continue;
            dist[nIdx] = dist[cur] + 1;
            queue.add(nIdx);
          }
        }
      }
      return dist;
    }

    // Pick a free cell with weight = min(distToEdge, distToFilled). +1 so
    // border cells still have a tiny chance to be picked — pure 0 would
    // make the first growth step on an edge-only board impossible.
    int? pickSeed() {
      final dEdge = List<int>.generate(size, distToEdge);
      final dFilled = distToFilled();
      final weights = List<double>.filled(size, 0);
      double total = 0;
      for (int i = 0; i < size; i++) {
        if (solved.cells[i].value != 0) continue;
        final fillTerm = dFilled[i] == -1 ? dEdge[i] : dFilled[i];
        // +1 to keep weights strictly positive for free cells.
        final w = (min(dEdge[i], fillTerm) + 1).toDouble();
        weights[i] = w;
        total += w;
      }
      if (total <= 0) return null;
      var r = _rng.nextDouble() * total;
      for (int i = 0; i < size; i++) {
        if (weights[i] == 0) continue;
        r -= weights[i];
        if (r <= 0) return i;
      }
      // Floating-point edge case: fall through to last positive-weight cell.
      for (int i = size - 1; i >= 0; i--) {
        if (weights[i] > 0) return i;
      }
      return null;
    }

    int filled = 0;
    // Tracks seeded pivots → final colour. Phase 2 posts a `GroupSize`
    // per entry using the post-fill actual group size, so growth during
    // the random-fill step is absorbed into the constraint value rather
    // than violating it.
    final List<({int pivot, int color})> seeds = [];

    // Phase 1: plant seeds and grow.
    while (filled < targetFilled) {
      final seed = pickSeed();
      if (seed == null) break;
      final color = _defaultDomain[_rng.nextInt(_defaultDomain.length)];
      final target =
          minGroupSize + _rng.nextInt(maxGroupSize - minGroupSize + 1);
      solved.cells[seed].setForSolver(color);
      filled++;
      seeds.add((pivot: seed, color: color));
      final groupCells = <int>[seed];

      while (groupCells.length < target) {
        // Collect free 4-neighbours of every cell in the current group.
        final frontier = <int>{};
        for (final c in groupCells) {
          for (final n in solved.getNeighbors(c)) {
            if (solved.cells[n].value == 0) frontier.add(n);
          }
        }
        if (frontier.isEmpty) break;
        final frontierList = frontier.toList();
        final pick = frontierList[_rng.nextInt(frontierList.length)];
        solved.cells[pick].setForSolver(color);
        groupCells.add(pick);
        filled++;
        if (filled >= size) break;
      }
      if (filled >= size) break;
    }

    // Phase 2a: random-fill the remaining ~30%.
    for (int i = 0; i < size; i++) {
      if (solved.cells[i].value != 0) continue;
      solved.cells[i].setForSolver(
        _defaultDomain[_rng.nextInt(_defaultDomain.length)],
      );
    }

    // Phase 2b: post one `GroupSize` per seed, using the post-fill actual
    // size of the connected same-colour blob anchored at the pivot. We
    // walk the connected component directly (BFS over same-colour
    // 4-neighbours) rather than calling `getGroups()` — we only need one
    // group per pivot, and `getMyColorGroup` is just 1-ring deep.
    //
    // Components are identified by their smallest cell index (canonical
    // pivot). We cap GS constraints per component at `maxSameGroup` to
    // avoid posting N redundant copies of the same statement when several
    // seeds collapsed into one component during phase 2a.
    final componentCounts = <int, int>{};
    for (final seed in seeds) {
      final pivot = seed.pivot;
      final color = solved.cells[pivot].value;
      final visited = <int>{pivot};
      final stack = <int>[pivot];
      int canonical = pivot;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        if (cur < canonical) canonical = cur;
        for (final n in solved.getNeighbors(cur)) {
          if (visited.contains(n)) continue;
          if (solved.cells[n].value != color) continue;
          visited.add(n);
          stack.add(n);
          if (n < canonical) canonical = n;
        }
      }
      final count = componentCounts[canonical] ?? 0;
      if (count >= maxSameGroup) continue;
      componentCounts[canonical] = count + 1;
      solved.addConstraint(GroupSize('$pivot.${visited.length}'));
    }

    return solved;
  }
}
