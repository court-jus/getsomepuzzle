# Third color

Currently, the game only works with two colors (black and white) but it could be interesting
to have some puzzles with more than two colors.

## Current state (as of 2026-05-13)

The "purple" third color is wired through the model (`CellValue.purple`),
the cell/options machinery (`Cell.options` + `Cell.removeOption`), the UI
(purple background + green foreground, plus option dots on free cells),
the generator (selectable domain via the CLI), and every player-facing
constraint and complicity has been ported to issue `removeOption`
deductions instead of forcing the opposite color.

What works:

* `CellValue` enum carries `free`, `black`, `white`, `purple`.
* `fullDomain` and `defaultDomain` live in `lib/getsomepuzzle/model/cell.dart`;
  `defaultDomain` is documented as "fullDomain truncated to its first two
  entries" and a unit test (`test/domain_constants_test.dart`) enforces
  that relationship since Dart `const` doesn't allow indexed lists.
* `Cell.options` is the authoritative per-cell domain; `removeOption`
  auto-converts to `setValue` when only one option remains.
* `Move` carries either `value:` (full assignment) or `removeOption:`
  (option pruning); every propagation loop in `puzzle.dart` handles
  both and bails out cleanly on no-op `removeOption` (option already
  pruned) or excluded-option `setValue`.
* `Puzzle.incrValue` cycles the tap through the puzzle's declared
  domain (`free → domain[0] → … → domain[last] → free`), so a 2-colour
  puzzle never surfaces purple. Wrapping back to free goes through
  `resetCell` so options are restored. `Puzzle.decrValue` is the exact
  mirror (`free → domain[last] → … → domain[0] → free`) and powers the
  right-click cycle and the mobile long-press: a single right-click
  (or long-press) on a free cell jumps straight to the last domain
  colour, so purple is reachable in one gesture on 3-colour puzzles
  instead of three taps via `incrValue`.
* Right-click and right-drag are uniform across domain sizes. The
  initial cell of a right gesture goes through `decrValue` (deferred
  to `pointer-up`, like the left-click deferred-tap dance, so a click
  is committed at release and a drag is committed at the first move).
  Subsequent free cells of a right-drag are painted with
  `_prevCycle(initialCellValue)` — i.e. the same colour the
  `decrValue` produced on the first cell. The 2-colour regression
  cost: erasing a white cell now takes two right-clicks
  (`white → black → free`) instead of one toggle — accepted as the
  price of uniformity.
* Left-drag uses `_nextCycle(initialCellValue)` as the paint colour
  (was `domain.whereNot(== initialCellValue).first`, which never
  produced purple on a 3-colour puzzle). Drag-painting a row in
  purple is now possible by starting the drag on a white cell.
* Long-press (mobile fallback for right-click) is wired through
  `GameModel.handleLongPress` to `Puzzle.decrValue`, mode-agnostic
  with respect to the paint / remove-option toggle (the long-press
  always means "previous colour", regardless of the left-tap mode).
* `CellWidget` renders one coloured dot per remaining option at the
  bottom of a free cell when `puzzle.domain.length > 2` (~10 % of the
  cell, with a thin grey outline so the white dot stays visible
  against the cyan "free" background). On 2-colour puzzles no dot is
  drawn (would carry no information).
* All twelve player-facing constraints ported (NC, EY, QA, GC, CC, RC,
  SH, FM, PA, GS, LT, DF, SY). Each emits `removeOption` (or `value`)
  with the `cells[idx].options.contains(X)` guard, falling back to
  `isImpossible` when the deduction conflicts with the option set.
* Complicities ported: `LTGSComplicity`, `SYFMComplicity` (both
  branches), `GSGSComplicity`, `LTFMComplicity`, `SHGSComplicity`,
  `GSAllComplicity`. `value: opposite(X)` patterns replaced by
  `removeOption: X` with `options.contains` guards (and the
  no-op-should-not-be-impossible convention from `parity.dart:182`).
* Hint UI handles `removeOption` end-to-end: tap 2 says
  "One of the options for this cell can be ruled out", tap 3 uses
  `hintRemoveOptionDeducedFrom` / `hintForceRemoveOption` /
  `hintRemoveOptionComplicity` / `hintRemoveOptionComplicityTwin`
  (parallel set to the setValue-side phrasings). Tap 4 applies the
  `removeOption` and the relevant cell-dot disappears.
* The hint button on a completed-and-valid puzzle repurposes as
  "next puzzle" past tap 1: tap 1 still shows
  `hintAllCorrectSoFar`, the next tap fires the same
  `onPuzzleCompleted` callback used by automatic validation.
* The CLI generator's domain is selected by `--domain N` (N ∈ {2, 3}),
  default 2. `GeneratorConfig.domain` flows through the worker
  isolate. The dashboard's `Config:` line surfaces the selected
  domain alongside size range, required rules and bans.
* `generateOne` auto-shrinks the puzzle's declared domain just before
  `lineExport` when the validated solution doesn't use a colour AND
  no constraint references it. A `--domain 3` run that produces a
  black-and-white-only solution exports as `v2_12_...`.
* `GroupCountConstraint.verify` and `apply` filter
  `getFreeCellsWithoutNeighborColor` candidates by
  `options.contains(color)` so cells pruned of `color` no longer
  inflate the "could still form a new group" count.
* Solver soundness fixes (see "Solver soundness audit (2026-05-13)"
  below): five constraints had the same domain-3 `isImpossible` trap
  that let multi-solution puzzles slip past `isDeductivelyUnique()`.
* `_overrepresentedSlugs` in `worker_io.dart` hard-bans slugs whose
  observed share exceeds 3× the uniform target (k=3), stopping
  propagation-friendly slugs (NC, EY) from flooding every attempt.
* `NTypesTarget` keeps the picker's N chosen slugs as a *soft*
  preference (`preferredSlugs`) instead of hard-restricting
  `allowedSlugs`. Trades exact ntypes guarantee for ~10× generator
  productivity in equilibrium mode.
* CLI `--strategy` accepts a comma-separated list; workers are
  assigned round-robin so a heterogeneous pool (e.g.
  `--strategy phase-gate,phase-1-oneshot,prop-only`) covers each
  strategy's strengths in a single run.

## Solver soundness audit (2026-05-13)

An end-to-end audit uncovered a recurring soundness bug in five
constraints' `apply()` methods on domain 3+. Pattern: the constraint
correctly closes its borders by removing `color` from free
neighbours via `removeOption`, then on the next propagation pass —
finding no remaining neighbour with `color` in options — wrongly
returns `Move(0, this, isImpossible: this)`.

* In domain 2, the auto-set on single-option-remaining
  (`cell.dart:60`) ran the neighbour to non-free after one
  `removeOption`, so the buggy branch was unreachable.
* In domain 3+, `removeOption` leaves the cell free with two
  options, so the constraint loops back here with nothing to do and
  trips the false impossibility. `applyWithForce` then uses that
  spurious `isImpossible` to eliminate valid branches, making
  `isDeductivelyUnique()` return true on puzzles that brute-force
  enumeration shows to have multiple completions.

Five constraints fixed (each returns `null` / `continue` instead of
the spurious `isImpossible`):

| Constraint                     | File                            | Branch                                   |
|--------------------------------|---------------------------------|------------------------------------------|
| `ShapeConstraint`              | `constraints/shape.dart`        | Level 2 (group matches variant, borders closed) |
| `LineCentricConstraint` (RC/CC) | `constraints/base_line_constraint.dart` | `colorCount == count` post-close |
| `GroupCountConstraint`         | `constraints/group_count.dart`  | `currentCount == count` with no merge-cell still colourable |
| `QuantityConstraint`           | `constraints/quantity.dart`     | `myValues.length == count` post-close   |
| `EyesConstraint`               | `constraints/eyes_constraint.dart` | Upper-bound unique candidate already pruned |

Other audited constraints (`NC`, `PA`, `FM`, `SY`, `LT`, `GS`, `DF`)
either don't have the pattern or already fall through correctly.

A separate fix in `Puzzle.restart()` (`puzzle.dart`): the old code
assigned `cell.options = cell.domain` — every cell aliased the same
shared list, so the first post-restart `removeOption` wiped that
colour from every cell at once. Now uses `cell.reset()` which copies
the domain into a fresh per-cell list.

Regression test in `test/unique_solution_test.dart` brute-force-counts
solutions for two reported multi-solution puzzles; both correctly
fail `isDeductivelyUnique()` post-fix. After the audit, brute-force
flagged 47 / 174 of the dev `assets/domain3.txt` puzzles as
previously-undetected multi-solution; we dropped them. Production
assets (`1-easy`, `overfilled-easy`) were unaffected; `6-mad`'s
domain-3 entries were entirely regenerated.

The user's stats file confirmed the player-visible cost of the bug:
on 147 recently-played domain-3 puzzles, the 18 that turned out to
be multi-solution under the post-fix solver took **4.3× longer to
solve** (119.7 s vs 28.0 s on valid puzzles) and incurred **1.9×
more errors** (7.4 vs 4.0).

## Open issues

### Generator throughput on `--domain 3` remains low

On a fresh 4x4 / `--domain 3` benchmark the standalone profiler measured
~4–10 % success per attempt with a 2–3 s median. The wider puzzle the
slower it gets. Root causes:

* **Weaker propagation.** Each cell has 3 options instead of 2, so a
  single `removeOption` deduction no longer collapses a cell; the
  iterative loop needs more constraints to push `currentRatio` below the
  0.25 acceptance threshold, and most candidates don't help enough.
* **Cost of force.** `_forceOneCell` iterates every free cell × every
  option (16 × 3 vs. 16 × 2 on a 4x4), and each per-option propagation
  is itself longer because the per-cell option space is larger.
  Aggregate cost goes up roughly 2–3×.

Mitigations already in place (improve attempt-level throughput and
make rejections cheap rather than expensive):

* `Puzzle.solveExplained` correctly forwards `m.removeOption` into the
  `SolveStep` it emits — previously every `removeOption` deduction
  became a no-op step in the trace, the trace replay never completed,
  and **100 % of 4+-cell 2-colour puzzles** were rejected as
  `!isUnique`. This was the dominant regression introduced by the
  3-colour migration; covered by
  `test/solve_explained_test.dart::solveExplained trace carries
  removeOption moves end-to-end`.
* `PuzzleGenerator.generateOne` pre-filters LT candidates so that, for
  each letter, only pairs sitting in a *single connected same-colour
  component* of `solved` survive. Two LT:A.x.y pairs that *individually*
  satisfy `verify(solved)` can otherwise merge (via the silent
  same-letter aggregation in `Puzzle.addConstraint`) into an LT:A
  whose union spans several components and no longer satisfies
  `solved` — the whole attempt then gets rejected late at
  `!isUnique`. The pre-filter picks the largest component per letter
  (most generative) and drops pairs from any other component. A
  belt-and-braces re-verify inside the iterative loop catches any
  pre-filter corner case before `cloned.solve()` runs.
  `LetterGroup.generateAllParameters` itself cannot do this filter:
  its signature doesn't carry `solvedValues`.
* `generateOne` re-checks `shouldStop` at the top of the *inner*
  candidate sweep so a long sweep (hundreds of `solve()` calls on a
  hard 3-colour grid) honours the deadline within seconds, not at the
  next outer-iteration boundary.
* After accepting a `ColumnCountConstraint` the iterative loop drops
  every other CC candidate targeting the same column from
  `allConstraints`; same for `RowCountConstraint` and rows. At most
  one CC per column / one RC per row keeps the puzzle clean (two
  would be redundant on a 2-colour domain and at best partially
  redundant on 3-colour) and saves the inner loop from re-evaluating
  doomed candidates every cycle.
Possible next steps (not done):

* Raise the `currentRatio > 0.25` threshold for 3-colour puzzles, or
  derive it from `domain.length`.
* Smarter pre-fill: choose colours that maximise constraint
  satisfiability instead of uniform random.

Experiments tried and reverted:

* **Propagation-only signal in the iterative loop.** The idea was to
  swap the per-candidate `cloned.solve()` for `propagateToFixpoint()`:
  the inner loop only needs a propagation-power signal, and skipping
  `_forceOneCell` (the dominant cost on 3-colour grids — one clone +
  full propagation per `(cell, value)` pair, on every stall, twice per
  candidate) would speed each candidate measurement up. The final
  validity check would still use `solve()` with force.
  Initial verdict (12s run, 19 attempts on `size 4-5 × 4-7 | domain 3`):
  1 puzzle, **100% of rejects classified as `ratioTooHigh`**, reverted.
  **Re-bench with rigorous methodology (5min × 4 workers on
  `4-6 × 4-8 | domain 3`) overturned the verdict**: 121 puzzles in
  one run (median per-success 629ms, max complexity 100), throughput
  24.2 puzzles/min versus 14.8-17.1 for the other strategies, and
  per-worker variance σ≈2.8 (3× tighter than the alternatives). The
  diagnosis "force-enablers get rejected" is still structurally
  correct — prop-only does refuse them and the puzzles produced
  lean heavily on propagation-friendly slugs (NC ~4.5/puzzle, EY
  ~2.75/puzzle, vs ~0.3 for force-leaning FM/PA/GS/LT/DF). But the
  PRACTICAL impact is much smaller than the original 12s sample
  suggested: ~14% success rate is fine when each rejection costs
  ~141ms.
  Shipped as the `propOnly` strategy (CLI: `--strategy prop-only`),
  available for benchmarking or as a fast-throughput batch-generation
  mode that emits a restricted constraint mix. Not the default —
  for a balanced corpus the other strategies still earn their place
  by surfacing force-enabler slugs.
* **Hybrid: propagation-only candidates + occasional force on `pu`.**
  Inner sweep used `propagateToFixpoint()` (cheap); rejected
  candidates were parked in a `secondChance` queue; when no candidate
  improved propagation, one `findAMove(tryForce: true)` step was
  applied directly on `pu`, then the parked candidates were retried
  against the advanced state. `pu.restart()` reverted the
  force-placed cells before the final validity check so they wouldn't
  leak into the exported prefill.
  Measured outcome on `size 4-5 × 4-7 | domain 3`: ~2% success rate
  (worse than the ~6% force-aware baseline), still dominated by
  `ratioTooHigh`. Even with `--allow NC,EY,RC,CC` (constraints with
  little force-enabler character), the rejection rate stayed at
  ~97%. Diagnosis: constraints accepted during the loop were
  validated against `pu` states reached via a *specific sequence* of
  force decisions made with a *partial* constraint set. After
  `pu.restart()`, the final `solve()` sees the full final constraint
  set, and its `_forceOneCell` may pick a different cell — the
  loop's trajectory isn't reproducible from the clean state, so the
  accepted constraints don't actually drive `solve()` to completion.
  Reverted. The force-aware signal stays in the loop; only a
  cached-before-ratio optimisation survives.

### Targeted constraint generation to lower `ratioTooHigh` — IMPLEMENTED

Status: steps 1 and 3 of the plan below shipped. Step 2 was folded
into step 3 (the undetermined-cells list is cached alongside the
`ratioBefore` probe and consumed directly by the targeted sort, so it
never needed a separate phase).

What landed in `generator.dart`:

* The `!isUnique` post-loop check is gone. Validity now follows from
  `currentRatio == 0` after the optional fill-from-solution; the
  redundant `solveExplained` + replay was removed along with the
  `GenerationRejectReason.notUnique` enum value.
* The fill step reuses the already-solved `solvedPu` rather than
  running a third `solve()` on a fresh clone.
* The iterative loop now requeues rejected candidates into a
  `secondChance` list and re-pools them after every accept — a
  candidate that didn't propagate against the old state may now
  propagate against the new one (peer-constraint synergy).
* After each accept, the loop runs one probe `solve()` to refresh
  both the cached ratio AND the cached list of undetermined cells.
  `_generateTargetedKeys` then computes the serialise-keys of DF /
  NC / CC / RC candidates that touch those cells, and the sort
  comparator promotes those candidates to the front of
  `allConstraints`. Other slugs fall back to usage-based ordering.

Measured outcome on `size 4-5 × 4-5 | domain 3 | allow all`,
4 workers: 26 successes / 34 attempts ≈ 76% success rate, only 4
`ratioTooHigh` rejects across the run (no `notUnique` category by
construction). Compares with ~5-6% in the pre-change baseline on a
similar configuration.

### Two-tier candidate acceptance + post-loop cleanup

Profiling after the above optimisations showed `loop_candidate` (the
per-candidate `cloned.solve()` test inside the iterative loop) at
**91.9% of total CPU**, averaging 55 ms × 234 calls per attempt. The
full-solve cost is dominated by `_forceOneCell`, which sweeps every
free × domain combination — overkill when the candidate's
contribution is a single propagation step.

A first attempt swapped the single-tier `cloned.solve()` check with
a **two-tier** test (every candidate runs propagation first, then
falls back to full solve if propagation didn't advance). On
domain 3 the cheap path's hit rate measured at **~0.4 %** — almost
no candidate propagates anything new from a 3-colour state. The
5 ms cheap probe became pure overhead on every test, and a logic
bug compounded the regression: cheap-accept set `currentRatio =
cloned.computeRatio()` (the prop-fixpoint ratio, ≥ true full-solve
ratio). The outer loop's `currentRatio == 0` exit condition then
fired only on full-accepts, so cheap-accepts in a sequence made
the loop visibly *increase* `currentRatio` (worker logs showed
e.g. 0.13 → 0.37 → 0.63) and keep running past the natural close
point. Effect: candidate count blew up from ~234 to ~660-1300 per
attempt, success rate dropped from ~76 % to ~25 %. Reverted.

The current shipped design is **phase-gated**:

* **Phase 1 (cheap-only)** — `cloned.propagateToFixpoint()` and
  accept iff prop-fixpoint free-cells of cloned drop below `pu`'s.
  No full-solve fallback in phase 1: candidates that don't propagate
  go to `secondChance`. `currentRatio` is NOT updated by phase-1
  accepts (it would lie); phase 1's own exit signal is
  `cachedPropFreeCells == 0` (prop alone closed the puzzle).
  Phase 1 uses **single-accept-per-outer-iter**: the inner sweep
  breaks at the first accept, the outer loop re-pools `secondChance`
  with the targeted re-sort, and the next sweep starts from the
  reprioritised queue. A "multi-accept" variant (drain the whole
  queue per outer iter, accept everything that fires) was tried and
  reverted: on 3-colour grids cheap accepts are sparse, so each
  outer iter only accepted 1-2 candidates anyway, and draining the
  full queue cost ~10× more cheap probes than the early-stop sweep
  (12 successes vs 27 in matched benches). Single-accept's re-sort
  between accepts surfaces the highest-targeted candidate next,
  pushing the average accept toward the front of each sweep.
* **Phase 2 (strict full-solve)** — triggered exactly when phase 1
  plateaus (inner sweep exhausts without acceptance) and
  `secondChance` is non-empty. Phase 2 runs the pre-two-tier
  single-tier criterion: `cloned.solve()` and accept iff
  `fullRatio < cachedRatioBefore`. No cheap probe in phase 2,
  same per-call cost as the original baseline (~55 ms). Picks up
  the force-enablers phase 1 dropped.

Easy puzzles close fast via phase 1 propagation cascade (the
revert-investigation logs showed phase-1-only successes in 569 ms
and 671 ms with only 4-10 candidates tested). Hard puzzles
transition to phase 2, which behaves like the pre-two-tier baseline
and accepts force-enablers. Crucially, the cheap probe is paid only
on phase 1 candidates — on a 3-colour grid phase 1 plateaus quickly,
so the cheap-probe overhead stays bounded.

`removeUselessRules` (`puzzle.dart:859`) still runs post-loop on
every successful attempt. Phase 1's lax cheap accept may pick
constraints later subsumed by phase 2 or by fill-from-solution
hints; the cleanup walks the constraint list last-to-first and
drops any whose removal preserves deductive uniqueness.

Three stage timers in the dashboard:
* `loop_candidate_prop` — phase-1 candidate tests.
* `loop_candidate_full` — phase-2 candidate tests.
* `cleanup` — `removeUselessRules`, one call per successful attempt.

The dashboard also prints a derived "Two-tier breakdown" line:
`prop_calls candidates tested → (prop_calls - full_calls) phase-1
accepts, full_calls fell to phase 2`. Reading off the phase 1
hit rate directly is the quickest way to judge whether phase 1 is
paying off on a given configuration.

Original problem (kept for context):

The iterative loop samples constraint candidates at random
and accepts whatever happens to lower the post-`solve()` ratio. When
3 or 4 cells remain undetermined, this random sampling rarely lands a
candidate that targets exactly those cells — and we exhaust
`allConstraints` without closing the puzzle → `ratioTooHigh`.

User's proposal: at any point in the loop, we already know via
`solvedPu.solve()` which cells are still undetermined. We can use
that information to drive constraint generation *toward* those cells
rather than at random.

Also: the post-loop `!isUnique` check is redundant with the
`currentRatio == 0` invariant (after fill-from-solution). Both use
the same `findAMove` engine. The `notUnique` rejects we still see
come from small asymmetries between `solve()` and `solveExplained()`
halt conditions (excluded-option `setValue` bail at puzzle.dart:797,
no-op `removeOption` bail at puzzle.dart:802), not from a genuine
non-uniqueness — by construction a puzzle whose `solve()` reaches
ratio 0 from its readonly cells is unique under the project
convention.

**Which constraints are easy to target?**

| Slug | Targetable per-cell? | How |
|------|---------------------|-----|
| `DF`   | Yes        | Link X to a readonly singleton holding `solved[X]` |
| `NC`   | Yes        | `NC:X.C.count` where count = neighbours of `solved[X]` with colour C |
| `CC`/`RC` | Per axis | Compute each colour's count on X's column/row in `solved` |
| `EY`   | Partial    | Cell-centric but requires anchor + group analysis |
| `GS, LT, SH, FM, PA, SY, QA, GC` | Hard | Non-local combinatorics; current random sampling stays |

**Three-step plan, each step shippable on its own:**

1. **Drop the `!isUnique` check.** Replace with `currentRatio == 0`
   after the optional fill-from-solution. Align `solveExplained`'s
   halt conditions with `solve()`'s, or just remove the redundant
   re-solve. Cuts ~33% of post-loop work; removes one rejection
   category. Low risk.
2. **Maintain a `determinedMask`** during the loop (cells where
   `solvedPu.solve()` aboutit). Pure instrumentation — exposes the
   "where are the gaps" signal that step 3 needs.
3. **`generateTargetedParameters(slug, cellIdx, solved)`** — a
   variant of `generateAllParameters` returning parameters whose
   propagation effect lands on `cellIdx`. Wire it into the loop's
   plateau path: when `allConstraints` is exhausted and there's
   still an undetermined cell, ask the targeted generator for
   constraints that could close it. Implement DF and NC first
   (smallest combinatorial cost, highest hit rate), then CC/RC.

Prioritise step 1 (low-risk perf + correctness cleanup), then
step 3 (the real lever on `ratioTooHigh`).

### Equilibrium-mode bench (2026-05-13, post-audit)

Two methodology issues invalidated the earlier benches: the picker
runs a much easier *warmup target* until the corpus reaches ≥ 100
puzzles, and the solver had a soundness bug (see "Solver soundness
audit" above) that let multi-solution puzzles slip past the validity
gate, inflating apparent success rates. Both were addressed before
the numbers below:

* Preseed the output file with an existing corpus to enter
  equilibrium mode immediately (`PRESEED` env var in
  `bench_strategies.sh`).
* All five `apply()` soundness bugs fixed.

Bench (10 min × 4 workers per strategy, 4-6 × 4-8 grids, domain 3,
watchdog 15 s, preseed = 117-puzzle bootstrap):

| Strategy            | Puzzles | Rejects                                  | Success rate |
|---------------------|---------|------------------------------------------|--------------|
| phase-gate          | 9       | ratioTooHigh=30, attemptStalled=51       | 10 %         |
| prop-only           | 26      | ratioTooHigh=77, attemptStalled=26       | 20 %         |
| **multi-strat pool** | **19** | ratioTooHigh=51, attemptStalled=41       | 17 %         |

The multi-strategy pool runs one strategy per worker via round-robin
(`--strategy phase-gate,phase-1-oneshot,prop-only`); its worker breakdown
shows phase-gate and prop-only each contributing ~8 successes,
phase-1-oneshot ~1-2 — confirming the strategies cover complementary
slug regions.

Slug coverage is now uniform across 11 of 13 slugs. NC and EY remain
hard-banned by the equilibrium picker (they were over-represented at
32 % / 31 % in the bootstrap); the other 11 slugs all show up in
every strategy's output. **prop-only now produces FM** — the 22 FM
occurrences in this run invalidate the previous claim that
prop-only's acceptance signal could never accept a force-needing
slug. The structural argument still holds for *purely* force-only
candidates, but in practice FM constraints often piggyback on cells
where propagation alone advances after they're added.

#### Before / after summary

The whole generator overhaul, end-to-end, on 3-colour grids:

| Generator state                         | Date       | Config         | Mode        | Rate          |
|-----------------------------------------|------------|----------------|-------------|---------------|
| Pre-3-colour (2-colour baseline)        | early 2026 | 2-colour       | -           | ~75-80 %      |
| Post-3-colour migration                 | mid 2026   | 4-5×4-5        | warmup      | < 1 %         |
| `solveExplained` removeOption fix       | mid 2026   | 4-5×4-7        | warmup      | ~5-6 %        |
| Targeted-sort + `removeUselessRules`    | 2026-05-12 | 4-5×4-5        | warmup      | ~76 %         |
| Phase-gate + watchdog (4 strategies)    | 2026-05-13 | 4-6×4-8        | warmup      | 14-27 %       |
| Phase-gate + watchdog + preseed (pre-audit) | 2026-05-13 | 4-6×4-8        | equilibrium | 27-57 % (inflated by solver bug) |
| Hard-ban k=3 + ntypes-soft + solver audit | 2026-05-13 | 4-6×4-8        | **equilibrium** | **10-20 %**   |

The pre-audit equilibrium row reported 27-57 % only because false
`isImpossible` paths let the solver "succeed" on multi-solution
puzzles. The post-audit row is what the production generator
actually delivers.

#### Production decision

* **Multi-strategy worker pool** is the recommended default for
  batch CLI generation:
  `--strategy phase-gate,phase-1-oneshot,prop-only` (round-robin
  assignment across the worker pool). The pool combines prop-only's
  throughput on propagation-friendly targets with phase-gate's
  force-enabler coverage in a single run; no need to pick a strategy
  per workload.
* **Drop `singleTier`** as a live strategy. Pre-audit benches
  already showed it watchdog-limited (93 % `attemptStalled`); the
  enum value is retained for benchmarking only.
* **`GeneratorConfig.strategy`** default stays `phaseGate` for
  callers that don't override (in-app generator, tests). The
  multi-strategy split is a CLI / worker-pool concern, not a default
  change.

#### Caveats and follow-ups

* The watchdog threshold (15 s) penalises strategies with expensive
  per-candidate tests. Re-bench with 30 s or 60 s to confirm
  `singleTier` is structurally weak rather than watchdog-unlucky.
* Productivity in equilibrium mode drops sharply once the corpus is
  balanced — the picker keeps pushing into harder ntypes / less
  represented slug combinations. The 10-20 % rate is for a freshly
  preseeded corpus; long-running benches plateau lower as the easy
  targets exhaust.
* All measurements are on a single hardware setup; absolute timings
  will vary. The relative rankings should be robust.

### `FMFMComplicity` and `PAFMComplicity` inert on 3-colour

* `FMFMComplicity` synthesises a "wildcard FM" from two FMs that
  differ in exactly one position whose two values cover the domain.
  On 3-colour, two FMs alone can never cover the three-value domain,
  so no synthesis happens. Could be generalised to fuse *three* FMs
  (O(n³) candidate triples instead of O(n²) pairs).
* `PAFMComplicity` is explicitly gated to `domain == {black, white}`.
  Generalising means enumerating C(n; n/3, n/3, n/3) balanced
  colourings instead of C(n; n/2) — fine for small sides (n=6 → 90)
  but blows up fast (n=9 → 1680, n=12 → 34650). Needs a tighter cap
  or a smarter generator.

## TODO (remaining)

* **Generator: equilibrium-aware domain.** The CLI generator picks
  between 2- and 3-colour domains via `--domain`, but the equilibrium
  picker has no domain axis: it can't preferentially generate puzzles
  to balance the corpus between domain sizes. Needs a new
  `kTargetDomainProfile` analogous to `kTargetNTypesProfile`.
* **UI: opt-in/opt-out switch for domain3 puzzles** in the player
  settings — once the corpus has both, the player needs to be able
  to filter them.
* **Re-tune complexity scoring** for 3-colour puzzles. The scoring
  was tuned for 2-colour traces; 3-colour traces tend to produce
  more `removeOption` steps that each carry a tier-0..5 complexity.
  The bands (`beginner` / `player` / … / `mad`) may need re-anchoring
  against a 3-colour corpus.

## Sketch of the original phased plan

The work was originally laid out in eight phases; all are complete.
Kept here for archeology, with one-line statuses.

1. **Constants instead of integers** for cell values — done.
2. **Tap cycles through the whole domain** — done, domain-aware.
3. **`removeOption` in solving steps** — done; every constraint's
   `verify` / `apply` understands the option-pruning model.
4. **Port the easy constraints** (NC, EY, QA, GC, CC, RC, SH) — done.
5. **`Cell.removeOption` auto-collapses to `setValue`** when only one
   option remains — done.
6. **Sample-generate puzzles** with the new domain — done; output
   committed in `assets/domain3.txt`.
7. **Port the remaining constraints** (FM, PA, GS, LT, DF, SY) — done.
8. **Fix regressions and the generator hang** — done. Five propagation
   loops now guard against both excluded-option `setValue` and no-op
   `removeOption`. `Constraint.apply`'s dead default body replaced by
   `throw UnimplementedError` to match `Constraint.rotated`. Eleven
   constraint sites + seven complicity sites guarded against
   `setValue` on a pruned option.

## SymmetryConstraint port notes

The SY port is structurally different from the other constraints
because several 2-colour deductions **stop being valid** on 3+
colours: they relied on "non-myValue" = "the unique other colour",
which collapses to a single value on 2-colours but not on 3+. The
port deliberately weakens those rules to preserve correctness,
accepting a small loss of in-game deduction power on 2-colour
puzzles (cells are still deduced, just later in the cascade, often
after the anchor's colour is fixed by another constraint).

Per-step changes:

* **Step 1 (group symmetry)** — emit `value: myValue` on a free
  mirror (with the `options.contains` guard); emit `isImpossible`
  when the mirror is out of bounds **or** already coloured a
  different value (the "different value" check is new; previously
  the resulting contradiction was only surfaced by `verify`).

* **Step 2 (cells adjacent to G)** — split into two cases.
  * **Free neighbour `n`**: if `n` becomes `myValue` it joins `G`,
    forcing `sym(n) = myValue`. If the mirror is out of bounds or
    coloured something other than `myValue` (or `myValue` itself —
    that's fine), the neighbour cannot take `myValue` →
    `removeOption: myValue` on `n`. *This also fixes a latent
    2-colour bug where a sym coloured `myValue` would force the
    neighbour to the opposite when in fact the configuration was
    consistent.*
  * **Coloured neighbour `n` (colour `nv ≠ myValue`)**: `n ∉ G`, so
    by symmetry `sym(n) ∉ G`. Since `sym(n)` is adjacent to
    `sym(member) ∈ G`, `sym(n)` cannot be `myValue` — emit
    `removeOption: myValue` on `sym(n)` (if free) or `isImpossible`
    (if `sym(n)` is already `myValue`). **We do NOT force `sym(n) =
    nv`**, even though the 2-colour code did. Example: `1 2 3` with
    vertical symmetry through the centre cell coloured 2 is a valid
    SY state — `sym(cell 0) = cell 2` with different colours, and
    the constraint only requires `sym(n) ∉ G`, not `sym(n) = nv`.

* **Step 0 (anchor empty)** — same weakening, applied to the anchor.
  With anchor free and a coloured neighbour `n` of value `nv`, we
  used to conclude `sym(n) = nv`. On 3+ colours we instead deduce
  only what the anchor cannot become:
  * `sym(n)` null → anchor ≠ nv.
  * `sym(n)` free, nv not in its options → anchor ≠ nv.
  * `sym(n)` coloured `c' ≠ nv` → anchor ≠ nv AND anchor ≠ c'.
  * `sym(n)` coloured nv → no constraint on anchor.
  * `sym(n)` free with nv in its options → no immediate deduction.

* **Step 3 (look-ahead through myValue chains)** — emits
  `removeOption: myValue` on the free neighbour when extending
  through myValue cells would create a merged group with an
  impossible mirror. Logic unchanged from the 2-colour version
  apart from the move shape.

## Complicity audit (3-colour readiness)

All eight complicities have been ported. The table below records the
original pattern (the *reason* each complicity needed work) so future
contributors can understand the shape of the fix. Statuses are now
all "ported" — see the source for the current code.

| Complicity                       | Original 2-colour assumption          | Status |
|----------------------------------|---------------------------------------|--------|
| `LTGSComplicity`                 | none — colour read off a coloured cell on the path | ported, options-guard added |
| `SYFMComplicity._solveEmpty…`    | none — domain-agnostic by construction | ported, options-guard added |
| `GSGSComplicity`                 | `value: opposite(vi)` to deny same group | ported, now `removeOption: vi` |
| `LTFMComplicity`                 | `value: forcedColor` after FM blocks adjacency | ported, now iterates LT cells looking for one with the option |
| `SHGSComplicity`                 | `value: remaining.first` after SH-vs-GS size mismatch | ported, emits `removeOption: excluded[i]` one per call |
| `SYFMComplicity._solveColoured…` | `value: opposite(c)` when FM blocks the SY extension | ported, now `removeOption: c` with frontier filter |
| `GSAllComplicity` `allInSealed`  | `value: opposite(c)` for cells outside every sealing | ported, now `removeOption: c` |
| `GSAllComplicity` `allInGroup`   | `value: c` for cells inside every sealing | ported, options-guard added |
| `FMFMComplicity`                 | synthesises a wildcard FM from two FMs whose differing values cover the domain | guarded by `values.length != domain.length`; inert on 3-colour (would need 3-FM synthesis — see Open issues) |
| `PAFMComplicity`                 | parity-as-colour-counter only meaningful on `{1, 2}` | inert on 3-colour (`_domainIsOneTwo` guard — see Open issues) |

The **"no-op should not be impossible"** convention is consistent
across the ported complicities (matches `parity.dart:182`): when a
complicity wants to emit `removeOption: X` on a cell whose options
have already excluded `X`, it skips to the next candidate rather
than raising `isImpossible`. The complicity loop sees this as "no
deduction available here" and moves on to the next instance.
