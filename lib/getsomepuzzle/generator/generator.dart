import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/registry.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
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

  /// Use the experimental "seed-and-grow" prefill instead of the default
  /// random/SH prefill. Targets large grids ("Boss" levels): plants seed
  /// cells weighted toward the grid centre, grows each one into a group
  /// of 15–25 cells, then random-fills the remaining ~30% and posts a
  /// GS constraint per seeded group with its final size.
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
    this.count = 1,
    this.targetLevel,
    this.easingBudget = const Duration(seconds: 30),
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
    void Function(String message)? onLog,
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
    // paints a valid Shape motif so the SH constraint is satisfiable. The
    // experimental "Boss" prefill (seed-and-grow) takes precedence when the
    // caller requested it via `useBossPrefill` — it produces large coherent
    // blobs instead of white-noise random fill, which matters at 30×20+
    // grid sizes.
    final hasSH = prioritySlugs.contains("SH");
    final Puzzle solved;
    final String prefillKind;
    if (config.useBossPrefill) {
      prefillKind = 'boss';
      solved = _preFillBoss(width, height);
    } else if (hasSH) {
      prefillKind = 'sh';
      solved = _preFillSh(width, height);
    } else {
      prefillKind = 'regular';
      solved = _preFillRegular(width, height);
    }
    onLog?.call(
      'phase1 prefill=$prefillKind ${width}x$height done in ${phaseDelta()}ms',
    );
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
          (generateAllParameters(
                  slug,
                  width,
                  height,
                  _defaultDomain,
                  slug == 'DF' ? readonlyIndices : null,
                ) ??
                [])
            ..shuffle(_rng);
      final paramCount = params.length;
      onLog?.call(
        '  [$slug] generateAllParameters → $paramCount params (shuffled) '
        '(${slugSw.elapsedMilliseconds}ms)',
      );
      int kept = 0;
      final logEvery = paramCount < 20 ? paramCount : (paramCount / 10).ceil();
      int nextLogAt = logEvery;
      int i = 0;
      while (i < paramCount && kept < maxConstraintParameters) {
        if (i >= nextLogAt) {
          final pct = (i * 100 / paramCount).toStringAsFixed(0);
          onLog?.call(
            '  [$slug] verify $pct% ($i/$paramCount kept=$kept '
            'elapsed=${slugSw.elapsedMilliseconds}ms)',
          );
          nextLogAt += logEvery;
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

    // 4. Iteratively add constraints that improve the puzzle.
    //
    // `currentRatio` here is the *pre-solve* ratio — it counts only
    // the cells that already have a value (readonly prefill cells),
    // not what propagation could deduce. It's expected to start
    // close to 1.0 on big grids; the first batch's solveBefore will
    // give the post-propagation baseline.
    var currentRatio = pu.computeRatio();
    int tried = 0;
    onLog?.call(
      'phase4 start: ${allConstraints.length} candidates, '
      'pre-solve ratio=${currentRatio.toStringAsFixed(3)} '
      '(=${(currentRatio * size).round()}/$size cells still free)',
    );
    int lastLoggedTried = 0;

    // Tries to refill `allConstraints` from per-slug reserves, then
    // re-shuffles and re-sorts using the current puzzle's slug usage.
    // Returns `true` iff at least one candidate is now available.
    bool tryRefillAndResort() {
      if (!refillFromReserve()) return false;
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
      onLog?.call(
        '  phase4 refilled: ${allConstraints.length} candidates available',
      );
      return true;
    }

    // Boss-only: batch addition + incremental `bossSolvedState`.
    //
    // Standard mode tests candidates one by one (2 solves per
    // candidate: baseline then with-candidate). On 30×20+ each solve
    // is expensive, so for boss puzzles we group candidates by
    // batches of `addConstraintsInBatch`. The trade-off is verbosity
    // (the final puzzle may carry some "passenger" constraints that
    // weren't strictly needed for the gain). Acceptable for boss
    // because the project's cleanup pass
    // (`sortConstraintsByDifficulty`) is also skipped in this mode —
    // boss puzzles are not asked to be minimal.
    //
    // Additional optimisation: deductive propagation is monotone — a
    // cell value deduced from constraint set C₁ remains valid for any
    // superset C₁∪C₂. So instead of re-cloning `pu` (back to readonly-
    // only cells) and re-solving from scratch on every batch, we keep
    // a `bossSolvedState` that holds the cumulative post-propagation
    // state. Each batch is tested on a clone of that state; on accept
    // the clone (already post-propagation) is promoted to the new
    // state. Saves one full `solve()` per batch.
    //
    // `maxConsecutiveFailedBatches` is the anti-infinite-loop guard:
    // after that many rejected batches in a row (no improvement at
    // all), we try to refill from the per-slug reserves; if reserves
    // are empty too, we give up.
    const addConstraintsInBatch = 30;
    const maxConsecutiveFailedBatches = 20;
    int consecutiveFailures = 0;

    // Initialise `bossSolvedState` once, with the single constraint
    // added before the loop. From now on it tracks `pu.constraints`
    // exactly, plus its own propagated cell values.
    Puzzle? bossSolvedState;
    if (config.useBossPrefill) {
      bossSolvedState = pu.clone();
      final initSw = Stopwatch()..start();
      bossSolvedState.solve(tryForce: false);
      currentRatio = bossSolvedState.computeRatio();
      onLog?.call(
        'phase4 boss: initial solvedState '
        'ratio=${currentRatio.toStringAsFixed(3)} '
        'filled=${bossSolvedState.cells.where((c) => c.value != 0).length}/$size '
        'in ${initSw.elapsedMilliseconds}ms',
      );
    }

    while (currentRatio > 0) {
      if (shouldStop?.call() == true) {
        onReject?.call(GenerationRejectReason.cancelled, pu);
        return null;
      }

      if (allConstraints.isEmpty) {
        if (!tryRefillAndResort()) break;
      }

      if (config.useBossPrefill) {
        // ─── Batch path (boss) ──────────────────────────────────────
        final batchSize = min(addConstraintsInBatch, allConstraints.length);
        final batch = allConstraints.sublist(0, batchSize);
        allConstraints.removeRange(0, batchSize);
        // `scanned` counts candidates *queued for testing* so far, not
        // candidates we've already proven useful — the solves below
        // haven't run yet at this point.
        tried += batchSize;
        onProgress?.call(
          GeneratorProgress(
            puzzlesGenerated: 0,
            totalRequested: config.count,
            constraintsTried: tried,
            constraintsTotal: total,
            currentRatio: currentRatio,
          ),
        );

        final batchSw = Stopwatch()..start();
        // Clone the cumulative solved state (not `pu`!) so the new
        // batch starts from cells already deduced by previously
        // accepted constraints. Saves one full re-propagation per
        // batch. Monotonicity guarantees this is sound: adding
        // constraints never invalidates a deduction.
        final cloned = bossSolvedState!.clone();
        final cloneMs = batchSw.elapsedMilliseconds;

        // Live solve instrumentation. Throttled so we don't get one
        // log line per iter (200 max per solve). Logs at most every
        // 10 iters AND every 500ms. Also always logs the final iter
        // (break point) so we can see why the solve stopped.
        int lastLogIter = -1;
        int lastLogMs = 0;
        void Function(int, int, bool) iterLogger(Stopwatch sw) {
          int cumFindMs = 0;
          return (int iter, int findMs, bool moveTaken) {
            cumFindMs += findMs;
            final now = sw.elapsedMilliseconds;
            final shouldLog =
                !moveTaken ||
                (iter - lastLogIter >= 10 && now - lastLogMs >= 500);
            if (shouldLog) {
              final filled = cloned.cells.where((c) => c.value != 0).length;
              onLog?.call(
                '    [solve] iter=$iter findAMove=${findMs}ms '
                'cumFind=${cumFindMs}ms elapsed=${now}ms '
                'filled=$filled/$size moveTaken=$moveTaken',
              );
              lastLogIter = iter;
              lastLogMs = now;
            }
          };
        }

        // Boss mode = propagation-only. The force fallback
        // (`_forceOneCell`) is O(freeCells × |domain|) clones-per-call
        // — wall-clock explodes immediately on big grids.
        //
        // We compare ratio against `currentRatio` (= the cumulative
        // post-propagation ratio after previously accepted batches),
        // not a freshly computed baseline. One solve per batch instead
        // of two.
        for (final c in batch) {
          cloned.addConstraint(c);
        }
        batchSw.reset();
        batchSw.start();
        lastLogIter = -1;
        lastLogMs = 0;
        cloned.solve(tryForce: false, onIter: iterLogger(batchSw));
        final solveMs = batchSw.elapsedMilliseconds;
        final ratioAfter = cloned.computeRatio();

        final decision = ratioAfter < currentRatio ? 'ACCEPT' : 'reject';
        onLog?.call(
          '  phase4 batch=$batchSize scanned=$tried '
          'pu_constraints=${pu.constraints.length} '
          'clone=${cloneMs}ms solve=${solveMs}ms '
          'r:${currentRatio.toStringAsFixed(3)}→${ratioAfter.toStringAsFixed(3)} '
          '→ $decision '
          'remaining=${allConstraints.length} '
          'reserves=${reserveParams.length}',
        );
        lastLoggedTried = tried;

        if (ratioAfter < currentRatio) {
          for (final c in batch) {
            pu.addConstraint(c);
          }
          // Promote the just-solved clone as the new cumulative state
          // — no additional solve needed.
          bossSolvedState = cloned;
          currentRatio = ratioAfter;
          consecutiveFailures = 0;
          // Re-shuffle remaining so the next batch is a fresh draw.
          allConstraints.shuffle(_rng);
        } else {
          // Batch didn't help — return its constraints to the pool
          // and reshuffle so the next batch is a different draw.
          // `bossSolvedState` stays untouched: rejected constraints
          // had no effect on it.
          allConstraints.addAll(batch);
          allConstraints.shuffle(_rng);
          consecutiveFailures++;
          if (consecutiveFailures >= maxConsecutiveFailedBatches) {
            onLog?.call(
              '  phase4 stuck after $consecutiveFailures rejected batches, '
              'attempting refill...',
            );
            if (!tryRefillAndResort()) break;
            consecutiveFailures = 0;
          }
        }
        continue;
      }

      // ─── Single-candidate path (standard, unchanged) ──────────────
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
          onLog?.call(
            '  phase4 ACCEPT slug=${constraint.slug} '
            'tried=$tried accepted=${pu.constraints.length} '
            'ratio=${currentRatio.toStringAsFixed(3)} '
            'remaining=${allConstraints.length}',
          );
          lastLoggedTried = tried;
          break;
        }
      }

      if (!found) {
        // Burned through the current batch without improvement. Try
        // pulling another batch from reserves; if none, we're done.
        if (!tryRefillAndResort()) break;
        continue;
      }

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

    // Compute the solved ratio (not the raw pre-filled ratio).
    //
    // In boss mode this whole pass is redundant: `bossSolvedState` is
    // already the post-propagation state for `pu.constraints` and we
    // already know `currentRatio` matches it. We just reuse it instead
    // of cloning + re-solving 600 cells.
    final Puzzle solvedPu;
    if (config.useBossPrefill && bossSolvedState != null) {
      solvedPu = bossSolvedState;
      currentRatio = bossSolvedState.computeRatio();
      onLog?.call(
        'phase6 (boss): reusing bossSolvedState '
        'ratio=${currentRatio.toStringAsFixed(3)} '
        'pu_constraints=${pu.constraints.length} '
        'phaseTotal=${phaseDelta()}ms',
      );
    } else {
      solvedPu = pu.clone();
      final phase6Sw = Stopwatch()..start();
      solvedPu.solve(tryForce: !config.useBossPrefill);
      final phase6SolveMs = phase6Sw.elapsedMilliseconds;
      currentRatio = solvedPu.computeRatio();
      onLog?.call(
        'phase6 deductive solve: ratio=${currentRatio.toStringAsFixed(3)} '
        'solve=${phase6SolveMs}ms pu_constraints=${pu.constraints.length} '
        'phaseTotal=${phaseDelta()}ms',
      );
    }
    if (currentRatio > 0.25) {
      onReject?.call(GenerationRejectReason.ratioTooHigh, pu);
      return null;
    }

    if (currentRatio > 0) {
      // Fill remaining cells from solution. In boss mode `solvedPu` is
      // `bossSolvedState` itself — no need to re-clone-and-solve.
      final Puzzle reference;
      if (config.useBossPrefill && bossSolvedState != null) {
        reference = bossSolvedState;
      } else {
        reference = pu.clone();
        reference.solve(tryForce: !config.useBossPrefill);
      }
      for (final (_, idx) in reference.freeCells()) {
        pu.cells[idx].setForSolver(solvedValues[idx]);
        pu.cells[idx].readonly = true;
      }
    }

    // Project-wide validity convention: a puzzle is valid iff `solve()`
    // (propagation + force, no backtracking) reaches the unique completion
    // from its readonly cells. This guarantees the player can solve it
    // with the in-game hint system, which uses the same `solve()` engine.
    //
    // We use `solveExplained` rather than `isDeductivelyUnique`/`solve`
    // because the trace it produces is also what the level classifier
    // needs — running both would mean two solves for the same answer.
    //
    // In boss mode we propagate-only here too — force is intractable on
    // 30×20 (see batch loop comments above). Trace will only contain
    // propagation steps, and the puzzle is accepted iff propagation
    // alone closes it.
    final phase8Sw = Stopwatch()..start();
    final steps = pu.solveExplained(tryForce: !config.useBossPrefill);
    final solveExplainedMs = phase8Sw.elapsedMilliseconds;
    final replay = pu.clone();
    for (final s in steps) {
      replay.setValue(s.cellIdx, s.value);
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
        simplifyResult = pu.simplify(
          targetLevel: target,
          maxTime: config.easingBudget,
          allowedSlugs: config.allowedSlugs,
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
        if (!config.useBossPrefill) {
          pu.sortConstraintsByDifficulty(simplifyResult.finalSteps);
        }
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
    //
    // Boss mode skips this final sort entirely: with batch addition
    // the constraint set can carry "passenger" constraints we don't
    // want to spend cycles reordering, and boss puzzles aren't held
    // to the easier-first invariant.
    if (!config.useBossPrefill) {
      pu.sortConstraintsByDifficulty(steps);
    }

    return (line: pu.lineExport(), level: level);
  }

  static Puzzle _preFillSh(int width, int height) {
    final solved = Puzzle.empty(width, height, _defaultDomain);
    final chosenMotif = _pickShapeMotif(width, height);
    final sc = ShapeConstraint(chosenMotif);
    _placeInitialVariant(solved, sc);
    _fillRemainingWithOpposite(solved, sc.color);
    solved.addConstraint(sc);
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
