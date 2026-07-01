# SY-based puzzles — generation by island growth

Pipeline lives in `lib/getsomepuzzle/generator/prefill/sy.dart`, gated
by `GeneratorConfig.syBasedScenario` (set by `--scenario sy-based` or
by the equilibrium's `profile` axis picking
`ProfileCategory.syBased`).

Sibling of [`path_based.md`](path_based.md). Same family — *theme-first*
generation built around a single dominant constraint — but the
dominant slug here is `SY` (SymmetryConstraint) rather than `LT`.

## What a SY-based puzzle is

The player's primary reasoning is **reconstructing symmetric shapes**
from a few seeds. The grid is partitioned into:

- a **background** of one uniform colour (say white) filling most of
  the grid;
- a few **islands**, each in its own colour drawn from
  `domain \ {bg}`, each carrying one or more `SY` constraints that pin
  its shape down. On a 2-colour domain this degenerates to the classic
  dichotomy (all islands in the colour opposite to the background).

The intellectual work is mirroring a few revealed island cells across
their declared axis until each island is fully recovered, while
convincing oneself that two islands can't be merged without breaking
their respective symmetries.

> **Domain-aware.** `preFillSy` receives `GeneratorConfig.domain` and
> colours islands within it. On a 3-colour domain, the colour
> assignment (`pickIslandColors` in `sy.dart`) guarantees at least two
> distinct island colours whenever there are ≥ 2 islands — otherwise
> the puzzle would be functionally 2-colour and the generator's
> auto-shrink would relabel its exported line as `v2_12_...`, wasting
> the domain-3 attempt.

### Why this design

- **Aesthetic identity.** `SY`'s icons (`⟍ | ⟋ ― 🞋` — cf.
  `axisRepresentation` in `symmetry.dart`) are the most graphically
  expressive in the constraint set. A puzzle that pins three or four
  such icons on a mostly-empty grid signals visually: *those marked
  cells are the pivots of geometric shapes; uncover them.* In the
  grid-first flow `SY` typically applies to a single isolated cell,
  collapsing into a triviality check.
- **Lifts a generator limitation.** A uniformly random fill rarely
  produces geometrically clean symmetric shapes; planting them
  deliberately makes SY-rich puzzles tractable.
- **Surfaces under-used deduction.** `SymmetryConstraint.apply`
  carries three rules at complexity 1–3 (mirror inside the group;
  frontier rule; out-of-bounds/opposite-mirror look-ahead). A
  SY-dominant puzzle brings rule 3 — "if I extend this island one
  step left, its mirror lands outside the grid; this cell must stay
  background" — to the centre of the trace.

## Player view (example)

6×6 puzzle with two islands:

```
. . . . . .
. ⟍ . . . .
. . . . . .
. . . | . .
. . . . . .
. . . . . .
```

`⟍` at (1, 1) carries the diagonal axis; `|` at (3, 3) carries the
vertical axis. The two groups can't merge (the merged group would
need both symmetries). The greedy adds a few guardrails (`QA:8`,
`GS:…`) and/or reveals one cell per island; from there the player
propagates mirrors outward until each island is closed off.

The trace shape we aim for:

- high `sy-share` (analogue of `lt-share` for path-based);
- moderate `force_depth` — the SY look-ahead rule already stretches
  the deduction;
- low `cascade_ratio`.

## Pipeline

`preFillSy` plugs in as the fourth pre-fill mode alongside
`preFillRegular`, `preFillSh`, and `preFillPath`. Unlike
`preFillRegular`/`preFillSh`/`preFillPath` — which all feed a solved
grid to candidate enumeration + greedy cherry-pick — it builds the
complete puzzle itself, so `generateOne` **bypasses candidate enumeration
and greedy cherry-pick** and `return`s through `_finalize` directly. Only
the shared finalisation tail (validity replay, classification, easing,
polish, domain auto-shrink) runs.

The pipeline runs five stages.

### 1. Background colour

Uniform random over the domain values (purple can be the background on
a 3-colour domain). No a priori bias. Island colours are assigned
after growth, per island, from `domain \ {bg}` (`pickIslandColors`),
with the ≥ 2 distinct island colours guarantee on 3-colour domains.

### 2. Seed sampling

Places `N` *seeds* — the cells that will carry the SY anchors — with
two separation rules:

- **Seed distance from grid edge** ≥ `edgeMargin` (1 on 6×6, up to
  2 on 8×8). `SymmetryConstraint.computeSymmetry` returns `null` when
  the mirror falls outside the grid, so a seed flush against a wall
  has half its axes dead from the start. Interior seeds keep all
  five axes alive. **This rule applies to the seed only** — islands
  are expected to grow into the border. A puzzle where no island ever
  touches the border tells the player every border cell is
  background.
- **Inter-seed distance** ≥ `minSeedDist` (target
  `max(3, ⌈min(W,H)/2⌉)`). Two seeds whose islands could plausibly
  merge under their respective axes break the puzzle's intent.

`N` is small — default `N ∈ {2, 3}` on grids ≤ 6×6, up to `{3, 4}` on
8×8. If the interior is too small for `N` seeds the pre-fill bails
and the caller retries with a fresh RNG.

### 3. Axis assignment per seed

For each seed, draw an axis from `1..5` (`⟍ | ⟋ ― 🞋`), filtered to
those that keep room to grow:

```
feasible_axes(seed, W, H) := { a ∈ 1..5 |
   computeSymmetry(seed, a) ≠ null
   AND distance from seed (along the perpendicular of a) ≥ growthMin }
```

For axis 5 (`🞋` point-symmetric) the seed shouldn't be on the
boundary; for axis 2 (`|` vertical), the seed needs room left and
right; etc. Selection is currently uniform random over feasible axes.

### 4. Growth under SY

Each island starts as `{seed, mirror(seed)}` (or just `{seed}` if the
seed sits on its own axis) and grows one **pair** at a time — a new
cell and its mirror.

Per-island invariants kept during growth:

- `island` — set of grid indices belonging to the island (painted in
  the island's own colour at the end of growth);
- `moat` — set of cells currently `bg` that *border* the island.
  Non-negotiable: turning a moat cell `fg` would either expand past
  the symmetric closure or merge with a neighbour;
- `forbidden_for_growth` — globally computed: all other islands ∪
  their seeds ∪ a one-cell halo around them (merge-prevention
  buffer). The halo includes the mirror under each neighbour's axis
  of every moat cell, otherwise mirror-image collisions slip
  through.

A growth step (per island, randomised order across islands) picks a
free 4-neighbour of the island that is not forbidden, computes its
mirror under the island's axis, and adds the pair. It refuses cells
whose mirror falls out of bounds or into `forbidden_for_growth`.
Self-mirroring cells (on the axis) are added alone.

Two stopping signals:

- A successful growth step has probability `stopProb` (target
  0.15–0.25) of terminating the island. Keeps shapes diverse —
  without it every island grows to maximum density.
- `maxSize` (default `⌈W·H / (2·N)⌉` — half the grid divided by the
  number of islands) caps very aggressive growth so one island
  doesn't eat half the grid before another even starts.

When every island is frozen, each island is painted in its own colour
(`pickIslandColors`) and the rest of the grid `bg`.

### 5. Bipartite disambiguation

Same cascade structure as the SY pre-fill's own bipartite step, with
SY-aligned priorities:

| # | Action | Accept iff |
|---|---|---|
| 1 | **Seed reveal** — mark the SY anchor cell `readonly` | propagates ≥ 2 free cells |
| 2 | **Island-body reveal** — mark a non-anchor island cell `readonly` | propagates ≥ 2 free cells |
| 3 | **GC or QA** (50/50), capped at one per `(slug, color)` | `puzzle.computeRatio()` drops |
| 4 | **Any other guardrail** — LT, FM, PA, GS, … | `puzzle.computeRatio()` drops |

`SY` is excluded from the guardrail pool (it's the dominant
constraint; we don't want collisions). `SH` is excluded (two
shape-flavoured constraints would compete). `FM` candidates touching
any island cell are filtered. `LT` is kept with one filter: all
anchors must lie in the same region (all ocean, or all inside one
specific island) — inter-island LT would force a merge.

**Candidate consumption (steps 3/4) — classic-style.** A guardrail
candidate that does not lower `computeRatio()` is **definitively
removed** from the candidate pool. Same convention as the legacy
generator loop. Rationale: with 4 000+ candidates on a 6×6 grid,
keeping non-helpers in the pool causes O(N × iterations) re-tests at
the worst possible moment — when `puzzle.constraints` is fattest and
each `clone().solve()` is most expensive.

**Shared solved snapshot.** Each cascade iteration solves the current
puzzle once into a `solvedBase` snapshot; every probe of the iteration
(reveal candidates via `_revealPropagates`, guardrail candidates via
`_constraintHelps`) clones *that* instead of re-solving the base — one
solve per candidate instead of two, starting from an already-propagated
state. The snapshot is refreshed after a rollback (the puzzle changed).
This matters most on 3-colour domains, where weak propagation makes
every `solve()` degenerate into `_forceOneCell` sweeps.

**Deadline (`shouldStop`).** `preFillSy` accepts the caller's
`shouldStop` and checks it between attempts, cascade iterations, pool
entries and candidates, and forwards it to every inner `solve()`
(including `isDeductivelyUnique`, where an aborted solve returns
`false` — never a false positive). Without it, a single 3-colour
attempt can run for minutes past the worker's `maxAttemptTime`.

**Non-monotonic `solve()` rollback safety net.**
`_constraintHelps(solvedBase, c)` is the fast filter: add `c` on top of
the solved snapshot, re-solve, compare ratios. Cheap but
**non-monotonic** — adding `c` to an already-solved clone is not the
same as adding `c` to the original puzzle and solving from scratch,
because `solve()` is order-sensitive. A candidate that looks helpful
in the filter can therefore make the real puzzle regress.

Mitigation: at the top of each cascade iteration, measure free cells
on a fresh probe and compare against the previous iteration. If
`free` strictly grew **and** the previous phase was a guardrail
(phase 3/4), pop the last constraint and continue. Reveals
(phase 1/2) are immune to rollback — materialising a cell cannot
regress propagation by construction.

Two hard bailouts complete the safety net:

- `guardRail ≥ 8` — a 6×6 puzzle that hasn't converged after 8
  guardrails rarely will in the current attempt.
- `consecutiveRollbacks ≥ 5` — the cascade is consuming candidates
  without lowering the deduction floor.

## What ends up readonly

Three sources of `readonly` cells in the final puzzle:

1. **Standard-style prefill sprinkle** (in `sy.dart`, after SY
   anchors are attached). Mirrors `preFillRegular`: pick
   `ratio ∈ [0.75, 1.0]`, set `prefilled = ⌈size · (1 − ratio)⌉`
   random cells to their solution value as `readonly`. Crucial:
   without it the bipartite cascade has to brute-force uniqueness
   from zero anchored cells and almost never converges.
2. **Strategic seed reveals** (cascade step 1).
3. **Strategic island-body reveals** (cascade step 2).

Guardrails (steps 3–4) never add readonly cells, only constraints.

## API

```dart
SyPrefillResult? preFillSy(
  int width,
  int height,
  List<CellValue> domain,   // 2- or 3-colour; islands ∈ domain \ {bg}
  Random rng, {
  int? numIslands,          // default: 3 if W·H ≥ 40 else 2
  int edgeMargin = 1,
  int? minSeedDist,         // default: max(3, ⌈min(W,H)/2⌉)
  double stopProb = 0.2,
  int minIslandSize = 3,
  int? maxIslandSize,       // default: ⌈W·H/(2·N)⌉
  int maxRetries = 30,
  int? bipartiteMaxReveals, // default: 2 per island
  bool Function()? shouldStop,          // caller deadline
  void Function(String)? debugLog,      // instrumentation hook
});

class SyPrefillResult {
  final Puzzle puzzle;              // SY + guardrails + reveals
  final List<CellValue> solution;
  final int numIslands;
  final int seedRevealedCount;
  final int islandCellRevealedCount;
  final int guardRailCount;
  int get revealedCount => seedRevealedCount + islandCellRevealedCount;
}
```

`bin/validate_sy_domain3.dart` runs the pipeline end-to-end over a
seed sweep with per-cascade-iteration instrumentation (`--domain`,
`--seeds`, `--retries`, `--budget-ms`, `--quiet`) and reports the
ok / timeout / failed split — the tool of choice before touching the
cascade's cost profile.

## Why SY makes this naturally work

Reading `SymmetryConstraint.verify` (`symmetry.dart:67-81`):

- The constraint is parameterised by **one anchor cell**
  (`indices[0]`) and one **axis**.
- `verify` checks that the *group containing the anchor* has every
  member's mirror either free or same-coloured.

Two consequences that align with the pipeline:

1. **Merge prevention is automatic.** If a growth step bridged two
   islands `I₁` and `I₂` with different axes `a₁` and `a₂`, the
   merged group would need to be symmetric under both — generally
   infeasible. The solver detects this via `verify` returning
   `false`. Merge-prevention comes for free.
2. **Look-ahead rule fires often during play.** The rule at
   `symmetry.dart:160-186` checks whether extending an island one
   cell further would import a subtree with any mirror out-of-bounds
   or already opposite-coloured. That's the "this cell must stay
   background" deduction we want to surface.

## Caveats

- **Trivial shapes.** A 2-cell island has no shape personality.
  Growth must reliably produce ≥ 4-cell islands on standard grids;
  configurations that don't are tracked by `min_island_size` and
  rejected.
- **Trivial border tell.** Mitigated by keeping only *seeds* off the
  border (§ 2); growth is free to reach it. Worth post-checking that
  a healthy fraction of puzzles has at least one island touching the
  border.
- **Visual collisions.** Two SY icons too close on the rendered grid
  look noisy. Guarded by `minSeedDist`.
- **Self-mirroring seeds.** When the seed sits on its axis
  (e.g. axis 5 centred on the seed, axis 2/4 with the seed on the
  axis line), `computeSymmetry(seed) == seed` and the island starts
  as the singleton `{seed}`. `feasible_axes` filters configurations
  where no growth is possible (would emit trivial 1-cell islands).

## Convergence profile (June 2026, 6×6, 2 islands)

Measured with `bin/validate_sy_domain3.dart` (20-seed sweeps, after
the shared-snapshot optimisation):

- **Domain 2**: most seeds converge in well under 10 s.
- **Domain 3**: ~30 % converge within 10 s, ~50 % within 30 s
  (8 retries); with the default `maxRetries = 30` and a
  production-like budget (`max-attempt-time 240s`), **10/10 seeds
  converge** — median ≈ 51 s, max ≈ 94 s. Domain-3 sy-based costs
  roughly 4-10× domain-2 per puzzle; weak 3-colour propagation makes
  every `solve()` lean on `_forceOneCell`, so attempts are slower and
  more topologies need several retries.

## Known gaps (May 2026)

- **Partial convergence (domain 2).** On 6×6 with the default
  2-island setup, roughly 60 % of seeds finish the bipartite cascade
  in under 10 s after the readonly-prefill + rollback-on-regression
  additions. The remaining ~40 % exhaust the retry budget
  (`maxRetries = 30`) or trigger the `guardRail ≥ 8` /
  `consecutiveRollbacks ≥ 5` bailouts. Hypothesis: some island
  topologies are structurally ambiguous (multiple SY-valid completions
  distinguishable only by reasoning beyond what the solver does with
  propagation alone). Levers worth trying: smarter axis pick (drop
  axes producing islands too small or too close to the border),
  stricter reveal acceptance (require unlocking a propagation chain
  that crosses an island boundary), independent two-clone
  `_constraintHelps` (slower per candidate but fewer rollbacks).
- **No `sy-share` measurement script yet.** The analogue of
  `bin/extract_path_like.dart` for SY still needs to be written.
