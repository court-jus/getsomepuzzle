# Propagation-Driven Constructive Generation — Analysis & Refinement

Based on the existing codebase (commit date July 2026). All line references
point to the files in `/home/debian/perso/getsomepuzzle`.

---

## A. État initial — firing behaviour on a fully empty grid

Test: a `Puzzle.empty(W, H, domain)` where every cell is `CellValue.free`.
Can `Constraint.apply()` return a non-null `Move`?

### Classification

#### Category 1 — Fires on fully empty grid (no pre-filled cells)

**NC (NeighborCount)** — `lib/constraints/neighbor_count.dart:91`

Fires when `count == 0` (remove colour from all neighbours) or when
`targetColorNeighbors + freeNeighbors == count` (force all neighbours
to the colour). On an empty grid `targetColorNeighbors = 0`,
`freeNeighbors = degree(cell)`.

- Example: `NC(0, black, 0)` on cell 0 (top-left corner of a 4×4, degree 2).
  `0 == 0` → line 110 fires: removes `black` from neighbours 1 and 4.
- Example: `NC(5, black, 4)` on cell 5 (interior of a 4×4, degree 4).
  `0 + 4 == 4` → line 126 fires: `SetValue(neighbour[0], black)`.

Parameter generation (`generateAllParameters`, line 42–66): enumerates
`0..degree-1` for every colour and every cell. Both examples above are
in the parameter space for any cell with the required degree.

**EY (EyesConstraint)** — `lib/constraints/eyes_constraint.dart:168`

Fires when `count == totalMax` (every cell in every line of sight must
take the colour). On a 3×3 grid, centre cell (idx=4): `totalMax = 4`.
`EY(4, black, 4)`:

- For the left direction: `seen = 0`, `max = 1`, `othersMax = 3`,
  `othersSeen = 0`. `minD = max(0, 4 − 3) = 1`. Since `1 > 0` (seen),
  line 189 fires: `SetValue(leftNeighbour, black)`.

Parameter generation (line 88–108): enumerates `0..totalMax-1` per colour
per cell. `totalMax` is the *exclusive* upper bound (`count < maxCount`),
so `count == totalMax` is **not** generated on a 3×3 center cell
(maxCount = 4, loop is `count < maxCount` → count ∈ {0, 1, 2, 3}). EY
therefore does **not** fire on empty grid with the *current* parameter
generation — the extreme case is excluded. Only with custom parameters
(outside `generateAllParameters`) could it fire.

→ **Corrected conclusion: no slug fires on a fully empty grid** under
the constraint set emitted by the current `generateAllParameters` functions.

**Exception**: NC with `count = 0` does fire. `NC(0, black, 0)` generates
`removeOption(neighbour, black)` because `targetColorNeighbors (0) == count (0)`.
This is a valid `generateAllParameters` output for any cell whose degree ≥ 1.

#### Category 2 — Fires with 1–2 pre-filled cells

| Slug | Pre-filled cells needed | Mechanism | File & line |
|------|------------------------|-----------|-------------|
| NC | 1 determined cell in neighbourhood | `have == count` → removeOption on rest, or `have + free == count` → setValue | `neighbor_count.dart:110,126` |
| DF | 1 cell of the pair | `cell1.value != free` → `removeOption(cell2, cell1.value)` | `different_from.dart:143-148` |
| RC/CC | 1 cell at the count target | `colorCount == count` → removeOption on all remaining line cells | `base_line_constraint.dart:52-58` |
| FM | 1 cell matching the motif minus the wildcard | Submotif search finds the match, target cell forced | `motif.dart:138-166` |
| PA | 2 cells on same side reaching the per-colour target | `perColor[color] == targetCount` → removeOption on free side cells | `parity.dart:224-233` |
| SY | 1 coloured neighbour of the anchor | 2-colour fast path: `neighbor = nv` → `SetValue(sym(n), nv)` | `symmetry.dart:105-129` |
| GS | 1 cell as anchor with a value and `size == 1` | `myGroup.length == size` → removeOption on neighbours | `group_size.dart:188-206` |

**Concrete example for each:**

- **NC**: 3×3 grid, cell 4 (centre) pre-filled black. `NC(4, black, 1)`:
  neighbours = {1,3,5,7}, `targetColorNeighbors = 1` (cell 4). Since
  `1 == 1`, line 110: `RemoveOption(neighbour, black)` on the 3 free
  neighbours.

- **DF**: 3×3, cell 0 pre-filled black. `DF(0, right)`: `cell1.value = black`,
  `cell2.value = free`. Line 143-145: `RemoveOption(1, black)`.

- **RC**: 4×4, row 0 cells 0 and 1 pre-filled black. `RC(0, black, 2)`:
  `colorCount = 2 == count`, line 52: `RemoveOption(black)` on remaining
  row cells {2, 3}.

- **CC**: same principle on columns. 4×4, column 0 cells {0,4,8,12}, 1
  cell pre-filled black. `CC(0, black, 1)`: `colorCount = 1 == count` →
  RemoveOption on the 3 other cells of column 0.

- **FM**: 3×3 grid, cell 0 pre-filled 1 (black). `FM:12` (motif = [[1,2]]):
  submotif with wildcard at (0,1) = [[1,0]]. `findMotifPositions` matches
  at position 0 (grid has "1" then "0" = "10" which matches "1."). Target
  cell = position 1. `cellValues[1] = free` and options contain 2.
  `RemoveOption(1, 2)` fires.

- **PA**: 3×3 grid, anchor at cell 4 (centre). `PA(4, left)` — left side
  has cells {3,4}, with domain 2 → target = 1 per colour. Pre-fill cells
  3 and 4 as black → black count = 2 > 1 → Impossible. Pre-fill cell 3
  as black → black count = 1 = target → line 224: `RemoveOption(black)`
  from cell 4. So 1 pre-filled cell suffices for PA on a small side.

- **SY**: 3×3 grid, anchor at cell 4 (centre), axis 4 (horizontal). Cell
  1 (above anchor) pre-filled black. 2-colour fast path line 105-129:
  `neighbor.value = black`, `sym(1) = 7` (below anchor). `cellValues[7] = free`,
  options contain black. `SetValue(7, black)` fires.

- **GS**: 3×3 grid, anchor at cell 4, `GS(4, 1)` — group must have size 1.
  Pre-fill cell 4 as black. `myGroup.length (1) == size (1)`, line 188:
  `RemoveOption(black)` on all free neighbours of the group.

#### Category 3 — Never fires directly (needs richer context)

| Slug | Reason |
|------|--------|
| QA | Fires only when `count == currentCount` (RemoveOption) or `deficit == free` (SetValue). Parameter range excludes `count == totalCells` (max = total-1) and `count == 0` (min = 1). |
| GC | Fires only when the group count exactly matches a target, or when a merge-cell must be forced. Requires existing coloured groups. |
| SH | Needs a partially-painted shape motif in the grid. |
| LT | Needs coloured cells to detect articulation points / colour forcing. |
| IM | Needs source cell coloured + target cell free. |
| EY | (See above: `generateAllParameters` excludes `count == totalMax`, so it can't fire on empty grid.) |

---

## B. Minimal seed

### Per-slug minimum pre-filled cells to enable first deduction

| Slug | Min cells | Condition |
|------|-----------|-----------|
| NC | 1 | One determined neighbour on an anchor with `have == count` |
| DF | 1 | One cell of the adjacent pair determined |
| RC/CC | 1 | Determined cell matches the count target for that line |
| FM | 1 | Cell matches the non-wildcard part of the smallest submotif |
| PA | 1 | On a side with `targetCount == 1` (side length = domain.length) |
| SY | 1 | Coloured neighbour of the anchor |
| GS | 1 | Anchor determined and `size == 1` |
| EY | *0* | (Not with current params — would need count=totalMax which is excluded) |
| QA | ceil(totalCells/2) | A count that meets `deficit == free` — impractical |
| GC | 3-5 | Enough groups to force a merge or a minimum-count case |
| SH | motif area | Needs the full shape motif painted on the grid |
| LT | 2 (same letter) | Needs two same-letter cells to detect connectivity forcing |

### Universal seed — minimum set that enables all category-2 slugs

**Size**: 4 cells forming a cross in the centre of a 5×5 grid:
```
. . . . .
. . B . .
. B A B .
. . B . .
. . . . .
```
- `A` (centre, idx=12) — anchor for PA, SY, GS, NC, EY
- `B` (idx=7,11,13,17) — neighbours for NC/DF/SY; same-row cells for RC;
  same-column cells for CC; match cells for FM; side cells for PA

This enables:
- `NC(12, black, 0)`: `B` cells are black → `targetColorNeighbors = 4`.
  With `count = 0`, this reports Impossible (too many black neighbours).
  Better: `NC(12, black, 4)`: `have == count` → RemoveOption on remaining free in between.

Actually the universal seed needs to be much smaller. A 2×2 block in
the centre is better:
```
. . . . .
. . . . .
. . B B .
. . B B .
. . . . .
```
4 pre-filled cells enable:
- DF between any adjacent pair
- NC with count matching the determined neighbours
- PA on sides that include these cells (if the side length divides by domain)
- SY with these cells as neighbours of a central anchor
- GS anchored on one of these cells with size = count of same-color neighbours
- RC/CC on rows/columns containing these cells

But a smaller seed is even more practical. **Recommended seed**: 3 cells
forming an L-shape in the centre:
```
. . . . .
. . . . .
. . B . .
. . B B .
. . . . .
```
3 cells cover DF (horizontal + vertical adjacency), NC (anchor at one
end sees 2 determined neighbours), PA (side length 2 with 2 black cells
= target met), RC/CC (one cell per row/col).

### Seed positions

Best positions, in order:
1. **Centre cluster** — maximises symmetry axes, minimises distance to all
   constraints (SY/EY/PA anchors work from centre).
2. **Slightly off-centre** — prevents SY from becoming trivial (a centred
   SY anchor with perfect mirror = every cell forced immediately).
3. **Spread out** — 2-3 clusters across the grid to seed different
   neighbourhoods for RC/CC/PA diversity.

Positions to avoid: grid edges and corners (NC has too few neighbours,
EY/PA have small max values, SY can't mirror beyond the bounds).

### Constraint-based seeding

Can a constraint act as the seed without pre-filled cells?

**SH (Shape)**: a ShapeConstraint with a painted motif placed as readonly
is effectively the seed. The current `preFillSh` (generator.dart line 543)
already does this: it paints the SH motif on the solved grid and leaves
those cells as readonly in the player puzzle. For PDCG this is the natural
"constraint-as-seed" mechanism — place an SH whose motif IS the seed.

**RC/CC with extreme count**: on a **1-row puzzle** (height=1), `RC`
can have `count = width - 1`. `colorCount = 0`, `freeCells = width`,
`deficit = width - 1`. `deficit (width-1) == free (width)` is false,
so it doesn't fire. For it to fire we need `deficit == free` → `count == width`,
but the current generation excludes `count = width`. **Change needed**:
extend `generateAllParameters` to include `count = width` (and `count = height`
for CC) — this would let RC/CC fire on the all-free state as a seed.

**QA with count = totalCells**: same limitation — `maxCount = totalCells - 1`.
Not viable without parameter change.

---

## C. Cell-targeting constraint selection

### Targeting capability per slug

| Slug | Targeting type | How to parameterise | File & line |
|------|---------------|-------------------|-------------|
| NC | **Direct** — cell = `indices[0]` | `cellIndex.color.count` | `neighbor_count.dart:24` |
| DF | **Direct** — cell = `indices[0]`, neighbour = `getNeighborIndex()` | `cellIndex.right` or `cellIndex.down` | `different_from.dart:43` |
| GS | **Direct** — cell = `indices[0]` | `cellIndex.size` | `group_size.dart:29` |
| SY | **Direct** — anchor = `indices[0]` | `cellIndex.axis` | `symmetry.dart:33` |
| PA | **Direct** — anchor = `indices[0]`, side relative to anchor | `cellIndex.side` | `parity.dart:44` |
| EY | **Direct** — eye = `indices[0]` | `cellIndex.color.count` | `eyes_constraint.dart:72` |
| FM | **Global / window** — no cell-specific parameter; matches anywhere motif fits | Motif string | `motif.dart:29` |
| RC | **Line-based** — row identified by index, affects all cells in that row | `rowIdx.color.count` | `row_count.dart:16` |
| CC | **Line-based** — column identified by index, affects all cells in that column | `colIdx.color.count` | `column_count.dart:16` |
| QA | **Global** — no positional parameter | `color.count` | `quantity.dart:22` |
| GC | **Global** — no positional parameter | `color.count` | `group_count.dart:23` |
| SH | **Shape-based** — motif size defines affected region | Motif string + colour | shape.dart |
| LT | **Letter-based** — anchors at letter's cells | `letter.idx1.idx2...` | letter_group.dart |

### Constraint selection priority ordering

When targeting a specific free cell, try slugs in this order:

1. **DF** (cheapest, complexity 0, purely local) — succeeds if either cell
   of an adjacent pair is already determined. Cost: O(1).
2. **NC** (complexity 0, neighbourhood-local) — succeeds if the count is
   met or the deficit matches the remaining neighbours. Cost: O(degree).
3. **FM** (complexity 0-3, window-local) — succeeds if one cell of the
   submotif needs forcing. Cost: O(grid area) for findMotifPositions.
4. **RC/CC** (complexity 0, line-based) — succeeds if the line's count
   for the target's colour is met or the deficit matches remaining free
   cells. Cost: O(line length).
5. **PA** (complexity 0-2, side-based) — succeeds if one colour has
   reached its balanced target on a side that contains the target cell.
   Cost: O(side length × domain).
6. **GS** (complexity 0-4, group-based) — succeeds if the anchor's group
   has reached its target size or a bottleneck forces the target cell.
   Cost: O(grid) for `getGroups` (flood-fill).
7. **SY** (complexity 1-2, symmetry-based) — succeeds with a coloured
   neighbour of the anchor. Cost: O(group frontier).
8. **EY** (complexity 0-3, line-of-sight) — succeeds when the count
   forces a cell in one direction. Cost: O(grid dimension).
9. **QA/GC** (complexity 0-4, global) — succeeds only when counts are
   critically near their targets. Falls back in priority when local
   constraints fail.

Rationale: DF and NC are the "cheapest" deductions (pure local, O(1) to
O(degree)), so they should be tried first. FM requires a full-grid search
but its submotif is at most 3×3. RC/CC are line-scans that can fire on
many cells at once. GS and SY need flood-fill. QA/GC are global and
rarely fire on a partially-determined grid.

### The existing targeted sort

The current generator already implements a targeted re-sort in
`_generateTargetedKeys` (`generator.dart:1314-1388`). It computes
serialised constraint keys for DF, NC, CC, RC that touch each still-
undetermined cell. The PDCG can reuse this function directly —
it already does exactly what we need: "which constraints affect a
given free cell?"

---

## D. Satisfiability checking without a solution grid

### Key insight: `propagateToFixpoint()` as satisfiability oracle

`Puzzle.propagateToFixpoint()` (`puzzle.dart:1064-1092`) runs the
propagation-only solver (no force) until fixed point, contradiction,
or completion. It returns `null` on contradiction (`Impossible` move
detected), else the number of moves made.

**Claim**: `propagateToFixpoint()` returning non-null is sufficient to
prove that the *current* state (with the candidate constraint added) is
**not immediately contradictory**. It does NOT guarantee that a complete
extension exists — that requires `solve()` (which adds force).

### Can a constraint be non-contradictory yet make the grid globally insoluble?

**Yes**, for two reasons:

1. **Force-only deductions**: a constraint may not fire in propagation but
   still be needed for force-based reasoning. If the candidate constraint
   is the *only* way a particular cell can be determined, and that cell
   requires a force step, propagation alone won't detect that the cell is
   now determinable — it would just see the cell as free and stuck.
   However, this is **not a contradiction**: the state is still reachable
   (a completion exists, just not via pure propagation). The PDCG loop
   only needs to avoid contradictions; a stuck-but-reachable state is
   fine — we'll add another constraint to progress.

2. **Global unsolvability via constraint interaction**: two constraints
   that individually pass `propagateToFixpoint()` may interact to make
   the grid unsolvable (e.g., RC+CC crossing with incompatible counts).
   `propagateToFixpoint()` detects this when the interaction produces an
   `Impossible` move (e.g., a cell forced to both colours). If the
   interaction is subtle (requires force to surface), it would be missed.

### Can `propagateToFixpoint()` miss contradictions?

Checking the code: `findAMove(checkErrors: false, tryForce: false)` at
line 1067 — force is explicitly disabled. Contradictions from force
(where setting a cell to one value and propagating reveals a conflict)
are NOT detected. A constraint that makes the grid *force-soluble but
not propagation-soluble* passes `propagateToFixpoint()` without issue.

### Detection cost of global insolubility

`Puzzle.solve()` (propagation + force, no backtracking) — `puzzle.dart:1361`.
Runs `findAMove(tryForce: true)` in a loop. Cost:
- Propagation: O(moves × constraints × grid access) — fast
- Force: O(freeCells × domain × propagation) — potentially expensive,
  but bounded by 200 maxSteps and the `shouldStop` callback.

On a 30×20 grid with 600 cells, worst-case force:
- 600 cells × 2 colours × propagateToFixpoint() ≈ 1200 × propagation
- Each propagateToFixpoint iterates constraints (typically 5-15) and
  makes at most ~O(cells) moves.

Total: could reach several seconds per `solve()` call. But the PDCG
only needs it for the **optional** final validation (section A's Option B),
not every iteration.

### Proposed validation protocol

```
Tentative add of constraint C to state S:

Phase 1 (mandatory — every iteration):
  1. Clone S → S'
  2. S'.addConstraint(C)
  3. result = S'.propagateToFixpoint()
  4. If result == null: C is contradictory → discard
  5. If S'.complete: C determines everything → keep, break loop
  6. Else: C is non-contradictory → keep, continue

Phase 2 (optional — budget-gated, for "force gentle" mode):
  7. result = S'.solve()
  8. If !result: C makes the grid force-insoluble → discard
     (counterexample: C adds a constraint that indirectly forces a
      contradiction only visible via force)
```

Phase 1 alone is sufficient for Tier 1 (pure propagation) puzzles.
Phase 2 adds protection for Tier 2 (gentle force) puzzles but costs
more. Recommended: Phase 1 for the inner loop, Phase 2 as a final
validation pass after the puzzle is assembled, where the cost is
paid once instead of per-iteration.

### Edge case: `propagateToFixpoint` returning `null` early

At `puzzle.dart:1070-1071`: `Impossible()` causes an immediate null
return. This catches:
- A line constraint where the colour count already exceeds the target
- A motif that already appears in the grid
- A PA side with too many of one colour
- An NC with more coloured neighbours than the count
- A GS with group size already exceeding the target

At `puzzle.dart:1076-1077`: `SetValue` targeting a value no longer in
the cell's options. This catches constraints that would force a cell
to a value that was already excluded by another constraint.

Both are correct contradiction detections and are already exercised
by the existing generator's `propagateToFixpoint` calls in phase 1
(generator.dart line 886).

---

## E. Loop convergence and termination

### Can the process loop indefinitely?

**No constraint removal path**: constraints are only added, never removed
(except `removeUselessRules` in post-processing, which is optional and
removes redundancies, not structural constraints). Adding a constraint is
a monotonic restriction of the solution space: the set of completions can
only shrink. Since the grid is finite (≤ 600 cells on 30×20) and each
constraint addition either determines at least one new cell (progress) or
adds a redundant constraint (no progress but no regression), the loop
cannot oscillate.

**Redundant constraints**: it is possible to add a constraint that does
nothing new — the same slug with different parameters that don't fire on
the current state. This wastes an iteration but does not cause a loop.
**Protection**: track `cells.size` at each iteration. If N consecutive
additions don't increase the determined-cell count, fall back to a
different targeting strategy (different cell, different slug category).

### Termination criteria

**Success**:
- `complete == true` — all cells determined (propagateToFixpoint after
  the latest addition returns a complete state)
- A second `propagateToFixpoint()` run from scratch confirms stability

**Abandon**:
- `maxAttempts` iterations without reaching `complete` (recommended:
  gridArea × 2, so 1200 iterations on 30×20)
- `maxStallMs` wall-clock elapsed since the last determined-cell increase
  (reuse the existing `GeneratorConfig.maxStall` clock, `generator.dart:109`)
- All slug categories exhausted for the current target cell, and no cell
  left to target

### Handling "no constraint targets this cell"

Three strategies, in increasing order of complexity:

1. **Skip and move on**: if no constraint targets cell `c`, pick another
   free cell. This works because every cell gets targeted eventually as
   the free set shrinks.

2. **Switch category**: if local constraints (DF, NC) can't target `c`,
   try line-based (RC/CC), then global (QA/GC). The global constraints
   can always target any cell (they apply to the whole grid), though
   they rarely fire on a sparsely determined state.

3. **Restart last choice**: if multiple consecutive cells have no
   targeting constraint, backtrack to the previous iteration and pick
   a different constraint for that cell (requires keeping a history of
   choices). This is more complex and should be a last resort.

**Recommendation**: strategy 1 + strategy 2 (switch to global slugs
when local fails), with a safety counter. If 20+ consecutive cells have
no targetable constraint, the state is at a true plateau — either accept
as-is (if enough cells are determined to be interesting) or restart with
a different seed.

---

## F. Integration with the existing generator

### What gets reused as-is

| Component | File | Use in PDCG |
|-----------|------|-------------|
| `GeneratorConfig` | `generator.dart:18-135` | Core config (width, height, domain, allowedSlugs, preferredSlugs) |
| `GenerationRejectReason` | `generator.dart:141-221` | Rejection taxonomy — add `pdcgStalled`, reuse the rest |
| `Puzzle.clone()` | `puzzle.dart:1017-1031` | Tentative constraint addition (clone → add → propagate) |
| `propagateToFixpoint()` | `puzzle.dart:1064-1092` | Core satisfiability check (Phase 1 protocol) |
| `_generateTargetedKeys` | `generator.dart:1314-1388` | Constraint→cell targeting lookup |
| `autoShrinkDomain` | `generator.dart:1275-1296` | Post-generation domain cleaning |
| `sortConstraintsByDifficulty` | `puzzle.dart:531-559` | Final constraint ordering |
| `_StageTimer` | `generator.dart:299-310` | Per-stage timers for diagnostics |
| `slugDeficits` | `equilibrium.dart:1007-1026` | Secondary slug bias |
| `removeUselessRules` | `puzzle.dart:1408-1431` | Post-generation cleanup |
| `Puzzle.simplify` | `puzzle.dart:1472-1614` | Easing loop (same target-level filter) |

### What gets adapted

| Component | Adaptation |
|-----------|-----------|
| `_generateOneTimed` | New code path parallel to the existing pre-fill dispatch. The PDCG replaces the entire "random grid → candidate enumeration → greedy solve-ratio loop" pipeline with a seed + constraint-addition loop. |
| `preFillRegular` / seed logic | Reduced to just placing 3-15 readonly cells (instead of 0-25%). Or replaced by the constraint-based seed (SH motif). |
| `cachedSolution` | Still needed as final validation target. Not needed *during* the incremental loop (Propagation-only satisfiability doesn't need the solution). |

### What gets left aside

| Component | Reason |
|-----------|--------|
| `solve()`-based candidate evaluation (`generator.dart:909-912`) | The PDCG uses `propagateToFixpoint()` only (Phase 1). The full `solve()` is replaced by the incremental loop. |
| Candidate pre-enumeration via `generateAllParameters` + `verify(solved)` (`generator.dart:580-598`) | The PDCG generates constraint parameters *on demand* for a specific target cell, not exhaustively upfront. But `generateAllParameters` is still the factory — we just call it lazily. |
| `preFillPath` / `preFillSh` / `preFillSy` / `preFillBB` | These are alternative pre-fill strategies. The PDCG has its own seed phase. (They can coexist as seed strategies.) |
| `computeUsageStats`, corpus deficit for candidate sort | Not needed: candidates are selected by cell-targeting, not by corpus deficit. Slug deficit is still relevant for *which* constraint to prefer among those targeting the same cell. |

### Adding as a new generation strategy

**Option: new `GenerationStrategy` value**

Add `GenerationStrategy.pdcg` to the enum at `generator.dart:257-291`.
In `_generateOneTimed`, dispatch after line 483:

```dart
if (config.strategy == GenerationStrategy.pdcg) {
  return _generateOnePdcg(config, ...);
}
```

This keeps the existing code paths untouched. The new PDCG-specific
reject reasons (e.g. `pdcgNoSeed`, `pdcgStalled`) are added to the
`GenerationRejectReason` enum.

**`_generateOnePdcg` signature:**

Same return type `({String line, PuzzleLevel level})?`. Accepts the same
callbacks (`onProgress`, `onReject`, `shouldStop`, `onTimings`). Internally:
- Seed phase: place 3-15 readonly cells (or SH motif)
- Loop: pick free cell → enumerate targetable constraints → filter by
  `propagateToFixpoint()` → add best → repeat
- Post-loop: `removeUselessRules`, `sortConstraintsByDifficulty`, export

### Equilibrium integration

The existing equilibrium axes (slug, ntypes, pair, size, profile,
composition, domain) remain fully relevant for PDCG:

- **Slug axis**: the PDCG loop selects constraints by targeting a cell,
  but among equally-targeting candidates, the slug with the highest
  deficit score should be preferred. The existing `slugDeficits` map
  (`equilibrium.dart:1007-1026`) can be passed into the PDCG selector.
- **Size axis**: identical — the PDCG generates puzzles at the requested
  size.
- **Profile axis**: PDCG could generate `classic` puzzles (seed + random
  constraint selection) or a new `pdcg` profile category with a specific
  seed strategy and constraint ordering.
- **New "deductive purity" axis**: a `purity` axis with buckets `pure`
  (Tier 1, no force) and `gentle` (Tier 2, shallow force). This would
  let the equilibrium push puzzles toward one style or the other, and is
  a natural differentiator from the existing generator (which always
  produces puzzles solvable with both propagation and force).

The equilibrium's per-iteration target resolution (`worker_io.dart`)
already configures `GeneratorConfig` fields — it can set
`GenerationStrategy.pdcg` and any PDCG-specific parameters (seed size,
purity target, max stall).

---

## G. Gentle force extension

### How `_forceOneCell` works

`_forceOneCell()` (`puzzle.dart:881-938`) iterates every (cell, value)
pair on a **clone**, runs `_propagateCount()` (propagation only, no
recursive force), and checks for contradiction. Returns a `RemoveOption`
move with the refuted value.

Key detail: `_propagateCount()` at line 945-979 runs `findAMove` with
`tryForce: false` — it does **not** recurse through force. The force
detection is shallow: it tests "if I set this cell to this value, does
propagation alone reach contradiction?". This matches the "gentle force"
concept from the vision: the player can reason "if this were black,
that white line would overflow → contradiction".

### Reusability for PDCG

`_forceOneCell()` can be called directly on the semi-resolved state
during the PDCG loop. However:

1. **Cost**: on a 30×20 grid with 600 cells × 2 colours ×
   `propagateToFixpoint()`, a full `_forceOneCell()` scan is
   prohibitively expensive for every iteration. Solution: only run
   `_forceOneCell()` on a **subset of cells** — those with the most
   determined neighbours (where force is most likely to succeed).

2. **Integration point**: after propagation plateaus (no constraint
   fires), before giving up on the current target cell, run
   `_forceOneCell()` on just that cell. If it returns a `RemoveOption`
   move, that's a valid deduction (Tier 2). Add it to the puzzle as
   a constraint (or just apply the move directly to the state).

3. **Force depth budgeting**: `_forceOneCell` already returns the
   shallowest contradiction (`bestDepth`). The PDCG can reject force
   deductions deeper than a threshold (e.g. `forceDepth > 2`) to keep
   puzzles approachable — matching the vision's "gentle force" concept.

### Hybrid mode (recommended flow)

```
Phase 1 — Pure propagation:
  while free cells remain:
    pick a free cell c
    for slug in [DF, NC, FM, RC, CC, PA, GS, SY, EY]:
      for constraint of slug targeting c:
        if propagateToFixpoint(clone + constraint) succeeds:
          add constraint, apply propagation
          goto next cell
    // No propagation constraint fires for c
    fall through to phase 2 for this cell

Phase 2 — Gentle force on this cell:
    result = _forceOneCell(clone, targetCell: c)
    if result exists and result.forceDepth <= maxForceDepth:
      apply RemoveOption to state
      goto next cell
    else:
      mark c as "unresolvable", try next free cell

Post-loop:
  if free cells remain → accept (seed fills the gap) or reject
  optional: solve() for final validation
```

This is analogous to the existing `phaseGate` strategy
(`GenerationStrategy.phaseGate`, `generator.dart:268`) but adapted
to the cell-targeting loop: phase 1 tries propagation constraints,
phase 2 tries force on the same cell before giving up.

---

## H. Scaling to 30×20

### Cost analysis of key operations

| Operation | Complexity | 30×20 (600 cells) cost |
|-----------|-----------|----------------------|
| `propagateToFixpoint()` | O(moves × constraints × grid-op) | `moves` ≤ 600, `constraints` ∼ 5-20, `grid-op` O(1) to O(line length) → ∼ 10-100K operations. Acceptable (∼1-5 ms). |
| `getGroups()` | Flood-fill over all cells | O(600) per call. Group operations in GS/SY/GC call this. Cached (`puzzle.cachedGroups` at `puzzle.dart:265`) and invalidated on cell mutation. ∼ 0.5 ms per call, few calls per iteration. |
| `_forceOneCell()` full scan | O(cells × domain × propagation) | 600 × 2 × 10-100K ops → ∼ 1-10 million operations. **Prohibitive** per iteration. |
| `_forceOneCell()` single cell | O(domain × propagation) | 2 × 10-100K ops → acceptable (∼ 0.1-1 ms). |
| `solve()` | O(maxSteps × (propagation + force)) | 200 × (propagation + K × force). Could reach 5-30 seconds. Only at final validation. |
| `generateAllParameters` (all slugs) | O(slugs × parameter-space) | ∼ 500K-1M parameter strings. Only for offline enumeration (current generator). PDCG calls it **per slug per target cell** — much less. |
| `findMotifPositions` | O(grid area) = O(W×H) | 600 cells per call. FM is called per iteration; with 10-30 iterations, ∼ 6000-18000 cell scans. Acceptable (∼ 1 ms per call). |

### Critical hot spot: `_forceOneCell()`

The full-scan variant iterates every free cell (up to 600) × every option
(2 on 2-colour). **Mitigations**:

1. **Never scan all cells.** Only scan the targeted cell (1 cell) or the
   neighbourhood of the targeted cell (at most 4 cells). The single-cell
   scan is O(domain × propagation) = cheap.

2. **Budget the scan.** If targeting a specific cell fails for both
   propagation (Phase 1) and force (Phase 2), don't retry. Move to the
   next free cell.

3. **Cache `getGroups`.** The puzzle already caches `cachedGroups`
   (`puzzle.dart:265`) which invalidates on cell mutation. Force
   deductions trigger this invalidation, but the next propagation step
   recomputes it once. This is acceptable.

### Windowed propagation

The current `propagateToFixpoint` runs on the **entire grid**. At 30×20
this is fine because local constraints (DF, NC) only touch a few cells,
and line constraints (RC/CC) only scan one line. The O(600) overhead per
propagation call is negligible compared to the `_forceOneCell` cost, so
**full-grid propagation is acceptable** for PDCG at 30×20.

Global constraints (QA, GC) need the full count — O(600) per call.
These are called rarely (only when targeted). Acceptable.

### Iteration budget for 30-second puzzles

Target: 30 seconds per puzzle on 30×20.

| Step | Time | Notes |
|------|------|-------|
| Seed (3-15 readonly cells) | < 1 ms | Random index selection |
| Constraint generation per cell | ∼ 0.5 ms | `generateAllParameters` per slug × 2-3 slugs per cell |
| `propagateToFixpoint()` per constraint | 1-5 ms | 600-cell propagation, 5-20 constraints |
| Constraint selection (5-10 candidates) | 5-50 ms | Try 5-10, each with clone+propagate |
| Iterations (50-200 for 600 cells) | 0.25-10 s | 50-200 × 5-50 ms |
| `_forceOneCell` per cell (phase 2) | 1-5 ms | Single-cell force scan |
| Final `solveExplained()` | 0.5-5 s | One full solve for validation |
| Post-processing | < 1 s | `sortConstraintsByDifficulty` + `lineExport` |

**Estimated total**: 1-15 seconds per puzzle — well within the 30-second
budget. Headroom for 2-3 retries on failure.

### Optimisation recommendations

1. **Don't clone the full puzzle every time.** The current
   `clone()` → `addConstraint()` → `propagateToFixpoint()` pattern
   clones all cells and constraints. For PDCG, a lightweight state
   snapshot (just the cell values/options) would suffice for the
   satisfiability check. **Impact**: reduces per-candidate cost by
   50-70% (no constraint deep-clone).

2. **Batch constraint generation.** Instead of calling
   `generateAllParameters` per slug per cell, pre-compute a `Map<cell,
   List<Constraint>>` once after each propagation step. **Impact**:
   reduces repeated parameter string parsing.

3. **Parallel candidate testing.** The 5-10 candidates per cell can be
   tested in parallel (each is an independent clone+propagate). Flutter
   web cannot use isolates, but `Future.wait` on chunked async iteration
   (as the existing web worker does) would work. **Impact**: 2-5×
   speedup on multi-core devices, 1× on web.

4. **Use `propagateToFixpoint(verifyAfterEachMove: false)`** — the
   current default. The `verifyAfterEachMove` flag adds O(constraints ×
   domain ops) per move. Leaving it off is the right choice for PDCG
   (contradictions from constraint interaction are caught by the
   `Impossible` move, not by `verify`). Already done by the current
   `propagateToFixpoint` call.

---

## Summary of key findings

1. **No slug fires on a fully empty grid** under the current
   `generateAllParameters` except NC with count=0. Every slug needs
   at least 1-4 pre-filled cells (the "seed") to start deducing.

2. **The seed should be 3-8 cells** in a cross or L-shape near the
   centre. Too many cells (current 0-25%) and the puzzle is over-
   determined.

3. **`propagateToFixpoint()` is the right satisfiability oracle** for
   the inner loop (Phase 1). It misses force-only contradictions, but
   those are acceptable — they're either caught by a final `solve()`
   or handled in Phase 2 (gentle force).

4. **The existing `_generateTargetedKeys` function** can be reused
   directly for the cell→constraint mapping.

5. **No backtracking is needed** — constraints are only added, never
   removed (monotonic). Redundant constraints are harmless and can be
   pruned post-loop with `removeUselessRules`.

6. **The new generator fits as a `GenerationStrategy` value** with a
   new `_generateOnePdcg` function, reusing most of the existing
   infrastructure (timers, config, reject reasons, callbacks).

7. **`_forceOneCell` is reusable** for the gentle-force extension but
   must be limited to single-cell scans (not full-grid) at 30×20 scale.

8. **30×20 scaling is achievable** under 30 seconds per puzzle. The
   key is avoiding full-grid `_forceOneCell` scans and using the
   incremental propagation loop.

