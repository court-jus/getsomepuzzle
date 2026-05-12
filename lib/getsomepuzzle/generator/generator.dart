import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/motif.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
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
  final int count;

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
    this.domain = defaultDomain,
    this.strategy = GenerationStrategy.phaseGate,
    this.maxStall = const Duration(seconds: 15),
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

/// Why a `generateOne` attempt was discarded. Surfaced through the
/// `onReject` callback so callers (CLI dashboard, tests) can attribute
/// failures and tune the pipeline. `shouldStop` is NOT a rejection —
/// it's a graceful cancellation and doesn't fire this callback.
enum GenerationRejectReason {
  /// `generateAllParameters` produced no valid constraints for the
  /// pre-filled grid. Almost never happens on real configs; usually
  /// signals a too-tight `allowedSlugs` filter.
  noConstraints,

  /// User passed `--require X,Y` but the iterative loop didn't pick at
  /// least one constraint per required slug. Strict filter — re-rolling
  /// the prefill / order eventually surfaces the right candidate.
  requiredRulesMissing,

  /// After the final `solve()` (propagation + force), more than 25% of
  /// the grid stayed free — the puzzle would need too many extra
  /// readonly cells to be playable. Typically the iterative loop didn't
  /// accept enough constraints to drive the deduction chain.
  ratioTooHigh,

  /// No-progress watchdog tripped: the iterative loop went `maxStall`
  /// without an acceptance, so the attempt was abandoned to free the
  /// worker for fresher attempts. Observed empirically on hard
  /// equilibrium targets where one attempt would otherwise eat
  /// minutes of CPU at a plateau ratio. See `GeneratorConfig.maxStall`.
  attemptStalled,
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
    void Function(GenerationRejectReason)? onReject,
    bool Function()? shouldStop,
    Map<String, int>? usageStats,
    void Function(Map<String, int> micros, Map<String, int> calls)? onTimings,
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
    void Function(GenerationRejectReason)? onReject,
    bool Function()? shouldStop,
    Map<String, int>? usageStats,
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
    final width = config.width;
    final height = config.height;
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
    // paints a valid Shape motif so the SH constraint is satisfiable.
    final hasSH = prioritySlugs.contains("SH");
    final solved = hasSH
        ? _preFillSh(width, height, domain)
        : _preFillRegular(width, height, domain);
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
    tPrefill.exit();

    tInitConstraints.enter();
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
      }
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
      tInitConstraints.exit();
      onReject?.call(GenerationRejectReason.noConstraints);
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
      if (shouldStop?.call() == true) return null;

      // Phase-specific exit: phase 1 ends when propagation alone
      // closes the puzzle; phase 2 ends when full solve does.
      if (phase == 1 && cachedPropFreeCells == 0) break;
      if (phase == 2 && currentRatio == 0) break;
      // Common exit: nothing left to try.
      if (allConstraints.isEmpty && secondChance.isEmpty) break;

      bool found = false;
      while (allConstraints.isNotEmpty) {
        // Re-check shouldStop inside the inner loop so a long candidate
        // sweep honours the deadline within seconds rather than waiting
        // for the next outer iteration.
        if (shouldStop?.call() == true) return null;
        // No-progress watchdog. Checked before incrementing `tried` so
        // a single super-slow candidate test (e.g. a 30 s full solve
        // on a hard 3-colour grid) can't single-handedly trip it; the
        // window is consumed by lack-of-progress, not by a slow tick.
        if (watchdogEnabled &&
            attemptSw.elapsedMilliseconds - lastAcceptMs > maxStallMs) {
          onReject?.call(GenerationRejectReason.attemptStalled);
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
          // baseline). No cheap probe — `cloned.solve()` does
          // propagation + force from scratch.
          tLoopCandidateFull.enter();
          cloned.solve();
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
        final aTargeted = targetedKeys.contains(a.serialize()) ? -1 : 0;
        final bTargeted = targetedKeys.contains(b.serialize()) ? -1 : 0;
        if (aTargeted != bTargeted) return aTargeted.compareTo(bTargeted);
        return (localUsage[a.slug] ?? 0).compareTo(localUsage[b.slug] ?? 0);
      });
      tLoopSort.exit();
    }

    // Strictly enforce the user-facing required rules (CLI `--require`).
    // Target-pushed `preferredSlugs` are NOT enforced here — if the iterative
    // loop never picked them, the puzzle is still credited to whatever bin it
    // actually falls in (cross-axis recycling).
    if (config.requiredRules.isNotEmpty) {
      final presentSlugs = pu.constraints.map((c) => c.slug).toSet();
      if (!config.requiredRules.every((r) => presentSlugs.contains(r))) {
        onReject?.call(GenerationRejectReason.requiredRulesMissing);
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
      onReject?.call(GenerationRejectReason.ratioTooHigh);
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
      tCleanup.enter();
      pu.removeUselessRules();
      tCleanup.exit();
    }

    // `solveExplained` is needed for the trace the classifier consumes.
    // The trace is also what makes `pu` "solvable" from a player's
    // perspective; we trust it reaches completion because `solve()`
    // does on the same state.
    tSolveExplained.enter();
    final steps = pu.solveExplained();
    tSolveExplained.exit();

    tClassify.enter();
    final prefill = pu.cells.where((c) => c.readonly).length / pu.cells.length;
    final level = classifyTrace(
      steps: steps,
      prefillRatio: prefill,
      solved: true,
    );
    tClassify.exit();

    tShrink.enter();
    // Auto-shrink the declared domain. When the validated solution never
    // uses a colour, and no constraint references it explicitly, the
    // puzzle is functionally a smaller-domain puzzle — saving it with
    // the original (larger) domain would expose a never-used colour to
    // the play UI (option dots, incrValue cycle). For `--domain 3`
    // runs this auto-promotes purely-2-colour outcomes back to `12`.
    // `solvedValues` is the full solution grid built at step 1; it has
    // every cell set, so the unused-colour check sees the complete
    // colour palette of the validated puzzle.
    final usedColours = <CellValue>{};
    for (final v in solvedValues) {
      if (v != CellValue.free) usedColours.add(v);
    }
    final referencedColours = <CellValue>{};
    for (final c in pu.constraints) {
      referencedColours.addAll(_colorsReferencedBy(c));
    }
    final keep = {...usedColours, ...referencedColours};
    final shrunkDomain = pu.domain.where(keep.contains).toList();
    if (shrunkDomain.length < pu.domain.length) {
      pu.domain = shrunkDomain;
      for (final cell in pu.cells) {
        cell.domain = shrunkDomain;
      }
      // Complexity was not yet computed for this puzzle, but reset the
      // cache anyway in case a future caller adds an intermediate
      // computeComplexity() before lineExport() — the shrunken domain
      // gives slightly different propagation behaviour and the cache
      // would otherwise reflect the wrong domain.
      pu.cachedComplexity = null;
    }
    tShrink.exit();

    tExport.enter();
    final line = pu.lineExport();
    tExport.exit();
    return (line: line, level: level);
  }

  /// Colours referenced by [c] either directly (the `color` field of a
  /// quantity-style constraint) or implicitly (the non-free values in an
  /// FM/SH motif). Used by the auto-shrink pass to decide whether a
  /// colour that is absent from the solution can also be dropped from
  /// the puzzle's declared domain without orphaning a constraint.
  /// Constraints with no colour reference (`PA`, `GS`, `LT`, `DF`, `SY`)
  /// contribute the empty set.
  static Set<CellValue> _colorsReferencedBy(Constraint c) {
    if (c is LineCentricConstraint) return {c.color};
    if (c is GroupCountConstraint) return {c.color};
    if (c is NeighborCountConstraint) return {c.color};
    if (c is EyesConstraint) return {c.color};
    if (c is QuantityConstraint) return {c.color};
    if (c is ShapeConstraint) return {c.color};
    if (c is ForbiddenMotif) {
      final colors = <CellValue>{};
      for (final row in c.motif) {
        for (final v in row) {
          if (v != CellValue.free) colors.add(v);
        }
      }
      return colors;
    }
    return const {};
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

  static Puzzle _preFillSh(int width, int height, List<CellValue> domain) {
    final solved = Puzzle.empty(width, height, domain);
    final chosenMotif = _pickShapeMotif(width, height, domain);
    final sc = ShapeConstraint(chosenMotif);
    _placeInitialVariant(solved, sc);
    _fillRemainingWithOpposite(solved, sc.color, domain);
    solved.addConstraint(sc);
    _placeAdditionalVariants(solved);
    return solved;
  }

  /// Pick one motif string via weighted random sampling, where the weight
  /// depends on the motif's bounding-box size (`rows × cols`).
  static String _pickShapeMotif(int width, int height, List<CellValue> domain) {
    final possibleMotifs = ShapeConstraint.generateAllParameters(
      width,
      height,
      domain,
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

  /// Fill every still-free cell of [solved] with a random opposite color
  /// drawn from [domain].
  static void _fillRemainingWithOpposite(
    Puzzle solved,
    CellValue color,
    List<CellValue> domain,
  ) {
    final opposite = domain.whereNot((i) => i == color).shuffled().first;
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
    List<List<CellValue>> variant,
    int rowOffset,
    int colOffset,
  ) {
    for (final (ridx, row) in variant.indexed) {
      for (final (cidx, value) in row.indexed) {
        if (value == CellValue.free) continue;
        solved.cells[(ridx + rowOffset) * solved.width + (cidx + colOffset)]
            .setForSolver(value);
      }
    }
  }

  static Puzzle _preFillRegular(int width, int height, List<CellValue> domain) {
    final solved = Puzzle.empty(width, height, domain);
    final size = solved.width * solved.height;
    for (int i = 0; i < size; i++) {
      solved.cells[i].setForSolver(domain[_rng.nextInt(domain.length)]);
    }
    return solved;
  }
}
