# Boss Mode — "seed-and-grow" generator

A generator variant aimed at **large puzzles** (≥ 30×20), playable on
desktop / tablet only. The default random prefill (`preFillRegular`)
produces white-noise grids that are uninteresting at this scale; boss
mode replaces that first step with a "plant seeds, grow each one"
algorithm that builds coherent blobs, then tunes the rest of the
generator pipeline to be tractable on 600+ cell grids.

## CLI activation

Dedicated flag: `--boss`.

```bash
dart run bin/generate.dart -n 1 -j 1 \
  -W 30 --max-width 30 -H 20 --max-height 20 \
  --boss --max-time 600
```

- Without `-o`, output goes to `assets/boss.txt` (so boss puzzles don't
  pollute the difficulty-routed default sinks).
- `--boss` **implicitly disables `--equilibrium`**: the warm-up phase
  locks the generator into a 2-slug configuration that is way too thin
  for 30×20 grids.
- No upper-bound dimension validation: the CLI accepts whatever you
  pass — your responsibility.

## Prefill algorithm

The prefill lives in `lib/getsomepuzzle/generator/prefill/boss.dart` as
a standalone `preFillBoss` function, following the same pattern as the
other prefill files (`prefill/sh.dart`, `prefill/bb.dart`, etc.).

### Constants

- `_fillRatio` = 0.70 — target fill proportion for phase 1.
- `_minGroupSize` = 15, `_maxGroupSize` = 25 — each seed targets a
  group size drawn uniformly from this range.
- `_maxSameGroup` = 3 — cap on GS constraints targeting the same
  connected component (prevents N copies of the same statement when
  several seeds fuse during random fill).

### Phase 1 — Seed-and-grow (until ~70 % filled)

1. Compute a **weight** for every free cell:
   - First seed: `weight = min(x, w-1-x, y, h-1-y)` (Chebyshev distance
     to the nearest edge).
   - Subsequent seeds: `weight = min(distEdge, distFilled)` — Chebyshev
     distance both to the edge and to the nearest already-filled cell,
     whichever is smaller. `+1` so weights stay strictly positive.
   - `distFilled` is recomputed at each seed via 8-connected Chebyshev
     BFS (O(n) per call).
2. **Sample a seed** via cumulative weighted draw.
3. Random colour in `domain`, uniform target size in `[15, 25]`.
4. **Grow**: while `group.length < target`:
   - Collect all free 4-neighbours of every group cell.
   - Empty → break (group ends up smaller than target — accepted).
   - Pick one uniformly, paint it, add to the group.
5. Store `(pivot, color)` in `seeds`. The `GroupSize` constraint is
   **not posted yet** — its final value depends on phase 2b fusion.

### Phase 2a — Random fill of the remaining ~30 %

For every still-empty cell, draw a random colour and paint it. This
**can grow** a seeded group if the random colour matches a neighbour
that belongs to one. Empirically this fuses many same-colour seeds
into one.

### Phase 2b — Post-fill: post the GroupSize constraints

Maintain a `Map<int canonical, int count>` of components already
constrained. For each seed:
- BFS the same-colour connected component from `pivot`. Track the
  canonical pivot (smallest cell index in the component).
- If `componentCounts[canonical] >= _maxSameGroup`, skip — too many
  copies of the same statement already posted.
- Otherwise post `GroupSize('$pivot.${visited.length}')` with the
  **actual** post-fusion size, increment the counter.

This keeps the constraint set lean even when several seeds collapse
into one component during phase 2a, and avoids any post-hoc mutation
of `GroupSize.size`.

### Phase 3 onward — Standard generator

The puzzle produced by `preFillBoss` enters the standard generator
pipeline (`_generateOneTimed`) which adds more constraints via the
phase-gated loop until the puzzle is uniquely deductive.

## Playing a boss puzzle in-app

A 30×20 grid carries ~600 cells and several hundred constraints after
the phase 4 batches. The in-app solver-driven features were never tuned
for that scale: leaving them on during play saturates a CPU core
continuously and the UI judders on every interaction.

**Recommendation: before opening a boss puzzle, disable solver-driven
features in Settings.**

| Setting | Recommended value | Why |
|---|---|---|
| **Hints** (`hintsEnabled`) | **OFF** | Disables the lightbulb button and all three post-mutation hint pre-computes. Without this, every tap triggers a `findAMove(tryForce=true)` (~1100 clones on 600 cells). |
| **Grayout** (`grayoutEnabled`) | **OFF** | Disables the per-tap `isCompleteFor` scan. Several constraints (`GS`, `SY`, `EY`) walk the full grid in their `isCompleteFor`. |
| **Validation** (`validateType`) | **Manual** | `checkPuzzle` early-returns when `validateType == manual && !manualCheck`. |

## Out of scope

- Dynamic group-size parameterisation by grid size.
- Flutter UI (`generate_page.dart`) — CLI-only for now.

## Porting context from `origin/boss`

The seed-and-grow prefill code originates from commit
[`d66cb79`](https://github.com/anomalyco/getsomepuzzle/commit/d66cb799b2598690e7c136e45b968902a96e604e)
on `origin/boss`. That commit also included:

- Batch addition (30 constraints at a time instead of 1 by 1)
- Persistent solved state (`bossSolvedState`) avoiding re-solves
  from scratch between batches
- Capped candidates (1000 per slug) + per-slug reserves
- Propagation-only mode (skip force) throughout the pipeline
- Per-phase debug `onLog` callback

These optimisations were designed for the old monolithic generator
(before the `phaseGate` / `_StageTimer` / `_generateTargetedKeys`
refactor). The current generator (`_generateOneTimed`) has too
different an architecture to cherry-pick them as-is. They were
**not** ported in this first step.

### What was ported (this step)

| Item | File |
|---|---|
| Seed-and-grow algorithm | `lib/getsomepuzzle/generator/prefill/boss.dart` |
| `useBossPrefill` field in `GeneratorConfig` | `generator.dart` |
| Dispatch in `_generateOneTimed` | `generator.dart` |
| `--boss` CLI flag + default `assets/boss.txt` + help | `bin/generate.dart` |
| Documentation | `docs/dev/boss.md` |

### What was *already ported* from `origin/boss` into HEAD

The two Settings toggles `hintsEnabled` / `grayoutEnabled` and the
`tryForce` parameter on `solve()` / `solveExplained()` / `findAMove()`
were already in HEAD before this port.

### What remains to be ported or re-implemented from `origin/boss`

| Item | Status |
|---|---|
| Capped candidates (max 1000/slug) + reserves | Not ported — needs re-implementation in the current architecture |
| Batch addition (30/batch) | Not ported — requires `phaseGate` re-architecture |
| Persistent solved state (`bossSolvedState`) | Not ported — coupled to batch addition |
| Propagation-only mode throughout the pipeline | Partially ported: `tryForce: false` exists, but is not activated by `useBossPrefill` in the generator |
| Per-phase debug `onLog` callback | Not ported — `_StageTimer` partially covers this |
| Generate and ship `assets/boss.txt` puzzles | TODO — run `dart run bin/generate.dart --boss` |
| Pipeline tweaks: skip `sortConstraintsByDifficulty` in boss mode | Not ported |
| UI optimisations for boss puzzles in `main.dart` | Not ported — `hintsEnabled`/`grayoutEnabled` toggles exist, but no auto-detection of large grids |
