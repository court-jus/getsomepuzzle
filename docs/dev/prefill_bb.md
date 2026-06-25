# BB pre-fill — generation by bounding-box islands

Pipeline lives in `lib/getsomepuzzle/generator/prefill/bb.dart`
(`preFillBB`, `findAdditionalBoxPositions`, `_growBox`, `_walkToSide`).

Activated when `BB` is in the `prioritySlugs` set (union of
`config.requiredRules` and `config.preferredSlugs`). Dispatch priority
inside `generateOne` is `SH > BB > regular`: when both `hasSH` and
`hasBB` are true, SH pre-fill takes precedence.

## Why a dedicated pre-fill is necessary

A random grid almost never survives the candidate `verify` filter for
`BoundingBoxConstraint`: the colour groups produced by uniform random
fill have heterogeneous bounding-box extents, so the constraint
`verify(solved)` returns `false` for nearly every parameter set and the
iterative loop finds no valid BB candidate to accept. `preFillBB`
solves this by constructing — rather than sampling — a solved grid
whose colour groups all share a single declared `W×H` extent by
design.

## Integration with the generator

### Dispatch

Inside `PuzzleGenerator._generateOneTimed` (`generator.dart`):

```dart
final hasSH = prioritySlugs.contains("SH");
final hasBB = prioritySlugs.contains("BB");
// …
solved = hasSH
    ? preFillSh(width, height, domain, _rng)
    : hasBB
    ? preFillBB(width, height, domain, _rng)
    : preFillRegular(width, height, domain, _rng);
```

The path-based and SY-based pre-fills short-circuit before this branch.

### Scenario stamp

The emitted v2 line carries `scenario:bb` only when `hasBB && bbAttached`,
where `bbAttached` is true iff `preFillBB` successfully painted at least
one island for `color1` (see Phase 4 below). When `bbAttached` is false
the result falls back to `scenario:classic`.

### Equilibrium wiring

`ProfileCategory.bb` targets 5 % of the profile axis
(`kTargetProfile` in `equilibrium.dart`):

```
classic=0.80, sh=0.05, bb=0.05, pathBased=0.05, syBased=0.05
```

When the equilibrium picks `ProfileTarget(bb)`, `_resolveTarget` in
`worker_io.dart` returns `_ResolvedTarget(preferredSlugs: {'BB'})` —
the same lightweight wiring as SH. No `bbBasedScenario` flag is
threaded through `GeneratorConfig`; the presence of `BB` in
`prioritySlugs` is sufficient.

`_resolveScenario` in `worker_io.dart` checks in priority order:
`pathBased → syBased → sh → bb → classic`. A `scenario:bb` attempt is
therefore only reported when neither a path-based nor a SY-based nor an
SH preference was active.

Unlike SH, BB is **not** excluded from the slug axis in
`slugDeficits`. SH receives a hardcoded zero deficit to prevent the
slug axis from double-promoting SH (the profile axis already steers
toward it). BB has no equivalent protection and participates in both
the profile and slug axes.

### Profile detection

`detectPuzzleProfile` (`equilibrium.dart`) reads the authoritative
`scenario:` suffix first. When the suffix says `bb`, the function
returns `ProfileCategory.bb` immediately (court-circuit). For lines
without that suffix, it falls through to emergent detection: the
presence of any `BB` slug causes the function to classify the puzzle as
`bb`.

## Pipeline

`preFillBB(width, height, domain, rng)` runs four phases and returns a
`Puzzle` with the chosen `BoundingBoxConstraint`(s) already attached.

```
── Phase 0 : parameter selection ──
color1 = random element of domain
W1 = _drawExtent(width); H1 = _drawExtent(height)   # small-biased, [2, dim-1]

if domain.length > 2 AND rng.nextDouble() < 0.35:
  color2 = random element of domain \ {color1}
  W2 = _drawExtent(width); H2 = _drawExtent(height)
else:
  color2 = null

── Phase 1 : color1 islands ──
placed1 = _placeColorIslands(solved, color1, W1, H1, rng)

── Phase 2 : color2 islands (when color2 ≠ null) ──
placed2 = color2 != null
          && _placeColorIslands(solved, color2, W2, H2, rng)

── Phase 3 : background fill ──
remaining free cells → random colour ∉ {color1, color2}

── Phase 4 : attach constraints ──
if placed1: solved.addConstraint(BoundingBoxConstraint("color1.W1.H1"))
if placed2: solved.addConstraint(BoundingBoxConstraint("color2.W2.H2"))
```

### Phase 0 — parameter selection

The second BB colour is drawn only when the domain has room for at
least one background colour (`domain.length > 2`). On a 2-colour
domain the second colour would exhaust all available colours, leaving
no background, so the guard is structural. The `p=0.35` draw makes
dual-BB puzzles less common than single-BB puzzles.

### Phase 1 / 2 — island placement (`_placeColorIslands`)

Each colour's islands are placed by `_placeColorIslands`, which mirrors
`_placeAdditionalVariants` in `sh.dart`:

1. Call `findAdditionalBoxPositions` with an empty grid (no
   same-colour cells yet). If no window returns a valid shape, the
   colour gets no island and `_placeColorIslands` returns `false`.
2. Pick one shape from the returned list at random and paint it
   outright (the first island is always placed).
3. Recompute valid positions with the now-populated grid. While any
   positions remain:
   - pick one at random;
   - accept it (paint it) with probability ~50 %;
   - recompute positions.

This place-then-find loop stops when `findAdditionalBoxPositions`
returns an empty list. Island density is emergent — no target count is
specified.

A colour may fail to place even its first island if the other colour's
islands have saturated the grid and no fitting window is left. In that
case `_placeColorIslands` returns `false` and Phase 4 skips the
constraint for that colour. Attaching a `BoundingBoxConstraint` with
zero groups would be a degenerate rule (it would forbid the player from
ever forming one), so the skip is deliberate.

### Phase 3 — background fill

Every remaining free cell receives a colour drawn uniformly at random
from `domain \ {color1, color2}`. Background cells are never part of a
BB group, so they cannot accidentally extend the bounding box of a
placed island.

### Phase 4 — constraint attachment

One `BoundingBoxConstraint` per colour that actually received at least
one island. Because islands are grown before-the-fact to touch all four
sides of their declared `W×H` window, `verify(solved)` is satisfied by
construction for every attached constraint (see Correctness section).

## Island growth (`findAdditionalBoxPositions` and `_growBox`)

`findAdditionalBoxPositions` scans every `H×W` window that fits the
grid (windows may overlap). For each window it calls `_growBox` to
attempt to grow a shape. Windows where growth succeeds are returned as
a list of cell sets; windows where growth fails are silently skipped.
Because the scan is randomized at the walk level and `_growBox` can
fail for a given seed, not every geometrically fitting window returns a
shape.

### Forbidden set

Before growing, `_growBox` builds a `forbidden` set from the
same-colour cells already placed **plus their orthogonal 4-neighbour
halo**. A shape may never contain or be adjacent to a forbidden cell.
This halo keeps newly grown islands distinct from all prior same-colour
islands (no orthogonal adjacency → each island is a separate connected
component → groups stay distinct). Cells of a *different* colour are
not forbidden — different-colour adjacency is permitted — but they are
occupied and therefore not usable for growth.

### Growth algorithm (skeleton → thicken)

`_growBox` uses a biased random walk that builds a connected skeleton
reaching all four sides of the window, then thickens it stochastically:

1. **Anchor.** Collect all usable free cells in the window. If none
   exist (the window is fully blocked), return `null`. Otherwise pick
   one uniformly at random as the initial cell set `cells`.

2. **Side-reaching loop.** While at least one of the four window sides
   (top, bottom, left, right) is not yet touched by any cell in
   `cells`:
   - Pick one untouched side at random as `target`.
   - Pick a random starting cell from the *existing* `cells` set
     (guarantees the walk stays connected to the growing island).
   - Walk step by step:
     - At each position, collect orthogonal neighbours that are
       either already in `cells` (stepping back into own territory is
       allowed) or usable (free and not forbidden).
     - Compute the *preferred* subset: neighbours strictly closer to
       `target` in the relevant axis direction.
     - With probability 0.75, move to a random preferred neighbour;
       otherwise move to any valid neighbour.
     - Add the chosen cell to `cells`.
     - Stop when the cell is on the target side.
   - If at any step no valid neighbour exists, or if the total steps
     taken exceed `4·W·H`, the window **fails** (return `null`).

3. **Thickening.** For each skeleton cell, with probability 0.2, add
   one randomly chosen usable orthogonal neighbour. This is
   unconditional — the chosen neighbour need not be in any particular
   direction — producing hollow, irregular shapes rather than
   thin paths.

After thickening, the cell set is returned. It is guaranteed to touch
all four sides (ensured by the walk) and to have exact bounding-box
extent `W×H` (all cells lie within the window by the `usable` predicate
which enforces `r0 ≤ r ≤ rMax`, `c0 ≤ c ≤ cMax`).

### Worked example: 5×3 window

```
Window rows 0-2, cols 0-4 (5 wide, 3 tall). Anchor at (1,2).
After side-reaching walks (top → row 0, bottom → row 2,
left → col 0, right → col 4):

. X . X .   row 0  (top side touched at col 1 or 3)
X X X X X   row 1  (anchor + walk path)
. X . X .   row 2  (bottom side touched)

Thickening may grab one more cell per skeleton cell with p=0.2.
```

The result has extent exactly 5×3 and the anchor + all walk cells form
a connected set.

## Separation is per cell, not per rectangle

Two islands of the same colour can have overlapping bounding rectangles
as long as no cell of one island is orthogonally adjacent to any cell
of the other. The separation guarantee is enforced by the
same-colour-cell halo in the `forbidden` set.

Example: on a 5×3 grid two islands with extent 3×3 may interlock:

```
1 0 1 1 1
1 0 0 0 1
1 1 1 0 1
```

Island A (left group): cells at columns 0, rows 0-2 plus the bottom
row. Island B (right group): columns 2-4 with gaps. Boxes overlap in
the column dimension, but no cell of A is orthogonally adjacent to any
cell of B.

## Correctness (verify-by-construction)

`BoundingBoxConstraint.verify(solved)` passes on `preFillBB`'s output
because every island's shape is constrained to the `W×H` window by the
`usable` predicate in `_growBox` and the walk reaches all four sides,
so:

- **Lower bound**: the island touches all four sides ⇒ its bounding
  box spans at least `W` columns and `H` rows.
- **Upper bound**: no cell is placed outside the window ⇒ the bounding
  box is at most `W×H`.
- **Distinctness**: the halo in `forbidden` prevents same-colour
  orthogonal adjacency ⇒ each grown shape is a separate connected
  component ⇒ groups are distinct.

Together these guarantee `verify(solved) == true` for every attached
`BoundingBoxConstraint`. The regression test in
`test/prefill_bb_test.dart` pins this invariant across grids of sizes
`(6,5)`, `(8,8)` and `(5,7)`, over 25 random seeds each, for both 2-
and 3-colour domains.

## Comparison with SH pre-fill

| Property | SH (`preFillSh`) | BB (`preFillBB`) |
|---|---|---|
| Dispatch trigger | `hasSH` (priority over BB) | `hasBB` (when `!hasSH`) |
| Scenario stamp | `hasSH && shAttached` → `'sh'` | `hasBB && bbAttached` → `'bb'` |
| Slug axis exclusion | SH excluded from slug deficit axis | BB participates in slug axis |
| `_resolveScenario` order | checked third (after path/sy) | checked fourth (after sh) |
| Profile weight | 0.05 | 0.05 |
| Shape per island | shared motif across variants | grown fresh per window |
| Island count | emergent (place-then-find loop) | emergent (place-then-find loop) |
| Island shapes | all variants share the same motif | each island has a unique shape |

## Edge cases and known limitations

- **Single island only.** When `color2` saturates the remaining space
  during Phase 2, `color1` may end up with a single island. The
  pre-fill still succeeds as long as that island was placed. A
  `BoundingBoxConstraint` with a single group is valid and solvable.
- **Color2 gets no island.** When `color1`'s islands densely pack the
  grid, `findAdditionalBoxPositions` for `color2` may return empty
  on the very first call. Phase 4 skips the BB constraint for `color2`
  and only attaches one for `color1`. The scenario stamp becomes `'bb'`
  only if `placed1` is true.
- **All windows fail for color1.** Rare on large grids; can happen on
  very small grids where the chosen `W1×H1` leaves no room after the
  forbidden halo. The pre-fill returns a puzzle with no BB constraint
  attached (`bbAttached = false`), causing the generator to emit a
  `classic` puzzle rather than a `bb` one.
- **Step cap `4·W·H`.** Biased walks can loop in sparse or highly
  obstructed windows. The step cap prevents infinite walks; the window
  is discarded and the next window tried. On highly fragmented grids
  (many forbidden cells from a previously saturating colour) most
  windows may fail, reducing island density.
- **Domain 2 always single-BB.** The `domain.length > 2` guard in
  Phase 0 means a 2-colour domain never draws a second BB colour. The
  regression test in `test/prefill_bb_test.dart` (`domain 2 never
  draws a second BB colour`) pins this.
- **Extent draw is small-biased and stays inside the grid.** `_drawExtent`
  returns the minimum of two uniform draws over `[2, dim − 1]`, skewing
  the mass toward small extents while letting larger boxes appear in a
  thinning tail that widens with the grid. The upper bound of `dim − 1`
  means a planted box never spans a full grid dimension — the same space
  `BoundingBoxConstraint.generateAllParameters` enumerates. A grid
  dimension below 3 has no valid interior extent and clamps to 2.
- **Why exclude full-span dimensions.** A 1×? box is a no-adjacency rule
  rather than a bounding box, and a box spanning a full grid width or
  height is a weak rule (it constrains only the other axis). Both the
  pre-fill draw and the candidate enumeration therefore restrict each
  extent to `[2, dim − 1]`.

## Source files

- `lib/getsomepuzzle/generator/prefill/bb.dart` — `preFillBB`,
  `findAdditionalBoxPositions`, `_growBox`, `_walkToSide`,
  `_placeColorIslands`, `_drawExtent`
- `lib/getsomepuzzle/generator/generator.dart` — `hasBB` flag,
  `hasSH ? preFillSh : hasBB ? preFillBB : preFillRegular` dispatch,
  `bbAttached` scenario stamp
- `lib/getsomepuzzle/generator/equilibrium.dart` — `ProfileCategory.bb`,
  `kTargetProfile`, `detectPuzzleProfile`
- `lib/getsomepuzzle/generator/worker_io.dart` — `_ResolvedTarget
  (preferredSlugs: {'BB'})` in `_resolveTarget`, `_resolveScenario`
- `test/prefill_bb_test.dart` — regression tests (by-construction
  invariant, domain-2 guard, `findAdditionalBoxPositions` separation)
