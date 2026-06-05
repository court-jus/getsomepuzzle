# Third color

The game historically worked with two colors (black and white). The engine
now supports wider domains; "purple" is the shipped third color. The design
is domain-prefix based: a concrete puzzle's domain is always a prefix of
`fullDomain` (`model/cell.dart`), and 2-colour puzzles behave exactly as
before the port.

## Model

* `CellValue` carries `free`, `black`, `white`, `purple` (order is
  canonical; everything keys off it).
* `fullDomain` and `defaultDomain` live in `lib/getsomepuzzle/model/cell.dart`;
  `defaultDomain` is documented as "fullDomain truncated to its first two
  entries" and a unit test (`test/domain_constants_test.dart`) enforces
  that relationship because Dart `const` doesn't allow indexed lists.
* `Cell.options` is the authoritative per-cell domain; `removeOption`
  auto-converts to `setValue` when only one option remains; `reset()`
  copies the domain into a fresh per-cell list. `Puzzle.restart()` goes
  through `cell.reset()` — assigning `cell.options = cell.domain` would
  alias one shared list across every cell, so the first post-restart
  `removeOption` would wipe that colour from the whole grid at once.
* `Move` is a sealed class with three shapes: `SetValue` (full
  assignment), `RemoveOption` (option pruning) and `Impossible`. Every
  propagation loop in `puzzle.dart` handles all three and bails out
  cleanly on a no-op `RemoveOption` (option already pruned) or an
  excluded-option `SetValue`.
* `Puzzle.solveExplained` forwards `RemoveOption` moves into the
  `SolveStep` it emits, so trace replays (hint ranking, complexity
  scoring) complete on 3-colour traces — without it every `removeOption`
  deduction becomes a no-op step and the replay never terminates.
  Covered by `test/solve_explained_test.dart`.

## UI

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
  cost: erasing a white cell takes two right-clicks
  (`white → black → free`) instead of one toggle — accepted as the
  price of uniformity.
* Left-drag uses `_nextCycle(initialCellValue)` as the paint colour
  because `domain.whereNot(== initialCellValue).first` never produced
  purple on a 3-colour puzzle. Drag-painting a row in purple works by
  starting the drag on a white cell.
* Long-press (mobile fallback for right-click) is wired through
  `GameModel.handleLongPress` to `Puzzle.decrValue`, mode-agnostic
  with respect to the paint / remove-option toggle (the long-press
  always means "previous colour", regardless of the left-tap mode).
* `CellWidget` renders one coloured dot per remaining option at the
  bottom of a free cell when `puzzle.domain.length > 2` (`_OptionDots`,
  ~10 % of the cell, with a thin grey outline so the white dot stays
  visible against the cyan "free" background). On 2-colour puzzles no
  dot is drawn because it would carry no information.
* The hint UI handles `RemoveOption` end-to-end: tap 2 shows
  `hintCellOptionRemovable`, tap 3 uses `hintRemoveOptionDeducedFrom` /
  `hintForceRemoveOption` / `hintRemoveOptionComplicity` /
  `hintRemoveOptionComplicityTwin` (parallel set to the setValue-side
  phrasings), tap 4 applies the `removeOption` and the relevant
  cell-dot disappears.
* The hint button on a completed-and-valid puzzle repurposes as
  "next puzzle" past tap 1: tap 1 still shows `hintAllCorrectSoFar`,
  the next tap fires the same `onPuzzleCompleted` callback used by
  automatic validation.
* 3-colour puzzles are opt-in for the player: `Filters.wantedDomains` /
  `bannedDomains` (`model/database.dart`, persisted in
  SharedPreferences) default to `bannedDomains = {"d3"}`, and the
  collection page (`widgets/open_page.dart`) exposes a domain
  flag-selector. The corpus level files carry both 2- and 3-colour
  lines (`v2_12_…` vs `v2_123_…`).

## Solver soundness invariants

Two dual failure modes recur when solver code meets domain 3+. Both are
invisible on domain 2 because a single `removeOption` immediately
collapses the cell to a value (`Cell.removeOption` auto-set); on 3+ the
cell stays free with two options and the buggy branch becomes reachable.
Use them as the review grid for any new constraint or port:

* **Too-strict — spurious `isImpossible` once borders close.** A
  constraint correctly closes its borders by pruning `color` from free
  neighbours, then on the next propagation pass — finding no remaining
  neighbour with `color` in options — wrongly reports impossibility.
  `applyWithForce` then uses that spurious `Impossible` to eliminate
  valid branches, making `isDeductivelyUnique()` accept multi-solution
  puzzles. The affected branches (`ShapeConstraint` Level 2,
  `LineCentricConstraint` RC/CC `colorCount == count` post-close,
  `GroupCountConstraint` `currentCount == count`, `QuantityConstraint`
  post-close, `EyesConstraint` upper-bound with the unique candidate
  already pruned) all return `null` / `continue` instead: "nothing to
  do here" is not "impossible".
* **Too-lenient — counting a pruned option as still available.** Solver
  code that counts a still-`free` cell as able to take a colour already
  pruned from its `options` accepts unreachable states. The option-aware
  fixes: `GroupCountConstraint` funnels every "can a new `color` group
  still form?" question through the single helper
  `getFreeCellsThatCanStartNewColorGroup` (free, no `color` neighbour,
  `color` still in options — still monotone decreasing, so the
  monotonicity arguments hold); `EyesConstraint._scan` treats a free
  cell with `color` pruned as blocking the line of sight exactly like a
  committed opposite cell (it is destined to be non-`color`);
  `ShapeConstraint.isOpen` treats a group whose only free neighbours
  have `color` pruned as *closed*, so an undersized frozen group is
  rejected; `NeighborCountConstraint.isCompleteFor` counts only free
  neighbours that can still become `color`. The conservative
  `isCompleteFor` predicates (QA, MJ, PA, DF, base-line) only ever grey
  out *late*, never early — sound as-is.
* **Apply-side incompleteness is accepted.** The "full-need" branches of
  QA / NC / MJ / base-line use the unfiltered free-cell count, so on
  domain 3 they can miss a force that an option-aware count would catch.
  Left as-is because no invalid state can result: each force is guarded
  by `options.contains` (else `Impossible`) and `verify` is option-aware
  — only some valid deductions are delayed. Revisit if 3-colour
  generator throughput needs it.
* **Brute-force counting must restore with `reset()`.** `countSolutions`
  (`test/unique_solution_test.dart`) restores a backtracked cell with
  `reset()`, not `setValue(free)`, because the latter leaves an empty
  option list and the option-aware `verify()`s treat a
  free-but-optionless cell as impossible, over-pruning the search
  (a `count ≥ 2` is always reliable — each counted completion is a fully
  verified assignment — but `count == 0/1` is only trustworthy with the
  `reset()` restore).
* **Every `verify` tightening needs a corpus re-validation.** Changing
  3-colour deductions changes which lines pass `--check`; lines that
  were only "unique" under a more lenient solver must be flagged and
  dropped.

## Per-constraint port notes

Most constraints are domain-generic through the option model; the ones
below carried 2-colour assumptions that needed deliberate decisions.

### SY (`symmetry.dart`)

Several 2-colour SY deductions relied on "non-myValue = the unique other
colour", which collapses on 2 colours but not on 3+. The port weakens
those rules on the general (3+) branch to preserve correctness; cells are
still deduced, just later in the cascade.

* **Step 1 (group symmetry)** — emit `value: myValue` on a free mirror
  (with the `options.contains` guard); emit `isImpossible` when the
  mirror is out of bounds **or** already coloured a different value.
* **Step 2 (cells adjacent to G)** — two cases.
  * *Free neighbour `n`*: if `n` became `myValue` it would join `G`,
    forcing `sym(n) = myValue`. If the mirror is out of bounds or
    coloured something other than `myValue`, the neighbour cannot take
    `myValue` → `removeOption: myValue` on `n`. (This also fixes a
    latent 2-colour bug where a sym coloured `myValue` wrongly forced
    the neighbour to the opposite.)
  * *Coloured neighbour `n` (colour `nv ≠ myValue`)*: `n ∉ G`, so by
    symmetry `sym(n) ∉ G`; since `sym(n)` is adjacent to `G` it cannot
    be `myValue` → `removeOption: myValue` on `sym(n)` (free) or
    `isImpossible` (already `myValue`). We do **not** force
    `sym(n) = nv` on 3+ colours: `1 2 3` with vertical symmetry through
    the centre is a valid SY state — the constraint only requires
    `sym(n) ∉ G`, not `sym(n) = nv`.
* **Step 0 (anchor empty)** — split by domain size, because the strong
  2-colour form is sound there and dropping it uniformly made `--check`
  falsely reject unique 2-colour puzzles whose anchor never got fixed by
  another rule:
  * `domain.length == 2` fast path: a coloured neighbour `n = nv` of a
    free anchor forces its mirror `sym(n) = nv` (if anchor = nv, `n`
    joins the group and the mirror matches; if anchor = ¬nv, `n` is on
    the frontier and `sym(n)` — adjacent to the group — can't be ¬nv
    without joining it; both branches agree). Positive force kept as
    `value:` per convention; `removeOption: nv` on the anchor when the
    mirror is out of bounds; `isImpossible` on a conflicting coloured
    mirror.
  * General branch (3+): the force is unsound (a third colour escapes
    the frontier argument), so we only deduce what the anchor cannot
    become: `sym(n)` null → anchor ≠ nv; `sym(n)` free without nv in
    options → anchor ≠ nv; `sym(n)` coloured `c' ≠ nv` → anchor ≠ nv
    and ≠ c'; `sym(n)` coloured nv or free with nv available → no
    deduction.
* **Step 3 (look-ahead through myValue chains)** — emits
  `removeOption: myValue` on the free neighbour when extending through
  myValue cells would create a merged group with an impossible mirror.

### PA (`parity.dart`)

The `PA` slug is historically named "parity", but on the option model it
is a **balanced colour partition**: the targeted side of the anchor must
hold the same count of every domain colour,
`targetCount = side.length / domain.length` per colour. On 2 colours this
collapses to "as many black as white" — what the name refers to; on 3 it
generalises to "as many black as white as purple". The slug is kept
unchanged so previously stored `PA:` lines keep parsing.
`generateAllParameters` only emits a side whose length is divisible by
`domain.length`, guaranteeing an integer per-colour target.

### LT (`letter_group.dart`)

The two "a rival letter's cell touching my group can't share my colour"
deductions emit `removeOption: myColor` (with the `options.contains`
guard) because forcing one specific opposite
(`domain.whereNot(== myColor).first`) guesses between the two
non-`myColor` colours on domain 3 — unsound, and it falsely rejected
valid LT-only 3-colour puzzles at `--check`. On a 2-colour domain the
prune collapses to the single opposite, preserving the old behaviour.
The empty-member check tests `!= myColor` (not `== myOpposite`) so a
third-colour member is caught, and a free member with `myColor` pruned
reports `isImpossible`.

### MJ (`majority.dart`)

`apply` only forces `value: targetColor` (positive, domain-agnostic);
soundness comes from the `currentCount + freeCount < target` bound. The
non-target side counts **every** coloured cell ≠ `targetColor` because
counting a single "opposite" colour was a binary vestige —
sound-but-incomplete on 3 colours.

### CH (`chain.dart`)

`_isBlocked` is driven by a `_passable(puzzle, idx)` predicate (free with
`color` still in options, or already `color`) for both the border seed
and the BFS, because collapsing "non-color" to one `oppositeColor` made
third-colour cells traversable when they actually block the path
(`verify` too lenient — unsound). Border saturation counts blocking
cells (`!_passable`). The forced-bridge probe picks its blocker from the
cell's *own* options (any non-`color` option blocks equally) because
committing a fixed `domain.firstWhere((v) => v != color)` can pick a
pruned colour and throw; cells whose only option is `color` are skipped,
and when the probe shows the chain blocked, `color` is forced only if it
is still an option, else `isImpossible`. CH still only forces
`value: color` (positive).

### RT/CT (`transition_utils.dart`)

The 2-colour deduction blocks (`domain == 2`) are left intact; 3-colour
behaviour lives alongside:

* *Saturated* (`t == count`): forcing a free cell to *equal* its
  coloured neighbour (`value: nv`) is positive and domain-agnostic, so
  it needs no port (one coloured neighbour → force; two equal → force;
  two different → `isImpossible`).
* *Full-need* (`t + fp == count`), `domain ≥ 3`: a free cell adjacent to
  a coloured `nv` must differ → `removeOption: nv` (with the
  `options.contains` guard); `isImpossible` if no option survives all
  coloured neighbours.
* *Endpoint `count == 1`*, `domain ≥ 3`: exactly two runs ⇒ the
  endpoints differ → `removeOption` the known end's colour on the free
  end, or `isImpossible` if both ends are coloured and equal; mirrored
  in `verify`. (`count == 0` is covered by saturated; `count ≥ 2` has no
  endpoint generalisation.)
* *Lower-bound probing fallback* (tier 4, `domain ≥ 3`, only when
  nothing above fired): for each free cell × option,
  `_lineFeasibleWith` re-checks the transition bounds + the `count == 1`
  endpoint rule under that hypothetical assignment; an infeasible colour
  is pruned. Sound oracle (infeasible ⇒ impossible); catches the
  "wedged" case, e.g. `[1, ., 2]` count 1 → prune the third colour.

## Complicities

All complicities are ported to the option model. The table records the
original 2-colour pattern (the *reason* each one needed work) so future
contributors can recognise the shape; see the source for current code.

| Complicity                       | Original 2-colour assumption          | Current shape |
|----------------------------------|---------------------------------------|--------|
| `LTGSComplicity`                 | none — colour read off a coloured cell on the path | options-guard added |
| `SYFMComplicity._solveEmpty…`    | none — domain-agnostic by construction | options-guard added |
| `GSGSComplicity`                 | `value: opposite(vi)` to deny same group | `removeOption: vi` |
| `LTFMComplicity`                 | `value: forcedColor` after FM blocks adjacency | iterates LT cells looking for one with the option |
| `SHGSComplicity`                 | `value: remaining.first` after SH-vs-GS size mismatch | `removeOption: excluded[i]` one per call; impossibility judged on the cell's current options, not the full domain |
| `SYFMComplicity._solveColoured…` | `value: opposite(c)` when FM blocks the SY extension | `removeOption: c` with frontier filter |
| `GSAllComplicity` `allInSealed`  | `value: opposite(c)` for cells outside every sealing | `removeOption: c` |
| `GSAllComplicity` `allInGroup`   | `value: c` for cells inside every sealing | options-guard added |
| `GSQAComplicity`                 | anchor forced to the single feasible colour | feasible/infeasible partition (see below) |
| `PABalancedSideComplicity`       | binary `C(n, n/2)` enumeration, gated to `{black, white}` | multinomial enumeration, gate dropped (see below) |
| `FMFMComplicity`                 | synthesises a wildcard FM from two FMs whose differing values cover the domain | guarded by `values.length != domain.length`; inert on 3-colour because two FMs can never cover a 3-value domain (see TODO) |

* **Convention: a no-op is not impossible.** When a complicity wants to
  emit `removeOption: X` on a cell whose options already exclude `X`, it
  skips to the next candidate rather than raising `isImpossible` — the
  complicity loop sees "no deduction available here" and moves on.
* **GSQA (`gsqa.dart`).** `_solveGS` partitions the domain into
  feasible/infeasible anchor colours: `feasible.isEmpty → isImpossible`;
  a committed anchor → `isImpossible` iff its colour is infeasible, else
  `null`; a free anchor with one feasible colour → force it; a free
  anchor with several feasible colours (only reachable on domain ≥ 3) →
  `removeOption` an infeasible colour still in the anchor's options.
  `_colorIsFeasible` counts a placed same-colour cell as out-of-group
  only when its 4-connected distance over {colour ∪ free} from the
  anchor is ≥ `gs.size` (a connected run containing both would exceed
  the group) or it is unreachable — counting every cell outside the
  *immediate committed cluster* over-counts the QA pressure on a
  partially-solved board and forces the wrong colour (this stayed latent
  on 2 colours because the stronger pre-port SY deductions coloured the
  connecting cells early).
* **PABalancedSide (`pa_balanced_side.dart`).** Domain-generic: a
  multinomial `_enumerateMultinomial(n, colors, need)` enumerates the
  balanced colourings (`need[c] = targetCount − fixedCount[c]`,
  `targetCount = side.length / domain.length`); on a 2-colour domain it
  produces exactly the old `C(n, k)` set (unified path). The
  side-length validity gate is `side.length % domain.length == 0` and
  the cap is domain-aware (`_maxSideLen`: 10 on 2 colours, 6 on 3+,
  because `multinomial(6;2,2,2) = 90` is fine and
  `multinomial(9;3,3,3) = 1680` is not). Per free cell: force if every
  survivor agrees, else `removeOption` a colour no survivor uses (still
  in the cell's options). Lifting the old `{black, white}` gate is
  generator-safe — only sound deductions are added.

## Generator

### Domain selection and auto-shrink

* The CLI generator resolves the colour domain **per attempt**, not per
  run. Without a `--domain` flag both domains are eligible and the
  worker draws each attempt's domain gap-based toward the 60/40 (2:3)
  corpus profile (`kTargetDomainProfile` — see `equilibrium.md` § axis
  7). `--domain N` (N ∈ {2, 3}) *freezes* the run to that domain and
  disables the domain axis. The dashboard's `Config:` line surfaces the
  mode (`domain auto(2/3)` or the frozen value). The draw governs the
  regular (grid-first) and SH flows only: the **path-based and sy-based
  pre-fills are 2-colour by design** (their colourings are intrinsically
  binary — see `path_based.md` / `prefill_sy.md`), so the worker forces
  domain 2 upfront on any path/sy iteration rather than handing them a
  3-colour domain.
* The in-app generator calls `GeneratorWorker.start` without
  `allowedDomains`, which freezes the domain to `GeneratorConfig.domain`
  — its behaviour is unchanged by the per-attempt machinery.
* `autoShrinkDomain` (public, `generator.dart`) shrinks the declared
  domain just before `lineExport` when the validated solution doesn't
  use a colour AND no constraint references it (`c.referencedColors`).
  `generateOne` calls it on both export paths (default and
  simplify/easing). It is covered by deterministic unit tests in
  `auto_shrink_domain_test.dart` that drive the shrink directly; there
  is no wiring test asserting the call fires, because Dart can't
  intercept a static call and an output-only check can't tell a skipped
  shrink from a genuinely 3-colour puzzle.

### Validity criterion

A generated puzzle is valid iff `currentRatio == 0` after the optional
fill-from-solution (which reuses the already-solved `solvedPu`). There is
no post-loop `!isUnique` check and no `notUnique` reject category: the
re-solve used the same `findAMove` engine and was redundant by
construction — the occasional `notUnique` verdicts it produced came from
halt-condition asymmetries between `solve()` and `solveExplained()`, not
genuine ambiguity.

### Iterative loop

* Rejected candidates are requeued into a `secondChance` list and
  re-pooled after every accept, because a candidate that didn't
  propagate against the old state may propagate against the new one
  (peer-constraint synergy).
* After each accept, one probe `solve()` refreshes both the cached ratio
  and the cached list of undetermined cells. `_generateTargetedKeys`
  computes the serialise-keys of DF / NC / CC / RC candidates that touch
  those cells and the sort comparator promotes them to the front of
  `allConstraints`, because random sampling rarely lands a candidate
  targeting exactly the 3-4 cells still undetermined — the dominant
  `ratioTooHigh` failure mode. Those four slugs are the cheap-to-target
  ones (DF: link to a readonly singleton; NC: read the count off
  `solved`; CC/RC: per-axis colour counts); the non-local slugs
  (GS, LT, SH, FM, PA, SY, QA, GC) stay randomly sampled.
* After accepting a `ColumnCountConstraint`, every other CC candidate on
  the same column is dropped from `allConstraints` (same for RC and
  rows), because a second one is redundant on 2 colours and at best
  partially redundant on 3 — and the inner loop stops re-evaluating
  doomed candidates.
* Per-letter LT pre-filter: for each letter, only pairs sitting in a
  *single connected same-colour component* of `solved` survive (the
  largest component per letter — most generative), because
  `Puzzle.addConstraint` silently aggregates same-letter LTs and two
  individually-valid pairs from different components merge into an LT
  whose union no longer satisfies `solved`, rejecting the whole attempt
  late. A belt-and-braces re-verify inside the loop catches any
  pre-filter corner case before `cloned.solve()` runs.
  `LetterGroup.generateAllParameters` itself cannot do this filter: its
  signature doesn't carry `solvedValues`.
* `shouldStop` is re-checked at the top of the *inner* candidate sweep
  so a long sweep (hundreds of `solve()` calls on a hard 3-colour grid)
  honours the deadline within seconds.
* `removeUselessRules` (`puzzle.dart`) runs post-loop on every
  successful attempt, because phase 1's lax cheap accept may pick
  constraints later subsumed by phase 2 or by fill-from-solution hints;
  it walks the constraint list last-to-first and drops any whose removal
  preserves deductive uniqueness.

### Phase-gated candidate acceptance

Per-candidate full `solve()` dominates attempt cost (its
`_forceOneCell` sweeps every free × domain combination), so candidate
testing is **phase-gated**:

* **Phase 1 (cheap-only)** — `cloned.propagateToFixpoint()`, accept iff
  the prop-fixpoint free-cell count drops below `pu`'s. No full-solve
  fallback: candidates that don't propagate go to `secondChance`.
  `currentRatio` is NOT updated by phase-1 accepts because the
  prop-fixpoint ratio overstates the true full-solve ratio and breaks
  the loop's `currentRatio == 0` exit condition; phase 1's own exit
  signal is `cachedPropFreeCells == 0`. Phase 1 is
  **single-accept-per-outer-iter** (break at the first accept, re-pool
  `secondChance` with the targeted re-sort, restart the sweep) because
  cheap accepts are sparse on 3-colour grids — draining the whole queue
  per outer iter costs ~10× more cheap probes for the same 1-2 accepts,
  and the re-sort between accepts surfaces the highest-targeted
  candidate next.
* **Phase 2 (strict full-solve)** — triggered exactly when phase 1
  plateaus (inner sweep exhausts without acceptance) and `secondChance`
  is non-empty: `cloned.solve()`, accept iff
  `fullRatio < cachedRatioBefore`. No cheap probe in phase 2. Picks up
  the force-enablers phase 1 drops.

Easy puzzles close fast via the phase-1 propagation cascade; hard ones
transition to phase 2. The cheap probe is paid only on phase-1
candidates, and phase 1 plateaus quickly on a 3-colour grid, so its
overhead stays bounded.

Designs tried and rejected (kept as conclusions):

* A **two-tier per-candidate test** (cheap probe, then full-solve
  fallback on the same candidate) is pure overhead because the cheap
  path hits ~0.4 % on domain-3 states — and updating `currentRatio`
  from a prop-fixpoint result makes the loop run past its natural close
  point.
* **Advancing `pu` itself with occasional forces** (probing parked
  candidates against the advanced state) doesn't work because
  constraints accepted along a *specific* force trajectory with a
  *partial* constraint set aren't reproducible by the final clean-state
  `solve()` — its `_forceOneCell` may pick different cells, so the
  accepted set doesn't actually drive `solve()` to completion.

Dashboard instrumentation: stage timers `loop_candidate_prop`,
`loop_candidate_full` and `cleanup`, plus a derived "Two-tier breakdown"
line; reading the phase-1 hit rate off it is the quickest way to judge
whether phase 1 pays off on a given configuration.

### Strategies

* `GeneratorConfig.strategy` defaults to `phaseGate` for callers that
  don't override (in-app generator, tests).
* CLI `--strategy` accepts a comma-separated list; workers are assigned
  round-robin. The recommended batch default is
  `--strategy phase-gate,phase-1-oneshot,prop-only` because the
  strategies cover complementary slug regions in a single run.
* `propOnly` (CLI: `--strategy prop-only`) has the best raw throughput
  but is not the default because its acceptance signal skews output
  toward propagation-friendly slugs (NC, EY) and starves force-leaning
  ones (FM/PA/GS/LT/DF) — fine as a fast batch mode, not for a balanced
  corpus. (FM still occurs in its output: FM constraints often piggyback
  on cells where propagation alone advances after they're added, so the
  "prop-only can never accept a force-needing slug" argument only holds
  for *purely* force-only candidates.)
* `singleTier` is retained for benchmarking only, because it is
  systematically watchdog-limited.

### Equilibrium

* `_overrepresentedSlugs` (`worker_io.dart`) hard-bans slugs whose
  observed corpus share exceeds 3× the uniform target
  (`kOverrepBanRatio = 3.0`) because propagation-friendly slugs (NC, EY)
  otherwise flood every attempt. `SlugTarget` / `NTypesTarget` re-add
  their own targeted slug even when over-represented, because the ban
  would otherwise empty the allowed/preferred intersection.
* `NTypesTarget` keeps the picker's N chosen slugs as a *soft*
  preference (`preferredSlugs`) instead of hard-restricting
  `allowedSlugs`, because the hard restriction costs ~10× generator
  productivity — the exact-ntypes guarantee is traded away.
* `detectPuzzleProfile` (`equilibrium.dart`) classifies corpus lines by
  scenario suffix, falling back to an SH-slug heuristic for legacy lines
  without one.
* The picker has a **domain axis** (`DomainTarget`, target profile
  60 % dom2 / 40 % dom3); on top of it, every iteration whose target is
  *not* the domain axis draws its domain gap-based via
  `pickWeightedDomain`, so the corpus converges on the profile no matter
  which axis is being pushed. Domain accounting reads the *emitted*
  line (`parts[1].length`), so an auto-shrunk domain-3 attempt honestly
  counts as domain 2. The infeasibility blacklist separates the two
  populations by suffixing the `AttemptKey` scenario with `+d3`
  (`attemptScenarioKey`, `feasibility.dart`). Full description in
  `equilibrium.md` (§ axis 7) and `feasibility.md`.

### Throughput on 3 colours

3-colour generation remains structurally slower than 2-colour
(roughly 10-20 % success in equilibrium mode on a fresh preseed, vs
~75-80 % for the 2-colour baseline), because propagation is weaker (each
cell has 3 options, so a single prune no longer collapses it and more
constraints are needed to close the puzzle) and `_forceOneCell` costs
2-3× more (free-cell × option sweep, each per-option propagation itself
longer). Productivity also drops as the corpus balances — the picker
pushes into harder, less-represented targets.

The **in-game hint** pays the same `_forceOneCell` cost on a hard
3-colour puzzle, with no phase-gate-style mitigation. Not observed as a
playable problem; monitor if complaints arise (possible optimisations:
incremental-propagation cache, parallelising the `(cell, option)` probes
across an isolate).

Possible next steps (not done): derive the `currentRatio > 0.25`
acceptance threshold from `domain.length`; smarter pre-fill choosing
colours that maximise constraint satisfiability.

## Frozen decisions

### Player play-state: options not serialised on reload

`lineWithPlayState` and `lineExport` (`puzzle.dart`) only serialise each
cell's `value`; `Cell.options` are never persisted, and the `Puzzle()`
constructor resets every free cell's options to `domain.toList()` on
reload. On a 3-colour puzzle a player who *manually* pruned an option
(remove-option mode / `cycleRemoveOption`) loses that work if the game
is interrupted and resumed; on 2-colour it is inert (a prune collapses
immediately to a serialised `setValue`). Frozen by decision — not
implemented. If revisited: an `o:<options>` field in the v2 format
(per-cell bitmask over `{black, white, purple}`, one hex digit per
cell), or store only the diff from the full domain.

## TODO

* **Re-tune complexity scoring** for 3-colour puzzles. The scoring was
  tuned for 2-colour traces; 3-colour traces produce more `removeOption`
  steps that each carry a tier-0..5 complexity, so the bands
  (`beginner` / … / `mad`) may need re-anchoring against a 3-colour
  corpus.
* **Option dots on small screens.** `_OptionDots` is not yet validated
  on a real phone < 5". Verify legibility before promoting 3-colour
  beyond opt-in; if cramped, bump the dot to 12-15 % or add a
  "highlight pruned options" toggle.
* **Complicities still inert or capped on 3 colours.**
  * `FMFMComplicity` only synthesises a wildcard FM when two FMs'
    differing values cover the whole domain — never true on 3 colours.
    Generalising means fusing *three* FMs (O(n³) candidate triples
    instead of O(n²) pairs).
  * `PABalancedSideComplicity`'s multinomial enumeration is capped at
    side length 6 on 3+ colours; a wider cap needs a smarter generator
    (`multinomial(9;3,3,3) = 1680`, `multinomial(12;4,4,4) = 34650`).

## Adding a new colour

Adding a fourth colour (say `orange`) is mostly mechanical, but several
spots are *not* type-enforced and will silently misbehave if missed.
Checklist:

1. **`enum CellValue`** (`model/cell.dart`) — append the new value
   **after** `purple` (order is canonical; everything keys off it).
2. **`fullDomain`** (`model/cell.dart`) — append the new value. Leave
   `defaultDomain` (the 2-colour prefix) untouched; re-run
   `test/domain_constants_test.dart` (the prefix relationship is
   asserted there, not by the type system).
3. **Serialisation** (`model/cell.dart`) — extend the two switch helpers
   in lockstep: `cellRepresentationToValue` (`"4" → orange`) and
   `cellValueToString` (`orange → "4"`). The numeric tags are what land
   in the `v2_<domain>_…` line, so the domain field of a 4-colour puzzle
   becomes e.g. `1234`.
4. **Rendering** (`widgets/cell.dart`) — add the value to both colour
   maps: `bgColors` (cell background) and `fgColors` (digit / glyph
   foreground). A missing entry falls back to `Colors.black` and is easy
   to miss visually. `_OptionDots` already iterates `options`, so option
   dots pick the new colour up automatically once `bgColors` has it.
5. **Per-constraint widgets** that carry their own colour map — e.g.
   `widgets/column_count.dart` / `row_count.dart` keep a private
   `_textColors` map. Add the new value there too.
6. **Constraints that hard-assume a colour count.** Most constraints are
   domain-generic via the option model, but audit these before relying
   on the new colour:
   * `FMFMComplicity` — only synthesises a wildcard FM when two FMs'
     differing values *cover the whole domain*; inert beyond 2 colours
     until N-FM synthesis lands (see TODO).
   * `PABalancedSideComplicity` — domain-generic via the multinomial
     enumeration, but `_maxSideLen` must be re-checked for the wider
     domain (combinatorial growth).
   * `PA` (`parity.dart`) — domain-generic (`% domain.length`), but the
     candidate count and per-colour target grow with the domain;
     re-check generator cost.
7. **Generator domain plumbing** — extend the accepted range of
   `--domain N` (the freeze flag) in `bin/generate.dart`, the
   `allowedDomains` lists (CLI resolution, `_IsolateParams`,
   `TargetUniverse`), and `kTargetDomainProfile` /
   `pickWeightedDomain` in `equilibrium.dart` (the per-attempt draw and
   the equilibrium domain axis only know the sizes the profile
   declares). The path-based and sy-based pre-fills are intrinsically
   binary; the worker forces them to domain 2 regardless of the range
   (see `path_based.md` / `prefill_sy.md`).
8. **Re-validate** the full corpus with `--check` after generating any
   N-colour lines — the soundness invariants above are domain-sensitive
   and a wider domain can resurface "too-lenient on pruned options"
   bugs.

## Branch state (2026-06-05)

The third-colour work lives on `third-color` = `master` (`bb2def1`) plus
two commits (`767fb4b` Third color, `8052c87` Generator fixes, more docs
and puzzles), pushed to `origin/third-color`. Release gates pass
(`flutter analyze` clean, `flutter test` green). Remaining: merge into
`master`.
