# Equilibrium

The CLI generator (`bin/generate.dart`) biases generation toward
under-represented categories across six independent axes (slug, number of
types, pair of types, size, profile, composition). This document describes how the system works.

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

The six axes are counted independently (no conditional distributions,
except as noted on axis 3):

1. **Slug** — every constraint type (FM, SH, GC, …), counted at most once
   per puzzle.
2. **Number of types per puzzle** — every value declared in the profile is
   an explicit target, with weights decreasing sharply: the bulk on n=1
   and n=2, an intermediate tail on n=3..5, and a long low-weight tail for
   higher-n puzzles so they keep being produced without ever becoming a
   common target. The CLI dashboard collapses n≥6 into a single "6+" bin
   for display; that aggregation is presentational only. See the profile
   table below.
3. **Pair of types** — unordered pair `{slug_a, slug_b}` present in the
   puzzle. Only puzzles with **exactly 2 types** contribute to this axis;
   a 3-type puzzle `{A, B, C}` does **not** count toward `{A,B}`,
   `{A,C}`, or `{B,C}`.
4. **Size** — grid *shape*, canonicalized to `width ≤ height`, so `4x5`
   and `5x4` are the **same bin** (`canonicalSize` in `equilibrium.dart`):
   only the shape matters for variety, not the orientation. Range:
   `kMinSide × kMinSide` up to `kMaxSide × kMaxSide` (3 to 10 inclusive).
   `TargetUniverse.allowedSizes` holds the deduplicated canonical bins, and
   `EquilibriumStats.sizeCounts` tallies a puzzle and its transpose
   together. When a `SizeTarget` (or `pickWeightedSize`) selects a
   non-square bin, the worker picks one of the two orientations at random
   (`_orientSize` in `worker_io.dart`, constrained to the width/height
   bounds), so both orientations keep being emitted while counting as one.
5. **Profile** — pre-fill scenario category (`classic`, `sh`, `pathBased`,
   `syBased`). Identification reads the authoritative `scenario:<name>`
   suffix written by the generator at emission time (see
   `detectPuzzleProfile` in `equilibrium.dart`); unmarked lines —
   including the legacy corpus — are counted as `classic`.
6. **Composition** — ordered triple of the puzzle's three principal
   constraint families (see `families.md`). Each constraint instance
   contributes to its family's count, so a puzzle with `3×LT, 2×PA, 1×FM`
   yields `(path, line-centric, local)`. Families with fewer than three real
   families are padded with the virtual `none` family. The axis is
   **uniform** over all valid ordered triples — including the focused
   one-family and two-family tuples — so it pushes both *combination variety*
   and *thematic focus*. For the full five-family universe `allCompositions`
   enumerates 85 distinct bins. Implementation: `compositionOf` in
   `families.dart`, `CompositionTarget` in `equilibrium.dart`.

## Algorithm

### Main loop

Each iteration in `worker_io.dart`:

1. Recompute the six distributions from the existing puzzle corpus
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
explodes when `exp` is small (the low-weight n-types tail — e.g. n=14 at
0.1 % — would amplify trivial fluctuations into huge "deficits"). Absolute
differences stay in `[0, 1]` and are directly comparable across axes.

**Empty-axis bootstrap**: if `axis_total == 0` (e.g. the corpus contains
no 2-type puzzles, so the pair axis is empty), `observed_share(c) = 0`
for every category and `gap(c) = expected_share(c)`. This kicks the
algorithm into populating the empty axis.

### Number-of-types profile

Every `n` listed in `kTargetNTypesProfile` is its own ranking target.
`_scoreAll` iterates over `kTargetNTypesProfile.keys` and emits one
`_ScoredTarget` per entry, so a high-n bin can be the iteration's chosen
target whenever its observed share drifts below its (small) expected
share. The profile assigns the bulk of the mass to n=1 and n=2, an
intermediate share to n=3..5, and a long low-weight tail to higher-n
puzzles — sufficient to keep them from disappearing, low enough to
never become a frequent target.

| Number of types | Target share                                            |
| --------------- | ------------------------------------------------------- |
| 1               | ≈ 35 %                                                  |
| 2               | ≈ 30 %                                                  |
| 3               | ≈ 12 %                                                  |
| 4               | ≈ 12 %                                                  |
| 5               | ≈ 10 %                                                  |
| 6+              | small (~5 % cumulative, decreasing per n in the tail)   |

The dashboard CLI collapses every n≥6 into a single "6+" bin to keep
the display order stable (1, 2, 3, 4, 5, 6+) regardless of how far the
tail stretches; the picker itself still treats each n individually.
Tunable via `kTargetNTypesProfile` — see `equilibrium.dart` for the
exact per-n weights.

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
  `preferredSlugs` (soft push, not strict — cross-axis recycling still
  accepts the puzzle if the iterative loop ends up not picking it). The
  rest of the slug pool stays available.
- **Size**: when the target is a size, `worker_io.dart` overrides the
  random `(w, h)` draw with the target dimensions.
- **Number of types**: hard restriction. The candidate-constraint pool is
  reduced to a random subset of `target.n` slugs (each `n` declared in
  `kTargetNTypesProfile` is its own target — no special "bucket" case).
  The puzzle is rejected if the final number of distinct slugs differs
  from `target.n`.
- **Pair**: same approach with `n = 2` and the two specific slugs of the
  target pair. The iteration is rejected if both slugs are not actually
  used in the final puzzle (otherwise the puzzle would land in a
  different bucket and not help the targeted pair).
- **Profile**: the resolver routes the iteration through the matching
  pre-fill function — see the "Pre-fill scenarios" section below. The
  iteration is rejected if the emitted puzzle's `scenario:` suffix does
  not match the targeted profile.
- **Composition**: when the target is a composition triple, the worker
  restricts `allowedSlugs` to the union of slugs in the real families
  of the target (the `none` padding is a placeholder — no slug belongs
  to it) and biases `preferredSlugs` toward the dominant families.
  Within each family, slugs are sorted by their secondary deficit score
  (see "Secondary slug bias" below) to also advance the slug axis. More
  preferred slugs are drawn from the first family than the second, and
  even fewer from the third (3:2:1 ratio). This is a bias, not a hard
  quota — the iterative loop may still produce a puzzle whose realised
  composition differs, but the `allowedSlugs` restriction prevents
  cross-family drift.

The post-solve free-cell ratio cap of `kMaxAcceptableRatio` (= 0.25)
applies to every size, including 10x10.

### Secondary slug bias via `slugDeficits`

In addition to the primary target push, the generator applies a **soft
secondary bias** that favours other under-represented slugs during
constraint candidate selection. The bias does not add new hard
restrictions; it adjusts the sort order inside `generateOne`.

**Mechanism.** Before calling `generateOne`, `worker_io.dart` calls
`slugDeficits(equiStats, universe)` to produce a `Map<String, double>`
whose values are the per-slug gap:

```
deficitScore(slug) = max(0, avgK/nSlugs − observedShare(slug))
```

where `avgK = totalSlugUses / totalPuzzles` and `nSlugs` is the number
of allowed slugs — the same arithmetic used by `_scoreAll` on the slug
axis and by `pickWeightedSlugs`. A positive value means the slug is
under-represented relative to the balanced expected share.

This map is stored in `GeneratorConfig.slugDeficitScores` and consumed by
`generateOne`'s candidate sort, which uses a **three-level key**:

1. `prioritySlugs` (`requiredSlugs ∪ preferredSlugs`) — primary target push,
   unchanged from the earlier design.
2. `deficitScore` descending — secondary bias toward corpus-level
   under-representation.
3. Local usage ascending — tie-breaker, promoting intra-puzzle diversity.

The same three-level key is also applied when the remaining pool is
re-sorted after each accepted constraint, except that the priority layer
is dropped at that point (the priority candidate has already been
consumed).

**Snapshot semantics.** The deficit map is computed once per attempt,
outside the `generateOne` call, and does not change during the iterative
constraint-addition loop. This is deliberate: if the snapshot were updated
after each accepted constraint, the target slug (whose corpus share has not
yet increased — the puzzle is not emitted yet) would accumulate a growing
artificial deficit and dominate every re-sort step, defeating the
diversity intent. The single-snapshot approach keeps the bias stable
throughout the attempt.

**Warm-up and disabled equilibrium.** `slugDeficitScores` is `null` when
the corpus is below `kEquilibriumWarmupSize` or when `--no-equilibrium` is
active. A `null` or empty map collapses the sort back to the original
two-level ordering (priority + local usage), preserving the legacy
behaviour exactly.

**Interaction with `NTypesTarget` and `PairTarget`.** Those targets already
populate `preferredSlugs` with multiple under-represented slugs chosen via
`pickWeightedSlugs`. The deficit-score layer is additive: it applies to the
full candidate pool beyond the 2–3 slugs carried by the target, nudging
the remaining slots toward slugs that are also lagging globally.

**Dashboard visibility.** The `slugs={…}` label on the worker dashboard
reflects `preferredSlugs` (the primary target). The secondary deficit bias
acts after that and is deliberately invisible there — its effect surfaces
over time in the per-slug histogram of the dashboard's "Constraints" view.
For per-attempt audit, `worker_io.dart` serialises the deficit snapshot
(slugs with strictly positive gap only) into the `slug_deficits` column of
`generator_stats.csv`, as a `slug:gap|slug:gap|…` string. Slugs at zero
gap are omitted to keep the column compact; the column is empty during
warm-up.

**Worked example.** Suppose the corpus has 500 puzzles, `NC` appears in
40 of them (`observedShare = 0.08`), and with 11 allowed slugs and
`avgK = 2.2` the expected share is `2.2/11 = 0.20`. Then
`deficitScore(NC) = 0.20 − 0.08 = 0.12`. A candidate `NC` constraint
will sort above a `GC` candidate with `deficitScore(GC) = 0.03`, even
though neither is in `prioritySlugs` for this iteration. If the iterative
loop can keep both — i.e. each reduces the free-cell ratio — the emitted
puzzle contributes to both the `NC` and `GC` bins without the target for
this iteration being either of them.

**SH exclusion from slug deficit.** SH is excluded from the `slugDeficits`
map — its deficit is hard-coded to 0.0 in `equilibrium.dart`. This prevents
the slug axis from actively pushing SH, which already receives a 5 % target
via `ProfileTarget(sh)` on the profile axis. Without this exclusion, the slug
axis would push SH at the corpus-average expected share (~17.6 % with 11
slugs and `avgK ≈ 1.94`), overwhelming the profile axis's 5 % intent.
Three points enforce the policy:

1. **`slugDeficits`** — returns 0.0 for SH, so the secondary sort never
   elevates SH candidates above other deficit-positive slugs.
2. **`_resolveTarget` (slug axis)** — `SlugTarget('SH')` returns a no-op
   `_ResolvedTarget()` without adding `'SH'` to `preferredSlugs`.
   Only `ProfileTarget(sh)` adds SH to `preferredSlugs`.
3. **Dashboard `_computeAxisTargets`** — the slug target histogram skips
   SH, so its bar does not appear among the slug-axis deficits.

SH remains fully available for organic inclusion — it stays in `allowedSlugs`
for all `TargetUniverse` contexts (NTypesTarget, PairTarget, SizeTarget,
ProfileTarget). The exclusion is *active avoidance of targeted pushing*, not
a ban.

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
| `preFillSh`        | `prioritySlugs` contains `"SH"` (via `requiredRules` or `preferredSlugs`, SH allowed by `allowedSlugs`) | `sh`           |
| `preFillPath`      | `pathBasedScenario == true`                                       | `pathBased`                |
| `preFillSy`        | `syBasedScenario == true`                                         | `syBased`                  |

Sources of each trigger:

- **SH**: the user passing `--require SH` (which fills `requiredRules`), or
  equilibrium picking a target that involves SH (slug, pair, or n-types
  with SH in the chosen subset) — the resolver adds `"SH"` to
  `preferredSlugs` for that iteration. In both cases SH lands in
  `prioritySlugs = requiredRules ∪ preferredSlugs`, which is what
  `generateOne` checks to enable the SH pre-fill.
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
all five resolved axes so any attempt is fully identifiable:

```
  #00 [att 12/ok 3] → [slug=SY] 10x8 ntypes≤3 slugs={SY,QA,PA} scenario=classic
  #01 [att  8/ok 1] → [ntypes=3] 6x4 ntypes=3 slugs={SY,QA,PA} scenario=classic
  #02 [att 15/ok 2] → [profile=pathBased] 12x8 ntypes=free slugs={} scenario=pathBased
  #03 [att 21/ok 7] → warmup 4x4 ntypes≤3 slugs={SY,QA,PA} scenario=classic
  #04 [att  3/ok 0] → 8x8 ntypes=free slugs={} scenario=classic
  #05 [att  9/ok 1] → [comp=path+line-centric+local] 6x4 ntypes≤6 slugs={LT,CH,RC} scenario=classic
```

The prefix before the body (`WxH ntypes… slugs=… scenario=…`) encodes the
equilibrium state for that worker:

| Prefix | Meaning |
|---|---|
| `[<target.label>]` | Chasing a specific equilibrium target (e.g. `[slug=SY]`, `[ntypes=3]`, `[comp=path+line-centric+local]`) |
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
threshold the six distributions are too sparse to drive meaningful
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

- `kTargetNTypesProfile` — map for axis 2. Declares an explicit target
  share for every `n` it covers (currently n=1..14, with the bulk on
  n=1/n=2, intermediate weights on n=3..5, and a decreasing low-weight
  tail through n=14). Any `n` absent from the map has an implicit target
  of 0 and is never pushed. Refer to `equilibrium.dart` for the exact
  per-key percentages — the constant is the source of truth.
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
- `slugDeficits(stats, universe)` — returns a `Map<String, double>` of
  per-slug deficit values (= `max(0, avgK/nSlugs − observedShare(slug))`)
  covering every slug in `universe.allowedSlugs` **except SH** (which is
  hard-coded to 0.0 — see "SH exclusion from slug deficit" above).
  Exposes the slug-axis gap computed internally by `_scoreAll` as a
  standalone pure function so the generator's secondary sort key shares a
  single definition of "under-represented" with `pickTarget`. Consumed by
  `worker_io.dart` to populate `GeneratorConfig.slugDeficitScores` before
  each `generateOne` call (see "Secondary slug bias via `slugDeficits`"
  above).

The gap computation, target ranking (`rankTargets`), target selection
(`pickTarget`), and deficit snapshot (`slugDeficits`) are pure functions
covered by `test/equilibrium_test.dart`.

## Out of scope

- No persistent equilibrium statistics — distributions are recomputed at
  each run from the output corpus.
- No equilibration of arbitrary n-tuples of slugs — the composition axis
  addresses family-level combination variety, not individual slug combinations.
- No conditional distributions, with one structural exception: the pair
  axis is by construction conditional on puzzles with exactly 2 types.
- No quantitative quota — equilibrium is a bias, not a target count.

Per-attempt telemetry is persisted (see [`feasibility.md`](feasibility.md)),
but this is for infeasibility learning and offline analysis, not for updating
the equilibrium distributions themselves.
