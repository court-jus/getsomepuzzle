# Adapt to player

The game selects puzzles that match the player's current skill. The player's
level is inferred from their recent history and used to pick puzzles slightly
ahead of that level, nudging them upward while keeping the pace comfortable.

## Overview

- **Player level** is an integer in the same scale as puzzle `cplx` (0–100).
  It is either set manually with the slider in the settings, or computed
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

`playerLevel` lives in `Settings` (0–100, persisted in `SharedPreferences`).
The scale is **anchored at 50 = the calibration cohort's pace**: a
player who solves at the same speed as the historical baseline trends
toward 50, faster players go above, slower below. This puts the
"average" player in the middle of [0, 100] instead of at 0 or near 0.

The unit is still puzzle-`cplx`-compatible: the puzzle selector compares
`level` against `cplx` directly via the Gaussian weighting (see below).
But the absolute number `42` no longer means "performs like a `cplx=42`
solver" — it means "42 in the centred-on-50 skill scale".

### Expected duration

The core model is OLS-fit on real plays:

```
expectedDuration(cplx, cells, failures, n_constraints)
    ≈ 8.62 · cells^0.442 · exp(cplx / 27.3)
         · 1.145^failures · 1.085^n_constraints      (R²=0.70, MAPE=29%)
```

- `cells = width · height` — duration grows sub-linearly with the grid
  (exponent 0.442): a fraction of the cells in larger grids are "obvious"
  and cost little.
- `cplx` slope of `1/27.3` — much steeper than the previous `1/74`
  estimate. Once `n_constraints` is in the model, cplx and constraint
  count untangle and `cplx` carries a stronger marginal signal.
- `1.145^failures` penalises wrong-click episodes. Mild on purpose:
  ~84 % of plays have zero failures, so the multiplier is fit to the
  cases where there *are* failures; aggressive multipliers (1.65) have
  always overcorrected.
- **`1.085^n_constraints`** captures parsing/setup cost, new in
  v1.6.1. A 4×4 grid with 12 constraints takes meaningfully longer
  than the same grid with 3, even at identical `cplx`. Adding the term
  lifts R² from 0.61 to 0.70 on the calibration cohort.
- The intercept (`8.62 = exp(2.155)`) is **anchored**: it is shifted
  from the OLS-minimum-MSE intercept by `+1.50` so the cohort's mean
  `level_i` lands on **50** instead of on the cohort's mean `cplx`.
  This is a deliberate shift in interpretation, not a fit error: the
  formula intentionally over-predicts the cohort's durations, because
  we want a "matches the cohort" pace to read as middle-of-the-bar,
  not bottom-of-the-bar.
- No artificial clamp on `cplx`. Puzzles with `cplx=100` (the legacy
  "non-deductively-solvable" bucket) are no longer emitted by the
  generator; they're still in legacy `assets/default.txt` lines but no
  longer biased the calibration once recomputed.

This model sits inside `Database` as `_expectedDuration` and is not exposed:
nothing outside the level computation needs it. The companion
`_impliedCplx(dur, cells, failures, nConstraints)` is its algebraic
inverse, used by the level computation below.

### Level computation

`Database.computePlayerLevel({required int fallback})` uses a skill
inversion: faster than expected ⇒ implicit level above `cplx`; slower ⇒
below. The intercept anchor on the duration model shifts the output up
by ~41 cplx-units so the cohort centres on 50.

```
level_i = 2 · cplx_i − impliedCplx(duration_i, cells_i, failures_i, n_cons_i)
       where impliedCplx(d, c, f, n) = 27.3 · ( log(d) − log(8.62)
                                            − 0.442·log(c)
                                            − 0.135·f − 0.082·n )
```

When a play's duration matches the (anchored) expected duration for its
`cplx`, `level_i = cplx`. The cohort's *typical* pace, however, is
faster than this anchored expected — by design — so cohort plays come
in around 50 on average rather than around their puzzle's `cplx`.

For each of the last 50 plays — filtered to `played && finished &&
!skipped && duration > 0` — we compute `level_i` and take a weighted
average with **exponential decay, half-life = 25 puzzles**. The
duration is clamped to `[1, 10·expected]` up front so a puzzle left
open for hours does not swing the result.

If fewer than 2 usable plays are available, we return `fallback`
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

`preparePlaylist` uses this when `shouldShuffle` is `false`. When
`shouldShuffle` is `true`, the player has explicitly asked for the full
filtered catalog in random order — the Gaussian bias is bypassed
entirely. `autoLevel` and `shouldShuffle` are orthogonal; shuffle wins.

User-set filters (size, rules) intersect the catalog before weighting:
they act as hard constraints the player has chosen to impose. When they
backfire, `EndOfPlaylist` surfaces it (see below).

The selection knobs `selectionOffset` and `selectionSigma` are
constants today. Wiring them through `Settings` would unlock UX
modes like "challenge" (`offset = +5`), "rest" (`offset = −3`) or
"variety" (`σ = 10`).

## End of playlist

When `getPuzzlesByLevel` returns an empty list, `loadPuzzle` clears the
puzzle state and `EndOfPlaylist` takes over. With Gaussian sampling the
list is empty only when `filter()` itself is empty, which yields just
two cases — surfaced via `Database.hasUnplayedIgnoringFilters()`:

- **Filters are hiding candidates** — at least one unplayed/non-skipped/
  non-disliked puzzle exists in the catalog but is excluded by the
  user's filters. The widget invites the player to relax them.
- **Catalog genuinely exhausted** — every puzzle has been played,
  skipped or disliked. The widget congratulates the player.

There is no longer a "jump to the next populated level" affordance:
with weighted sampling, no level is unreachable by definition.

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

Current model and its immediate predecessor on the recomputed dataset:

| Formula | R² | MAPE | Notes |
|---|---:|---:|---|
| `1.4·cells^0.85·exp(cplx/74)·1.29^f` | 0.44 | 59 % | pre-1.6.1 (no `n_constraints`, OLS-minimum intercept) |
| **`8.62·cells^0.442·exp(cplx/27.3)·1.145^f·1.085^n_cons`** | **0.70** | **29 %** | **current (1.6.1+, anchored at level 50)** |

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

Per-play noise is still substantial — per-play std of `level_i` ≈ 13 on
the cohort, so the rolling average over 50 plays (half-life 25) is what
gives a stable reading. R² of 0.70 means ~30 % of variance is
irreducible with this feature set; richer instrumentation (per-cell
timestamps, per-constraint durations) would be needed to push further.

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
