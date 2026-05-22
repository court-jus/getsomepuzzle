# SY-based puzzles — generation by island growth

> **Status**: implemented (WIP). Pipeline lives in
> `lib/getsomepuzzle/generator/prefill/sy.dart`; gated by
> `--scenario sy-based` in `bin/generate.dart` and by
> `GeneratorConfig.syBasedScenario` in the app. Convergence is partial:
> on 6×6, ~3 seeds out of 5 finish in seconds; the rest exhaust the
> retry budget. See § 11 for known gaps.
>
> Sibling of [`path_based.md`](path_based.md). Same family — *theme-first*
> generation built around a single dominant constraint — but the
> dominant slug here is `SY` (SymmetryConstraint) instead of `LT`.

## 1. Pitch

A "SY-based" puzzle is one where the player's primary reasoning is
**reconstructing symmetric shapes** from a few seeds. The grid is
partitioned into:

- a **background** of one uniform color (say white), which fills most
  of the grid;
- a few **islands** of the opposite color (black), each carrying one or
  more `SY` constraints that pin its shape down.

The intellectual work is no longer "count cells" or "route a chain"
but **mirror a few revealed black cells across their declared axis
until each island is fully recovered**, while convincing oneself that
two islands can't be merged without breaking their respective
symmetries.

## 2. Why this lead

### 2.1. Aesthetic identity

`SY` already has the most graphically expressive icons of any
constraint (`⟍ | ⟋ ― 🞋` — cf. `axisRepresentation` in
`symmetry.dart`). A puzzle that pins three or four such icons onto a
mostly-empty grid carries an immediate visual promise: *those marked
cells are the pivots of geometric shapes; uncover them.*

By contrast, in the current grid-first generator `SY` is just one of
~11 candidate slugs sampled by the greedy. When it appears it usually
applies to a single isolated cell with no surrounding shape — the
constraint becomes a triviality check ("am I alone?") rather than a
shape-recovery puzzle.

### 2.2. Limitation of the current generator lifted

Same root cause as for `LT`: a uniform random fill rarely produces
geometrically clean symmetric shapes. When it does (by chance) the
greedy might pick the matching `SY`, but the rest of the grid is
incidental noise. A theme-first generator can **plant** the symmetric
shapes deliberately and then let the existing pipeline add guardrails
around them.

### 2.3. New deduction style

The current solver already handles SY deductions in
`SymmetryConstraint.apply` — three rules with `complexity: 1..3`:

- mirror cells inside the group (basic, `complexity: 1`);
- frontier rule: a cell adjacent to the group whose mirror is filled
  with the opposite color must itself be the opposite (`complexity: 2`);
- look-ahead: a free cell whose adoption into the group would import
  out-of-bounds or already-opposite mirrors must be excluded
  (`complexity: 3`).

A SY-dominant puzzle brings these to the front. The expected feel is:
> *"If I extend this island one step left, its mirror lands outside the
> grid. So this cell must stay background."*

That's mechanically the look-ahead rule (rule 3), which is rarely the
star of the show in current puzzles.

## 3. The played scenario

### 3.1. Player view

Take a 6×6 puzzle with two islands:

```
. . . . . .
. ⟍ . . . .
. . . . . .
. . . | . .
. . . . . .
. . . . . .
```

(SY anchor `⟍` at row 1 col 1 with the diagonal `⟍` axis; SY anchor
`|` at row 3 col 3 with the vertical `|` axis.)

The player knows:
- Cell (1, 1) is part of a group symmetric along the `⟍` diagonal.
- Cell (3, 3) is part of a group symmetric along the vertical `|` axis.
- The two groups cannot merge (their respective symmetries would have
  to coexist on the merged group — generally impossible).

The puzzle starts ambiguous. The greedy adds a few guardrails
(`QA:8`, `GS:..`, …) and/or reveals one cell per island. From there
the player propagates mirrors outward until each island is closed off
by background cells.

### 3.2. Expected resolution style

On the score of [`generator.md`](generator.md) § 3.1 we want:
- a high share of `SY`-issued propagation steps (call it `sy-share`,
  the analogue of `lt-share` for path-based);
- moderate `force_depth` — the SY look-ahead rule is already a forced
  deduction (complexity 3), no need to stack on top;
- low `cascade_ratio` — no totalitarian FM chains.

## 4. Proposed generation pipeline

### General framework — a 4th pre-fill mode

The generator currently dispatches between three pre-fill modes
(cf. [`path_based.md`](path_based.md) § 4):

- `preFillRegular(W, H)` — uniformly random 50/50 grid;
- `preFillSh(W, H)` — grid pre-painted with a valid SH motif;
- `preFillPath(W, H, ...)` — LT-dominant routing.

**We add a fourth mode** `preFillSy(W, H, syConfig)` that produces:

- a complete solution grid with a background color and N
  symmetric-shape islands of the opposite color;
- the N corresponding `SymmetryConstraint`s already attached;
- the list of seed indices that may later become `readonly` reveals.

All downstream stages (candidate enumeration, greedy cherry-pick,
finalization, easing, polish) stay identical.

### 4.1. Stage 1 — background color

```
bg := rng.nextBool() ? 1 : 2
fg := domain.opposite(bg)
```

50/50 random. There is no a priori reason to bias toward one color.
We measure post-generation whether one direction produces harder
puzzles and rebalance later if needed.

### 4.2. Stage 2 — seed sampling

Place `N` *seeds* — the cells that will carry the `SY` anchors — with
two separation constraints:

- **Seed distance from grid edge** ≥ `edgeMargin` (target: 1 on 6×6,
  potentially 2 on 8×8). Reason: `SymmetryConstraint.computeSymmetry`
  returns `null` when the mirror falls outside the grid. A seed flush
  against the wall has half its axes infeasible from the start.
  Interior seeds keep all 5 axes alive.

  **This rule applies to the *seed*, not to the island it grows
  into.** Islands are expected — and encouraged — to reach the grid
  border via growth. If they never did, the player would trivially
  deduce that every border cell is background, killing the puzzle.
  Growth (§ 4.4) accepts any cell whose mirror lands in-bounds,
  including border cells.

- **Inter-seed distance** ≥ `minSeedDist` (target: `max(3, ⌈min(W,H)/2⌉)`).
  Reason: two seeds whose islands could plausibly merge under their
  respective axes break the puzzle's intent. A generous gap leaves
  room for each island to grow without colliding.

```
function sample_seeds(W, H, N, rng) -> List<int>?
  zone := interior_zone(W, H, edgeMargin)
  if |zone| < N * 3:
    return null                  // grid too small for N seeds
  placed := []
  for i in 1..N:
    for try in 1..MAX_LOCAL_TRIES:
      idx := random cell from zone
      if any p ∈ placed with manhattan(idx, p) < minSeedDist:
        continue
      placed.append(idx)
      break
    else:
      return null                // can't fit i-th seed → restart upstream
  return placed
```

`N` is small — initial target `N ∈ {2, 3}` on grids ≤ 6×6, up to
`{3, 4}` on 8×8. Beyond that the islands compete for room.

### 4.3. Stage 3 — axis assignment per seed

For each seed, draw an axis from `1..5` (`⟍ | ⟋ ― 🞋`). Two
sub-questions:

**Feasibility filter.** A seed at the very center of an axis is fine,
but a seed near a wall on a horizontal axis (`―`) would force the
single-cell island; that's not necessarily bad (a trivial SY) but
combined with growth (§ 4.4) it limits the achievable size sharply.
Filter to axes that keep room to grow:

```
feasible_axes(seed, W, H) := { a ∈ 1..5 |
   computeSymmetry(seed, a) ≠ null
   AND distance from seed (along the perpendicular of a) ≥ growthMin }
```

For axis 5 (`🞋` point-symmetric) this means the seed shouldn't be on
the boundary (otherwise growing one step requires growing into the
boundary on the other side too); for axis 2 (`|` vertical), it means
the seed has room left and right; etc.

**Choice weighting.** First version: uniform random over feasible
axes. To explore: bias toward axes that produce more compact shapes
(`🞋` and the diagonals 1/3) when room is tight, and toward axes that
produce elongated shapes (`|` and `―`) when room is generous. Defer
this calibration until we have a first batch to measure.

### 4.4. Stage 4 — growth under SY

This is the heart of the algorithm. Each island starts as `{seed,
mirror(seed)}` (often degenerate — see below) and grows one **pair**
at a time, where the pair is the new cell and its mirror.

**Per-island invariants** kept during growth:

- `island` — set of grid indices currently `fg` (opposite of bg);
- `moat` — set of cells currently `bg` that *border* the island. These
  are non-negotiable: turning a moat cell `fg` would either expand the
  island past its symmetric closure or merge with a neighbor;
- `forbidden_for_growth` — cells that must remain `bg`, computed
  globally: all other islands ∪ their seeds ∪ a one-cell halo around
  them (the merge-prevention buffer).

**Growth step** (per island, randomized order across islands):

```
function grow_one_pair(island, axis, seed, rng) -> bool
  candidates := neighbors(island) ∩ free ∩ not forbidden_for_growth
  rng.shuffle(candidates)
  for c in candidates:
    m := computeSymmetry(c, axis, seed, W, H)
    if m == null:                    // mirror out of bounds → can't grow this way
      continue
    if m in forbidden_for_growth:    // mirror lands on another island / halo
      continue
    if m == c:                       // self-mirror (cell on the axis itself)
      island.add(c)
      return true
    island.add(c)
    island.add(m)
    return true
  return false                       // no growth possible → island closed
```

**Outer loop**:

```
function grow_all_islands(seeds_with_axes, rng, params)
  islands := [ {seed_i} for each seed_i ]
  while ∃ island still growing:
    pick random island still growing
    if grow_one_pair(...) == false OR island.size ≥ params.maxSize:
      island.frozen := true
      continue
    if rng.nextDouble() < params.stopProb:
      island.frozen := true
  paint all islands as fg, the rest as bg
```

`stopProb` (target ~0.15–0.25): each successful growth has a chance of
terminating the island. Keeps shapes diverse — without it every
island grows to maximum density.

`maxSize` (target: ⌈W·H / (2·N)⌉ — half the grid divided by number of
islands): caps very aggressive growth. Without this cap one island
can eat half the grid before another even starts.

### 4.5. Stage 5 — bipartite desambiguation

Same cascade as [`path_based.md`](path_based.md) § 4.4, with SY-aligned
priorities:

- **Step 1: reveal a seed** (= the SY anchor cell) in `readonly`.
  Pulls the player's attention to the SY icon and forces the chain
  `seed → mirror → moat → expand` to start firing.
- **Step 2: reveal a non-seed island cell** in `readonly`. Subtle:
  one revealed body-cell forces its mirror cell across the axis even
  without committing the seed yet. Analogous to "path cell reveal" in
  path-based.
- **Step 3: GC or QA (50/50)**, capped at one per `(slug, color)`.
- **Step 4: any other guardrail** (LT, FM, PA, GS, …; SY and SH
  excluded — SY is the dominant constraint and we don't want
  collisions, SH would re-introduce shape interference).

Acceptance criterion for steps 1/2: the reveal must propagate beyond
the cell itself (`freeCellsBefore − freeCellsAfter ≥ 2`). Same strict
check as in `path.dart`.

**Candidate consumption (steps 3/4) — classic-style.** A guardrail
candidate that does not lower `computeRatio()` is **definitively
removed** from the candidate pool on the same iteration it is tested,
not kept for re-evaluation. Same convention as the legacy iterative
loop in `generator.dart`. Rationale: with 4 000+ candidates enumerated
on a 6×6 grid, keeping non-helpers in the pool causes O(N × iterations)
re-tests at the worst possible moment — when `puzzle.constraints` is
fattest and each `clone().solve()` is most expensive. Measured: at
guardRail=21, a single iteration dropped from 14 700 ms to ~50 ms after
switching to consume-on-test. The downside (a candidate that would have
helped *after* further reveals is lost) is acceptable because the
candidate pool is huge and the diversity easily covers the loss.

**Non-monotonic `solve()` — rollback safety net.**
`_constraintHelps(puzzle, c)` is the cheap-and-approximate filter: it
solves the puzzle once, adds `c`, re-solves, and compares
`computeRatio()`. Faster than two independent solves but
**non-monotonic**: adding `c` to an already-solved clone is not the
same as adding `c` to the *original* puzzle and solving from scratch,
because `solve()` is order-sensitive (the propagation chain it walks
depends on which constraints are present at the start). A candidate
that looks helpful in the filter can therefore make the real puzzle
*regress* on the next iteration.

Mitigation in the cascade loop: at the top of each iteration, measure
`free` on a fresh probe (`puzzle.clone().solve()`) and compare against
the previous iteration's value. If `free` strictly grew **and** the
previous phase was a guardrail (phase 3/4), pop the last constraint
off and continue. Reveals (phase 1/2) are immune to rollback —
materialising a cell value cannot regress propagation by construction.

Two hard bailouts complete the safety net:

- `guardRail ≥ 8` — empirically, a 6×6 puzzle that hasn't converged
  after 8 guardrails almost never does in the current attempt; better
  to retry with a fresh seed.
- `consecutiveRollbacks ≥ 5` — the cascade is consuming candidates
  without lowering the deduction floor; same call.

Measured: convergence rate on 6×6 went from ~33 % (2/6 seeds) to ~60 %
(6/10 seeds) in well under 10 s each, with no manual
`maxRetries`/`maxIterations` tuning.

### 4.6. Result shape

```dart
class SyPrefillResult {
  final Puzzle puzzle;              // player-facing: SY + guardrails + reveals
  final List<int> solution;         // full solution values
  final int seedRevealedCount;
  final int islandCellRevealedCount;
  final int guardRailCount;
  int get revealedCount => seedRevealedCount + islandCellRevealedCount;
}
```

## 5. What's `readonly` at the end

Three sources of `readonly` cells in the final puzzle:

1. **Standard-style prefill sprinkle** (`sy.dart`, after SY anchors are
   attached). Mirrors `preFillRegular`: pick `ratio ∈ [0.75, 1.0]`, set
   `prefilled = ⌈size · (1 − ratio)⌉` random cells to their solution
   value as `readonly`. Crucial: without it, the bipartite cascade has
   to brute-force unicity from zero anchored cells and almost never
   converges. This is the same lever that `preFillPath` should
   probably adopt — see the `TODO(prefill-readonly)` in `path.dart`.
2. **Strategic seed reveals** (cascade step 1): the SY anchor cell
   itself, when revealing it propagates `≥ 2` free cells.
3. **Strategic island-body reveals** (cascade step 2): any non-anchor
   island cell, same `≥ 2` propagation gate.

The cascade's guardrails (steps 3-4) never add readonly cells, only
constraints.

## 6. Why SY makes this naturally work

Reading `SymmetryConstraint.verify` (`symmetry.dart:67-81`):

- The constraint is parameterized by **one anchor cell** (`indices[0]`)
  and one **axis**.
- `verify` looks at the *group containing the anchor* and checks every
  member has a mirror that is either free or same-colored.

Two consequences that are exactly what we want for this pipeline:

1. **Merge prevention is automatic.** If a growth step bridged two
   islands `I₁` and `I₂` with different axes `a₁` and `a₂`, the
   merged group would have to be symmetric under both `a₁` and `a₂` —
   generally infeasible (the intersection of two symmetry orbits is
   usually trivial). The solver detects this via `verify` returning
   `false` on the proposed move. We get merge-prevention for free.

2. **Look-ahead rule fires often during play.** When a player tentatively
   extends an island one cell further, the rule at
   `symmetry.dart:160-186` checks whether the imported subtree
   (cells connected to the candidate through fg cells) has any mirror
   out-of-bounds or already opposite-colored. That deduction is
   exactly the "this cell must stay background" feeling we want.

## 7. Open questions

### 7.1. One SY per island, or several?

Default: one `SY` per island (one axis per shape). But several axes
can be simultaneously valid on a shape (a square shape is symmetric
along `|`, `―`, and both diagonals). Stacking multiple `SY`
constraints on the same island would pin the shape harder and reveal
more information — at the cost of a busier puzzle.

Recommendation for v1: one SY per island. Re-evaluate after measuring
`sy-share` distribution.

### 7.2. Self-mirroring seeds

When the seed is on the axis (e.g. axis 5 centered on the seed, or
axis 2/4 with the seed on the axis line), `computeSymmetry(seed)` ==
`seed`. The island starts as a singleton `{seed}` — trivially
symmetric. Growth from there proceeds normally by pairs.

Edge case: a seed with axis 5 (`🞋` point-symmetric) whose neighbors
all map to grid-out-of-bounds → no growth possible → the island is
the singleton. Verify in `feasible_axes` (§ 4.3) that such
configurations are filtered out, otherwise we emit trivial 1-cell
islands.

### 7.3. Two islands sharing a mirror cell

If during growth of island `A` we want to add cell `c`, and `c`'s
mirror under `A`'s axis is *also* the mirror of a cell already in
island `B` under `B`'s axis, we have a structural collision: cell `c`
can't be both `fg` (joining `A`) and `bg` (the moat of `B`). The
growth step must refuse `c`. Captured by the
`forbidden_for_growth` halo (§ 4.4) as long as the halo accounts for
**both** islands' mirror images, not just the islands themselves.

To verify in implementation: the halo of an island under axis `a`
must include the mirror under `a` of every moat cell.

### 7.4. Choice of seeds & axes vs. solvability

`preFillPath` calls DPLL to verify routing feasibility before
committing. We need an analogue here: given the seeds + axes, is the
intended shape (after growth) **achievable**? The growth procedure
itself is monotone — it only adds cells respecting all invariants —
so if it terminates with non-degenerate islands and the final grid
satisfies all SY constraints by construction, feasibility is
guaranteed.

But the resulting puzzle might still be **multi-solution** even with
the cascade. The bipartite cascade is the same uniqueness-pursuing
loop as in path-based; if it exhausts without reaching uniqueness,
the whole attempt aborts and restarts with new seeds.

### 7.5. Mode mixing with LT, FM, SH

`SH` is excluded from the guardrail pool (§ 4.5 step 4) — two
shape-flavored constraints would compete. `FM` is risky: an FM
forbidden motif occurring inside an island would force one of its
cells to flip color, breaking symmetry. We need to filter FM
candidates that touch any island cell.

`LT` is kept in the guardrail pool with one filter: **all of an LT's
anchors must lie in the same region** — either all in the ocean
(background) or all inside one specific island. Two flavours are
welcome:

- **Ocean-LT**: anchors in background cells. The LT routes through
  ocean cells of one color (background), contributing deductions
  that interact with the island geometry from the outside without
  ever crossing fg territory.
- **Intra-island LT**: all anchors inside the same island. The LT
  routes through fg cells of that island, pinning its internal shape
  further and reinforcing the SY deduction.

What we exclude is **inter-island LT** (anchors in two different
islands): solving such an LT would force the islands to merge,
breaking each island's SY. The guardrail enumeration must filter LT
candidates whose anchors span more than one island (or one island +
ocean).

## 8. Parameters to expose

Mirroring `pathBasedScenario` in `generator.dart`:

```
class SyScenarioConfig {
  int numIslands;        // 2..4
  int edgeMargin;        // 1..2
  int minSeedDist;       // ≥ 3
  double stopProb;       // 0.15..0.25
  int? maxIslandSize;    // default: ⌈W·H/(2·N)⌉
  int? bipartiteMaxReveals;
  int maxRetries;
  int routingTimeoutMs;  // unused for now (no DPLL stage), kept for symmetry with path
}
```

Wired through `bin/generate.dart` via `--scenario sy-based`.

## 9. First validation experiment

After implementation, generate ~200 puzzles via:

```
dart run bin/generate.dart --scenario sy-based -n 200 -o /tmp/sy1.txt
```

And measure (script to be added — analogous to `extract_path_like`):
- `sy-share`: % of `solveExplained` propagation steps issued by an
  `SY` constraint.
- Distribution of `seedRevealedCount` and `islandCellRevealedCount`.
- `force_depth` distribution (we want a healthy mass at depths 1-3,
  little at 0, very little at 4+).
- Visual sanity: random sampling of 10 puzzles, eyeball the shapes —
  do they look like deliberate symmetric figures or random blobs?

Success criterion (echoing the path-based 50 % bar): **`sy-share ≥
40 %` median** on grids 5×5–7×7 with N=2-3. Below that and the SY
identity isn't really carried by the final trace.

## 10. Risks and pitfalls

- **Trivial shapes**: a 2-cell island has no shape personality —
  growth must reliably produce ≥ 4-cell islands on standard grids.
  Track `min_island_size` and reject below threshold.
- **Trivial border tell**: if no island ever touches the border, the
  player immediately concludes that every border cell is background
  — a free hint that kills the puzzle. Mitigated by the design choice
  in § 4.2: only seeds are kept off the border, growth is free to
  reach it. Worth measuring post-generation that ≥ some fraction of
  puzzles actually has at least one island touching the border.
- **Over-determination**: same risk as path-based — too many
  guardrails dilute the SY share. Cascade cap on reveals + strict
  acceptance helps; measure `sy-share` to confirm.
- **Visual collisions**: two SY icons too close on the rendered grid
  look noisy. Already guarded by `minSeedDist` but worth visually
  validating at small grid sizes.
- **Color-symmetry confusion**: bg as black vs bg as white may not be
  visually neutral. Player intuition might read the bg cells as the
  "shape" and the islands as the "absence." Check by running the same
  generation with bg=1 vs bg=2 and surveying preferences.

## 11. Known gaps (May 2026)

- **Partial convergence.** On 6×6 with the default 2-island setup,
  roughly 6 seeds out of 10 finish the bipartite cascade in under 10 s
  after the readonly-prefill + rollback-on-regression additions. The
  remaining ~40 % exhaust the retry budget (`maxRetries = 30`) or
  trigger the `guardRail ≥ 8` / `consecutiveRollbacks ≥ 5` bailouts.
  Hypothesis: some island topologies are structurally ambiguous
  (multiple SY-valid completions distinguishable only by reasoning the
  solver cannot do with propagation alone). Next levers to try:
  - Smarter axis pick: drop axes that produce islands too small or too
    close to the border.
  - Force-depth check on the strict reveal: today only `≥ 2` free
    cells; could require the reveal to *unlock* a propagation chain
    that crosses an island boundary.
  - Independent (two-clone) `_constraintHelps`: the current
    fast/non-monotonic filter with rollback works but rejects many
    real helpers post-hoc. A stricter filter would be slower per
    candidate but might converge in fewer iterations.
- **No `sy-share` measurement script yet.** § 9's `extract_sy_like`
  analogue still needs to be written before the 40 % median criterion
  can be tested at scale.
