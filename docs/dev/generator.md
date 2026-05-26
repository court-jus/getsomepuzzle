# Puzzle generation

This document describes the implemented generation pipeline. Three layers
work together:

1. **Single-puzzle generation** — `lib/getsomepuzzle/generator/generator.dart`,
   the core "grid → constraints" greedy algorithm.
2. **Equilibrium bias** — `lib/getsomepuzzle/generator/equilibrium.dart`
   (with a dedicated doc: see [`equilibrium.md`](equilibrium.md)). Steers
   the per-iteration target toward the most under-represented bin across
   four independent axes.
3. **Post-generation polishing** — CLI tools (`bin/trace_score.dart`,
   `bin/filter_score.dart`, `bin/polish.dart`) that score puzzles by
   deduction elegance and reject or repair the weakest ones.

## 1. Core greedy algorithm

The generator is "grid → constraints": it starts from a concrete solved
grid, then collects the constraints that characterise it best.

### 1.1. Pipeline

1. **Build a random solution grid.** Each cell is filled with a random domain
   value (`{1, 2}`) by `preFillRegular`. Themed pre-fills replace the
   random grid for specific scenarios: `preFillSh` when SH is required
   (or pushed by the equilibrium target), `preFillPath` when
   `pathBasedScenario` is set, `preFillSy` when `syBasedScenario` is
   set. Each themed pre-fill stamps a `scenario:<name>` suffix on the
   emitted v2 line and may exit early with `pathPrefillFailed` /
   `syPrefillFailed` if it can't converge within its retry budget.
   See `equilibrium.md` "Pre-fill scenarios" for the dispatch table
   and `docs/dev/path_based.md` / `docs/dev/prefill_sy.md` for the
   themed algorithms.

2. **Pre-fill a few cells.** A random ratio in `[0.75, 1.0]` decides what
   fraction of cells stays empty for the player; the others are locked
   (`readonly`) at their solution value. So 0–25 % of the grid is given
   as hints.

3. **Enumerate every valid constraint.** For each registered slug
   (`FM, PA, GS, LT, QA, SY, DF, SH, CC, GC, NC, RC`),
   `generateAllParameters` yields every parametric instance for the
   grid dimensions; the generator keeps only the ones that **verify
   against the solution grid**. This is the "true" constraint set for
   that solution. The candidate enumeration honours `--allow`
   (whitelist) and `--ban` (blacklist) CLI flags: the effective set is
   `allow.difference(ban)`, or every registered slug minus `ban` when
   `--allow` is unset.

4. **Sort the candidates.** Random shuffle, then a stable three-level sort:
   - **Level 1 — priority**: `prioritySlugs` (= `requiredRules ∪
     preferredSlugs`) bubble to the front. `requiredRules` is what the user
     demanded via `--require`; `preferredSlugs` is what the equilibrium /
     warm-up target *would like* to see, but never strictly enforces.
   - **Level 2 — corpus deficit** (descending): among non-priority candidates,
     slugs whose share in the corpus falls furthest below their target
     (`deficitScore = expected_share − observed_share`, clamped to ≥ 0)
     come next. This soft secondary bias pulls in other globally
     under-represented slugs alongside the one pinned by the target — not
     just the target slug alone.
   - **Level 3 — local usage** (ascending): tie-breaker. Slugs already present
     fewer times in the puzzle-under-construction come first, promoting
     intra-puzzle diversity.

   The deficit snapshot (`GeneratorConfig.slugDeficitScores`) is computed
   once per attempt in `worker_io.dart` via `slugDeficits(equiStats,
   universe)` before the call to `generateOne`. It is `null` during warm-up
   and when equilibrium is disabled, which collapses the sort back to the
   original two-level ordering (priority + local usage).

5. **Greedy cherry-picking.** While the puzzle is not fully determined:
   - Pop the next candidate.
   - Clone the puzzle and `solve()` (propagation + force, no backtracking)
     to get `ratio_before`.
   - Add the candidate to the clone and `solve()` again to get
     `ratio_after`.
   - If `ratio_after < ratio_before`, the constraint is "useful" and is
     kept.
   - After each accepted constraint, the remaining candidates are
     reshuffled and re-sorted by corpus deficit (descending) then *local*
     usage (ascending). The priority layer is absent from the re-sort
     because the priority candidate was consumed at the very start of the
     loop.

6. **Finalisation.**
   - If the residual ratio reaches 0: the puzzle is fully determined by
     its constraints.
   - If `0 < ratio ≤ kMaxAcceptableRatio` (= 0.25): fill the remaining
     cells with the known solution as readonly hints.
   - Otherwise: discard.
   - Final gate: `Puzzle.solveExplained()` runs on the puzzle (with any
     hint cells now readonly). The resulting `SolveStep` trace is
     replayed on a clone; the puzzle is accepted only when
     `replay.complete && replay.check().isEmpty`. This is stricter than
     the old `countSolutions() == 1` check (which relied on
     backtracking): every accepted puzzle is solvable by the in-game
     hint system, with no guessing required. The same trace is reused
     immediately by `classifyTrace()` (see `lib/getsomepuzzle/level.dart`)
     to assign a difficulty level — no extra solve is performed.
   - `generateOne` returns `({String line, PuzzleLevel level})?` so that
     callers receive the classification alongside the serialised puzzle.

7. **Target-collection filter** (optional, `--target-collection NAME`).
   When the player has asked for a specific level, the just-classified
   puzzle is routed (each branch maps to a `GenerationRejectReason`):
   - level matches the target → emit.
   - level is *lower* (too easy) → reject with `targetTooEasy`; the
     caller retries with a fresh seed.
   - level is *higher* (too hard) → enter the **easing loop** described
     in § 4. The loop attempts to lower the trace difficulty by adding
     constraints, bounded by `--easing-budget` (default 30 s). If
     easing plateaus or times out, reject with `targetEasingFailed`.
   - level is `overfilled`, `overfilledEasy`, or `undetermined` →
     reject with `targetOutOfCascade`. The prefill ratio doesn't
     change with more constraints, so these puzzles cannot be eased
     into a playable collection.

### 1.2. Why this design

- **Solution known by construction.** The grid is the input, so every
  candidate constraint is trivially satisfiable; no global feasibility
  check is needed.
- **The solver doubles as the metric.** A constraint's "usefulness" is
  measured by how much the solver's free-cell ratio drops when it is
  added. Generation and resolution stay tightly coupled.
- **No backtracking anywhere.** Neither in the constraint selection
  loop nor in the final uniqueness check. The pipeline is easy to
  parallelise (each attempt is independent) and easy to debug.
- **Required / banned slugs are upstream filters**, not last-mile
  rejections.

### 1.3. Known limitations

- **The random grid decides everything.** A bland 50/50 grid will not
  produce an elegant `SY` or `SH` puzzle even if such a puzzle exists at
  those dimensions.
- **The usefulness metric is coarse.** `ratio_before − ratio_after` does
  not distinguish a constraint that unlocks one trivial cell from one
  that triggers a cascade or that interacts with another constraint.
- **Greedy without regret.** A constraint accepted early can shadow a
  more elegant later candidate. Section 3 below describes the
  post-generation polish that mitigates this.
- **The 0.25 ratio cap is a fallback.** When constraints don't determine
  everything, hints fill the gap — visually heavier puzzles.
- **Bias toward "soft" solutions.** Random 50/50 grids rarely have
  notable structure, which under-uses structural constraints
  (`GS`, `SY`, `SH`, `GC`).

### 1.4. Reject reasons

When a `generateOne` attempt returns `null`, the generator now reports
*why* via the `onReject(GenerationRejectReason, Puzzle)` callback.
`GenerationRejectReason` (see `generator.dart`) enumerates the exits:

| Reason                | Trigger                                                                              |
|-----------------------|--------------------------------------------------------------------------------------|
| `noCandidates`        | `generateAllParameters ∩ verify(solution)` was empty (extreme `--allow`/`--ban`).    |
| `ratioTooHigh`        | Iterative loop finished but `solve()` left > 25 % of cells free.                    |
| `requiredMissing`     | A `--require RULES` slug was never accepted by the iterative cherry-pick.           |
| `notUnique`           | Defensive: trace replay didn't reach a clean completion. Should be unreachable after the ratio check. |
| `targetOutOfCascade`  | `--target-collection` set and the puzzle classified into `overfilled`, `overfilledEasy`, or `undetermined`. |
| `targetTooEasy`       | `--target-collection` set and the puzzle classified strictly easier than the target (can't be made harder by adding constraints). |
| `targetEasingFailed`  | `--target-collection` set and `Puzzle.simplify` couldn't reach the target within `--easing-budget`. |
| `cancelled`           | The caller's `shouldStop` callback fired between candidates, mid-`solve()`, or during the finalisation `solveExplained()`. |
| `pathPrefillFailed`   | `preFillPath` exhausted its retry budget without producing a deductively-unique puzzle. |
| `syPrefillFailed`     | `preFillSy` exhausted its retry budget without producing a deductively-unique puzzle.  |

The worker (`worker_io.dart`) persists every rejected puzzle to
`assets/<reason>.txt` for post-run analysis. The path is currently
hard-coded; see the "Caveats" section below. Per-reason counters surface
in the `FAILURE in Nms (..., reason=<name>)` line the worker logs after
each failed attempt.

**Caveats on reject persistence:**

- The path is `assets/<reason>.txt` relative to the working directory
  of the worker process. Callers not running from the repo root may
  create a stray `assets/` next to their CWD. Plan to make this
  configurable via `GeneratorConfig`.
- Append writes are not atomic across worker isolates when a v2 line
  exceeds `PIPE_BUF` (4096 bytes on Linux); large lines from multiple
  workers can theoretically interleave. Acceptable for human inspection
  but not for downstream re-ingestion without a sanity pass.

## 2. Equilibrium and the per-worker main loop

`bin/generate.dart` invokes the generator inside a per-iteration loop
that rebalances the corpus across five axes (slug, number of types,
pair of types, size, profile). The full description lives in
[`equilibrium.md`](equilibrium.md). In short: every iteration picks the
most under-represented `(axis, category)`, configures the generator
accordingly, and lets the greedy algorithm produce a puzzle for that
target.

### 2.1. Infeasibility skip

Before emitting the `'target'` event — and therefore before any attempt
counter is incremented — the worker builds an `AttemptKey` (the tuple
`(target_key, sorted_preferred_slugs, scenario, size_bucket)`) and checks
it against two sources:

1. **Persistent seed blacklist** — serialized keys loaded from
   `generator_stats.csv` at CLI startup via `readPersistentBlacklist`.
   Covers combos that historically produced zero successes across past
   runs (threshold: `--blacklist-min-attempts`, default 30).
2. **In-session adaptive tracker** — an `InfeasibilityTracker` owned by
   each worker that accumulates `{attempts, successes}` per key within
   the current run (threshold: `--blacklist-adaptive-k`, default 20).

If either source flags the combo as infeasible, the iteration executes
`continue` immediately — no `'target'` event, no `'attempt'` event, no
CSV row. From the CLI's point of view the attempt never happened. A
consecutive-skip counter enforces a safety brake (`--blacklist-skip-safety`,
default 100): after that many consecutive skips, the next blacklisted combo
runs anyway to prevent deadlock.

Full details on `AttemptKey` granularity, the `generator_stats.csv` schema,
and the CLI flags are in [`feasibility.md`](feasibility.md).

### 2.2. Per-attempt telemetry

After every `generateOne` call (success or abandon) the worker emits a
`GeneratorAttemptMessage` (`lib/getsomepuzzle/generator/messages.dart`).
The CLI receives it in the `GeneratorAttemptMessage` branch of its consumer
loop and appends one row to `generator_stats.csv` (append-only;
header written only on first creation). Multiple CLI runs accumulate rows
naturally, and concurrent workers serialize their CSV writes through a
`statsChain` Future to avoid interleaving.

The CSV schema and its role in seeding the next run's blacklist are described
in [`feasibility.md`](feasibility.md). The in-app generator
(`lib/widgets/generate_page.dart`) ignores `GeneratorAttemptMessage` with a
no-op case — the CSV is CLI-only telemetry.

## 3. Post-generation scoring and polishing

The greedy algorithm has no notion of *deduction elegance*. A
post-generation pass scores each puzzle by the shape of its
solver trace and either filters or repairs the weakest puzzles.

### 3.1. Trace score (`bin/trace_score.dart`)

`Puzzle.solveExplained()` already returns a list of `SolveStep`s tagged
with the responsible constraint and the deduction kind (`propagation` or
`force`). From that trace, `scorePuzzle()` computes:

| Metric | Definition |
|---|---|
| `switch_ratio` | Fraction of prop→prop transitions where the responsible constraint changes (proxy for interleaved deductions / aha-chains). |
| `cascade_ratio` | Length of the longest single-constraint cascade ÷ total propagation steps (penalises a single "overwhelming" constraint, e.g. FM:12). |
| `force_ratio` | Number of force steps ÷ total steps. |
| `force_depth` | Sum and max of propagation depths inside force steps (deeper force = harder to do mentally). |
| `diversity` | Constraints that contributed at least once ÷ total constraints declared. |
| `start_ok` | 1 if at least one propagation step precedes the first force, 0 otherwise — guarantees a starting point. |
| `needs_backtrack` | 1 if propagation+force don't close the puzzle → disqualified. With `isDeductivelyUnique()` enforced at generation time, this should always be 0 on shipped puzzles. |

Combined score:

```
forcePenalty = forceSteps == 0
             ? 0
             : 3 + 2 · forceDepthAvg + 1.5 · forceDepthMax

score = 40 · switch_ratio
      − 40 · cascade_ratio
      − forcePenalty
      + 20 · diversity
      + 20 · start_ok
```

The penalty on force steps is no longer a flat `−20 · force_ratio` — it
weighs the *depth* of each force round, since shallow force is easier
on the player than deep force.

### 3.2. Validation against player ratings

`bin/rating_correlation.dart` cross-references the score with the
liked/neutral/disliked ratings stored in `stats/stats.txt`. On the
1277-play sample collected so far:

| Rating | n | mean score | cascade_ratio | switch_ratio |
|---|---|---|---|---|
| **Liked** | 404 | **48.9** | **0.22** | **0.59** |
| Neutral | 858 | 46.3 | 0.26 | 0.57 |
| **Disliked** | 15 | **34.7** | **0.47** | **0.38** |

A `score ≥ 40` filter keeps 79 % of liked puzzles and removes 73 % of
disliked. `cascade_ratio` is the strongest single signal — most disliked
puzzles are dominated by a `FM:12` / `FM:21` propagating across the
whole grid.

### 3.3. Filtering (`bin/filter_score.dart`)

S1 — rejection sampling. Reads puzzle lines, scores each one with
`scorePuzzle()`, and emits only those that meet the threshold (default
40). Per-puzzle timeout (default 15 s) protects against pathological
solver behaviour. Stats on rejection rate are reported on stderr.

### 3.4. Polishing (`bin/polish.dart`)

S2 — local-search polish. For each input puzzle, tries random mutations
that

1. preserve uniquely-deductive solvability, **and**
2. improve the trace score.

Greedy best-improvement loop until no mutation helps or the iteration /
candidate / time budget is exhausted. Output: improved puzzles plus a
summary of the mutations applied.

These two tools are intentionally separate from the generator inner
loop: post-processing is opt-in and runs offline on collections, not on
every interactive generation.

The CLI also reorders constraints by trace-min `Move.complexity` via
`Puzzle.sortConstraintsByDifficulty` (`bin/recompute.dart`,
`bin/dedup_puzzles.dart`, `bin/aggregate_player_stats.dart`). Shipped
puzzles therefore carry their constraints in "easiest first" order on
disk, which in turn drives what the hint system surfaces — see
[`algorithm.md`](algorithm.md) § "Constraint ordering".

## 4. Easing loop (`Puzzle.simplify`)

When `--target-collection NAME` is set and a freshly-generated puzzle
classifies at a higher difficulty tier than `NAME`, the worker invokes
`Puzzle.simplify(targetLevel: NAME, maxTime: easingBudget)` to try to
lower the puzzle's difficulty by **adding** constraints. (Adding a
constraint can only restrict the search space, so the trace can only
get shorter or simpler — never harder.)

### 4.1. Strategy: indispensable-by-exploration

Naïvely adding every candidate that doesn't break uniqueness reaches
the target but bloats the constraint list with "scaffolding" rules. The
adopted strategy is surgical:

1. Trace `this` via `solveExplained()` and classify. If the level is
   already at or below the target, stop.
2. On a **clone**, naively expand: add candidates one by one until the
   clone's classified level drops by at least one tier. The candidate
   that triggered the drop is marked **indispensable** — every
   candidate added before it served only as *context* and is discarded.
3. Graft only the indispensable onto the original via
   `prependConstraint`. Front insertion is required so the cheaper
   deduction consults `apply` before any pre-existing dominant
   constraint (e.g. an SH that the player asked for via `--require`).
4. Reclassify the original. Whether or not its level actually dropped
   (the indispensable may have needed clone-context to fire alone),
   loop back to step 1.

Candidates are drawn from `generateAllParameters` over `allowedSlugs`
(default: every registered slug), filtered to those compatible with
the puzzle's unique solution and not already present. Stable
serialize-order so the same puzzle yields the same simplification trace.

### 4.2. Important invariants

- **Mutates `this`** by prepending each accepted indispensable. Cell
  values (including readonly) are never modified.
- **`removeUselessRules` is never invoked.** Calling it would strip the
  very constraints we just added.
- **Bounded.** The loop honours both a `maxSteps` cap (default 50) and
  a wall-clock `maxTime` budget (the CLI `--easing-budget`, default
  30 s). The `shouldStop` callback lets the worker cancel from outside
  if its global watchdog fires.
- **Returns `SimplifyResult`** — `additionsCount`, the final
  `PuzzleLevel`, a `reachedTarget` flag, and the solve trace of the
  final state (so the caller can reuse it for
  `sortConstraintsByDifficulty` without paying for another
  `solveExplained()`).

## 5. Future directions

A handful of bigger ideas were sketched during the trace-score
design — refining the C2-interleaving signal, detecting
meta-inferences (`M`: a new constraint logically implied by the
existing ones, independent of the grid), theme-first generation
(skeleton-first instead of grid-first), and local search on the joint
`(grid, constraint set)` space.

None are blocking. The combination of greedy generation + equilibrium
bias + post-generation polish covers the practical needs for the
corpus shipped today.
