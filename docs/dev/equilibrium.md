# Equilibrium

The CLI generator (`bin/generate.dart`) biases generation toward
under-represented categories across five independent axes (slug, number of
types, pair of types, size, profile). This document describes how the system works.

The implementation lives in `lib/getsomepuzzle/generator/equilibrium.dart`
(pure logic — constants, stats, gap-based picker) and
`lib/getsomepuzzle/generator/worker_io.dart` (per-iteration loop, target
resolution).

## Goal

Equilibrium is a **bias**, not a hard quota. Each axis has a **target
profile** — uniform on most axes, non-uniform on the "number of types" axis
— and after every generated puzzle the algorithm finds the bin that
deviates most from its profile and steers the next iteration toward it.
Categories are never declared "done": when a bin reaches its target share
the algorithm simply moves on to the next most under-represented bin.

## Axes

The five axes are counted independently (no conditional distributions,
except as noted on axis 3):

1. **Slug** — every constraint type (FM, SH, GC, …), counted at most once
   per puzzle.
2. **Number of types per puzzle** — 1, 2, 3, … (no upper bound). Pushed
   toward an inversely-proportional shape: most puzzles use 1 or 2 types,
   a sizable share use 3 or 4, fewer use 5 or 6, and 7+ is residual. See
   the profile table below.
3. **Pair of types** — unordered pair `{slug_a, slug_b}` present in the
   puzzle. Only puzzles with **exactly 2 types** contribute to this axis;
   a 3-type puzzle `{A, B, C}` does **not** count toward `{A,B}`,
   `{A,C}`, or `{B,C}`.
4. **Size** — `(width, height)` ordered pair. `4x5` and `5x4` are
   **distinct**. Range: `kMinSide × kMinSide` up to `kMaxSide × kMaxSide`
   (3 to 10 inclusive).
5. **Profile** — pre-fill scenario category (`classic`, `sh`, `pathBased`,
   `syBased`). Identification reads the authoritative `scenario:<name>`
   suffix written by the generator at emission time (see
   `detectPuzzleProfile` in `equilibrium.dart`); unmarked lines —
   including the legacy corpus — are counted as `classic`.

## Algorithm

### Main loop

Each iteration in `worker_io.dart`:

1. Recompute the five distributions from the existing puzzle corpus
   (absolute counters; recomputed at startup, never persisted). The
   pair-axis distribution aggregates only puzzles with exactly 2 types.
2. Identify the most-imbalanced `(axis, category)` — the one whose
   share deviates most below its target profile (see metric below). Other
   axes stay random for this iteration.
3. Pick that target (e.g. `size 3x6`, `1 type`, `pair {FM, GC}`).
4. Generate a puzzle that satisfies the target.
5. Update stats with the result, then loop.

The chosen axis changes over time: the loop may spend several iterations
pushing 1-type puzzles, then switch to size `3x6` once that becomes the
weakest bin.

### Gap metric

For each `(axis, category)`:

```
gap(c) = max(0, expected_share(c) − observed_share(c))
```

- `expected_share(c)` — the target profile: `1 / |categories|` for
  uniform axes (slug, size, pair); table lookup for number of types.
- `observed_share(c) = count(c) / axis_total`.
- `max(0, …)` — over-represented categories are never reduced; only
  deficits matter.

The iteration's target is the `(axis, category)` with the highest gap
across all axes — a single ranking, not a per-axis aggregation.

**Why absolute over relative**: a relative metric `(exp − obs) / exp`
explodes when `exp` is small (the `7+ types` bucket at 2 % would amplify
trivial fluctuations into huge "deficits"). Absolute differences stay in
`[0, 1]` and are directly comparable across axes.

**Empty-axis bootstrap**: if `axis_total == 0` (e.g. the corpus contains
no 2-type puzzles, so the pair axis is empty), `observed_share(c) = 0`
for every category and `gap(c) = expected_share(c)`. This kicks the
algorithm into populating the empty axis.

### Number-of-types profile

Only `n ∈ {1, 2, 3, 4, 5}` are explicitly pushed by the picker. The
remaining ~11 % budget is left for the residual `6+` bucket, which the
dashboard surfaces as a single bin so we can monitor drift but never
target.

| Number of types | Target share |
| --------------- | ------------ |
| 1               | 25 %         |
| 2               | 30 %         |
| 3               | 12 %         |
| 4               | 12 %         |
| 5               | 10 %         |
| 6+              | 0 % (reliquat, never targeted) |

Tunable via `kTargetNTypesProfile`.

### Profile axis distribution

The bulk of puzzles come from the regular flow; the remaining ~15 % is
split between the three themed pre-fills.

| Profile     | Target share | Pre-fill source                                       |
| ----------- | ------------ | ----------------------------------------------------- |
| `classic`   | 85 %         | `preFillRegular` (random grid + greedy cherry-pick)   |
| `sh`        | 5 %          | `preFillSh` (seeded Shape motif)                      |
| `pathBased` | 5 %          | `preFillPath` (LT topology + bipartite desambiguation, cf. `path_based.md`) |
| `syBased`   | 5 %          | `preFillSy` (symmetric island growth, cf. `prefill_sy.md`) |

Tunable via `kTargetProfile`.

### Per-axis mechanism

The general principle: **filter at the candidate-selection step** rather
than reject after the fact.

- **Slug**: when the chosen target is a slug, that slug is added to
  `requiredRules`; the rest of the slug pool stays available.
- **Size**: when the target is a size, `worker_io.dart` overrides the
  random `(w, h)` draw with the target dimensions.
- **Number of types**: hard restriction. The candidate-constraint pool is
  reduced to a random subset of `n` slugs (with `n` = target count, or 7
  for the `7+` bucket). The puzzle is rejected if the final number of
  distinct slugs differs from `n`.
- **Pair**: same approach with `n = 2` and the two specific slugs of the
  target pair. The iteration is rejected if both slugs are not actually
  used in the final puzzle (otherwise the puzzle would land in a
  different bucket and not help the targeted pair).
- **Profile**: the resolver routes the iteration through the matching
  pre-fill function — see the "Pre-fill scenarios" section below. The
  iteration is rejected if the emitted puzzle's `scenario:` suffix does
  not match the targeted profile.

The post-solve free-cell ratio cap of `kMaxAcceptableRatio` (= 0.25)
applies to every size, including 10x10.

### Infeasibility blacklist

Some `(target_key, slugs, scenario, size_bucket)` tuples are structurally
impossible — the generator can never produce a valid puzzle for them regardless
of how many attempts it makes (for example, `ntypes=1` with `slugs={CH}` where
CH alone is too weak to force a unique solution on any small grid). Without
detection, a worker chasing such a combo burns through its entire `maxTime`
budget repeatedly.

Two complementary mechanisms address this. Both are implemented in
`lib/getsomepuzzle/generator/feasibility.dart` and wired through
`worker_io.dart`. Full details — including the `AttemptKey` granularity, the
`generator_stats.csv` schema, and the CLI flags — are in
[`feasibility.md`](feasibility.md).

**Persistent CSV seed.** `readPersistentBlacklist(csvPath, minAttempts)` reads
`generator_stats.csv` and returns the set of serialized `AttemptKey`s that have
been tried at least `minAttempts` times with zero successes across all logged
runs. The CLI loads this set once at startup and distributes it to every worker
via `_IsolateParams.seedBlacklist`.

**In-session adaptive tracking.** Each worker owns an `InfeasibilityTracker`
(a `Map<String, {attempts, successes}>`). After every `generateOne` call —
success or failure — the worker calls `tracker.record(key)`. A combo is locally
blacklisted when `attempts >= adaptiveK && successes == 0`.

**Skip decision.** Just before emitting the `'target'` event for an attempt, the
worker builds the `AttemptKey` and checks both sources. If blacklisted and the
safety brake has not fired, the iteration executes `continue` — no `'target'`
event, no `'attempt'` event, no dashboard counter update, no CSV row. The
attempt simply never happened from the CLI's point of view. The worker logs the
skip to its `.log` file.

**Safety brake.** After `skipSafety` (default 100) consecutive skips, the next
blacklisted combo runs anyway with a warning logged. This prevents deadlock when
every candidate tuple in the current worker state has been filtered.

**Relationship to `pickTarget`'s `blacklistedKeys` parameter.** `pickTarget`
and `rankTargets` accept an optional `blacklistedKeys` parameter that would
filter at the axis level (e.g. removing `ntypes:1` entirely). The infeasibility
blacklist deliberately does **not** use this parameter — blacklisting an axis key
is too coarse, as it would block every combo at that key regardless of the slug
set or scenario. The skip-then-continue approach at the resolved-tuple level
naturally re-rolls slugs and sizes and only suppresses the exact infeasible
combination.

## Pre-fill scenarios

Some constraint families need a custom seed grid because a random fill
almost never produces a valid puzzle for them. The generator dispatches
to one of four pre-fill functions inside `generateOne`:

| Pre-fill           | Trigger                                                           | Stamped `scenario:` suffix |
| ------------------ | ----------------------------------------------------------------- | -------------------------- |
| `preFillRegular`   | default — random grid                                             | *(none, read as `classic`)* |
| `preFillSh`        | `requiredRules` contains `"SH"` (SH allowed by `allowedSlugs`)    | `sh`                       |
| `preFillPath`      | `pathBasedScenario == true`                                       | `pathBased`                |
| `preFillSy`        | `syBasedScenario == true`                                         | `syBased`                  |

Sources of each trigger:

- **SH**: the user passing `--require SH`, or equilibrium picking a target
  that involves SH (slug, pair, or n-types with SH in the chosen subset)
  — the resolver adds `"SH"` to `requiredRules` for that iteration.
- **Path-based / SY-based**: only equilibrium can set these flags, via
  the profile axis (`ProfileCategory.pathBased`, `ProfileCategory.syBased`).
  See `path_based.md` and `prefill_sy.md` for the algorithms.

The dispatch is the only puzzle-flow-level branching in `generateOne`;
each pre-fill function is otherwise self-contained.

## Implementation details

### Activation

Equilibrium is **on by default** in `bin/generate.dart`. The CLI flag
disables it and falls back to the legacy slug-only bias (uniform size
draw, candidate constraints sorted by `usageStats` only):

```
--no-equilibrium    Disable the multi-axis equilibrium bias.
```

When the flag is set, no hard restriction (slug filtering, size
override) is applied.

### Worker dashboard format

Each line on the live dashboard shows a worker's current attempt context across
all four resolved axes so any attempt is fully identifiable:

```
  #00 [att 12/ok 3] → [slug=SY] 10x8 ntypes≤3 slugs={SY,QA,PA} scenario=classic
  #01 [att  8/ok 1] → [ntypes=3] 6x4 ntypes=3 slugs={SY,QA,PA} scenario=classic
  #02 [att 15/ok 2] → [profile=pathBased] 12x8 ntypes=free slugs={} scenario=pathBased
  #03 [att 21/ok 7] → warmup 4x4 ntypes≤3 slugs={SY,QA,PA} scenario=classic
  #04 [att  3/ok 0] → 8x8 ntypes=free slugs={} scenario=classic
```

The prefix before the body (`WxH ntypes… slugs=… scenario=…`) encodes the
equilibrium state for that worker:

| Prefix | Meaning |
|---|---|
| `[<target.label>]` | Chasing a specific equilibrium target (e.g. `[slug=SY]`, `[ntypes=3]`) |
| `warmup` | Corpus below `kEquilibriumWarmupSize`; using `pickWarmupConfig` |
| `[balanced]` | Equilibrium on, all axes balanced, no target picked |
| *(none)* | Equilibrium disabled (`--no-equilibrium`) |

The `ntypes` field distinguishes hard from soft constraints:
- `ntypes=N` — the target is a `NTypesTarget` with `target.n == N`.
- `ntypes≤N` — soft cap implied by `preferredSlugs.length`; the iterative loop
  may produce a puzzle with fewer types.
- `ntypes=free` — no slug preference active.

`slugs={…}` always lists the sorted preferred slugs. `scenario` is resolved by
`_resolveScenario` in `worker_io.dart` following the priority order
`pathBased > syBased > sh > classic`; `sh` activates whenever
`SH ∈ preferredSlugs`.

### Warmup threshold

Equilibrium is only **actually engaged** if the target file already
contains at least `kEquilibriumWarmupSize` (= 100) puzzles. Below the
threshold the five distributions are too sparse to drive meaningful
targets — `pickTarget` would chase impossible bins and waste time
blacklisting them. The CLI silently falls back to the legacy slug-only
bias and logs:

```
Equilibrium: OFF (warming up: 12/100 puzzles needed)
```

### Centralized parameters

All tunable knobs are declared at the top of
`lib/getsomepuzzle/generator/equilibrium.dart` as constants or pure
functions, so the behavior can be retuned without touching the
algorithm:

- `kTargetNTypesProfile` — map for axis 2 (`{1: 0.25, 2: 0.30, 3: 0.12,
  4: 0.12, 5: 0.10}`). Anything outside the map (the `6+` reliquat
  bucket) maps to share 0 and is never targeted.
- `kTargetProfile` — map for the profile axis (`{classic: 0.85, sh: 0.05,
  pathBased: 0.05, syBased: 0.05}`).
- `kMinSide`, `kMaxSide` — size axis bounds (3, 10).
- `kEquilibriumWarmupSize` — corpus size below which equilibrium stays
  off (100).
- `kMaxAcceptableRatio` — post-solve free-cell ratio cap (0.25).
- `kSizePeakArea`, `kSizeSigmaLeft`, `kSizeSigmaRight` — asymmetric
  Gaussian on grid area used by the size axis (peak ≈ 4×5, right tail
  almost twice as wide as the left).
- `kWarmupMaxWidth`, `kWarmupMaxHeight`, `kWarmupNTypesPool` — clamps
  and n-types pool used during corpus warm-up.
- `targetShare(axis, category, categoryCount)` — pure function returning
  the expected share. Uniform axes (slug, pair) and the legacy size
  fallback: `1 / categoryCount`. Number of types: lookup in
  `kTargetNTypesProfile` (any key not in the map yields 0).
- `sizeTargetShare(width, height, universe)` — non-uniform per-size
  weighting derived from the Gaussian on area, normalised over
  `universe.allowedSizes`.

The gap computation, target ranking (`rankTargets`), and target
selection (`pickTarget`) are pure functions covered by
`test/equilibrium_test.dart`.

## Out of scope

- No persistent equilibrium statistics — distributions are recomputed at
  each run from the output corpus.
- No equilibration of triplets or larger combinations.
- No conditional distributions, with one structural exception: the pair
  axis is by construction conditional on puzzles with exactly 2 types.
- No quantitative quota — equilibrium is a bias, not a target count.

Per-attempt telemetry is persisted (see [`feasibility.md`](feasibility.md)),
but this is for infeasibility learning and offline analysis, not for updating
the equilibrium distributions themselves.
