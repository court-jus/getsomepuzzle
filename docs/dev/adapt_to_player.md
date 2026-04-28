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
It is always expressed in the same unit as `PuzzleData.cplx` — no secondary
scale, no arbitrary multiplier. A level of 42 means "the player performs
like an average solver of `cplx=42` puzzles".

### Expected duration

The core model, recalibrated by log-linear regression on 1815 real plays
(see `bin/analyze_stats.dart`; cplx values were recomputed with the
current complexity formula to homogenise across game versions):

```
expectedDuration(cplx, cells, failures)
    ≈ 1.4 · cells^0.85 · exp(cplx / 74) · 1.29^failures      (R²=0.44, MAPE=59%)
```

- `cells = width · height` — duration grows sub-linearly with the grid
  (exponent 0.85): a fraction of the cells in larger grids are "obvious"
  and cost little.
- `cplx` slope of `1/74` — broadly consistent across game versions once
  cplx values are recomputed. Empirically the previous "x/50" scale was
  too steep and the older "x/75" was very close.
- `1.29^failures` penalises wrong-click episodes. Rare in practice
  (≈84 % of plays have zero failures). The earlier `1.65^failures`
  guess was much too aggressive; on real data each failure costs about
  29 % more time, not 65 %.
- No artificial clamp on `cplx`. Puzzles with `cplx=100` (the legacy
  "non-deductively-solvable" bucket) are no longer emitted by the
  generator; they're still in legacy `assets/default.txt` lines but no
  longer biased the calibration once recomputed.

This model sits inside `Database` as `_expectedDuration` and is not exposed:
nothing outside the level computation needs it. The companion
`_impliedCplx(dur, cells, failures)` is its algebraic inverse, used by
the level computation below.

### Level computation

`Database.computePlayerLevel({required int fallback})` uses a "skill"
inversion (A3): when a play's duration matches the model for its
`cplx`, `level_i = cplx` exactly. Faster than expected ⇒ implicit level
above `cplx`; slower ⇒ below.

```
level_i = 2 · cplx_i − impliedCplx(duration_i, cells_i, failures_i)
       where impliedCplx(d, c, f) = 74 · ( log(d) − 0.85·log(c)
                                            − 0.252·f − 0.336 )
```

This convention keeps `level_i ≈ cplx` as a fixed point and gives
intuitive direction: a player who consistently outpaces the model
trends *upward*.

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

The `expectedDuration` coefficients come from OLS on 1815 plays after
recomputing every play's `cplx` with the current complexity formula
(older entries had cplx values from earlier formulas that were not
comparable). The tool is `bin/analyze_stats.dart`:

```
dart run bin/analyze_stats.dart --recompute-cplx stats/
```

Headline numbers on the recomputed dataset:

| Formula | R² | MAPE | Notes |
|---|---:|---:|---|
| Previous `1.25·cells·exp(cplx/50)·1.65^f` | −0.11 | 150 % | worse than predicting the mean |
| Earlier `0.92·cells·exp(cplx/75)·1.65^f` | 0.41 | 70 % | calibration good, failures coef too high |
| **Current `1.4·cells^0.85·exp(cplx/74)·1.29^f`** | **0.44** | **59 %** | refit |

Three lessons from the refit:

- The `cplx` exponential scale stabilises around `1/74` once cplx values
  are homogenised — very close to the historical `1/75`. The intermediate
  `1/50` (post-714574d) was off because the model had drifted from data.
- The `cells` dependency is sub-linear (0.85 not 1.0). Larger grids
  cost less per cell because their solutions contain more "free" cells.
- The failures multiplier is much milder than first guessed: 1.29 per
  failure, not 1.65. Plays with high failure counts dominate the bias
  if the multiplier is too aggressive.

Per-play noise remains large (per-play std of `level_i` ≈ 35), which is
why we average over up to 50 plays. R² of 0.44 means ~56 % of the
variance is irreducible with this feature set; richer instrumentation
(per-cell timestamps, per-constraint durations) would be needed to push
further.

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
