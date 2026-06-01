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
  domain alongside size range, required rules and bans. It governs the
  regular (grid-first) and SH flows only: the **path-based and sy-based
  pre-fills are 2-colour by design and ignore the domain flag** (their
  colourings are intrinsically binary — see `path_based.md` /
  `prefill_sy.md`). Because the equilibrium can route any target to
  those scenarios, a `--domain 3` run still emits some 2-colour lines;
  auto-shrink relabels them `v2_12_...`, so the output stays correct.
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

## Solver soundness audit, round 2

The 2026-05-13 audit fixed the **too-strict** failure mode (spurious
`isImpossible` once borders close). Round 2 swept the **dual, too-lenient**
mode: solver code that counts a still-`free` cell as able to take a colour
already pruned from its `options`. Invisible on domain 2 (a prune collapses
the cell at once); on domain 3+ the cell stays free with two options and the
stale assumption survives.

Fixes (all preserve 2-colour behaviour exactly — the option filter is a no-op
there):

* **`GroupCountConstraint`** — the "can a new `color` group still form?"
  predicate is now the single option-aware helper
  `getFreeCellsThatCanStartNewColorGroup` (free, no `color` neighbour, `color`
  still in options), replacing the earlier split where two sites wrapped
  `getFreeCellsWithoutNeighborColor` with `.where(options.contains)` and three
  (`apply == count`, `isCompleteFor`, `_exceedingTargetIsImpossible`) did not.
  The unfiltered sites had counted a pruned free cell as a new-group seed →
  missed the `removeOption` force, never grey out, and missed over-count
  impossibilities. The set is still monotone decreasing, so the monotonicity
  arguments hold.
* **`EyesConstraint._scan`** — a free cell that has `color` pruned now blocks
  the line of sight exactly like a committed opposite cell (it is destined to
  be non-`color`). Previously it was counted as a fillable empty, inflating
  `totalMax` so `verify` accepted states where the target was actually
  unreachable (unsound).
* **`ShapeConstraint`** — `isOpen` (in both `verify` and `apply`) is now
  option-aware: a group whose only free neighbours have `color` pruned is
  *closed*, not "still growing", so an undersized frozen group is correctly
  rejected (Level 1 must-match). Previously such a group passed `verify`
  (unsound).
* **`NeighborCountConstraint.isCompleteFor`** — counts only free neighbours
  that can still become `color`; greys out once the rest are pruned (matches
  the GC invariant fix). The over-target / reachability `verify` arithmetic
  was already option-aware.
* **`SHGSComplicity`** — see "Complicity audit": impossibility is judged on
  the cell's current options, not the full domain.

Audited and already sound (no change): `QuantityConstraint`,
`NeighborCountConstraint`, `ParityConstraint`, `MajorityConstraint` and the
line-centric base all count free cells option-aware in `verify`; GS growth and
LT virtual groups go through the option-aware `groups.dart` helpers
(`toVirtualGroups`, `reachableComponentSize`, `canMergeGroups`, …); CH
`_passable` was fixed in round 1. The conservative `isCompleteFor` predicates
(QA, MJ, PA, DF, base-line) only ever grey out *late*, never early — sound.

Apply-side incompleteness (sound but not exhaustive): the "full-need" branches
of QA / NC / MJ / base-line use the unfiltered free-cell count, so on domain 3
they can miss a force that the option-aware count would catch. This never
forces a wrong value (each force is guarded by `options.contains`, else
`Impossible`) and `verify` is option-aware, so no invalid state is accepted —
only some valid deductions are delayed. Left as-is; revisit if generator
throughput on 3-colour needs it.

As with round 1, the `verify` tightenings change 3-colour deductions, so the
corpus needs a `--check` re-validation (lines that were only "unique" under
the lenient solver will be flagged and should be dropped).

## Open issues

### Player play-state: options not serialised on reload (frozen)

`lineWithPlayState` (`puzzle.dart`) and `lineExport` (`puzzle.dart`) only
serialise `cellValues` (each cell's `value`); `Cell.options` are never
persisted. On reload the `Puzzle()` constructor resets every free cell's
options to `domain.toList()`.

On a 3-colour puzzle a player who has *manually* pruned an option from a free
cell (via the remove-option mode / `cycleRemoveOption`) loses that work if the
game is interrupted and resumed. This is a legitimate 3-colour use case; on
2-colour it is inert (a pruned option collapses immediately to a `setValue`,
which *is* serialised).

Frozen by decision — not implemented. If revisited, options:
* a `o:<options>` field in the v2 format, per-cell bitmask over
  `{black, white, purple}` (one hex digit per cell); or
* store only the diff from the full domain to save space on lightly-edited
  puzzles.

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

The same `_forceOneCell` cost is paid by the **hint UI** when the player
asks for help on a hard 3-colour puzzle (the generator optimised around it
via phase-gate, but the in-game hint path has no such mitigation). Not
observed as a playable problem; monitor if complaints arise. Possible
optimisations: an incremental-propagation cache, or parallelising the
`(cell, option)` probes across an isolate.

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
* **Option dots on small screens.** `_OptionDots` (`widgets/cell.dart`)
  draws one ~10 %-of-cell dot per remaining option, with a thin grey
  outline — only on `domain > 2` puzzles. Not yet tested on a real
  phone < 5". Verify legibility before the public 3-colour release;
  if cramped, bump the dot to 12–15 % or add a "highlight pruned
  options" toggle for low-density screens.

## Adding a new colour

The engine is domain-prefix based: a concrete puzzle's domain is always a
prefix of `fullDomain` (`model/cell.dart`). Adding a fourth colour (say
`orange`) is mostly mechanical, but several spots are *not* type-enforced and
will silently misbehave if missed. Checklist:

1. **`enum CellValue`** (`model/cell.dart:3`) — append the new value
   **after** `purple` (order is canonical; everything keys off it).
2. **`fullDomain`** (`model/cell.dart:8`) — append the new value. Leave
   `defaultDomain` (the 2-colour prefix) untouched. The
   `defaultDomain == fullDomain.sublist(0, 2)` relationship is asserted in
   `test/domain_constants_test.dart`, not by the type system, so re-run that
   test.
3. **Serialisation** (`model/cell.dart`) — extend the two switch helpers in
   lockstep: `cellRepresentationToValue` (`"4" → orange`) and
   `cellValueToString` (`orange → "4"`). The numeric tags are what land in the
   `v2_<domain>_…` line, so the domain field of a 4-colour puzzle becomes e.g.
   `1234`.
4. **Rendering** (`widgets/cell.dart`) — add the value to both colour maps:
   `bgColors` (cell background) and `fgColors` (digit / glyph foreground).
   A missing entry falls back to `Colors.black` and is easy to miss visually.
   `_OptionDots` already iterates `options`, so option dots pick the new
   colour up automatically once `bgColors` has it.
5. **Per-constraint widgets** that carry their own colour map — e.g.
   `widgets/column_count.dart` / `row_count.dart` keep a private `_textColors`
   map. Add the new value there too.
6. **Constraints that hard-assume a colour count.** Most constraints are
   domain-generic via the option model, but a few are gated and would stay
   inert (sound but weaker) on a wider domain — audit them before relying on
   the new colour:
   * `FMFMComplicity` — only synthesises a wildcard FM when two FMs' differing
     values *cover the whole domain*; needs 3-of-N (or more) synthesis beyond
     2 colours (see "Open issues").
   * `PAFMComplicity` — gated to `{black, white}` via `_domainIsOneTwo`; its
     balanced-colouring enumeration blows up combinatorially on larger domains.
   * `PA` (`parity.dart`) — already domain-generic (`% domain.length`), but the
     candidate count and the per-colour target grow with the domain; re-check
     the generator cost (see "PA semantics on 3 colours").
7. **Generator domain flag** — `--domain N` in `bin/generate.dart` and
   `GeneratorConfig.domain`; extend the accepted range. The path-based and
   sy-based pre-fills are intrinsically binary and ignore the flag (see
   `path_based.md` / `prefill_sy.md`).
8. **Re-validate** the full corpus with `--check` after generating any
   N-colour lines — the soundness audits (see "Solver soundness audit" and
   `docs/dev/todo.md` § round 2) are domain-sensitive and a wider domain can
   resurface "too-lenient on pruned options" bugs.

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

## PA semantics on 3 colours

The `PA` slug is historically named "parity", but on the option model it is a
**balanced colour partition**: the targeted side of the anchor must hold the
same count of every domain colour, `targetCount = side.length / domain.length`
per colour (`parity.dart` `verify` / `apply`).

* On the 2-colour domain this collapses to "as many black as white" — an
  even side split in half — which is what the "parity" name refers to.
* On 3 colours it generalises to "as many black as white as purple". This is
  no longer a parity statement, so the name is a vestige; the slug is kept
  unchanged so previously stored `PA:` lines keep parsing.

`generateAllParameters` reflects this by only emitting a side whose length is
divisible by `domain.length` (was `% 2`, now `% domain.length`), guaranteeing
an integer per-colour target. The class doc on `ParityConstraint` points back
here.

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

## Release plan — merge with `master` (2026-06-01)

This section captures the plan to bring the `third-color` branch up to
date with `master` and prepare a release.

### Branch topology

Common ancestor of all three branches: **`9c7c476`**.

| Branch | Tip | Base | Nature |
|--------|-----|------|--------|
| `origin/third-color` | `87aab6b` (2026-05-13) | `9c7c476` | **Old** third-color work — obsolete |
| `third-color` (local) | `1530b66` (2026-05-29) | `b5c60a9` (master of 2026-05-27) | **Authoritative**: third-color redone on a recent master base |
| `master` | `3945bbd` (2026-05-31) | — | `b5c60a9` + 13 commits |

`origin/third-color` is **superseded** by the local branch (same ~7.3k-insertion
changeset replayed on a newer master base — nothing unique to salvage; it will be
overwritten on push). The real task is to **merge `master` (3945bbd) into the
local `third-color`**, i.e. absorb the 13 commits `b5c60a9..master`. Since
`b5c60a9` is an ancestor of master, the base is linear; conflicts come only from
files touched by **both** `b5c60a9..master` and `b5c60a9..HEAD`.

### What master added after `b5c60a9`

1. **Transition constraints (RT/CT)** — `a0872e9`, fixes `74fb392`/`540b3ec`.
   Count adjacent color changes on a line/column. Files: `transition_row.dart`,
   `transition_column.dart`, `transition_utils.dart`, `widgets/transition.dart`,
   `create_page/dialogs/transition_dialog.dart`. **2-colour only → ported to the
   removeOption model in Phase 2.**
2. **Families** — `dae45db`. Pure slug taxonomy (line-centric / local / path /
   group-topology / global) for corpus balancing. **Zero coupling to the colour
   model** → merges as-is. Touches `families.dart` (new), `equilibrium.dart`
   (composition axis, Gaussian warmup), `worker_io.dart` (`_resolveTarget`),
   `bin/generate.dart`, `bin/query_corpus.dart`, docs, tests.
3. **MJ (Majority) and CH (Chain)** — already in base `b5c60a9` and touched by the
   third-color port. Verified:
   * **MJ: 3-colour-safe.** `apply` only forces `value: targetColor` (positive,
     domain-agnostic) → no removeOption needed. Soundness from
     `currentCount + freeCount < target` (`majority.dart:111`/`:139`). The
     `opposite`/`oppositeCount` helper (`:99-102`, `:128-134`) is a binary vestige
     (counts only one non-target colour): sound-but-incomplete on 3 colours,
     duplicated by the freeCount check. Optional cleanup, not a bug.
   * **CH: incorrectly ported — 3-colour bug.** The port was a mechanical type
     migration; `_isBlocked` keeps
     `oppositeColor = puzzle.domain.whereNot((v) => v == color).first`
     (`chain.dart:102`, `:141`) and tests `!= oppositeColor` everywhere. On a real
     3-colour domain, third-colour cells are treated as traversable when they
     actually block the path → `verify` too lenient (**unsound**) and forced-bridge
     deductions possibly wrong. Fix scheduled for Phase 2.
4. Misc: collection-management tools, MacOS build, msix, marketing/, screenshots,
   reset-editor button, sharing baseUrl. Independent.

### Conflict surface (files touched by both sides)

Textual conflicts to resolve: `assets/{1-easy,2-player,4-strong,5-expert,6-mad,
overfilled,overfilled-easy}.txt` (master regenerated the 2-colour corpus +
scenarios + RT/CT; third-color added domain-3 puzzles), `assets/help.{en,es,fr}.md`,
`bin/generate.dart` (master composition dashboard vs third-color `--domain`/
`--strategy`/watchdog), `worker_io.dart` (master `CompositionTarget` case +
`_orientSize` vs third-color hard-ban / strategy / domain in `_resolveTarget` —
additive merge), `model/database.dart` (master `canonicalSize()` ×3 vs third-color
domain filters + onboarding lifecycle — mostly orthogonal), `registry.dart`
(RT/CT entries vs `List<CellValue>` signature), `constraints/{column_count,
row_count}.dart` (+9 lines transition support vs removeOption port), `main.dart`
(small master change vs 134-line third-color UI), `l10n/app_{en,es,fr}.arb` +
generated (union the keys, then `flutter gen-l10n`), `widgets/{puzzle.dart,
create_page/create_page.dart}`.

Independent (clean from master): `equilibrium.dart` (third-color untouched),
`onboarding.dart` (master adds `strictSlugs`/`strictCompletionTargets`;
third-color's lifecycle lives in `database.dart`), `families.dart`,
`transition_*`, all new `bin/`, `marketing/`.

### Two-phase execution

**Phase 1 — pure merge (no constraint-algorithm changes).** Goal: a merged branch
that compiles and passes the *existing* test suite, where 3-colour behaves exactly
as before the merge and 2-colour gains RT/CT + Families. Forbidden in Phase 1:
touching `apply`/`verify` of RT, CT, MJ, CH. Allowed: *mechanical* type alignment
to compile (`List<int>`→`List<CellValue>` signatures, `Move` shape,
`cellRepresentationToValue`).

1. Work branch from `third-color` (e.g. `third-color-merge`).
2. `git merge master`; resolve conflicts per the table above.
3. Bring master's new files in as-is.
4. Mechanical signature alignment only for RT/CT (and any master file) — master's
   2-colour deduction logic stays (endpoint-parity / full-need gated `domain==2`,
   saturated domain-agnostic → sound but weaker on 3-colour). MJ and CH unchanged.
   *Note: CH stays unsound on 3-colour after Phase 1 — pre-existing third-color
   condition, not worsened by the merge, fixed in Phase 2.*
5. Assets: resolve in favour of master, then re-append only the domain-3 lines from
   third-color (filter = existing `_puzzleLineHasThirdColor()` in `database.dart`;
   extraction/append script run by the user). Re-validate the merged corpus
   (`dart run bin/generate.dart --check`, run by the user).
6. `flutter gen-l10n`; `dart format .`.
7. Verify: `flutter analyze` clean; success criterion for `flutter test` is
   **no new failures vs pre-merge `third-color`** (the suite was not green to
   begin with — see "Phase 1 status"). Stop and validate before Phase 2.

#### Phase 1 status — DONE

Done on branch `merge-master-third-color` (merge commit; base was
`third-color` + the doc commit). Summary of what actually happened:

Conflicts resolved (11 files):

* `assets/*.txt` (7) — taken from master (`git checkout --theirs`). Domain-3
  re-append is the separate user-run step (not done here).
* `registry.dart`, `create_page.dart` — import-block conflicts only: kept both
  transition imports and `model/cell.dart`. The bodies had already auto-merged
  with the RT/CT entries and the `List<CellValue>` signature.
* `main.dart` — kept master's `RT`/`CT` slug-label cases, dropped the duplicate
  `RC` case master re-introduced (HEAD already had `RC`).
* `worker_io.dart` `_resolveTarget` — additive merge: master's
  SH-via-profile-axis early-return and `CompositionTarget` case combined with
  third-color's over-represented hard-ban; both `_overrepresentedSlugs` and
  `_orientSize` helpers kept. `SizeTarget` keeps the hard-ban; the `SlugTarget`
  case applies the SH early-return first, then the hard-ban.

Mechanical type alignment only (no deduction-logic change), to compile under
the `CellValue` model:

* `transition_utils.dart` — `!= 0`/`== 0` → `!= CellValue.free`/`==
  CellValue.free`, `int? forced` → `CellValue? forced`, old positional
  `Move(idx, value, c, …)` → `Move(idx, c, value: …)` / `Move(idx, c,
  isImpossible: c)`. Endpoint-parity and full-need stay gated `domain == 2`.
* `transition_row.dart` / `transition_column.dart` — `generateAllParameters`
  signature → `List<CellValue> domain`.
* `transition_test.dart` — int colour literals → `CellValue` (`1`→`black`,
  `2`→`white`), `[1, 2]` domain → `defaultDomain`.

Verification: `flutter analyze` clean. `flutter gen-l10n` produced no diff
(the auto-merged generated files were already consistent). `dart format`
applied.

**Problem found — the suite was NOT green to begin with.** The Phase 1 plan
assumed `flutter test` was green on `third-color`; it was not. 11 tests fail,
and a baseline run in a throwaway worktree of pre-merge `third-color` shows the
**same 11 failures** — so the merge introduces **zero new regressions** (the
correct success criterion). They are pre-existing WIP failures on `third-color`
and map onto the Phase 2 work:

* `complicities_test.dart` (4) — `GSQAComplicity` (×3), `PABalancedSideComplicity`
  (×1): `int`-vs-`CellValue` expectations / 3-colour porting.
* `third_color_suggestion_test.dart` (4) — `notePuzzleCompleted` lifecycle
  (`hasPlayedThirdColor`, `postOnboardingCompletions`, `onboardingCompletedAt`).
* `shape_utils_test.dart` (1) — `ShapeConstraint.apply` full chain.
* `hint_flow_test.dart` (2) — addConstraint-mode tap 1.

One extra generator test (`auto_shrink_domain_test.dart::every generated puzzle
has every domain colour justified`) is **flaky** (random generation): it passed
on the baseline and failed once on the merged tree, so it is not counted as a
regression.

These 11 are intentionally left untouched in Phase 1 (pure merge). Whether to
fix them as part of Phase 2 or separately is an open question for the user.

#### Phase 2 status — DONE

3-colour adaptation of the four constraints, shipped one at a time with
dedicated domain-3 regressions. The final shape differs from the initial sketch
on two points (noted below), so this records what the code actually does.

* **MJ — `majority.dart`.** Cosmetic only. The binary vestige
  `opposite = domain.firstWhere(...)` + `oppositeCount` (which counted a single
  non-target colour) is replaced by a count of **every coloured cell ≠
  `targetColor`**, in both `verify` and `apply`. No behaviour change — the
  `currentCount + freeCount < target` bound already carried soundness; the old
  count was a sound-but-incomplete subset on 3 colours.

* **CH — `chain.dart`.** Core 3-colour fix. `_isBlocked` no longer collapses
  "non-color" to one `oppositeColor`; a new `_passable(puzzle, idx)` predicate
  (free **or** already `color`) drives both the border seed and the BFS, so any
  committed cell of a different colour — including a third colour — blocks the
  path. Border-saturation counts blocking cells (`!_passable`) rather than a
  single opposite; forced-bridge commits a representative non-`color` colour to
  probe. CH still only forces `value: color` (positive). The now-unused
  `collection` import was dropped.

* **RT/CT — `transition_utils.dart`.** The 2-colour blocks (`domain == 2`) are
  left intact; 3-colour behaviour is added alongside.
  * *Saturated* (`t == count`): **unchanged** — forcing a free cell to *equal*
    its coloured neighbour (`value: nv`) is positive and domain-agnostic
    (one neighbour → force; two equal → force; two different → `isImpossible`;
    no coloured neighbour → no deduction). *(Sketch error corrected: this was
    described as needing a removeOption port; it does not.)*
  * *Full-need* (`t + fp == count`), `domain ≥ 3`: a free cell adjacent to a
    coloured `nv` must differ → `removeOption: nv` (with `options.contains`
    guard); `isImpossible` if no option survives all coloured neighbours.
  * *Endpoint `count == 1`*, `domain ≥ 3`: exactly two runs ⇒ the endpoints
    differ → `removeOption` the known end's colour on the free end, or
    `isImpossible` if both ends are coloured and equal; mirrored in `verify`.
    *(Sketch error corrected: endpoint reasoning was thought to have no 3-colour
    form; `count == 1` (and `count == 0`, via saturated) do generalise —
    `count ≥ 2` does not.)*
  * *Lower-bound probing fallback* (tier 4, `domain ≥ 3`, only when nothing
    above fired): for each free cell × option, `_lineFeasibleWith` re-checks the
    transition bounds + the `count == 1` endpoint rule under that hypothetical
    assignment; an infeasible colour is pruned with `removeOption`. Sound oracle
    (infeasible ⇒ impossible). Catches the "wedged" case, e.g. `[1, ., 2]`
    count 1 → `removeOption` the third colour.

Out of this commit (handled separately — see "Phase 2b" below): the complicities
`GSQAComplicity` / `PABalancedSideComplicity`. The other pre-existing WIP failures
(`hint_flow`, `shape_utils`, `third_color_suggestion`) remain deferred.

Verification: `flutter analyze` clean; new domain-3 regressions added to
`test/chain_test.dart` (third colour blocks the path; border-saturation) and
`test/transition_test.dart` (full-need removeOption, endpoint `count == 1`
removeOption / impossible, probing prunes a wedged third colour, reachable
`count == 1` not over-rejected). Full suite: **+8 passing, no new failures** vs
post-merge; the 11 pre-existing WIP failures are unchanged. Commit `2d7b9c9`.

#### Phase 2b status — DONE

Neither complicity had an opposite-forcing *bug*: `GSQAComplicity._solveGS`
already iterated the full domain and `PABalancedSideComplicity` was gated by
`_domainIsOneTwo` (a no-op on 3 colours). The four failing tests were 2-colour
and failed only on raw int literals. The work generalises both complicities to
emit `removeOption` on 3-colour domains and migrates the literals.

* **Test-literal migration** — the four `expect(move.value, 1|2)` assertions
  (`:252` PABalancedSide, `:617/:660/:679` GSQA) now use `CellValue.black|white`.
  No production change was needed for these to pass.

* **GSQA — `gsqa.dart`.** `_solveGS` is restructured around the
  feasible/infeasible partition: `feasible.isEmpty → isImpossible`; a committed
  anchor → `isImpossible` iff its colour is infeasible, else `null`; a free
  anchor with one feasible colour → force it; a free anchor with several feasible
  colours (only reachable on domain ≥ 3) → `removeOption` an infeasible colour
  still in the anchor's options (tier 3, `options.contains` guard). The
  removeOption loop never fires on a 2-colour domain, so 2-colour behaviour is
  unchanged. Regression: `GS:0.5`+`QA:1.4` on domain 3 → `removeOption` black on
  a free anchor; `isImpossible` when the anchor is already black.

* **PABalancedSide — `pa_balanced_side.dart`.** The `_domainIsOneTwo` gate is
  dropped from `isPresent`/`apply` (helper removed). The binary `C(n, n/2)`
  enumeration is replaced by a multinomial `_enumerateMultinomial(n, colors,
  need)` where `need[c] = targetCount − fixedCount[c]` and `targetCount =
  side.length / domain.length`; on a 2-colour domain it produces exactly the old
  `C(n, k)` set (unified path, 2-colour preserved). The side-length validity gate
  is now `side.length % domain.length == 0` and the cap is domain-aware
  (`_maxSideLen`: 10 on 2 colours, 6 on 3+, since `multinomial(6;2,2,2) = 90` and
  `multinomial(9;3,3,3) = 1680`). FM/LT filtering and `rejectingSlugs` are
  unchanged; `_withTag` now also carries `removeOption`. Per free cell: force if
  every survivor agrees, else `removeOption` a colour no survivor uses (still in
  the cell's options). Lifting the gate is generator-safe — only sound deductions
  are added. Regressions: domain-3 vertical-FM force (`FM:3.1`+`PA:9.top`,
  anchor purple → cell forced white) and domain-3 removeOption
  (`FM:1.3`+`PA:1.bottom`, black anchor → purple pruned from a non-unanimous cell
  that PA alone could not prune).

Verification: `flutter analyze` clean; `flutter test test/complicities_test.dart`
green (68 tests, +4 over the post-Phase-2 baseline). Full suite: the four
complicity failures are cleared with **no new failures**.

#### Phase 2c status — WIP test failures cleared, DONE

The seven remaining pre-existing WIP failures (`hint_flow` ×2, `shape_utils` ×1,
`third_color_suggestion` ×4) were all root-caused as 3-colour-migration
fallout — none were genuine product bugs. The full suite is now green (772
tests):

* **`third_color_suggestion` (×4) — `database.dart` + test.** The three
  *"Binding has not yet been initialized"* failures came from one unguarded
  fire-and-forget call: `notePuzzleCompleted` realigns the onboarding filters
  via `currentFilters.save()`, which hits SharedPreferences. Unlike the
  `_persist*` helpers it had no try/catch, so its async rejection escaped to the
  test zone. Fixed by swallowing that error at the call site
  (`currentFilters.save().catchError((_) {})`), matching the best-effort
  persistence convention. The fourth (`onboardingCompletedAt` stamped where the
  test expected `null`) was a test bug: the last onboarding phase introduces
  `QA`, so the graduating play must be a QA puzzle, not the FM `_twoColourLine`.
  The test now plays a `_qaLine`.

* **`hint_flow` (×2) — test fixtures.** Both failures (`canceled` instead of
  `inprogress`; a null-check throw) trace to `_deducibleFixture` (a lone
  `LT:A.0.4` on a 3×3) having no `cachedSolution`:
  `startHintConstraintComputation` early-returns to `canceled` without one, and
  `computeComplexity` can't produce one because seven cells are undeducible.
  Added a `_searchableFixture` that carries an embedded solution
  (line field 5 = `1:111111111`) for the two tests that need the search to
  start; the others keep `_deducibleFixture`.

* **`shape_utils` (×1) — test.** The "full chain" test still asserted the old
  `value: white` shape of the Level-4 block (and `value: 2` for Level 2);
  `ShapeConstraint.apply` emits `removeOption: black` for both (the Level-1..5
  tests above were already migrated). Steps 1 and 3 now assert `removeOption`
  and simulate it with `cell.removeOption`; step 2 (Level 5, a positive force)
  stays `value: black`.

#### Phase 2d status — corpus re-validation soundness fixes, DONE

Re-validating the corpus against the post-merge solver surfaced four latent
deduction bugs, in **both** directions. One let `--check` wrongly *accept*
ambiguous puzzles (GSQA over-counting, masked by stronger pre-port SY); two made
it wrongly *reject* valid, uniquely-solvable ones (the SY and LT ports each
dropped or mis-converted a sound 2-colour deduction). A fourth was a CH crash on
3-colour. Each was found by `--check` disagreeing with master and root-caused
with a per-step `solveExplained` trace diffed against the line's embedded
solution, plus a brute-force solution count to tell genuine multi-solution
puzzles from false rejections.

**A note on the brute-force counter.** `countSolutions` (in
`unique_solution_test.dart`) restores a backtracked cell with `reset()`, not
`setValue(free)`: the latter empties the cell's option list, and the
option-aware `verify()`s introduced by the port treat a free-but-optionless cell
as impossible, over-pruning the search (it reported 0 solutions for valid
puzzles). A `count ≥ 2` was always reliable — each counted completion is a fully
verified assignment — but `count == 0/1` was not until this fix.

* **GSQA over-counts out-of-group cells — `gsqa.dart`.** `_colorIsFeasible`
  counted *every* already-placed same-colour cell outside the anchor's
  *immediate committed cluster* as "outside the group", even cells still
  reachable through free intermediates. On a partially-solved board that
  over-counts the QA pressure (`gs.size + outside > cap`) and forces the wrong
  colour, so `solve()` reached a contradiction and `isDeductivelyUnique()`
  flipped to false. The bug stayed latent on master because stronger 2-colour
  SY deductions coloured the connecting cells early; the weaker 3-colour SY
  port left them free, fragmenting the cluster. Fix: a placed cell counts as
  out-of-group only when its 4-connected distance over {colour ∪ free} from
  the anchor is ≥ `gs.size` (a connected run containing both would exceed the
  group), or it is unreachable. Sound lower bound — never forces wrongly.
  Regressions: a minimal "reachable same-colour cell stays feasible" case in
  `complicities_test.dart` and the two reported lines in
  `unique_solution_test.dart`.

* **CH forced-bridge probes an excluded colour — `chain.dart`.** The
  forced-bridge probe committed each free cell to
  `domain.firstWhere((v) => v != color)` and called `setValue` without checking
  the cell's options; on a 3-colour grid where that colour had been pruned it
  threw a `RangeError` (surfaced by the generator on a random draw). Fix: pick
  the blocker from the cell's *own* options (any non-`color` option blocks
  equally); skip cells whose only option is `color`; and when the probe shows
  the chain blocked, force `color` only if it is still an option, else report
  `isImpossible`. Regression: a 3-colour bridge with the blocker pruned in
  `chain_test.dart`.

* **SY empty-anchor deduction lost on 2-colour — `symmetry.dart`.** The SY port
  deliberately weakened the empty-anchor (step 0) rule for 3-colour soundness:
  a coloured neighbour `n = nv` of a still-free anchor no longer forces its
  mirror `sym(n) = nv`, only prunes the anchor's own options. That force is
  **sound on 2 colours** (if anchor = nv, `n` joins the group and the mirror
  matches; if anchor = ¬nv, `n` is on the frontier and `sym(n)` — adjacent to
  the group — can't be ¬nv without joining it, so it is nv; both agree) but
  **unsound on 3+** (a third colour escapes the frontier rule). Dropping it
  uniformly cost valid 2-colour puzzles whose anchor never gets fixed by another
  rule: SY then stalls and `--check` falsely rejects a *unique* puzzle. Fix: a
  `domain.length == 2` fast path restores the strong form — force `value: nv` on
  a free mirror (positive force, kept as `value:` per the convention; the
  `removeOption` model is for exclusions), `removeOption: nv` on the anchor when
  the mirror is out of bounds, `isImpossible` on a conflicting coloured mirror —
  while the general branch keeps the weaker, sound 3-colour logic. It cannot
  re-accept ambiguous puzzles (the deduction is sound), so multi-solution lines
  stay rejected. Regressions: the two empty-anchor cases in `constraints_test.dart`
  updated to expect the restored force / immediate impossibility.

* **LT forced one specific opposite instead of pruning — `letter_group.dart`.**
  The LT port was only a mechanical type migration: the two "a rival letter's
  cell touching my group can't share my colour" deductions kept
  `value: myOpposite` (`domain.whereNot(== myColor).first`). On 3 colours that
  guesses *one* of the two non-`myColor` colours — unsound — so it could force a
  cell to the wrong colour and drive `solve()` into a contradiction, falsely
  rejecting valid LT-only 3-colour puzzles. Fix: emit `removeOption: myColor`
  (with the `options.contains` guard) in both places; on a 2-colour domain that
  collapses to the single opposite, preserving the old behaviour. The empty-
  member check was also generalised from `== myOpposite` to `!= myColor` so a
  third-colour member is caught, and a free member with `myColor` pruned now
  reports `isImpossible`. `myOpposite` is gone. Regressions: a domain-3 "prune
  not force" case and its 2-colour collapse twin in `constraints_test.dart`,
  plus the three reported LT lines in `unique_solution_test.dart`.

* **Auto-shrink coverage reworked — `generator.dart` + test.** The CH crash
  above was first seen through the flaky property test "every generated puzzle
  has every domain colour justified", which ran real generation and only
  checked a post-condition that holds vacuously when a puzzle happens to use
  every colour. It is replaced by `autoShrinkDomain` (renamed from
  `_autoShrinkDomain`, now public) plus a deterministic unit group in
  `auto_shrink_domain_test.dart` that drives the shrink directly (drops an
  unused+unreferenced colour, keeps a used one, keeps a constraint-referenced
  one, no-ops when all justified). `generateOne` calls `autoShrinkDomain`
  directly on both export paths (the default path and the simplify/easing
  branch); there is no wiring test asserting the call fires, since Dart can't
  intercept a static call and an output-only check can't tell a skipped shrink
  from a genuinely 3-colour puzzle.

### Remaining before release

* Re-append the domain-3 puzzles to the master corpus (assets) — **DONE**. 1652
  lines across seven level files were appended, then the user ran the full
  `--check` re-validation. The first pass surfaced the four Phase 2d soundness
  bugs (fixed above); the multi-solution puzzles those checks correctly reject
  were dropped (`Remove bad puzzles` commits), and the unique puzzles the SY/LT
  fixes recovered were kept. A final `--check` over every corpus puzzle bearing
  an `SY` constraint (the highest-risk family) passes with zero rejections —
  confirming the SY fast-path recovers only genuinely-unique lines and never
  re-accepts an ambiguous one.
* Release gates on `merge-master-third-color` (`c51f4ad`): `flutter analyze`
  clean, `flutter test` green (785 tests). Working tree clean, 19 commits ahead
  of `master` (`3945bbd`), 0 behind — linear history, `master` is a direct
  ancestor so a fast-forward is possible.
* Final integration (open decision for the user): fast-forward `master` to
  `c51f4ad` (or land via a merge commit), fast-forward the local `third-color`
  branch to the same tip, and overwrite/delete the obsolete
  `origin/third-color` (`87aab6b`).
