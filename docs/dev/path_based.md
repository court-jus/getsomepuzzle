# Path-based puzzles — generation by routing

Pipeline lives in `lib/getsomepuzzle/generator/prefill/path.dart`,
wired through `generator.dart` via `pathBasedScenario` and selectable
either via the CLI flag `--scenario path-based` (forces 100 %) or by
the equilibrium's `profile` axis picking `ProfileCategory.pathBased`.

This is the concrete instance of *theme-first* generation referenced
in [`generator.md`](generator.md): build the topology first, collect
the constraints later.

## What a path-based puzzle is

A path-based puzzle is dominated by the **LT** (LetterGroup) constraint.
The intellectual work for the player is no longer "counting / guessing
cells" but **routing** each letter through the grid:

- Each letter `A`, `B`, `C`… defines a set of anchors that must all end
  up in the same connected group of one colour.
- Two distinct letters can never share a group, so their paths repel
  each other.
- Other constraints (`PA`, `GS`, `QA`, `CC`, `RC`, `NC`, …) act as
  **guardrails**: they break ties between several a priori valid
  routings.

In spirit this is Number Link / Flow Free on top of a bicolouring: a
path is a chain of cells of a given colour that interleaves with the
opposing path rather than just avoiding its neighbours.

### Why this design

- **Strong aesthetic identity** — the player immediately knows what to
  do ("connect the A's, the B's, …") before reading the rest of the
  constraints. The puzzle has a visible *intent*.
- **Lifts a limitation of the grid-first generator** — random 50/50
  grids rarely produce long snakes or distant anchors, so LT is
  under-used in the classic flow. Building topology first makes
  topologically rich LT puzzles tractable.
- **New deduction style** — surfaces LT-specific deductions
  (articulation points, virtual groups, blocking-disconnects from
  `letter_group.dart`) at the centre of the trace rather than buried
  in an FM cascade. Trace shape we aim for:
  - high `switch_ratio` (alternation LT ↔ guardrail);
  - low `cascade_ratio` (no totalitarian FM);
  - moderate `force_depth` (articulation points are shallow forces).

## Player view (example)

5×5 puzzle with two letters:

```
. . . . A
. . . . .
B . . . .
. . . . .
A . . . B
```

The player knows the two A's share a colour, the two B's share a
colour (possibly the same as A's), and the two paths don't touch.
Without further constraints the routing is ambiguous; guardrails
(`QA:8`, `PA:12.right`, `GS:7.3`, …) disambiguate.

## Pipeline

The path-based scenario plugs into the generator as a **third pre-fill
mode**, alongside `preFillRegular` (random grid) and `preFillSh`
(SH-seeded). All three live in
`lib/getsomepuzzle/generator/prefill/`. The rest of `generateOne`
(candidate enumeration, greedy cherry-pick, finalisation,
classification, easing, polish) is unchanged: the scenario simply
feeds a different solved grid into the existing pipeline.

`preFillPath` orchestrates five stages.

### 1. Anchor placement — `sample_anchors`

Places `L × K` anchors on the grid (default `L=2`, `K ∈ {2, 3}`)
respecting separation rules, **preferring interior positions** (col
∈ [1, W-2] and row ∈ [1, H-2]). Two reasons:

- More gameplay depth: an interior path must *go around* its neighbour
  rather than hugging the edge. LT articulation points (rule 4 of
  `LetterGroup.apply`, complexity 4) become frequent.
- Dodges the Jordan-curve trap: Jordan's theorem only constrains
  bipartitions for points on the boundary. Interior anchors keep every
  colour configuration topologically reachable.

Separation rules:

- `min_same_letter = max(2, ⌈min(W, H) / 2⌉)` between two anchors of
  the same letter — prevents trivial routing.
- Manhattan distance > 1 between anchors of *different* letters — the
  only condition of immediate infeasibility derivable from
  `letter_group.dart` (two 4-adjacent letters can never live in
  separate groups).

If the interior is too small (`|interior| < 2·L·K`, typically on grids
≤ 4 wide) the placement falls back to the full grid. In that fallback
the alternating-anchor Jordan trap can re-appear; the routing stage
(below) will detect it, but late.

### 2. Colour assignment

For `L = 2`, a Bernoulli `sameColorProb` (default 0.5) chooses between:

- **Same colour** — both letters share one colour. More demanding:
  they must live in separate components of the same colour. Failures
  at the routing stage retreat to a new topology, which de facto
  biases the observed distribution toward different-colour.
- **Different colour** — easier.

### 3. Routing — `find_one_routing`

Given the anchors + colours, looks for **one** complete grid solution
satisfying the `L` LT constraints, ignoring other constraints (they
get added later by the greedy).

Implemented as a DPLL-style search composed from existing primitives:

1. Place anchors as readonly with their colour, attach the `L`
   `LetterGroup` constraints.
2. Recurse: `solve()` (propagation + force) to fix what is forced;
   pick the first free cell; branch on each domain value; if
   `check()` is clean, recurse; bail on a per-call `timeoutMs` budget
   (default 3 s).

Propagation between branches exploits `LetterGroup.apply`
(articulation points, virtual groups, blocks), which collapses the
search to a handful of branches at our target sizes. A timeout signals
the topology is unhealthy and we should resample anchors.

This is distinct from `_enumerateSolutions` in `bin/generate.dart`,
which does check-then-recurse without propagation between branches —
intentional for uniqueness verification on a quasi-complete puzzle
but a poor fit for routing search on a quasi-empty one.

### 4. Bipartite disambiguation

After stage 3 we have the solution grid and the `L` LT constraints,
but **no anchors are readonly**. The puzzle typically has several
solutions; the bipartite cascade adds context until uniqueness is
reached while keeping LT dominant in the final trace.

The cascade biases toward LT-aligned actions because reveals **don't
contribute propagation steps** to the `solveExplained` trace, so the
`lt-share` denominator stays small. Four levers, ordered by LT
alignment:

| # | Action | Accept iff |
|---|---|---|
| 1 | **Anchor reveal** — mark an LT anchor `readonly` with its solution colour (cascade via LT rule 1) | `freeCells.length` drops by ≥ 2 after `solve()` (propagation **beyond** the revealed cell) |
| 2 | **Path cell reveal** — mark a non-anchor cell on the letter's intended path `readonly` | same as step 1 |
| 3 | **GC or QA (50/50)** — capped at one constraint per `(slug, color)` pair (≤ 4 total) | `puzzle.computeRatio()` drops |
| 4 | **Any other guardrail** — PA, GS, CC, RC, NC, DF, SY, EY, FM | `puzzle.computeRatio()` drops |

GC and QA share a single dedicated step because both are
topologically aligned with LT (GC explicitly, QA arithmetically with
colour alignment). The cap prevents either from dominating the trace.

**Intended-path memory**: after routing, the connected component of
each letter's colour is computed once (BFS over 4-connected cells of
`solution[anchor_0]` starting from any anchor, minus the anchor set)
and persisted through the bipartite — see `_computeIntendedPaths` in
`path.dart`.

**Cascade behaviour**: failed-but-still-eligible candidates stay in the
pool — an anchor that didn't propagate this iteration may propagate
after a step 3/4 guardrail unlocks the deduction. Each iteration
restarts at step 1.

**Reveal cap**: `bipartiteMaxReveals` (default = total number of
anchors) is shared between anchor and path-cell reveals; beyond it
the cascade can only act through steps 3 and 4.

### 5. Orchestration — `preFillPath`

Loops stages 1–4 with retry on failure (default `maxRetries = 30`),
returning a `PathPrefillResult` carrying `puzzle` (player state with
LT + guardrails + reveals), `solution` (complete values, index-ordered),
and counters for anchor / path / guardrail reveals.

Failure modes surfaced to the caller as
`GenerationRejectReason.pathPrefillFailed`:

- anchor placement never converged;
- routing infeasible;
- routing exceeded `routingTimeoutMs`;
- bipartite exhausted without reaching uniqueness (rare in practice).

## API

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

class PathPrefillResult {
  final Puzzle puzzle;
  final List<int> solution;
  final int anchorRevealedCount;
  final int pathRevealedCount;
  final int guardRailCount;
  int get revealedCount => anchorRevealedCount + pathRevealedCount;
}
```

## Integration with `generator.dart`

`GeneratorConfig.pathBasedScenario` (bool, default `false`) gates the
dispatch in `generateOne`:

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
// SH / Regular flow continues otherwise.
```

`pathBasedScenario` is set by:

- the CLI flag `--scenario path-based` (forces 100 %);
- the equilibrium when it picks `ProfileTarget(ProfileCategory.pathBased)`.

`pathBasedScenario = cliFlag || equilibriumPick` — OR logic, so the
CLI flag is a short-circuit override.

**Easing**: when `pathBasedScenario` is active, `_finalize` passes
`allowedSlugs ∖ {LT}` to `Puzzle.simplify` so easing can't add more
letters during the easing loop.

## Anchor readonly status is dynamic

The bipartite decides how many anchors to reveal — no explicit
parameter. In practice we observe three families of puzzles:

- **0 anchors revealed** — routing + guardrails sufficed. The player
  deduces every letter's colour entirely from constraints.
- **1–2 anchors revealed** — pattern seen on user hand-built puzzles
  (cf. `playlist_path_based.txt`). A starting point fixes one
  letter's colour; the rest is deduced. Prefill ratio
  `revealed / (W·H)` ≪ 0.25.
- **Many anchors revealed** — the bipartite couldn't reach uniqueness
  otherwise. Beyond `bipartiteMaxReveals` we reject the puzzle rather
  than degrade it into "not really path-based".

LT semantics are unchanged. No special flag in the solver or
serialiser.

## Profile axis integration

The equilibrium carries a `profile` axis (`kTargetProfile` in
`equilibrium.dart`) with targets `{classic: 0.85, sh: 0.05,
pathBased: 0.05, syBased: 0.05}`. Pre-existing corpus puzzles are
classified heuristically by `detectPuzzleProfile(v2Line)`: SH in
constraints → `sh`; ≥ 2 LT with non-4-adjacent anchors →
`pathBased`; otherwise `classic`. The heuristic is fallible but the
equilibrium self-corrects over runs.

When the picker yields `ProfileTarget(pathBased)`, `_resolveTarget`
in `worker_io.dart` flips `pathBasedScenario = true` for that
iteration. Each generated path-based puzzle is fed back into
`EquilibriumStats.withPuzzle(..., profile: detectPuzzleProfile(line))`.

The v2 line carries no path-based marker — heuristic detection serves
both the equilibrium and `bin/extract_path_like.dart`. Any future
explicit marker would be a separate breaking change.

## Tunable parameters

| Parameter | Default | Effect |
|---|---|---|
| `W × H` | 4×4 to 8×8 | Below 4×4: no room for two paths. Above 8×8: routing combinatorics explode. |
| Letter count `L` | 2 | The pipeline is structured to extend to 3–4 letters without rewriting; only stage 2 (colour assignment) needs generalising. |
| Anchors per letter `K` | 2 or 3 (70/30 bias) | 2 = linear "Number Link" path. 3 = Steiner tree, topologically richer. |
| Min distance between anchors | `⌈min(W, H) / 2⌉` | Avoids trivial LT routings. |
| Placement zone | interior by default; full grid fallback if too small | Forces paths to navigate, dodges the Jordan trap. |
| Colour pairing | both | Same-colour and different-colour both allowed; natural difficulty knob at `L = 2`. |
| Guardrail count | bounded by bipartite | Steps 3 + 4 stop adding once uniqueness is reached. |

## Caveats

- **The "exterior" is not defined.** Cells outside the letter paths
  can themselves form multiple groups. That's fine as long as no
  constraint mandates otherwise. A non-letter cell can land in the
  same group as a letter cell — `LetterGroup.verify` tolerates it.
- **DPLL routing cost.** `solve()` propagation between branches keeps
  the search in the hundred-ms range on 6×6–7×7 with `L = 2`,
  `K = 2–3`. If a routing exceeds `routingTimeoutMs` the topology is
  resampled.
- **Over-determination.** If the bipartite needs too many guardrails
  to reach uniqueness, the puzzle loses its path-based identity.
  Observable via the `lt-share` of the final trace
  (`bin/extract_path_like.dart`); the bipartite's cascade order keeps
  this in check by spending its early budget on reveals (zero-prop
  contribution to the trace) before guardrails.
- **Dashboard.** `bin/generate.dart`'s live dashboard does not yet
  display `profileCounts` (only slug / ntypes / size / pair).
