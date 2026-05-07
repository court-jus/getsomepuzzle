# Third color

Currently, the game only works with two colors (black and white) but it could be interesting
to have some puzzles with more than two colors.

## Current state (as of 2026-05-12)

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
  `resetCell` so options are restored.
* Right-click toggling a coloured cell back to free also goes through
  `resetCell` (not `setValue(free, ignoreOptions: true)`), so the
  option dots reappear correctly on a 3-colour puzzle.
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

Possible next steps (not done):

* Skip force in the iterative loop's per-candidate `cloned.solve()`
  — we only need a propagation-power signal there. Force can stay in
  the final validity check.
* Raise the `currentRatio > 0.25` threshold for 3-colour puzzles, or
  derive it from `domain.length`.
* Smarter pre-fill: choose colours that maximise constraint
  satisfiability instead of uniform random.

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
* **UI: right-click / drag semantics on 3-colour puzzles.** Right-
  click currently still does the 2-colour toggle (free ↔ white) and
  drag still paints "set to the first-tap value". Both work, but
  neither uses the third colour — on a 3-colour puzzle the player
  has to use the regular tap cycle to reach purple. Probably fine
  as a first iteration, but worth a UX review.
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
