# Adapt to player

The game selects puzzles that match the player's current skill. The player's
level is inferred from their recent history and used to pick puzzles slightly
ahead of that level, nudging them upward while keeping the pace comfortable.

## Overview

- **Player level** is an integer in the same scale as puzzle `cplx` (0–100).
  It is either set manually with the slider in the settings, or computed
  automatically from the last plays (toggle `autoLevel`, `true` by default).
- **Puzzle selection** pulls from a `[level−1, level+2]` window around the
  player level. Asymmetric on purpose: one easier tier for variety, two
  harder tiers to pull the player upward.
- **End-of-tier UX**: when the window is exhausted, an `EndOfPlaylist`
  widget tells the player whether they have genuinely solved everything
  at this tier or whether their filters are hiding candidates, and offers
  a one-click jump to the next populated level.

## Player level

### Scale

`playerLevel` lives in `Settings` (0–100, persisted in `SharedPreferences`).
It is always expressed in the same unit as `PuzzleData.cplx` — no secondary
scale, no arbitrary multiplier. A level of 42 means "the player performs
like an average solver of `cplx=42` puzzles".

### Expected duration

The core model, calibrated by log-linear regression on ~1300 real plays:

```
expectedDuration(cplx, cells, failures)
    = 0.92 · cells · exp(cplx / 75) · 1.65^failures
```

- `cells = width · height` — grid size matters almost as much as `cplx`:
  the regression gave an exponent of 1.009 on `log(cells)`, i.e. duration
  grows linearly with grid size.
- `cplx` is clipped to 80 before evaluation: the complexity function
  attributes 100 to any puzzle that requires backtracking, including
  easily-guessed ones, which biases the model at the top end.
- `1.65^failures` penalises wrong-click episodes. Rare in practice
  (≈96 % of plays have no failures), but when they occur they roughly
  double-to-triple the duration.

This model sits inside `Database` as `_expectedDuration` and is not exposed:
nothing outside the level computation needs it.

### Level computation

`Database.computePlayerLevel({required int fallback})` inverts the model:

```
level_i = 75 · ( log(duration_i) − log(cells_i) − 0.504·failures_i + 0.086 )
```

For each of the last 50 plays — filtered to `played && finished && !skipped
&& duration > 0` — we compute `level_i` and take a weighted average with
**exponential decay, half-life = 25 puzzles**. The duration is clamped to
`10 · expected` up front so that a puzzle left open for hours does not
swing the result.

If fewer than 10 usable plays are available, we return `fallback` (usually
the currently stored level) rather than snapping to 0 — this preserves any
manually set level during onboarding.

`autoLevel` toggling is live: flipping it on in Settings triggers an
immediate recompute without waiting for the next puzzle to finish, and
updates the playlist and current puzzle on the fly. The slider in Settings
becomes read-only while `autoLevel` is on, with an `(auto)` hint next to
the label. The `TimerBottomBar` also shows `Lv N` during play, with a
trailing `*` when it is computed rather than manual.

## Puzzle selection

`Database.getPuzzlesByLevel(level)` returns `filter()`-ed puzzles whose
`cplx ∈ [level − 1, level + 2]`, shuffled. The window is tight on purpose:
with ~11 000 puzzles in `assets/default.txt`, even the thinnest tier still
yields dozens of candidates, and a wider window would water down the
"nudge upward" effect.

`preparePlaylist` uses this when `shouldShuffle` is `false`. When
`shouldShuffle` is `true`, the player has explicitly asked for the full
filtered catalog in random order — the adaptive window is bypassed
entirely. `autoLevel` and `shouldShuffle` are orthogonal; shuffle wins.

User-set filters (size, rules) combine with the level window: they act
as hard constraints the player has chosen to impose. The UX surfaces
that interaction when it backfires — see below.

## End of playlist

When `getPuzzlesByLevel` returns an empty list, `loadPuzzle` clears the
puzzle state and `EndOfPlaylist` takes over. It distinguishes two cases
using `Database.hasUnplayedAtLevelIgnoringFilters(level)`:

- **Filters are hiding candidates** — unplayed puzzles exist at this
  level, but are excluded by the user's filters. The widget says so
  explicitly, inviting the player to relax them.
- **Tier genuinely exhausted** — the player has played everything
  accessible at this level. The widget congratulates them.

In both cases, the widget also exposes a one-click jump to the next
populated level via `Database.nextPopulatedLevel(current)`. That method
walks upward and returns the smallest level whose window would produce
at least one candidate (respecting filters). The button label includes
the gap: "Jump to level 25 (+7)". When no higher level is populated,
the button is replaced by a "top of the catalog" message.

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

The `expectedDuration` coefficients are not speculative — they come from
OLS on 1335 plays (after trimming `duration > 600 s`). The analysis lives
in the git history of this file and on the `puzzle_stats.txt` artefact;
the headline results:

| Model | R² | MAPE |
|---|---:|---:|
| `log(dur) = a·cplx + b` | 0.21 | 73 % |
| `+ log(cells)` | **0.43** | 57 % |
| `+ failures` | **0.45** | 56 % |
| `+ sqrt(cplx)` variant | 0.47 | 54 % |

Adding `log(cells)` as a predictor roughly doubles the explained variance,
confirming that grid size is a first-order effect and not a correction.
The `sqrt(cplx)` variant is marginally better but harder to invert, so we
picked the linear-in-`cplx` form.

Per-play noise is large (IQR of the inferred level: ~72 points), which is
why the level is averaged over up to 50 plays. Fewer than ~10 plays give
too-noisy a signal to be useful — hence the fallback threshold.

### Known limitation: `cplx = 100`

Puzzles flagged `cplx=100` (those requiring backtracking) are not reliably
harder than the highest non-backtracking tier. Observed durations on these
puzzles are about half what the model predicts. The clamp to 80 in
`_expectedDuration` neutralises this for level inference. Refining the
complexity function to discriminate "shallow" vs "deep" backtracking is
a separate task.

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
`getPuzzlesByLevel`, `hasUnplayedAtLevelIgnoringFilters`, and
`nextPopulatedLevel` with inline fixtures. `test/cli_stats_test.dart`
covers `StatEntry.parse` including the backwards-compatible `hints`
field. Both suites build their data directly from synthetic puzzle lines
rather than shipping a stats fixture, so they run in milliseconds and do
not drift when the real `stats/` files change.
