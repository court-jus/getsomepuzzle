# Equilibrium

The CLI generator (`bin/generate.dart`) biases generation toward
under-represented categories across four independent axes (slug, number of
types, pair of types, size). This document describes how the system works.

The implementation lives in `lib/getsomepuzzle/generator/equilibrium.dart`
(pure logic — constants, stats, gap-based picker) and
`lib/getsomepuzzle/generator/worker_io.dart` (per-iteration loop, target
resolution, blacklist).

## Goal

Equilibrium is a **bias**, not a hard quota. Each axis has a **target
profile** — uniform on most axes, non-uniform on the "number of types" axis
— and after every generated puzzle the algorithm finds the bin that
deviates most from its profile and steers the next iteration toward it.
Categories are never declared "done": when a bin reaches its target share
the algorithm simply moves on to the next most under-represented bin.

## Axes

The four axes are counted independently (no conditional distributions,
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

## Algorithm

### Main loop

Each iteration in `worker_io.dart`:

1. Recompute the four distributions from the existing puzzle corpus
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

Decreasing overall, with a peak at 2 types:

| Number of types | Target share |
| --------------- | ------------ |
| 1               | 25 %         |
| 2               | 30 %         |
| 3               | 12 %         |
| 4               | 12 %         |
| 5               | 10 %         |
| 6               | 9 %          |
| 7+              | residual (~2 % combined) |

Tunable via `kTargetNTypesProfile` and `kTargetSevenPlusShare`.

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

The post-solve free-cell ratio cap of `kMaxAcceptableRatio` (= 0.25)
applies to every size, including 10x10.

### Failure blacklist

Some targets are unreachable in practice (e.g. pair `{SH, PA}` on a
`3x3` grid is too small to carry the necessary information). To avoid
spinning on them:

- Failure counts are tracked per target key.
- After `kBlacklistAfterFailures` (= 5) consecutive failures, the target
  is blacklisted for the session.
- Blacklisted targets are skipped by `pickTarget`, letting the loop fall
  back to the next-deepest gap.

## SH special case

`ShapeConstraint` requires a custom seed grid because a random fill
almost never contains a valid Shape motif. The generator switches between
`_preFillSh` and `_preFillRegular` based on a single rule:

> If `requiredRules` contains `"SH"` (and SH is allowed by `allowedSlugs`),
> use `_preFillSh`. Otherwise use `_preFillRegular`.

That rule subsumes both sources of "SH must appear":

- The user passing `--require SH` on the CLI.
- Equilibrium picking a target that involves SH (slug, pair, or n-types
  with SH in the chosen subset) — the resolver adds `"SH"` to
  `requiredRules` for that iteration.

There is no other SH-specific code path in the generator.

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

### Warmup threshold

Equilibrium is only **actually engaged** if the target file already
contains at least `kEquilibriumWarmupSize` (= 100) puzzles. Below the
threshold the four distributions are too sparse to drive meaningful
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

- `kTargetNTypesProfile` — map for axis 2 (`{1: 0.25, 2: 0.30, …}`).
- `kTargetSevenPlusShare` — residual share for the `7+` bucket (0.02).
- `kMinSide`, `kMaxSide` — size axis bounds (3, 10).
- `kBlacklistAfterFailures` — failures before blacklisting (5).
- `kEquilibriumWarmupSize` — corpus size below which equilibrium stays
  off (100).
- `kMaxAcceptableRatio` — post-solve free-cell ratio cap (0.25).
- `targetShare(axis, category, categoryCount)` — pure function returning
  the expected share. Uniform axes: `1 / categoryCount`. Number of
  types: lookup in `kTargetNTypesProfile` (or `kTargetSevenPlusShare`
  for `n ≥ 7`).

The gap computation, target ranking (`rankTargets`), and target
selection (`pickTarget`) are pure functions covered by
`test/equilibrium_test.dart`.

## Out of scope

- No persistent statistics — distributions are recomputed at each run.
- No equilibration of triplets or larger combinations.
- No conditional distributions, with one structural exception: the pair
  axis is by construction conditional on puzzles with exactly 2 types.
- No quantitative quota — equilibrium is a bias, not a target count.
