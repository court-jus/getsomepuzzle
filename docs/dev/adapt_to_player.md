# Adapt to player

The game selects puzzles that match the player's current skill. The player's
level is inferred from their recent history and used to pick puzzles slightly
ahead of that level, nudging them upward while keeping the pace comfortable.

## Overview

- **Player level** is an integer on a 0–100 skill scale calibrated in
  puzzle-`cplx` units (see "Scale" below). It is either set manually with
  the slider in the settings, or computed
  automatically from the last plays (toggle `autoLevel`, `true` by default).
- **Puzzle selection** weights the entire filtered catalog by a Gaussian
  centred on the player level (default `σ=5`). Every puzzle has a
  non-zero probability of being picked; the closer its `cplx` is to the
  player's level, the higher the chance. Soft tails ensure that a fast-
  progressing player never finds the well dry, since occasional out-of-
  centre puzzles are still surfaced.
- **End-of-list UX**: with weighted sampling there is no longer a
  "tier" to exhaust. The only empty states are (a) the player has
  literally solved every puzzle in the filtered catalog, or (b) the
  user's filters are too restrictive. `EndOfPlaylist` distinguishes
  the two with `Database.hasUnplayedIgnoringFilters()`.

## Player level

### Scale

`playerLevel` lives in `Settings` (≥ 0 — **unbounded above** — persisted in
`SharedPreferences`). The scale is **anchored at 50 = the calibration
cohort's pace**: a player who solves at the same speed as the historical
baseline trends toward 50, faster players go above, slower below. This puts
the "average" player in the middle of the range instead of at 0 or near 0.

The unit is still puzzle-`cplx`-compatible: the puzzle selector compares
`level` against `cplx` directly via the Gaussian weighting (see below).
But the absolute number `42` no longer means "performs like a `cplx=42`
solver" — it means "42 in the centred-on-50 skill scale".

> **`cplx` is unbounded (since 2026-08).** Puzzle complexity is no longer
> capped at 100 — force-heavy 6-mad puzzles compute to 100–230 (see
> `complexity.md`). `playerLevel` is **≥ 0 with no upper clamp** (a very
> fast player may exceed 100), and the Gaussian targeting uses cplx
> *differences*, so matching still behaves.
>
> **The duration-model anchor was re-calibrated on 2026-08-19**, after
> the corpus recompute. Re-running `bin/analyze_stats.dart
> --recompute-cplx` on the refreshed corpus showed the old constants
> (`3.31 · cells^0.515 · exp(cplx/123.8)` — calibrated on the *capped*
> distribution) pinned 56 % of plays at level 0/100. The current model is
> `4.8834 · cells^0.3437 · exp(cplx/59.39) · 1.1943^failures ·
> 1.0614^n_cons` (R² = 0.621, MAPE = 46 %), anchored so the cohort mean
> lands on 50 (see the "Expected duration" section below).

### Expected duration

The core model is OLS-fit on real plays:

```
expectedDuration(cplx, cells, failures, n_constraints)
    ≈ 4.8834 · cells^0.3437 · exp(cplx / 59.39)
         · 1.1943^failures · 1.0614^n_constraints      (R²=0.621, MAPE=46%)
```

- `cells = width · height` — duration grows sub-linearly with the grid
  (exponent 0.344): a fraction of the cells in larger grids are "obvious"
  and cost little. The exponent dropped from 0.515 in the previous fit
  once the recomputed cplx — which now carries part of the grid-size
  signal — entered the model.
- `cplx` slope of `1/59.4` — the current value after the 2026-08 corpus
  recompute. Unclamping the score restored discrimination at the top
  end, so each cplx point now maps to a steeper duration increase than
  under the old capped constants (`1/123.8`). The reference fit without
  `n_constraints` is even steeper (`1/48.7`), because high-cplx puzzles
  tend to carry more constraints; once constraint count is in the model,
  cplx and constraint count untangle.
- `1.1943^failures` penalises wrong-click episodes. Mild on purpose:
  ~84 % of plays have zero failures, so the multiplier is fit to the
  cases where there *are* failures; aggressive multipliers (1.65) have
  always overcorrected.
- **`1.0614^n_constraints`** captures parsing/setup cost, folded into
  the model since v1.6.1. A 4×4 grid with 12 constraints takes
  meaningfully longer than the same grid with 3, even at identical
  `cplx`. Adding the term lifts R² from 0.566 to 0.621 on the
  recomputed corpus.
- The intercept (`4.8834 = exp(1.586)`) is **anchored**: it is shifted
  from the OLS-minimum-MSE intercept by `+0.2399` (in log space) so the
  cohort's mean `level_i` lands on **50** instead of on the cohort's
  mean `cplx` (≈ 35.75 on the recomputed corpus). This is a deliberate
  shift in interpretation, not a fit error: the formula intentionally
  over-predicts the cohort's durations, because we want a "matches the
  cohort" pace to read as middle-of-the-bar, not bottom-of-the-bar.
- No artificial clamp on the model input: puzzle `cplx` is unbounded
  since 2026-08 (see the note under "Scale"). The legacy
  `cplx=100` "non-deductively-solvable" bucket is no longer emitted by
  the generator; it may survive in legacy corpus files but no longer
  biases the calibration once recomputed.

This model sits inside `Database` as `_expectedDuration` and is not exposed:
nothing outside the level computation needs it. The companion
`_impliedCplx(dur, cells, failures, nConstraints)` is its algebraic
inverse, used by the level computation below.

### Level computation

`Database.computePlayerLevel({required int fallback})` uses a skill
inversion: faster than expected ⇒ implicit level above `cplx`; slower ⇒
below. The intercept anchor on the duration model shifts the output up
by ~14 cplx-units so the cohort centres on 50 (the cohort's mean cplx
on the recomputed corpus is ≈ 35.75).

```
level_i = 2 · cplx_i − impliedCplx(duration_i, cells_i, failures_i, n_cons_i)
       where impliedCplx(d, c, f, n) = 59.39 · ( log(d) − log(4.8834)
                                            − 0.3437·log(c)
                                            − 0.1775·f − 0.0596·n )
```

When a play's duration matches the (anchored) expected duration for its
`cplx`, `level_i = cplx`. The cohort's *typical* pace, however, is
faster than this anchored expected — by design — so cohort plays come
in around 50 on average rather than around their puzzle's `cplx`.

The sample is the **global full play history**: every finished, non-skipped
play across **all collections** counts, and replays of the same puzzle are
separate samples (each distinct completion stamp). For each of the last 50
samples we compute `level_i` and take a weighted average with
**exponential decay, half-life = 25 puzzles**. The duration is clamped to
`[1, 10·expected]` up front so a puzzle left open for hours does not swing
the result — and two further guards prevent outliers from zeroing the
level:

- **Gross-AFK drop**: plays with `longestGapMs > 5 min` are excluded
  entirely rather than read as "very slow".
- **Winsorization**: each `level_i` is clamped to
  `[max(cplx − 30, 0), cplx + 60]` before weighting. The lower bound is
  deliberately gentler (a novice may legitimately take long on an easy
  puzzle and must not be pinned at 0); the upper bound guards against the
  opposite outlier — implausibly fast plays of hard puzzles (random
  tapping + luck).
- **No cached complexity**: plays whose puzzle line carries no `cplx`
  (custom / user playlists) are skipped, since they would otherwise read
  as `level_i = −impliedCplx < 0` and drag the average down.

The computed level is floored at 0 (never negative) with **no upper
clamp** — a very fast player can exceed 100. The manual slider in
Settings stays on a 0–100 scale (its displayed value is clamped); the
first manual drag snaps the committed value back into that range.

If fewer than 2 usable samples are available, we return `fallback`
(usually the currently stored level) rather than snapping to 0 — this
preserves any manually set level during onboarding. Two is a low bar:
the noise floor on a single play is large (per-play std ~ 35 of
`level_i`), so the rolling average needs many samples to stabilise.
Raising the threshold is a UX/responsiveness trade-off worth revisiting
once we expose a confidence band.

`autoLevel` toggling is live: flipping it on in Settings triggers an
immediate recompute without waiting for the next puzzle to finish, and
updates the playlist and current puzzle on the fly. The slider in Settings
becomes read-only while `autoLevel` is on, with an `(auto)` hint next to
the label. The `TimerBottomBar` also shows `Lv N` during play, with a
trailing `*` when it is computed rather than manual.

## Puzzle selection

`Database.getPuzzlesByLevel(level)` orders the entire `filter()`-ed
catalog by a Gaussian-weighted draw centred on `level + selectionOffset`
(default offset 0) with standard deviation `selectionSigma` (default 5).
Each puzzle gets a weight

```
w(cplx) = exp( −(cplx − μ)² / 2σ² )
```

The shuffle is implemented with the Efraimidis-Spirakis trick: each
candidate gets a sort key `−ln(uniform()) / w`, and ascending sort by
key is equivalent to weighted-sampling-without-replacement. The first
few elements of the returned list are very likely to be near `μ`; later
elements drift toward the tails. With σ=5 the practical reach is
roughly ±15 cplx (`exp(−4.5) ≈ 0.011`, so ~1 % of the central weight).

The Gaussian weight is further multiplied by the variety bias and, in
one onboarding case, a demotion factor: while the strict phase that
introduces `GS` is active (`currentPhase?.introducing == 'GS'`), a
puzzle flagged `PuzzleData.hasTrivialGroupSize` (a size-1 `GS` —
isolated cell) is multiplied by `selectionTrivialGsPenalty` (0.05).
This strongly deprioritises poorly-instructive instances during GS
discovery while keeping them drawable as a last resort. See
`docs/dev/onboarding.md`.

`preparePlaylist` uses this when `shouldShuffle` is `false`. When
`shouldShuffle` is `true`, the player has explicitly asked for the full
filtered catalog in random order — the Gaussian bias is bypassed
entirely. `autoLevel` and `shouldShuffle` are orthogonal; shuffle wins.

User-set filters (size, rules) intersect the catalog before weighting:
they act as hard constraints the player has chosen to impose. When they
backfire, `EndOfPlaylist` surfaces it (see below).

### Batch cap and `EndOfPlaylist` rotation

On the six built-in level collections (`1-easy` … `6-mad`),
`preparePlaylist` truncates the result to **`playlistBatchSize = 5`
puzzles** (`custom` and user playlists are exempt; the `tutorial`
collection itself was removed in the onboarding rework — see
[`onboarding.md`](onboarding.md)). The truncation makes `EndOfPlaylist`
fire predictably every ~5 plays — without the cap, a collection holding
~1 000 puzzles would never exhaust, and we'd never get a natural moment
to surface the cross-collection suggestion below.

The cap is applied uniformly whether the playlist comes from the
Gaussian draw or from `shouldShuffle`: it's about pacing the
`EndOfPlaylist` hook, not about ordering.

The catalog count surfaced in `OpenPage` (the *Puzzles matching
filters* line) is `filter().length`, not `playlist.length` — the
player needs to see how many puzzles their filters match against,
which is independent of the batch the engine is currently feeding
them.

### When `playerLevel` recomputes (auto mode)

With `autoLevel == true`, `Database.computePlayerLevel` is called
- **at app startup** (right after the stats are loaded, so a returning
  player's level is refreshed even if they never complete a batch), and
- exactly **at the end of each batch** (when `_onPuzzleCompleted` finds
  `playlist.isEmpty` after the last puzzle of the batch was consumed).

It is **not** called after every puzzle.

The reason is mechanical: every time the level changes,
`preparePlaylist` rebuilds the playlist with a fresh Gaussian draw —
so a per-puzzle recompute would replace the in-flight batch
continuously, the player would never reach the 20th puzzle, and
`EndOfPlaylist` would never fire. End-of-batch recompute is the only
schedule that lets the *Try `<recommended>`* prompt appear at all.

Side effect: the `Lv N*` indicator in `TimerBottomBar` is held steady
for the whole batch. That's intentional — a stable readout is easier
to act on than one that jitters per play. The level on screen reflects
"the level the engine is feeding you puzzles for", which is the right
signal anyway.

User-initiated changes (toggling `autoLevel` on, moving the manual
slider, ending the tutorial) still recompute and rebuild immediately;
the deferral applies only to the per-puzzle automatic loop.

The selection knobs `selectionOffset` and `selectionSigma` are
constants today. Wiring them through `Settings` would unlock UX
modes like "challenge" (`offset = +5`), "rest" (`offset = −3`) or
"variety" (`σ = 10`).

## End of playlist

`loadPuzzle` clears the puzzle state and shows `EndOfPlaylist` whenever
the active playlist is empty — which now happens at every batch
boundary on the six level collections (every ~20 plays), not just when
the catalog is fully exhausted. The widget reads three signals:

- **`filtersBlocking`** — `Database.areFiltersBlocking`: true only
  when `filter()` is empty *and* unplayed puzzles still exist
  (`hasUnplayedIgnoringFilters()`). At a normal batch boundary, the
  ~1000 untouched puzzles are still picked up by `filter()` so this
  stays false; the "relax filters" headline only fires when user-set
  filters (size, rules) genuinely exclude every candidate. Keying on
  `hasUnplayedIgnoringFilters` alone — the previous behaviour — would
  have surfaced the warning at every batch boundary. The
  *Try `<recommended>`* button still shows in this branch when
  applicable (switching collections is a legitimate escape hatch since
  filters may be permissive in another bucket); the *Continue* button
  is hidden because re-preparing would hit the same empty result.
- **`hasMoreInCurrent`** — `Database.hasMoreCandidatesInCurrentCollection()`:
  the current collection still has unplayed candidates that weren't in
  the just-finished batch. Drives the *Continue with `<X>`* button
  (load another batch of 20).
- **`recommendedCollectionKey`** (see below) — when non-null and
  different from the active collection, drives the *Try `<recommended>`*
  button (switch + new batch).

Both buttons are surfaced together when both apply; the player can
keep going in the current palier or graduate. A `Pick another
collection` text link routes back to `OpenPage` for full agency.

The headline keeps the running tally; the numeric `Current level: N`
caption and the generic "based on your level" hint were removed — the
suggestion is now captioned by direction (see below).

## Cross-collection suggestion

`Database.recommendedCollectionKey` returns the slug of a *different*
playable collection that better matches `playerLevel`, or `null` when
no suggestion is appropriate. Returns `null` whenever:

- the active collection is the tutorial (no rotation while teaching);
- fewer than `_minPlaysForRecommendation = 10` usable plays have been
  recorded — the rolling average is too noisy to act on;
- the recommendation matches the active collection (no badge needed).

The mapping `playerLevel → PuzzleLevel` lives in `level.dart` as
`recommendedLevelFor(int playerLevel)`. Thresholds are deliberately
hand-picked rather than derived from corpus medians:

```
< 25     → debutant       (1-easy)
25 - 39  → joueur         (2-player)
40 - 49  → avance         (3-advanced)
50 - 64  → balaise        (4-strong)
65 - 79  → expert         (5-expert)
≥ 80     → fouFurieux     (6-mad)
```

The cohort is anchored at `playerLevel = 50`, so an average-paced
player lands on the `avance` / `balaise` boundary — half the time the
suggestion will rotate them between those two paliers, which is the
intended steady state for the typical user.

### Gradual ±1 clamp

`recommendedLevelFor` is a pure mapping and may return any palier; the
gradual clamp lives in `recommendedCollectionKey` because only that
getter knows the active collection. The recommendation is bounded to
one tier above or below the currently played playlist: a very fast
player on `1-easy` is nudged to `2-player`, never sent straight to
`6-mad`. Because the getter is re-evaluated at every batch boundary
and `playerLevel` is refreshed each time, a consistently fast player
still climbs one palier per batch up to their natural level — the
progression is gradual rather than a single large jump.

The reference tier comes from `playableCollectionKeyToLevel[collection]`.
When the active collection is not a playable level (`custom`, `user_*`,
or the tutorial) there is no reference palier, so the unclamped
recommendation is kept.

A "closest median" rule was considered but rejected: corpus medians
for `avance` (36), `balaise` (39), and `expert` (37) are not
monotonic, so a closest-median assignment would flip erratically in
the [33, 45] band where many players cluster. Explicit thresholds are
stable and easy to test.

The recommendation surfaces in two places:
- **`OpenPage` dropdown** — a star badge marks the recommended
  collection in the dropdown list, with the localised tooltip
  *"Recommended for you"*.
- **`EndOfPlaylist`** — at every batch boundary, the *Try `<X>`*
  button switches to the recommended collection if it differs from
  the active one.

The caption above the suggestion buttons is directional:
`Database.recommendedCollectionDirection` is `up` when the suggested
tier sits one step above the active collection (the modal
congratulates — "Good job, do you want to try the next collection?"),
`down` when it sits one step below. When the active collection has no
ladder tier (`custom` / `user_*` / tutorial) the getter returns null
and the modal falls back to the softer invite — "Are you having fun?
Do you want to try this other collection?" — which stays accurate as a
plain alternative-offer.

## Data model

### `PuzzleData` / `Stats`

Each play tracks `duration` (seconds), `failures` (wrong-click episodes),
and `hints` (help requests). `hints` is incremented on each first reveal
of a hint in `GameModel.showHelpMove` and on each successful
`addHintConstraint`, then propagated from `Stats` to `PuzzleData` when
the puzzle is stopped.

### Stat file format

One line per solved puzzle, space-separated:

```
<timestamp> <duration>s <failures>f <puzzleLine> - <SLD> - <skipped> - <liked> - <disliked> - <pleasure> - <hints>h
```

The trailing `Nh` field was added after the initial rollout; `StatEntry.parse`
returns `hints = 0` for older lines without it. No migration is required.

## Calibration notes

`expectedDuration` is OLS-fit on real play data via
`bin/analyze_stats.dart`. Each refit recomputes every play's `cplx`
with the current complexity formula (older entries carry cplx values
from earlier formulas that are not directly comparable):

```
dart run bin/analyze_stats.dart --recompute-cplx stats/
```

Current model and its predecessors on the recomputed dataset:

| Formula | R² | MAPE | Notes |
|---|---:|---:|---|
| `1.4·cells^0.85·exp(cplx/74)·1.29^f` | 0.44 | 59 % | pre-1.6.1 (no `n_constraints`, OLS-minimum intercept) |
| `8.62·cells^0.442·exp(cplx/27.3)·1.145^f·1.085^n_cons` | 0.70 | 29 % | v1.6.1 (stale AFK-tolerant cleaning, capped cplx) |
| **`4.8834·cells^0.3437·exp(cplx/59.39)·1.1943^f·1.0614^n_cons`** | **0.621** | **46 %** | **current (2026-08 re-anchor on recomputed, unclamped corpus)** |

Three things changed in the v1.6.1 refit:

- **`n_constraints` is now in the model.** Once parsing/setup cost is
  accounted for explicitly, the previously-confounded `cplx` slope and
  `cells` exponent both shift dramatically — `cplx` becomes much more
  informative (slope `1/27.3` instead of `1/74`) and `cells` drops to
  `0.442` (each extra cell costs less, but each extra constraint costs
  ~8.5 % more time).
- **The intercept is anchored, not OLS-minimum.** Plain OLS would put
  the cohort's mean `level_i` at the cohort's mean `cplx` (≈ 9 on the
  v1.6.1 calibration set), which read as "no adaptation" in the UI.
  Adding `+1.50` to the intercept (multiplying expected duration by
  ~4.5) shifts the cohort to `level=50`. This is a UX choice — it
  trades MSE on the calibration set for an interpretable scale.
- **The failures multiplier softens from 1.29 to 1.145.** With
  `n_constraints` separated out, failures stop double-counting the
  parsing cost of busy puzzles.

In **2026-08** the complexity formula changed (unbounded score, domain
term, per-prune bump — see `complexity.md`) and the corpus was
recomputed. The re-anchor above refits the model on that recomputed
corpus: the previously-capped cplx values spread out (mean cplx rose to
≈ 35.75), and the old constants would have pinned 56 % of plays at
level 0/100. The new anchor restores the cohort mean to 50. R² is
slightly below the v1.6.1 number because the current cleaning
(`longestGapMs ≤ 30 s`) deliberately stops fitting the AFK tail — what
we lose in residual variance we gain in not pretending high-cplx
puzzles take half an hour.

Per-play noise is still substantial — the within-cplx-bucket std of
`level_i` is ≈ 23–39 across buckets on the recomputed corpus, so the
rolling average over 50 plays (half-life 25) is what gives a stable
reading. R² of 0.62 means ~38 % of variance is irreducible with this
feature set; richer instrumentation (per-cell timestamps, per-constraint
durations) would be needed to push further.

## Hints and future refinements

`hints` is tracked but not yet folded into the level computation — we
need a few hundred plays with non-zero hints before the regression
coefficient is meaningful. Once we have enough data, the same fitting
procedure will give us a multiplier that slots in next to `failures`:

```
expectedDuration *= k^hints     // k probably in [1.3, 2.0]
level_i = ... + 75·log(k)·hints
```

Other directions we may explore:

- **Per-constraint skill** — a player may breeze through `GS` puzzles
  and struggle on `SY`. The current level collapses all constraint types
  into a single scalar.
- **Observed difficulty** — aggregate the per-puzzle average duration
  across players as an alternative to the solver-derived `cplx`. The
  divergence between the two is the most interesting signal we do not
  currently capture.
- **Confidence metric** — expose the per-play variance (or a standard
  error on the averaged level) so the UI can say "Lv 42 ± 6" and
  suppress auto-adjustments when confidence is low.
- **Engagement signals** — skips, dislikes, and pleasure ratings
  currently feed nothing but the stats screen. They are candidates for
  future weighting.

## Testing

`test/adapt_to_player_test.dart` covers `computePlayerLevel`,
`getPuzzlesByLevel`, and `hasUnplayedIgnoringFilters` with inline
fixtures. The Gaussian draw is tested with a pinned RNG to make the
distribution check deterministic. `test/cli_stats_test.dart`
covers `StatEntry.parse` including the backwards-compatible `hints`
field. Both suites build their data directly from synthetic puzzle lines
rather than shipping a stats fixture, so they run in milliseconds and do
not drift when the real `stats/` files change.
