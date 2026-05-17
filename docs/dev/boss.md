# Boss Mode — "seed-and-grow" generator

A generator variant aimed at **large puzzles** (≥ 30×20), playable on
desktop / tablet only. The default random prefill (`_preFillRegular`)
produces white-noise grids that are uninteresting at this scale; boss
mode replaces that first step with a "plant seeds, grow each one"
algorithm that builds coherent blobs, then tunes the rest of the
generator pipeline to be tractable on 600+ cell grids.

## CLI activation

Dedicated flag: `--boss`.

```bash
dart run bin/generate.dart -n 1 -j 1 \
  -W 30 --max-width 30 -H 20 --max-height 20 \
  --boss --max-time 600 \
  --log-dir /tmp/boss_logs
```

- Without `-o`, output goes to `assets/boss.txt` (so boss puzzles don't
  pollute the difficulty-routed default sinks).
- `--boss` **implicitly disables `--equilibrium`**: the warm-up phase
  locks the generator into a 2-slug configuration that is way too thin
  for 30×20 grids.
- No upper-bound dimension validation: the CLI accepts whatever you
  pass — your responsibility.
- The Flutter UI (`generate_page.dart`) is **not touched** by this
  feature. CLI-only.

## Architecture & entry points

| File | Role |
|---|---|
| `bin/generate.dart` | `--boss` flag, defaults `output = assets/boss.txt`, forces equilibrium off, forwards to `GeneratorConfig.useBossPrefill`. |
| `lib/getsomepuzzle/generator/generator.dart` | `GeneratorConfig.useBossPrefill` field; new `_preFillBoss(int w, int h)`; branched into `generateOne()` before `_preFillSh` / `_preFillRegular`. All boss-specific generator behaviour gated by `config.useBossPrefill`. |
| `lib/getsomepuzzle/generator/worker_io.dart` | `_IsolateParams.useBossPrefill` propagated into the in-isolate `GeneratorConfig`. `onLog` wired into the per-worker file logger. |

The rest of `generateOne` (phases 2 → 10) is **unchanged** for the
non-boss path. Boss path branches at each step where the default
behaviour scales poorly.

## Prefill algorithm

Constants (hardcoded for the first iteration):

```dart
const fillRatio              = 0.70;
const minGroupSize           = 15;
const maxGroupSize           = 25;
const maxSameGroup           = 3;
const maxConstraintParameters = 1000;
const addConstraintsInBatch  = 30;
const maxConsecutiveFailedBatches = 20;
```

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
3. Random colour in `_defaultDomain = [1, 2]`, uniform target size in
   `[15, 25]`.
4. **Grow**: while `group.length < target`:
   - Collect all free 4-neighbours of every group cell.
   - Empty → break (group ends up smaller than target — accepted).
   - Pick one uniformly, paint it, add to the group.
5. Store `(pivot, color)` in `seeds`. The `GroupSize` constraint is
   **not posted yet** — its final value depends on phase 2a fusion.

#### Notes and ideas to try

1. Instead of using `GS` alone, combine with `SY` (symmetry): grow each
   group around a random symmetry axis. Could create nice synergies.
2. Instead of drawing the seed's colour at random from the domain,
   pick one "background" colour up front and only grow "islands" of
   the opposite colour. With this approach phase 2a disappears.
3. We see that `FM` only generates ~90 candidate params and none match
   the prefill — expected since at this grid size all 90 patterns are
   likely to appear *somewhere*. Worth trying to *impose* one or two
   `FM` constraints from the prefill itself.

### Phase 2a — Random fill of the remaining ~30 %

For every still-empty cell, draw a random colour and paint it. This
**can grow** a seeded group if the random colour matches a neighbour
that belongs to one. Empirically this fuses many same-colour seeds
into one (see "Observed behaviour" below).

### Phase 2b — Post-fill: post the `GroupSize` constraints

Maintain a `Map<int canonical, int count>` of components already
constrained. For each seed:
- BFS the same-colour connected component from `pivot`. Track the
  canonical pivot (smallest cell index in the component).
- If `componentCounts[canonical] >= maxSameGroup`, skip — too many
  copies of the same statement already posted.
- Otherwise post `GroupSize('$pivot.$actualSize')` with the **actual**
  post-fusion size, increment the counter.

This keeps the constraint set lean even when several seeds collapse
into one component during phase 2a, and avoids any post-hoc mutation
of `GroupSize.size`.

### Phase 3 onward — Standard generator with boss tweaks

`generateOne` keeps its usual flow but the boss path branches at
several points (see below). At the end, the puzzle's line is exported
as usual into `assets/boss.txt`.

## Generator pipeline tweaks (boss mode only)

All gated by `config.useBossPrefill`; the non-boss path is unchanged.

### Phase 3 — Candidate cap with per-slug reserves

`GS` alone produces ~8 400 candidates on a 30×20 grid (600 indices × ~14
sizes). Verifying them all up front is what makes phase 3 dominate the
wall clock. Boss mode:
- **Shuffles** each slug's parameter list before verification.
- Keeps only the first `maxConstraintParameters = 1000` that verify
  against the solution grid.
- Stashes the un-tried tail in `reserveParams[slug] = (params, next)`
  (cursor into the shuffled list).
- A helper `refillFromReserve()` is called by phase 4 when
  `allConstraints` runs out before the puzzle is solved.

### Phase 4 — Batch addition + persistent `bossSolvedState`

Standard mode tests candidates one by one (2 solves per candidate:
baseline then with-candidate). On a 600-cell grid each solve is
expensive, so boss mode:

1. **Batches candidates** in groups of `addConstraintsInBatch = 30`.
   Trade-off: the final puzzle may carry some "passenger" constraints
   that were kept because the batch as a whole helped, not because
   each member was strictly required. Acceptable for boss puzzles
   (they aren't asked to be minimal).
2. **Persistent `bossSolvedState`**: deductive propagation is
   monotone (a cell deduced from constraint set C₁ stays deduced
   under any superset). The boss path keeps a cumulative
   post-propagation state across batches:
   - Each batch is tested on `bossSolvedState.clone() + batch`.
   - On acceptance, the just-solved clone is **promoted** to be the
     new `bossSolvedState` — no extra solve needed.
   - `ratioBefore = currentRatio` is already known; only `ratioAfter`
     needs a solve. **1 solve per batch instead of 2.**
3. **Anti-infinite-loop guard**: after
   `maxConsecutiveFailedBatches = 20` rejected batches in a row,
   force a reserve refill. If reserves are empty too, stop.

### Phase 4–6 — Propagation-only solves

`_forceOneCell()` clones the puzzle once per `(free cell, value)` pair
— on a 600-cell grid that's ~1 100 clones per `findAMove` call. Wall
clock explodes immediately. Boss mode passes `tryForce: false` to
every `solve()` in the iterative loop and to the final ratio check
(`Puzzle.solveExplained` gained a `tryForce` parameter too, default
`true`). Propagation may plateau higher than full-solve would, but the
batch loop compensates by adding more constraints until propagation
alone closes the grid.

### Phase 6 — Reuse `bossSolvedState` instead of cloning + solving

The default `phase 6` `solvedPu = pu.clone(); solvedPu.solve()` is
redundant in boss mode: `bossSolvedState` already holds the
post-propagation state for `pu.constraints`. Boss path just reads
`bossSolvedState.computeRatio()` and `bossSolvedState.freeCells()`
straight from it.

### Phase 10 — Skip `sortConstraintsByDifficulty`

The standard pipeline sorts constraints `easier-first` at the end so
in-app hints surface simpler deductions first. Boss mode **skips**
both call sites (final pass and easing branch). Reordering hundreds
of constraints on a big grid isn't free, and the easier-first
invariant isn't required of boss puzzles.

## Debug instrumentation

### Per-phase / per-slug worker log — `--log-dir DIR/worker_<n>.log`

`generateOne` exposes an `onLog(String)` callback, wired by `worker_io`
to its synchronous flushed file logger (so the file stays readable if
the worker hangs). Emitted lines:

- `phase1 prefill=boss WxH done in Xms`
- `phase2 prefilled=N readonly=N done in Xms`
- `phase3 start: K slug(s)`
  - `[SLUG] generateAllParameters → X params (shuffled) (Yms)`
  - `[SLUG] verify P% (i/X kept=k elapsed=Yms)` — ~every 10 %
  - `[SLUG] capped: kept=K reserve=R (scanned i/X in Yms)`
  - `[SLUG] exhausted: kept=K/X in Yms`
- `phase3 done: N initial candidates, reserves=K slug(s) in Xms`
- `phase4 boss: initial solvedState ratio=… filled=…/size in Xms`
- `phase4 batch=B scanned=S pu_constraints=C clone=…ms solve=…ms r:…→… → ACCEPT/reject remaining=… reserves=…`
- `phase4 done: tried=T accepted=A final ratio=…`
- `phase6 (boss): reusing bossSolvedState ratio=…`
- `phase8 solveExplained: steps=N unique=… in Xms`

Plus inline `[solve] iter=… findAMove=…ms cumFind=…ms elapsed=…ms filled=…/size moveTaken=…`
(throttled to every 10 iters or 500 ms) while each batch's `solve()`
runs.

## Playing a boss puzzle in-app

A 30×20 grid carries ~600 cells and several hundred constraints after
phase 4 batches. The in-app solver-driven features were never tuned
for that scale: leaving them on during play saturates a CPU core
continuously and the UI judders on every interaction.

**Recommendation: before opening a boss puzzle, disable solver-driven
features in Settings.**

| Setting | Recommended value | Why |
|---|---|---|
| **Hints** (`hintsEnabled`) | **OFF** | Disables the lightbulb button **and** all three post-mutation hint pre-computes (`_scheduleHelpMe`, `startHintConstraintComputation`, `_scheduleHintRanking`) — gated through `GameModel.hintsEnabled`, synced from settings on every puzzle open and every settings change. Without this, every tap triggers a `findAMove(tryForce=true)` (~1 100 clones on 600 cells) and a `HintWorker`. |
| **Grayout** (`grayoutEnabled`) | **OFF** | Disables `Puzzle.updateConstraintStatus()` (the per-tap `isCompleteFor` scan). Several constraints (`GS`, `SY`, `EY`) walk the full grid in their `isCompleteFor`. When OFF the implementation also defensively forces every constraint's `isComplete = false` on every call. |
| **Validation** (`validateType`) | **Manual** | `checkPuzzle` now early-returns unconditionally when `validateType == manual && !manualCheck`. Without this, a tap that happened to fill the last cell would trigger a full constraint scan and surface errors uninvited. |
| **Errors** (`liveCheckType`) | **Wait** (default) | `checkPuzzle` skips the per-tap scan until the grid is complete. With validateType=manual already gating everything, this is mostly redundant but cheap. |

With those four in place, every `_afterMutation` (every tap) reduces to:
`_clearHint()`, `notifyListeners()`, `rearmIdleTimer()`. No solve, no
`check`, no `updateConstraintStatus`. Boss puzzles feel responsive.

### Periodic stats save

The legacy `_saveTimer` heartbeat fired `database.writeStats()` every
60 s. `writeStats` **re-reads every stats file** on each call (to
merge with other collections), which shows up as a regular CPU spike
proportional to the corpus size. Bumped to **5 minutes** in
`main.initState`. At worst we lose 5 min of plays on an abrupt kill;
every puzzle completion already has its own save path.

### Why not auto-disable these features on "large" puzzles?

Legitimate but out of scope for the first prototype:
1. The threshold (grid size? constraint count?) isn't obvious without
   benchmarks.
2. Forcing a setting without persisting it surprises the player when
   they switch back to a small puzzle.
3. Some "large-ish" puzzles (15×15) play fine with grayout on.

To revisit later.

### Flutter Isolate CPU priority (research notes)

Whether the background `HintWorker` could run at a lower CPU priority
to leave UI cycles free was investigated. **Verdict: not possible
through standard Flutter/Dart APIs.**

- `Isolate.spawn` takes no `priority` argument. The `priority`
  parameter on `Isolate.kill` controls termination latency, not CPU
  scheduling.
- `compute()` (`package:flutter/foundation.dart`) is a wrapper over
  `Isolate.run`; same limitation.
- A Dart Isolate on native is a *dedicated OS thread* with its own
  heap. The OS multiplexes them with a default priority
  (`SCHED_OTHER`/nice 0 on Linux). Dart does not expose an API to
  change that.

Possible workarounds (none implemented):
- **Cooperative yield from within the isolate**: sprinkle
  `await Future.delayed(Duration.zero)` in the worker loop to let its
  own event loop catch up. Has no effect on OS priority — if both
  threads are CPU-bound, the OS splits them roughly evenly.
- **FFI to OS APIs**: `setpriority(PRIO_PROCESS, tid, niceness)` on
  Linux/macOS, `SetThreadPriority` on Windows. Requires getting the
  worker thread's TID, which Dart doesn't expose. Invasive and
  platform-specific.
- **Third-party packages** like [`worker_manager`](https://pub.dev/packages/worker_manager)
  do expose a notion of priority, but it's the priority **between
  tasks in a queue** (execution order), not the CPU priority of the
  worker thread vs. main. Doesn't help.

**Conclusion**: we go with manual gating via settings — less elegant
but reliable and zero native code.

## Workflow

```bash
# Generate a boss puzzle (logs into /tmp/boss_logs/worker_0.log,
# output in assets/boss.txt)
dart run bin/generate.dart -n 1 -j 1 \
  -W 30 --max-width 30 -H 20 --max-height 20 \
  --boss --max-time 600 \
  --log-dir /tmp/boss_logs

# Same, banning extra GS candidates (prefill-posted GS constraints
# still ship — `--ban GS` only stops phase 3 from generating more).
dart run bin/generate.dart -n 1 -j 1 \
  -W 30 --max-width 30 -H 20 --max-height 20 \
  --boss --ban GS --max-time 600 \
  --log-dir /tmp/boss_logs

# Inspect
tail -f /tmp/boss_logs/worker_0.log
cat /tmp/boss_prefill_<ts>.txt
```

## Ideas for later

(Discussed but not implemented yet — revisit once we have a body of
boss puzzles to evaluate.)

- **Anti-fusion phase 2a**: instead of painting random colours, paint
  each remaining cell with the colour that *minimises* the number of
  same-colour bridges between seeded groups. Or leave "frontier"
  cells empty.
- **Decreasing batch size**: start at 30–50, step down (e.g. 30 → 10
  → 3 → 1) as `currentRatio` approaches 0, to avoid keeping passenger
  constraints in the fine phase.
- **Split & search** on accepted batches: dichotomise to find the
  minimal sub-batch that delivers the gain. Costs ~log₂(K) extra
  solves per acceptance; probably not worth it unless we want minimal
  puzzles.
- **All-in stress test**: post every phase-3 candidate at once,
  single solve, check whether ratio reaches 0. Sanity check on
  whether the chosen prefill + slug set could ever produce a
  deductive puzzle.
- **Short-circuit phase 3 for `GS` on boss**: restrict `GS` candidate
  cells to the seed pivots (~20–30) instead of all 600. Slashes
  candidate count from ~8 400 to ~30 for that slug.
- **Honour `shouldStop` inside phase 3**: today `--max-time` is
  ignored while candidate verification runs.
- **Adapt `[minGroupSize, maxGroupSize]` to grid size** instead of
  hardcoded 15–25.
- **UI**: extend `generate_page.dart` sliders (3–10 → 3–40), add a
  Boss toggle, propagate through the worker.

## Out of scope

- Dynamic group-size parameterisation by grid size.
- WON'T DO: Flutter UI (`generate_page.dart`).
- WON'T DO: web worker variant (`worker_web.dart`).
- Removing the `/tmp/boss_prefill_*.txt` dump (delete or gate behind
  a debug flag once the algorithm is stable).
