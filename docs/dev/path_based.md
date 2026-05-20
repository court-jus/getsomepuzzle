# Path-based puzzles — generation by routing

> **Status**: implemented. Pipeline lives in
> `lib/getsomepuzzle/generator/prefill/path.dart`, wired through
> `generator.dart` via `pathBasedScenario` and selectable via
> `--scenario path-based`.
>
> Counterpart to the *Future directions* section of
> [`generator.md`](generator.md): first concrete lead for *theme-first*
> generation (skeleton first, grid later).

## 1. Pitch

A "path-based" puzzle is dominated by the **LT** constraint (LetterGroup,
slug `LT`). The intellectual work for the player is no longer
"counting / guessing cells" but **routing** each letter through the
grid:

- Each letter `A`, `B`, `C`… defines a set of anchors (marked cells)
  that must all end up in the same connected group of one color.
- Two distinct letters can never share a group, so their paths repel
  each other.
- Other constraints (`PA`, `GS`, `QA`, `CC`, `RC`, `NC`, …) play the
  role of **guardrails**: they force one routing over another when
  several routings are a priori valid.

In spirit, this is the idea of *Number Link / Flow Free*, but on the
terrain of our bicoloring: a path is a chain of cells of a given color
that interleaves with the opposing path rather than simply avoiding
its neighbors.

## 2. Why this lead

### 2.1. Strong aesthetic identity

The player immediately knows what to do ("connect the A's, the B's,
the C's") before even reading the other constraints. The puzzle has a
visible *intent* — something a random slug mix doesn't always have.

### 2.2. Limitation of the current generator lifted

The "grid-first" generator draws a random 50/50 grid then collects
the constraints that verify it. Topological motifs (long snakes,
distant anchors) rarely appear, so LT is under-used or used trivially
(near-adjacent anchors). A *theme-first* generation can instead
**build** the topology first.

### 2.3. New deduction style

The current solver already handles LT deductions (see `letter_group.dart`:
articulation points, virtual groups, blocking-disconnects). But these
deductions are buried in puzzles where LT is just one constraint among
many. A puzzle dominated by LT brings these deductions to the front
and reveals the elegance of chains like:

> "If I color cell X white, B's path is cut in two with no possible
> reconnection bridge — so X must be black."

This is mechanically different from the current "FM cascade" (cf.
`generator.md` § 3.2, where `cascade_ratio` correlates with disliked
puzzles).

## 3. The played scenario

### 3.1. Player view

Take a 5×5 puzzle with two letters:

```
. . . . A
. . . . .
B . . . .
. . . . .
A . . . B
```

(A at top-right and bottom-left, B at bottom-right and top-left.)

The player knows:
- The two A's are connected by a path of the **same color**.
- The two B's too, in the **same color** (potentially the same as A's
  or different — that's part of the puzzle to discover).
- Paths A and B do not touch.

Without additional constraints the puzzle has multiple solutions
(several possible routings). So we add **shape/counting constraints**
that disambiguate:

- `QA:8` → exactly 8 black cells (forces the relative size of the two
  paths).
- `PA:12.right` → row 12 has a fixed parity (orients the passage).
- `GS:7.3` → the group containing cell 7 has 3 cells (segments).
- etc.

### 3.2. Expected resolution style

The ideal is a trace where:
- The first LT deductions propagate anchors (myColor on each member —
  `complexity: 0`).
- Then articulation points appear (`complexity: 4`): mandatory
  passages get closed.
- Then guardrail constraints (PA / GS / QA) cut between surviving
  routings.
- The end of the trace is a fine cascade, not a dominant FM:12.

So on the score of [`generator.md`](generator.md) § 3.1 we want:
- high `switch_ratio` (alternation LT ↔ guardrail),
- low `cascade_ratio` (no totalitarian FM),
- moderate `force_depth` (articulation points are *shallow* forces —
  already expensive for the solver but reasonable for the player).

## 4. Proposed generation pipeline

### General framework — a 3rd pre-fill mode

The current generator already has **two pre-fill modes** dispatched
based on context (`generator.dart:187-207`):

- `_preFillRegular(W, H)` — random 50/50 grid (default case).
- `_preFillSh(W, H)` — grid pre-painted with a valid SH motif when
  `SH ∈ prioritySlugs`. The corresponding `ShapeConstraint` is attached
  to the puzzle via `pu.addAllConstraints(solved.constraints)` and
  participates in the standard pipeline like any other.

**We add a third mode** `_preFillPath(W, H, pathConfig)` that produces:
- a complete solution grid satisfying an LT scenario (topology +
  routing),
- the `L` corresponding `LetterGroup` constraints,
- the list of anchor indices that should be `readonly` in the final
  puzzle (cf. § 5).

All the rest of the `generator.dart` pipeline (candidate enumeration,
greedy cherry-pick, finalization, classification, easing, polish)
**stays identical**. The path-based scenario doesn't invent a new
pipeline; it feeds the existing pipeline with a solved grid of a
different type.

Concretely, stages 4.1 and 4.2 below describe the **contents of
`_preFillPath`**. Stages 4.3 and 4.4 are mentioned for memory — they
already exist.

### 4.1. Stage 1 — topology (sample_anchors)

Place the `L × K` anchors on the grid respecting separation
constraints, **preferring interior positions** (col ∈ [1, W-2] and
row ∈ [1, H-2]). Two reasons:

1. **More gameplay depth**: a path that starts in the interior must
   *go around* its neighbor rather than hugging the edge in a straight
   line. LT articulation points (rule 4 of `LetterGroup.apply`,
   `complexity: 4`) become much more frequent — exactly the kind of
   deduction we want to highlight.
2. **Dodging the Jordan curve trap**: Jordan's theorem only constrains
   connected bipartitions for points on the region's boundary. Interior
   anchors → all color configurations remain topologically possible.

Algorithm:

```
function sample_anchors(W, H, L, K, rng) -> Map<Letter, List<int>>?
  min_same_letter := max(2, ⌈min(W, H) / 2⌉)
  zone := interior_zone(W, H)        // col ∈ [1, W-2], row ∈ [1, H-2]
  if |zone| < L * K * 2:             // interior too small
    zone := full_grid(W, H)          // fallback (typically W, H ≤ 4)
  placed := []                       // (letter, idx) tuples

  for letter in 'A'..'A'+L-1:
    for k in 0..K-1:
      for try in 1..MAX_LOCAL_TRIES:
        idx := random cell from zone
        if (_, idx) ∈ placed:
          continue                   // collision
        if ∃ (letter, j) ∈ placed with manhattan(idx, j) < min_same_letter:
          continue                   // same letter too close → trivial routing
        if ∃ (l, j) ∈ placed with l != letter ∧ manhattan(idx, j) ≤ 1:
          continue                   // different letters 4-adjacent → infeasible
        placed.append((letter, idx))
        break
      else:
        return null                  // couldn't place this anchor → restart
  return group_by_letter(placed)
```

Parameters:
- `min_same_letter`: prevents trivial routing (near-glued anchors).
  `⌈min(W,H)/2⌉` is a starting point; to be calibrated.
- Inter-letter adjacency ≤ 1 is the **only condition of immediate
  infeasibility** read from `letter_group.dart` (two adjacent letters
  can never live in separate groups). If we violate this rule when
  drawing, we may as well reject right away.
- `MAX_LOCAL_TRIES` (≈100): bounds the cost of a draw. On failure, we
  bubble up to the caller who can retry with a new RNG.

**Topological trap in fallback**: on grids too small to keep anchors
in the interior, Jordan's theorem comes into play. Four boundary
anchors that *alternate* in the different-color sub-case (e.g.
A=TL,BR ; B=TR,BL) → routing **topologically infeasible**. The DPLL
will detect it but only after exhausting its time budget. A priori
detection is desirable in this fallback:

- For the different-color case with ≥2 anchors on the boundary, verify
  that the pairs (A, B) **do not alternate** in the cyclic order along
  the boundary.
- In same-color, no such trap.

Not a blocker for the proto — the interior placement above avoids it
naturally in the majority of cases. See `test/backtrack_test.dart`
which covers the alternating scenario as a regression.

### 4.2. Stage 2 — color assignment

For L=2, two sub-cases (cf. § 2.3):

```
function assign_colors(L=2, sameColorProb, rng) -> Map<Letter, int>
  if rng.nextDouble() < sameColorProb:
    shared := rng.nextBool() ? 1 : 2
    return {'A': shared, 'B': shared}             // same-color
  else:
    a := rng.nextBool() ? 1 : 2
    return {'A': a, 'B': 3 - a}                   // different-color
```

`sameColorProb = 0.5` at the start. The same-color case is more
demanding feasibility-wise (the two letters must live in separate
components of the same color) — a failure at stage 4.3 will trigger
a retreat to a new topology, which *de facto* biases the observed
distribution toward different-color. To be measured empirically and
corrected if needed (for example by bumping `sameColorProb` above
0.5).

### 4.3. Stage 3 — routing (find_one_routing)

Given the anchors + colors, we look for **one** complete grid solution
satisfying the `L` LT constraints, ignoring the other constraints
(which will be added later by the greedy).

**DPLL-style** approach: composition of existing primitives
(`solve()`, `check()`, `clone()`), no new graph-based enumerator.

```
function find_one_routing(W, H, anchors_per_letter, colors_per_letter,
                          timeoutMs) -> Puzzle?
  pu := Puzzle.empty(W, H, [1, 2])

  // 1. Place anchors as readonly with their color
  for letter, indices in anchors_per_letter:
    color := colors_per_letter[letter]
    for idx in indices:
      pu.cells[idx].setForSolver(color)
      pu.cells[idx].readonly := true

  // 2. Attach the L LT constraints
  for letter, indices in anchors_per_letter:
    pu.addConstraint(LetterGroup("$letter.${indices.join('.')}"))

  // 3. Search by propagation + branching
  return _dpll_find_one(pu, deadline=now()+timeoutMs)

function _dpll_find_one(pu, deadline) -> Puzzle?
  if now() > deadline:
    return null
  if not pu.solve():                // propagation + force fail
    return null                     // state already inconsistent
  if pu.complete:
    return pu                       // ✓ solution found
  free_idx := first cell with value == 0
  for v in pu.domain:               // [1, 2]
    branch := pu.clone()
    branch.cells[free_idx].setValue(v)
    if branch.check(saveResult: false).isEmpty:
      result := _dpll_find_one(branch, deadline)
      if result != null:
        return result
  return null                       // both values fail
```

**Why DPLL rather than the current `_enumerateSolutions`**: the latter
(private to `bin/generate.dart:634`) doesn't propagate anything
between branches — it just does check-then-recurse. On a mostly-empty
grid with a few LT constraints, that explodes. The `solve()`
propagation between branches (which exploits `LetterGroup.apply` —
articulation points, blocks…) brings the search down to a handful of
branches at our target sizes.

**Recommended refactor**: extract `_enumerateSolutions` into a shared
module (e.g. `lib/getsomepuzzle/generator/backtrack.dart`) and add
the DPLL variant above. Both versions have their use case: the naive
enumerator stays useful for uniqueness verification on a quasi-complete
puzzle (its original use case), DPLL for solution search on a
quasi-empty puzzle. The refactor is not urgent — we can start with a
private function in `generator.dart` and factor out later.

**Execution guardrails**:
- `timeoutMs` (proposed: 2-3 s): on sizes 6×6-7×7 with 2 LT, DPLL
  should converge in < 100 ms. A timeout beyond that signals we should
  retry with another topology.
- No memoization cache: each call is short, nothing to reuse between
  puzzles.

### 4.4. Stage 4 — bipartite desambiguation (priority cascade)

At this point we have the solution grid and the `L` LT constraints,
but **no anchors are `readonly`**. The puzzle typically has several
possible solutions — we need to add context to make it uniquely
deductible while keeping LT dominant in the final trace.

**Motivation for the cascade design**: a simple `reveal / constraint`
alternation (the first implementation) produced *structurally*
path-shaped puzzles but allowed enough productive guardrails (NC, EY,
FM) to dominate the trace on grids ≥ 5×5 — `lt-share` collapsed to ~9 %
on a 227-puzzle test batch. The fix: bias the bipartite toward
LT-aligned actions (anchor reveals and path-cell reveals) which **do
not contribute propagation steps** to `solveExplained`, so the
`lt-share` denominator stays small.

Four levers, ordered by LT alignment:

- **Step 1: anchor reveal** — mark an LT anchor `readonly` with its
  solution color (cascade via LT rule 1).
- **Step 2: path cell reveal** — mark a cell of a letter's *intended
  path* `readonly` (a cell of the colored connected component reaching
  its anchors, minus the anchors themselves). More subtle than an
  anchor reveal; combines well with GC since it forces reasoning about
  connectivity around a midpoint.
- **Step 3: GC or QA (50/50)** — capped at one constraint per
  `(slug, color)` pair (max 4 such constraints total). GC is
  topological and naturally complementary to LT; QA is arithmetic but
  color-aligned.
- **Step 4: any other garde-fou** — PA, GS, CC, RC, NC, DF, SY, EY,
  FM. GC and QA excluded here (handled by step 3 with its cap).

**Intended path memory**: after DPLL routing, the connected component
of each letter's color is computed once and persisted through the
bipartite. See `_computeIntendedPaths` in `path.dart` — BFS over
4-connected cells of `solution[anchor_0]` starting from any anchor,
minus the anchor set.

**Acceptance criteria**:

| Step | Action | Accept iff |
|---|---|---|
| 1, 2 | Set cell `readonly` + value | `freeCells.length` drops by ≥ 2 after `solve()` (propagation **beyond** the revealed cell) |
| 3, 4 | Add constraint | `puzzle.computeRatio()` drops (same rule as the original `_tryAddConstraint`) |

The strict reveal criterion guarantees each reveal "earns" its slot in
the global cap; cells that would only be reproduced as readonly
without further propagation are skipped.

**Algorithm**:

```
function bipartite_desambiguate(pu, solution, anchors, intendedPaths,
                                 candidates, maxReveals, rng)
        -> _BipartiteResult?
  unrevealedAnchors  := shuffle(anchors)
  unrevealedPathCells := shuffle(flatten(intendedPaths.values))
  anchorReveals := 0
  pathReveals   := 0
  gardeFou      := 0

  for iter in 1..maxIterations:
    if pu.isDeductivelyUnique():
      return (anchorReveals, pathReveals, gardeFou)
    revealedTotal := anchorReveals + pathReveals

    if revealedTotal < maxReveals
       and try_reveal_anchor_strict(pu, solution, unrevealedAnchors):
      anchorReveals += 1; continue

    if revealedTotal < maxReveals
       and try_reveal_path_cell_strict(pu, solution, unrevealedPathCells):
      pathReveals += 1; continue

    if try_add_gc_or_qa(pu, candidates, rng):
      gardeFou += 1; continue

    if try_add_other_guardrail(pu, candidates):
      gardeFou += 1; continue

    return null                              // exhausted
  return null
```

Failed-but-still-eligible candidates **stay in the pool**: an anchor
that didn't propagate this iteration may propagate after a step 3/4
guardrail unlocks the deduction around it. The cascade restarts at
step 1 on each iteration.

**Anchor reveal policy** (step 1): pool is shuffled once at startup;
linear scan picks the first candidate that propagates. Future refinement:
prefer "letter A, anchor closest to the edge" for the first reveal
(easy visual landmark for the player) — not yet implemented.

**GC vs QA policy** (step 3): at each call, 50/50 random which slug is
tried first; if it has no helpful candidate (or all colors are
saturated), falls back to the other slug. Cap of 4 is checked via cast
on `puzzle.constraints` (`GroupCountConstraint.color` /
`QuantityConstraint.value`).

**Global reveal cap** (`bipartiteMaxReveals`): shared between anchor
reveals and path-cell reveals. Default = total number of anchors.
Beyond the cap, the cascade can only act through steps 3 and 4.

### 4.5. Stage 5 — orchestration (_preFillPath)

Loops stages 4.1-4.4 with retry on failure:

```
function _preFillPath(W, H, config, rng)
        -> ({Puzzle solved, Puzzle puzzle})?
  for attempt in 1..config.maxRetries:
    anchors := sample_anchors(W, H, config.L, config.K, rng)
    if anchors == null: continue           // placement failed → retry

    colors := assign_colors(config.L, config.sameColorProb, rng)

    solved := find_one_routing(W, H, anchors, colors, config.timeoutMs)
    if solved == null: continue            // routing infeasible → retry

    pu := empty_puzzle(W, H)
    for letter, indices in anchors:
      pu.addConstraint(LetterGroup(letter, indices))
    candidates := enumerate_garde_fou(W, H, allowedSlugs ∖ {LT})

    if bipartite_desambiguate(pu, solved, anchors, candidates, rng):
      return (solved, pu)                  // ✓ path-based puzzle ready

  return null                              // budget exhausted
```

Failure modes:
- `pathAnchorsFailed` — `sample_anchors` never converged.
- `pathRoutingInfeasible` — `find_one_routing` returned `null`.
- `pathTimeout` — DPLL exceeded `timeoutMs`.
- `pathBipartiteFailed` — bipartite desambiguation exhausted without
  reaching uniqueness. Symptom: not enough guardrails available + not
  enough anchors to reveal. Rare in practice (the candidate pool is
  large).

### 4.6. Signature and integration in `generator.dart`

**Implemented signature** (`lib/getsomepuzzle/generator/prefill/path.dart`):

```dart
PathPrefillResult? preFillPath(
  int width,
  int height,
  Random rng, {
  int numLetters = 2,
  int kMin = 2,
  int kMax = 3,
  double sameColorProb = 0.5,
  int maxRetries = 30,
  int routingTimeoutMs = 3000,
  bool preferInterior = true,
  int? bipartiteMaxReveals,
})
```

```dart
class PathPrefillResult {
  final Puzzle puzzle;               // player state (LT + guardrails + reveals)
  final List<int> solution;          // complete values, index-ordered
  final int anchorRevealedCount;     // anchors revealed via bipartite (step 1)
  final int pathRevealedCount;       // path cells revealed via bipartite (step 2)
  final int gardeFouCount;           // non-LT constraints added (steps 3 + 4)
  int get revealedCount => anchorRevealedCount + pathRevealedCount;
}
```

Returns `null` on failure (caller emits
`GenerationRejectReason.pathPrefillFailed`).

**File organization**: the three pre-fill functions now live in
`lib/getsomepuzzle/generator/prefill/`:
- `prefill/regular.dart` → `preFillRegular(W, H, domain, rng)`
- `prefill/sh.dart` → `preFillSh(W, H, domain, rng)` + SH helpers
- `prefill/path.dart` → `preFillPath(...)` + path-based helpers

This organization makes the cohabitation of the three modes explicit
and cleanly allows adding a fourth later if needed.

**`GeneratorConfig` extension**: `bool pathBasedScenario` field
(default `false`). Set by:
- the CLI flag `--scenario path-based` (semantic A, forces 100 %);
- eventually, the equilibrium when it draws `profile = path-based-LT`
  (cf. § 7.4) — not yet implemented.

**Dispatch in `generateOne`**: early-return in path-based mode,
otherwise the regular/SH flow continues. All paths then pass through
`_finalize` (extracted for DRY):

```dart
if (config.pathBasedScenario) {
  final result = preFillPath(width, height, _rng);
  if (result == null) {
    onReject?.call(GenerationRejectReason.pathPrefillFailed, ...);
    return null;
  }
  final pu = result.puzzle;
  pu.cachedSolution = result.solution;
  return _finalize(pu, config, onReject: onReject, shouldStop: shouldStop);
}

// Existing flow for SH and Regular:
final solved = hasSH
    ? preFillSh(width, height, _defaultDomain, _rng)
    : preFillRegular(width, height, _defaultDomain, _rng);
// ... rest of generateOne unchanged
```

**LT ban during easing**: implemented in `_finalize` — when
`config.pathBasedScenario` is active and we enter easing,
`Puzzle.simplify` receives `allowedSlugs ∖ {LT}` (cf. `generator.dart`,
the `easingAllowed` computed before the call).

### 4.7. Stage 6 — finalization (standard pipeline, reminder)

Identical to current: `solveExplained` gate, classification,
target-collection routing, easing loop (with LT ban in path-based,
cf. § 4.6), and offline trace_score → filter → polish. The score
distribution on this new puzzle type is to be measured empirically —
see § 7.5 (classification) for potential calibration.

## 5. Initial anchor status — dynamic

The readonly status of anchors **is not fixed in advance** — the
bipartite loop (§ 4.4) decides how many anchors to reveal. This
produces in practice three families of puzzles, without an explicit
parameter:

- **0 anchor revealed**: the bipartite succeeded in reaching
  uniqueness using only guardrails. The player deduces the colors of
  all `L` letters entirely from constraints. This is the analog of the
  former "variant 5.bis" — automatic when routing and guardrails are
  enough.
- **1-2 anchors revealed**: pattern observed on user hand-built
  puzzles (cf. `playlist_path_based.txt`). A starting point fixes the
  color of one letter, the others remain to deduce. Prefill ratio:
  `revealed / (W*H)` ≪ 0.25.
- **Many anchors revealed**: the bipartite couldn't reach uniqueness
  otherwise. If we exceed `bipartiteMaxReveals` (config option), we
  reject the puzzle rather than degrade it toward "not really
  path-based".

Consequence: no need for distinct variants A/B/C. The generator
produces what the puzzle needs.

LT semantics unchanged. No special flag in solver or serializer.

## 6. Parameters to fix / explore

To be calibrated empirically through batch generation:

| Parameter | Proposed range | Expected effect |
|---|---|---|
| `W × H` | 4×4 to 8×8 | < 4×4 = not enough room for two paths; > 8×8 = combinatorial explosion in routing. |
| Letter count `L` | **2 (proto), extensible 3-4** | The prototype caps at 2; the pipeline must remain extensible without rewriting (cf. § 4.2 architecture note). |
| Anchors per letter `K` | 2 or 3 (70/30 bias toward 2) | 2 = linear "Number Link" path; 3 = Steiner tree, topologically richer. |
| Min distance between anchors | `⌈min(W,H)/2⌉` | Avoids trivial LT. |
| Placement zone | interior (col ∈ [1, W-2], row ∈ [1, H-2]) by default; fallback to full grid if `\|interior\| < 2·L·K` | Paths must navigate around rather than hug the edge → frequent articulation points, dodges the Jordan curve trap. |
| Color pairing | both | Allow both same-color (rich, harder) and different-color (easy). Acts as a natural difficulty knob at L=2. |
| Max guardrail ratio | 3 to 5 non-LT constraints | Preserves "path-based" identity — beyond this we fall back to a generic puzzle. |

The current equilibrium (`equilibrium.md`) does not apply directly:
we no longer balance *all* slugs but a "path-based" vs "generic"
family. To be seen how it integrates — possibly an additional axis
(`shape`/`size`/`slug-mix`/**`scenario`**).

## 7. Open difficulties / known pitfalls

### 7.1. The "complement" is not defined

Once we've drawn paths A and B, the remaining cells are the
*exterior*. But this exterior isn't necessarily monochrome: it can
itself form multiple groups. That's OK as long as no constraint
mandates otherwise — but it can create "phantom" LT validating for
undeclared letters (impossible since LT is aggregated by letter —
see `letter_group.dart` line 61 comment). To verify: can a non-letter
cell get stuck in a group with a letter cell? The current `verify`
code allows it (a non-letter cell inside a letter's group is
tolerated).

### 7.2. DPLL routing cost

`find_one_routing` (§ 4.3) is DPLL: `solve()` (propagation+force)
between each branch, branching on the first free cell. To be measured
at the proto: on 6×6-7×7 with L=2 K=2-3 and the current `solve()`
that exploits `LetterGroup.apply` (articulation points, virtual
groups), we expect < 100 ms per call. Plan B if too slow: add an MRV
heuristic (most-constrained cell first) before writing anything more
complex.

Don't confuse with `_enumerateSolutions` (private to
`bin/generate.dart:634`) which is for **uniqueness** verification on a
quasi-complete puzzle: no propagation between branches, intentional in
that context but unsuited to routing search.

### 7.3. Over-determination

If the bipartite (§ 4.4) needs to add too many guardrails to reach
uniqueness, the puzzle loses its path-based identity. Observable
symptom: the LT-share of the final trace (measured as in
`bin/extract_path_like.dart`) drops below a threshold (proposed:
50–60 %).

**Initial implementation** (reveal/constraint alternation) produced a
9.3 % `lt-share ≥ 50 %` pass rate on a 227-puzzle batch — confirmed
the over-determination risk in practice. The bipartite added 16+
guardrails on 6×8 grids for 2 LT, so non-LT constraints dominated the
trace.

**Cascade fix** (current implementation, § 4.4): by prioritizing
reveals over guardrails, the cascade keeps the trace `totalProp`
small (reveals don't contribute propagation steps) so LT propagations
account for a higher fraction. The GC/QA cap in step 3 further limits
the dilution by productive guardrails.

**Optional post-condition** (not implemented): a stage-6 reject when
`lt_share(trace) < threshold`. Lighter to implement than the cascade
but wastes the generation budget instead of preventing the drift —
hence preferred only as a final safety net.

### 7.4. Interaction with `--require` / equilibrium

Implemented (cf. questions 3 and 4 of § 8):

- **5th equilibrium axis `profile`** with 3 categories `{classic, sh,
  pathBased}` and targets `{0.90, 0.05, 0.05}`. Cf. `kTargetProfile`
  in `equilibrium.dart`. The `pickTarget` picker treats this axis on
  equal footing with the other 4 (slug, ntypes, pair, size).
- **Heuristic profile detection**: `detectPuzzleProfile(v2Line)`
  (in `equilibrium.dart`) determines an existing puzzle's category
  without a marker in the v2 format. Rule: SH in constraints → `sh`;
  ≥2 LT with non-4-adjacent anchors → `pathBased`; otherwise
  `classic`. Heuristic is fallible (can over-count `pathBased` on
  lucky classic puzzles), acceptable for the equilibrium which
  self-corrects.
- **Pre-fill dispatch via `_resolveTarget`** (`worker_io.dart`):
  - `ProfileTarget(classic)` → no special constraint, default flow.
  - `ProfileTarget(sh)` → `preferredSlugs = {'SH'}`, `_preFillSh`
    activates via the existing mechanism.
  - `ProfileTarget(pathBased)` → `pathBasedScenario = true`,
    `preFillPath` activates in `generateOne`.
- **CLI `--scenario path-based`**: forces 100 % path-based for the
  run (complete short-circuit of the equilibrium). OR logic with the
  equilibrium decision: `pathBased = paramsFlag || equilibriumPick`.
- **Easing loop**: implemented in `_finalize` — when
  `config.pathBasedScenario` is active, `Puzzle.simplify` receives
  `allowedSlugs ∖ {LT}` to forbid adding more letters during easing.
- **Incremental stats**: `EquilibriumStats.withPuzzle` now accepts a
  `profile: ProfileCategory` (default `classic` for backwards
  compatibility). The worker passes `detectPuzzleProfile(line)` after
  each generation.
- **Output format**: no path-based marker added to the `v2_*` format —
  heuristic detection serves both `equilibrium` and
  `bin/extract_path_like.dart`. If we want an explicit marker
  eventually, it'll be a separate breaking change.

**Known limitations, to iterate on later**:
- The `bin/generate.dart` dashboard does not yet display the
  `profileCounts` distribution (only slug / ntypes / size / pair).
- The `pathBased` heuristic on the existing corpus counts ~6 % of
  existing puzzles as path-based — close to the 5 % target. For a
  strict metric, we'd need to add the format marker.

### 7.5. Level classification

`classifyTrace()` (cf. `levels.md`) was calibrated on the current
corpus. Path-based traces will likely have a different signature
(more `force` at depth 1 via articulation points). To measure before
integrating into collections.

## 8. First questions to settle

Before any prototyping, we need to agree on:

1. ~~**Anchor variant** (§ 5)~~ — **Settled**: anchors pre-colored
   `readonly`. The "unfixed-color letters" variant is preserved in
   § 5.bis as future exploration.
2. ~~**Typical letter count**~~ — **Settled**: L=2 strict for the
   prototype, K ∈ {2, 3} with bias toward 2, both color sub-cases
   (same-color and different-color) allowed. Explicit constraint: the
   pipeline must remain extensible to L≥3 without rewriting — hence
   the choice to reuse the existing solver for routing (§ 4.2).
3. ~~**Separate or integrated pipeline**~~ — **Settled**: integration
   via a 3rd pre-fill mode `_preFillPath` in `generator.dart`, in
   symmetry with `_preFillSh` and `_preFillRegular`. No new binary.
   Triggered via the new `profile` axis of the equilibrium; temporary
   CLI flag `--scenario path-based` for targeted calibration runs.
4. ~~**Position vs current corpus**~~ — **Settled**: injection into
   the existing corpus via a **5th equilibrium axis `profile`** with
   categories `{classic, SH, path-based-LT}` and targets
   `{0.90, 0.05, 0.05}`. SH becomes a first-class profile (no longer
   a hardcoded special case). No dedicated collection — path-based
   puzzles land in the usual tiers `[1-6]-*.txt` according to
   `classifyTrace`. The existing filters in `open_page.dart` continue
   to apply unchanged. The future notion of "game mode" / "player
   profile" is deferred; we can heuristically recognize path-based
   puzzles via `bin/extract_path_like.dart`.
5. **Manual demos first?** — before writing a generator, we could
   build 2-3 path-based puzzles by hand to verify that the solver
   handles them cleanly and that the score (`trace_score.dart`)
   judges them well.

Once these questions are settled, we can get into implementation
details (routing enumeration, choice of guardrails, calibration).
