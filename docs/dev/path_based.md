# Path-based puzzles — constructive generation

Pipeline lives in `lib/getsomepuzzle/generator/prefill/path.dart`,
wired through `generator.dart` via `GeneratorConfig.pathBasedScenario`
and selectable either via the CLI flag `--scenario path-based` (forces
100 %) or by the equilibrium's `profile` axis picking
`ProfileCategory.pathBased`.

This is the concrete instance of *theme-first* generation referenced in
[`generator.md`](generator.md): build the topology first, collect the
constraints later.

## What a path-based puzzle is

A path-based puzzle is dominated by the **LT** (LetterGroup) constraint.
The intellectual work for the player is no longer "counting / guessing
cells" but **routing** each letter through the grid:

- Each letter `Z`, `Y`, `X`… defines a set of anchors that must all end
  up in the same connected group of one colour.
- Two distinct letters sharing the same colour can never occupy the same
  connected component, so their paths repel each other.
- Other constraints (`PA`, `GS`, `QA`, `CC`, `NC`, …) act as
  **guardrails**: they break ties between several a priori valid routings.

In spirit this resembles Number Link / Flow Free layered on top of an
N-colouring: a path is a chain of cells of a given colour that interleaves
with opposing paths rather than merely avoiding their neighbours.

> **Domain-aware generation.** `preFillPath` accepts a `domain` parameter
> and propagates it through `Puzzle.empty`. On a domain of ≥ 3 colours
> every colour is guaranteed to be owned by at least one letter
> (see "Colour assignment" below), so the routed solution is genuinely
> N-colour and survives `autoShrinkDomain`. The LT constraint itself is
> colour-agnostic — it enforces monochrome connectivity of each letter's
> anchors but is blind to colours not belonging to its own letter. Without
> the full-coverage guarantee, `autoShrinkDomain` would relabel the puzzle
> back to 2 colours.

### Why this design

- **Strong aesthetic identity** — the player immediately knows what to do
  ("connect the Z's, the Y's, …") before reading the remaining constraints.
  The puzzle has a visible intent.
- **Lifts a limitation of the grid-first generator** — random 50/50 grids
  rarely produce long snakes or distant anchors, so LT is under-used in
  the classic flow. Building topology first makes topologically rich LT
  puzzles tractable.
- **Feasibility by construction** — regions are placed incrementally in
  a residual graph; routing feasibility is maintained at every step. A
  failure is detected in O(grid cells) via a BFS, never via exponential
  search.
- **New deduction style** — surfaces LT-specific deductions (articulation
  points, virtual groups, blocking-disconnects from `letter_group.dart`)
  at the centre of the trace. Desired trace shape:
  - high `switch_ratio` (alternation LT ↔ guardrail);
  - low `cascade_ratio` (no totalitarian FM);
  - moderate `force_depth` (articulation points are shallow forces).

## Player view (example)

5×5 puzzle with two letters:

```
. . . . Z
. . . . .
Y . . . .
. . . . .
Z . . . Y
```

The player knows the two Z's share a colour and the two Y's share a
colour (possibly the same as Z's), and that same-colour paths must stay in
disjoint connected components. Without further constraints the routing is
ambiguous; guardrails (`QA:8`, `PA:12.right`, `GS:7.3`, …) disambiguate.

## Algorithmic overview

`preFillPath` runs up to `maxRetries` (default 30) attempts. Each attempt
calls `buildPathBackbone` and, on success, `_completeBackground`.

### Step 1 — Colour assignment (`assignColors`)

`assignColors` is public and exercised directly by
`test/prefill_path_test.dart` (mirroring how `pickIslandColors` is tested
for the SY pre-fill).

The function has two branches depending on domain size.

**Domain ≥ 3 colours.** Every colour must be owned by at least one letter;
this is the condition that makes the routed grid genuinely N-colour (LT
only enforces monochrome connectivity — without full coverage
`autoShrinkDomain` would collapse the puzzle to fewer colours).
Implementation: a list `[...domain, <surplus random colours>]` is
shuffled, then mapped letter-by-letter. Surplus letters (L > |domain|)
receive a random colour from the domain, producing same-colour letter
pairs — the hard separation case where two letters of the same colour must
remain in disjoint components.

**Domain 2 colours.**
- `L = 2`: a Bernoulli `sameColorProb` (default 0.5) chooses between
  *same colour* (both letters share one colour; harder, as their components
  of the same colour must stay disjoint) and *different colour* (easier).
- `L ≥ 3`: each letter draws a colour independently (by pigeonhole at
  least one same-colour pair is always present).

**Letter-count floor.** `numLetters` is nullable. When not supplied, the
count is computed as:

```dart
final maxExtra = domain.length >= 3 ? 1 : 2;
final nLetters = numLetters ?? domain.length + rng.nextInt(maxExtra + 1);
```

This floors `L` at `domain.length` (ensuring full colour coverage) and
adds a random surplus: domain 2 → L ∈ {2, 3, 4}; domain 3 → L ∈ {3, 4}.

### Step 2 — Letter namespace (`pathLetterNames`)

The backbone letters are drawn from a namespace **disjoint** from the
names `LetterGroup.generateAllParameters` emits for greedy candidates
(which uses A, B, C… upward, skipping 'I'). The backbone takes Z, Y, X…
downward, also skipping 'I'. The function `pathLetterNames(n)` produces
this list.

The disjointness invariant means greedy-added LT candidates can never
accidentally reference a backbone letter's name and merge into a backbone
region.

### Step 3 — Region construction per letter (`_buildRegion`)

`buildPathBackbone` iterates over letters in order and calls `_buildRegion`
for each. The grid is modified in place; `owner[idx]` tracks which letter
owns each cell (null = background).

**Residual graph traversability.** A cell is traversable for letter L of
colour C if and only if:

1. It is free (not owned by another letter), AND
2. None of its 4-neighbours are owned by a *different* letter AND coloured C.

Condition 2 is the one-cell moat rule: it prevents two regions of the same
colour from becoming 4-adjacent, which would make them indistinguishable
to LT and constitute a forbidden same-colour merge. Regions of *different*
colours may be adjacent without restriction.

**First anchor.** A traversable free cell is chosen with a soft bias toward
the grid interior (tournament selection over 4 random candidates, scored by
`min(distance_to_top, distance_to_bottom, distance_to_left,
distance_to_right)`). Interior placement gives paths more room to wind.

**Subsequent anchors** (k − 1 more, k ∈ {kMin..kMax}, default 2..3):

1. BFS flood-fill (`floodFill` from `utils/groups.dart`) from the current
   region under the traversability predicate identifies all reachable free
   cells.
2. Reachable candidates must satisfy Manhattan distance ≥
   `minSameLetter = max(2, ⌈min(W, H) / 2⌉)` from every existing anchor.
3. A target cell `dst` is drawn uniformly from that set.
4. `_connect` builds a self-avoiding winding walk from `dst` toward the
   existing region.

**Failure semantics.** If no reachable candidate exists for the mandatory
second anchor, the entire attempt is dead (`_buildRegion` returns null →
`buildPathBackbone` returns null → `preFillPath` increments the retry
counter with `PathFailCause.placement`). A missing *third* anchor
(k = 3 attempt) degrades gracefully to k = 2 rather than failing.
`_buildRegion` returns null when fewer than 2 anchors were successfully
placed; the caller treats this as a placement failure.

### Step 4 — Winding self-avoiding walk (`_connect`)

`_connect` walks from a new anchor `dst` toward the existing region by
alternating between "step toward region" and "step away from region"
based on `windingProb`:

```
for each step:
  candidates = free neighbours of cur that are traversable AND
               can still reach the region without passing through cur
               (canReach BFS excluding the already-walked path)
  sort candidates by Manhattan distance to the nearest region cell
  if rng.nextDouble() < windingProb AND |candidates| > 1:
      step = farthest candidate   (winding)
  else:
      step = nearest candidate    (converging)
  add step to path
```

The `canReach` guard prevents dead ends: the walk only steps to a cell
from which the region is still reachable via the remaining traversable
cells. This ensures the walk terminates in O(W × H) steps without
exponential backtracking.

`windingProb = 0` produces near-shortest paths (easy puzzles; regions are
trivially separated). `windingProb = 1` produces snaking paths that wind
around each other, creating the topological tension that generates harder
LT deductions.

### Step 5 — Background completion (`_completeBackground`)

After all letter regions are placed, the background cells (those with
`owner[i] == null`) are still free. `_completeBackground`:

1. Builds the `LetterGroup` constraints from each letter's anchor list
   (e.g. `LetterGroup('Z.0.7.23')` for letter Z with anchors at indices
   0, 7, 23).
2. Clones `backbone.solved` and attaches the LT constraints to the clone
   only (`solved` itself receives no constraints and is returned pure).
3. Calls `findOneSolutionByDpll(copy, timeoutMs: completionTimeoutMs)` on
   the clone.

Because the regions are placed feasibly-by-construction, the background
completion is almost always solved in a handful of DPLL branches —
near-instant in practice. A timeout (default 2000 ms) or a
proven-infeasible result causes the attempt to fail with
`PathFailCause.routingTimeout` or `PathFailCause.routingInfeasible`
respectively.

The DPLL result is applied back to `backbone.solved` (only the free
background cells need updating; the region cells already carry their
colours). The function returns a `PathPrefillResult`.

## Data structures

### `PathBackbone`

Represents the intermediate state after region construction, before
background completion. Public so tests can verify structural invariants —
same-colour non-merge, monochrome connectivity, colour coverage — on the
construction alone without running the DPLL completion.

```dart
class PathBackbone {
  final Puzzle solved;                     // regions painted, background free
  final List<String?> owner;               // cell index → owning letter, or null
  final Map<String, List<int>> anchors;    // letter → list of anchor indices
  final Map<String, CellValue> colors;     // letter → assigned colour
  int get backboneCells;                   // count of cells owned by any letter
}
```

### `PathPrefillResult`

The output returned to the caller.

```dart
class PathPrefillResult {
  final Puzzle solved;                  // pure coloured grid, NO constraints
  final List<LetterGroup> letterGroups; // backbone LTs, to seed into `pu`
  final int backboneCells;              // cells in built regions (diagnostic)
}
```

`solved` carries no constraints by design. The candidate enumeration in
the classic greedy branch reads `solved.cellValues` and enumerates
`verify(solved)` candidates. If backbone LTs were attached to `solved`,
candidates for letters not in the backbone namespace could accidentally
merge with them. Keeping `solved` pure avoids the invariant violation
documented in `generator.dart` ("same-letter LT merge" comment at the
candidate loop).

## API

```dart
PathPrefillResult? preFillPath(
  int width,
  int height,
  List<CellValue> domain,
  Random rng, {
  int? numLetters,
  int kMin = 2,
  int kMax = 3,
  double sameColorProb = 0.5,
  double windingProb = 0.5,
  int maxRetries = 30,
  int completionTimeoutMs = 2000,
  PathPrefillStats? stats,
  bool Function()? shouldStop,
})
```

### `PathPrefillStats`

An optional diagnostics object passed in by the caller (typically
`generateOne`). Populated on both success and failure so calibration
tooling can observe the distribution from winning attempts as well as
failures.

```dart
class PathPrefillStats {
  final Map<PathFailCause, int> causeCounts; // tally of per-retry failure causes
  int retriesUsed;       // loop iterations consumed (1 on first-try success)
  int routingCalls;      // total DPLL background-completion calls
  int routingMsMax;      // wall time of the slowest single completion (ms)
  int routingMsTotal;    // cumulative completion wall time (ms)
  int prefillMs;         // total wall time of the preFillPath call (ms)
  PathFailCause? get dominantCause; // most frequent cause, null if none
}
```

`retriesUsed` counts *attempted* iterations, including the successful one
on a win; a value of 1 indicates the construction succeeded and the
background completed on the first try.

`routingMsMax` and `routingMsTotal` cover only the DPLL background
completion step (stage 5); construction time (stages 2–4) is folded into
`prefillMs`.

## Integration with `generator.dart`

`GeneratorConfig.pathBasedScenario` (bool, default `false`) gates the
dispatch in `generateOne`. When true, `generateOne` calls `preFillPath`,
seeds the backbone LTs into the player puzzle, and proceeds through the
standard greedy loop and `_finalize` tail. The key integration points are:

**Backbone seeding.** After `pu.addAllConstraints(solved.constraints)`
(a no-op when `solved` is pure), the backbone LTs are seeded explicitly:

```dart
for (final lt in constructiveLts) {
  pu.addConstraint(lt);
}
```

This places the backbone LTs in `pu` before the greedy loop runs, so they
appear in the puzzle regardless of whether the greedy would have selected
them. They are never candidates in the greedy loop (their letter namespace
is disjoint from what `generateAllParameters` emits).

**QA/GC deprioritization.** When `pathBasedScenario` is true, the greedy
sets `deprioritizedSlugs = {'QA', 'GC'}`. These slugs are placed at the
tail of both the initial candidate sort and the post-accept resort:

```dart
final aDep = deprioritizedSlugs.contains(sa) ? 1 : 0;
final bDep = deprioritizedSlugs.contains(sb) ? 1 : 0;
if (aDep != bDep) return aDep.compareTo(bDep);
```

QA and GC count cells by colour globally. When the backbone already
determines the colour of most non-background cells, a single QA constraint
pins the background count and can close the puzzle in one step — a
"= background" degeneracy where the player just fills in the remaining
cells of one colour without any path-routing reasoning. The
deprioritization keeps QA and GC available as a last resort but pushes
them to the back of every sort order so path-relevant constraints (NC, PA,
GS, …) are tried first.

**`removeUselessRules` with `preserveSlugs: {'LT'}`.** Post-loop cleanup
calls `pu.removeUselessRules(preserveSlugs: const {'LT'})`. This prevents
any backbone LT from being removed regardless of redundancy — removing it
would strip the puzzle's structural identity even if the remaining
guardrails happen to close it.

**Generation scenario stamp.** `pu.generationScenario = 'pathBased'` is
written into the v2 line's `scenario:pathBased` suffix. `detectPuzzleProfile`
in `equilibrium.dart` reads this suffix to classify puzzles for the
profile axis.

**Reject reason mapping.** `_pathRejectReason(stats)` translates
`stats.dominantCause` into the shared `GenerationRejectReason` taxonomy:

| `PathFailCause` | `GenerationRejectReason` |
|---|---|
| `placement` | `pathPlacementFailed` |
| `routingTimeout` | `pathRoutingTimeout` |
| `routingInfeasible` | `pathRoutingInfeasible` |
| `bipartite` (unused) | `pathPrefillFailed` |
| `null` | `pathPrefillFailed` |

`pathBasedScenario` is set by:

- the CLI flag `--scenario path-based` (forces 100 %);
- the equilibrium when it picks `ProfileTarget(ProfileCategory.pathBased)`.

`pathBasedScenario = cliFlag || equilibriumPick` — OR logic, so the CLI
flag is a short-circuit override.

### Calibration parameters

Two parameters are forwarded from `GeneratorConfig` to `preFillPath` and
exposed as CLI flags:

| `GeneratorConfig` field | Default | CLI flag | Effect |
|---|---|---|---|
| `pathMaxRetries` | 30 | `--path-retries N` | Maximum loop iterations in `preFillPath` before it returns null. |
| `pathWindingProb` | 0.5 | `--winding <0..1>` | Path sinuosity. 0 ≈ shortest path (easy puzzles, regions trivially separated); 1 ≈ maximum sinuosity (harder LT deductions). |

Both defaults are identical to the hardcoded values used before these
parameters were exposed; omitting the CLI flags preserves prior behaviour.

**Easing.** When `pathBasedScenario` is active, `_finalize` passes
`allowedSlugs ∖ {LT}` to `Puzzle.simplify` so easing can't add more
letters during the easing loop.

## Worked example: 4×4 grid with two letters

Letters Z (black) and Y (white), each with 2 anchors:

```
Construction after Step 3:

  . . . Z       Z  = first anchor of letter Z, painted black
  Z . . .       *  = cells painted during _connect walks
  . . . Y       Y  = first anchor of letter Y, painted white
  . Y . .

After _completeBackground (DPLL fills . cells):

  1 0 0 Z       1 = black, 0 = white
  Z 1 0 0       Z cells: black (LT: Z.0.4 = connected black group)
  0 0 1 Y       Y cells: white (LT: Y.11.13 = connected white group)
  0 Y 1 1
```

The LT constraints `Z.0.4` and `Y.11.13` are seeded into `pu`; the greedy
then adds guardrails (PA, NC, GS, …) until the routing is deductively
unique.

## Worked invariant: same-colour moat

Consider two letters Z and X, both assigned colour black. After Z's region
is placed at cells {0, 1, 4}, cell 5 has a neighbour (cell 4) owned by Z
with colour black. The traversability predicate for X excludes cell 5:

```
canTraverse(5) for letter X:
  owner[5] == null → ok (cell is free)
  getNeighbors(5) = [1, 4, 6, 9]
  owner[4] == 'Z' AND owner[4] != 'X' AND solved.cellValues[4] == black → FAIL
  → cell 5 is not traversable for X
```

X's region can touch Z's region only via cells of a *different* colour.
This makes the two black regions permanently non-adjacent in the residual
graph, satisfying LT's requirement that they stay in disjoint components.

## Profile axis integration

The equilibrium carries a `profile` axis (`kTargetProfile` in
`equilibrium.dart`) with targets `{classic: 0.85, sh: 0.05, pathBased:
0.05, syBased: 0.05}`. Path-based puzzles are identified by the explicit
`scenario:pathBased` suffix on the v2 line — there is no LT-pattern
heuristic. Lines without a recognised suffix fall back to `classic`.

When the picker yields `ProfileTarget(pathBased)`, `_resolveTarget` in
`worker_io.dart` flips `pathBasedScenario = true` for that iteration.
Each generated path-based puzzle is fed back into
`EquilibriumStats.withPuzzle(..., profile: detectPuzzleProfile(line))`.

## Per-attempt telemetry in `generator_stats.csv`

`worker_io.dart` appends five columns to every row of
`generator_stats.csv` for path-based attempts; non-path attempts emit
empty strings. The columns are added at the end of the row for backward
compatibility.

| Column | Type | Source field | Meaning |
|---|---|---|---|
| `path_retries` | int | `PathPrefillStats.retriesUsed` | Iterations consumed by `preFillPath` (includes the winning iteration on success). |
| `path_routing_calls` | int | `PathPrefillStats.routingCalls` | DPLL background-completion invocations across all retries. |
| `path_routing_ms_max` | int | `PathPrefillStats.routingMsMax` | Wall time of the slowest single background completion (ms). |
| `path_routing_ms_total` | int | `PathPrefillStats.routingMsTotal` | Cumulative background-completion wall time across all retries (ms). |
| `path_prefill_ms` | int | `PathPrefillStats.prefillMs` | Total wall time of the `preFillPath` call (ms). |

These values are emitted on both `SUCCESS` and `FAILURE` rows so
calibration of `--path-retries` and `--winding` can be informed by the
distribution of successful attempts as well as failed ones.

Worker log lines also include a condensed path-stats suffix on the
`SUCCESS`/`FAILURE` entry:

```
result: SUCCESS in 412ms (tried=7/22) [path retries=2 routingMaxMs=134 routingTotalMs=246 prefillMs=380]
```

## Tunable parameters

| Parameter | Default | Effect |
|---|---|---|
| `W × H` | 4×4 to 8×8 | Below 4×4: no room for two paths. Above 8×8: construction combinatorics grow large. |
| Letter count `L` | domain 2 → {2,3,4}; domain 3 → {3,4} | Nullable `numLetters`; floored at `domain.length` to guarantee full colour coverage. Same-colour letter pairs are the harder routing case. |
| Anchors per letter `K` | 2 or 3 | 2 = linear "Number Link" path. 3 = Steiner tree, topologically richer. |
| Min distance between anchors | `max(2, ⌈min(W, H) / 2⌉)` | Avoids trivial LT routings. |
| `windingProb` | 0.5 | Controls path sinuosity (0 = shortest, 1 = maximum winding). |
| Colour pairing | see `assignColors` | On 2-colour domain: same-colour and different-colour both allowed (difficulty knob). On ≥ 3-colour domain: every colour owned by ≥ 1 letter; surplus letters draw a random colour, producing same-colour pairs. |

## Caveats

- **The "exterior" is not defined.** Cells outside the letter paths can
  form multiple groups. A non-letter cell can land in the same group as a
  letter cell — `LetterGroup.verify` tolerates it, provided the cell's
  colour matches.
- **Background completion cost.** By-construction feasibility keeps the
  DPLL step near-instant in typical cases. The defensive `completionTimeoutMs`
  (default 2000 ms) protects against degenerate topologies where the
  background becomes tightly constrained. The `path_routing_ms_max` column
  in `generator_stats.csv` identifies whether the timeout is ever binding.
- **Over-determination.** If the greedy needs too many guardrails to reach
  uniqueness, the puzzle loses its path-based identity. Observable via the
  `lt-share` of the final trace; the QA/GC deprioritization keeps this in
  check by prioritising path-relevant guardrails.
- **Dashboard.** `bin/generate.dart`'s live dashboard does not yet display
  `profileCounts` (only slug / ntypes / size / pair).
