# Hint modes

When the player taps the hint button, the game reaches into one of two
behaviors depending on `Settings.hintType`
(`lib/getsomepuzzle/model/settings.dart:12`). Both share the same UI
button — the mode is purely a setting.

## The setting

```dart
enum HintType { deducibleCell, addConstraint }
```

- Persisted via `SharedPreferences` (key `settingsHintType`).
- Default: `deducibleCell`.
- Exposed in the settings page as "Hints" — see `_EnumSettingRow<HintType>`
  in `lib/widgets/settings_page.dart`.
- The enum is intentionally extensible — add new modes here, not via flags.

## Mode `deducibleCell` (default)

**Idea:** point at a cell the player could have deduced themselves, then
explain which constraint produces the deduction. The hint reveals
information progressively over four taps so the player keeps as much of the
work as they want for themselves.

### Tap flow

1. **Errors / "all correct".** If a constraint is currently violated, show
   that constraint. Otherwise, if a solution is known for the puzzle (from
   its line representation) and a colored cell differs from the solution,
   show the cell as an error without saying which constraint flagged it.
   Otherwise, tell the player that everything they have filled so far is
   correct.
2. **Cell only.** Highlight the deducible cell, without revealing which
   constraint produces the deduction.
3. **Cell + constraint.** Reveal the constraint and draw the arrow from
   the constraint to the cell.
4. **Apply.** Apply the move and reset the cycle.

The move from `findAMove` is either a `SetValue` ("this cell is X") or a
`RemoveOption` ("this cell is not X"), and each has its own wording. In a
2-colour domain (`puzzle.domain.length == 2`) the two are equivalent —
removing one option leaves exactly one — so a `RemoveOption` is surfaced with
the `SetValue` wording at every tap (cell-deduction phrasing on taps 2 and 3),
in `GameModel._revealCellOnly` / `_revealCellAndConstraint`. The
option-removal wording is reserved for 3-colour domains, where a pruned option
still leaves the cell free.

### Implementation

**Entry point:** `_MyHomePageState.showHelpMove()` in `lib/main.dart`,
falling through to `GameModel.showHelpMove()`.

**Computation:** `Puzzle.findAMove()`
(`lib/getsomepuzzle/model/puzzle.dart`) is run on the *current* puzzle
state on every meaningful change (debounced 300 ms in
`GameModel._scheduleHelpMe`). It tries, in order:

1. Error correction (if a constraint is already broken).
2. Cheap propagation: each constraint's `apply()` returns the first cell
   it can determine.
3. Force fallback: tentatively set each free cell to each domain value,
   propagate, and pick the one whose contradiction surfaces with the
   **shallowest** force depth (`_forceOneCell`). The "shallowest force"
   rule is load-bearing — see the comment on `_forceOneCell` for why we
   never break early on the hint path.

**Stats:** `currentMeta.hints` is incremented on the first reveal of a tap
cycle only — subsequent taps in the same cycle do not double-count.

**No background isolate:** `findAMove` is cheap enough to stay on the main
thread.

**Disabled state:** the hint button is disabled when `helpMove == null`
(see `_isHintButtonEnabled` in `main.dart`).

## Mode `addConstraint`

**Idea:** instead of pointing at a cell, attach a *new* constraint to
the puzzle — one that's true for the cached solution and that unlocks
at least one extra deduction. The puzzle becomes effectively easier.

Since puzzles carry their solution in the text representation, this
mode extends the legacy `findAMove`-driven hint with the option to
**add constraints** (more constraints = easier puzzle).

**Entry point:** `_MyHomePageState._showHintConstraint()` →
`GameModel.addHintConstraint()` (`lib/getsomepuzzle/model/game_model.dart:585`).

### Candidate generation

When a puzzle is loaded by the player **and the `addConstraint` mode is
active**, a background task computes every constraint that's valid for
the puzzle's solution.

**Method** — same pattern as the generator (`generator.dart:136-154`):

- The worker takes the full `Puzzle` object (`HintWorker.compute(puzzle: ...)`)
  and derives `width`, `height`, `domain`, `cachedSolution`,
  `existingConstraints` (via `serialize()`) and `readonlyIndices`
  internally — callers no longer have to unpack those fields.
- For each constraint type (FM, PA, GS, LT, QA, SY, DF, SH, CC, GC, NC,
  RC), call `generateAllParameters(width, height, domain)` to get every
  possible parameter set.
- Instantiate each constraint and check `constraint.verify(solved)`.
- Filter out constraints already present on the puzzle (compare via
  `serialize()`). Verified: every registry type implements
  `serialize()`. The base class returns `''`, so any future type that
  forgets to override will never be filtered — keep this in mind when
  adding a new type.
- Skip candidates whose `isCompleteFor(clone)` returns `true` — those
  constraints can no longer fire on the current state, so adding them
  would not unlock any deduction. Cheap pre-filter that avoids paying
  for a full `clone.solve()` on dead-on-arrival candidates.
- For each surviving candidate, clone the current puzzle, add the
  candidate, run `clone.solve()`, and keep the candidate iff the solve
  reaches a complete state where `constraint.verify(clone)` still holds.

The result is a `List<Constraint>` kept in memory (no persistent cache).

**Gated on `addConstraint` mode.** `GameModel.startHintConstraintComputation`
short-circuits when `hintType != addConstraint`. On web the worker runs
on the main isolate (no true background thread), so re-firing the
clone+solve loop on every cell mutation used to freeze the UI in
`deducibleCell` mode where the candidate list is never shown.
`GameModel.hintType` mirrors `Settings.hintType`; `main.dart` keeps the
mirror in sync before each call to the worker.

**Puzzles without a solution** (`0:0`): the feature is skipped. The
hint button stays disabled in `addConstraint` mode when the puzzle
has no stored solution.

**Architecture:** the computation runs in a dedicated hint Isolate
(`hint_worker_io.dart` / `hint_worker_web.dart`, selected via conditional
imports through `hint_worker.dart` / `hint_worker_stub.dart`). On web,
where there are no isolates, the worker is a cooperative async loop that
yields to the event loop every N candidates. The per-puzzle setup and
the per-candidate decision both live in `hint_worker_core.dart`
(`HintContext.forPuzzle` + `classifyHintCandidate`) so the two
platform shells only differ on their concurrency model (isolate spawn
vs cooperative yield + cancellation).

### Status state machine

`GameModel.hintConstraintsReady` is a `HintConstraintStatus` enum:

| Value          | Meaning                                                                  |
|----------------|--------------------------------------------------------------------------|
| `inprogress`   | Worker is computing. The hint button shows the localised "in progress" message (`hintConstraintInprogress`). |
| `ready`        | Worker finished and `availableHintConstraints` is non-empty. The button can graft a constraint. |
| `nohint`       | Worker finished and no candidate survived (`availableHintConstraints` is empty). The button shows `hintConstraintNone`. |
| `canceled`     | A puzzle change (cell tap, undo, mode toggle, puzzle rotate, exit) cancelled the in-flight worker. The button is treated as not-ready until a new worker is started. |

Transitions: `inprogress → ready/nohint` on worker completion;
`inprogress|ready|nohint → canceled` on player action; `canceled →
inprogress` when the worker is restarted (e.g. after a hint constraint
is grafted and the next round is computed). `canAddHintConstraint` is
true only in the `ready` state with a non-empty candidate list.

### Redundancy ranking

When a constraint is added it must bring new information to the
player. A constraint already implied by the existing ones (true, but
doesn't help solve) should not be proposed.

**Implementation:** after loading the valid candidates, the list is
shuffled. A second background job (`hint_rank_worker_io.dart` /
`hint_rank_worker_web.dart`, selected via conditional imports) ranks
candidates: it runs `applyConstraintsPropagation()` against each one
and records the *delta* — the number of additional cells the candidate
unlocks compared to the baseline (`scoreCandidate` in
`hint_rank_worker_core.dart`). Useful candidates (delta > 0) are
sorted by descending delta and placed at the front, so the hint
button surfaces the constraint that unlocks the most cells first.
Non-useful candidates (no extra progress, contradiction, or invalid)
are kept in the tail in their incoming order. Any player interaction
(`tap`, `undo`, etc.) cancels the current ranking pass and
reschedules it with a 300 ms debounce.

### Per-tap flow

1. **Selection:** take the front of `availableHintConstraints`
   (ranking has put useful candidates there). When the useful prefix is
   exhausted, the front is a non-useful (redundant) candidate — the player
   still gets a constraint if they ask for one, just one that doesn't
   unlock new deductions.
2. **Add:** attach the constraint to `currentPuzzle.constraints`, as if
   the puzzle had been created with this extra rule. This is
   effectively a new, easier puzzle.
3. **Display:** the UI updates so the player sees the new constraint,
   temporarily emphasized via `highlightColor` (same behavior as the
   `deducibleCell` highlight — disappears on the next tap).
4. **Persistence:** the added constraint is *not* written back to the
   playlist. It only lives in the in-memory puzzle for the current
   session.
5. **Stats:** `currentMeta.hints` ticks once per added constraint. No
   other scoring impact.
6. **Exhaustion:** the button only disables when `availableHintConstraints`
   is fully empty. While the list still contains non-useful candidates,
   `canAddHintConstraint` stays true.

### Cancel / restart

Any cell tap, undo, or mode toggle cancels the in-flight ranking via
`_cancelHintRanking` and re-debounces the next one (300 ms).

## UI gating summary

The hint button is enabled whenever a puzzle is open. Tap 1 (errors / "all
correct") must always be reachable, regardless of mode or whether deductive
work is possible. Subsequent taps are mode-specific; a tap that has nothing
to show (e.g. `helpMove == null` due to the 300 ms compute debounce, or
`addConstraint` candidate list exhausted) is a no-op or a terminal message
— it never disables the button.

| Mode             | Tap 1                          | Tap 2                  | Tap 3                            | Tap 4         |
|------------------|--------------------------------|------------------------|----------------------------------|---------------|
| `deducibleCell`  | Errors / "all correct"         | Cell highlighted alone | Cell + constraint (arrow drawn)  | Apply move    |
| `addConstraint`  | Errors / "all correct"         | Attach a new constraint *(or "none available" message)* | — *(cycle restarts at tap 1)* | — |

After the terminal action of each mode (apply move in `deducibleCell`,
attach constraint in `addConstraint`), the cycle restarts at tap 1 on the
next press.

## Adding a new hint mode

1. Add a value to the `HintType` enum.
2. Persist the new key in `Settings.load()` / `Settings.save()`.
3. Add a localization string in `app_localizations*.dart`.
4. Wire it through `_EnumSettingRow<HintType>` in `settings_page.dart`.
5. Branch on it in `showHelpMove`, `_isHintButtonEnabled`, and
   `_onHintTypeChanged` in `lib/main.dart`.
6. If the new mode needs precomputation, follow the worker/isolate
   pattern from `addConstraint` — don't block the UI thread.

---

## Multi-constraint hints

**Status:** implemented.
- ✅ `contributors` field on `Move` (`cell.dart:155`)
- ✅ Complicity → contributors, all 9 complicities, with **specific-instance** tracking
- ✅ Force move → contributors (`_propagateCount` / `_forceOneCell`)
- ✅ UI: `_revealCellAndConstraint` uses `contributors` instead of `givenBy` alone
- ✅ UI: `_computeArrowPositions` draws multiple arrows (geometric + per-constraint keys)

### Motivation

When a hint reveals a deducible cell (`deducibleCell` mode, tap 3),
the deduction may stem from multiple constraints working together
rather than a single constraint. There are two sources of
multi-constraint deduction:

1. **Complicity** — a `Complicity` (e.g. `GSAllComplicity`) combines
   info from two or more constraint types to produce a deduction that
   no single constraint could make alone. Currently the hint tags the
   `Complicity` instance as `givenBy`, which is opaque to the player
   — the UI shows something like "Deduced from GS+FM" instead of
   pointing at the actual constraints.

2. **Force move** — `_forceOneCell()` sets a cell to a value on a
   clone and propagates until contradiction. The contradiction
   surfaces at one constraint, but every constraint that fired during
   the propagation chain contributed to the deduction. Currently only
   the final contradicting constraint is tagged.

In both cases the player sees a single arrow from one constraint to
the target cell, when the truth is richer. Multi-constraint hints
surface *all* contributing constraints.

### Tap-3 visual change

Tap 2 (cell-only highlight) is unchanged. Tap 3 (`_revealCellAndConstraint`)
gains the ability to display **multiple arrows** — one per contributing
constraint — all pointing at the same target cell.

When only one constraint contributes, the behaviour is identical to
today (single arrow). When multiple contribute, the arrows fan out
from each constraint's widget to the target cell. All contributing
constraints are highlighted via `Constraint.isHighlighted`. The hint
text lists them (e.g. "Deduced from Groups, Forbidden Motif, and
Parity").

### `contributors` field on `Move`

```dart
sealed class Move {
  final CanApply givenBy;
  final List<CanApply> contributors;   // NEW
  const Move._(this.givenBy, {this.contributors = const []});
}
```

- `contributors` is the set of sources that *together* justify this
  deduction. It is always a superset of `givenBy`.
- When `contributors.length == 1` (the common case: a single
  constraint fired), `contributors` is `[givenBy]` and the arrow
  rendering is identical to today.
- When `contributors.length > 1`, the UI highlights all of them and
  draws an arrow from each.
- `Move.retag()` copies `contributors` unchanged from the source move
  (the new `givenBy` is already part of `contributors` if the caller
  added it there).

### Complicity → contributors

Each `Complicity.apply()` that returns a `Move` must populate
`contributors` with the actual `Constraint` (or `CanApply`) instances
it combined. How this is done depends on the complicity type:

- **`GSAllComplicity`** — tracks `blockers` as `Set<Constraint>`
  (not slugs). During sealing enumeration, each blocking constraint
  instance that rejects a colour is added directly. `_tagContributors`
  builds `[gs, ...blockers]` without lookup — no slug-to-instance
  expansion.
- **`PABalancedSideComplicity`** — uses `Set<CanApply> rejectingConstraints`
  instead of `Set<String> rejectingSlugs`. The specific FM/LT instances
  that reject a configuration are added. `_tagContributors` builds
  `[pa, ...rejectingConstraints]` directly.
- **`SYFMComplicity._solveEmptyAnchor`** — collects `participatingConstraints`
  from every move's `givenBy` during hypothesis propagation, plus any
  constraints whose `verify` fails. The set is unioned across all
  hypothesis runs (feasible and infeasible alike), so constraints that
  participated indirectly (e.g. FM firing `RemoveOption` during
  propagation) are credited even when no single constraint's `verify`
  directly failed.
- **`GSQAComplicity`** — `_qaThatRejects` identifies the specific
  `QuantityConstraint` that makes a colour infeasible (vs GS-merge
  failures which carry no QA). Only those QAs appear in `contribs`,
  not every QA in the puzzle.
- **`FMFMComplicity`** — introduces `_SynthNode`, pairing each
  synthesized FM with the `List<ForbiddenMotif>` of original FMs whose
  combination chain produced it. `apply` uses `node.origins` as
  contributors, so only FMs that actually entered the synthesis chain
  are credited.
- **`SHGSComplicity`, `LTGSComplicity`, `LTFMComplicity`,
  `GSGSComplicity`** — already track specific instances; they add the
  actual `ShapeConstraint`, `LetterGroup`, `GroupSize`, etc. that
  participated, not all constraints of that type.

The key invariant: `contributors` holds **references to constraint
instances that are part of `puzzle.constraints`** (or complicities
that are part of the puzzle's complicity list), so the UI can look
up their render position.

**No slug-based expansion.** Earlier versions used `Set<String>` of
slugs and then expanded each slug to all matching constraints via
`puzzle.constraints.where((c) => c.slug == slug)`, which credited
irrelevant constraints (e.g. both NCs when only one sealed a GS
expansion). All complicities now track specific instances directly.

### Force move → contributors

`_forceOneCell()` must now capture the full propagation chain that
led to the contradiction. This requires modifying `_propagateCount`:


```dart
// New return type
({int moves, bool failed, List<CanApply> fired})
```

- `fired` collects `move.givenBy` for every `SetValue` / `RemoveOption`
  that `_propagateCount` processes before hitting impossibility (or
  completion). An `Impossible` move itself is not added to `fired`
  since it carries no deduction — only the moves that led to it.
- `_forceOneCell()` receives the `fired` list from
  `clone._propagateCount()` and passes it as `contributors` on the
  returned `RemoveOption`.
- Duplicates across the chain (the same constraint firing on
  consecutive iterations) are collapsed to one entry per constraint,
  but deduplication is a display-level concern — the `fired` list may
  contain repeats that the UI deduplicates before drawing.

### UI: multiple arrows

In `PuzzleWidget._computeArrowPositions()`:

1. Instead of `break`-ing after the first highlighted constraint,
   collect *all* constraints where `isHighlighted == true`.
2. For each, compute the arrow start position (same logic as today —
   constraint widget's render box or cell-centric position).
3. Store `List<Offset>? _arrowStarts` and `Offset? _arrowEnd` (the
   cell position).
4. Render one `_ArrowPainter` per start position. All painters share
   the same end point.
5. When `_arrowStarts.length > 3`, consider fading less-important
   contributors (e.g., draw the 3 most recent with full opacity and
   the rest as grey dashes) to avoid visual clutter.

The `_constraintKey` assignment must also handle multiple highlighted
constraints: currently it is assigned to at most one constraint's
widget. For multi-arrow rendering, either:

- use one `GlobalKey` per constraint (the cell-centric key assignment
  already exists as a path per cell, but the top-bar/constraint-widget
  keys need expansion), or
- compute arrow origins from layout geometry without keys (scan the
  rendered widget tree, or compute positions from grid coordinates
  directly for cell-centric constraints).

### Tap flow (no change to stages)

| Tap | Behaviour | Change from today |
|-----|-----------|-------------------|
| 1   | Errors / "all correct" | Unchanged |
| 2   | Cell highlighted alone | Unchanged |
| 3   | Cell + **all** contributing constraints (arrows drawn) | Previously: single constraint. Now: all from `contributors`. |
| 4   | Apply move | Unchanged |

### Edge cases

1. **Single contributor** — degenerate case of the new system.
   Behaviour is identical to today: one arrow from one constraint,
   hint text unchanged.

2. **Complicity + force overlap** — a move whose `givenBy` is a
   complicity and whose `contributors` also includes constraints that
   the complicity combined. The complicity itself is in
   `contributors`; the UI highlights both the complicity and the
   individual constraints. The complicity is not an independent arrow
   source (it has no render widget) — it is represented textually in
   the hint message.

3. **No contributors** — `contributors` is empty (should not happen
   in practice). Fall back to highlighting `givenBy` alone.

4. **Overlapping contributors** — a constraint appears both as a
   direct propagator and as a participant in a complicity. The UI
   deduplicates by identity before drawing arrows.

5. **Complicity retag uniqueness** — when all rejecting constraints
   share the same slug (e.g. all rejectors are FMs), `_tagContributors`
   retags `givenBy` to a synthetic one-slug `PABalancedSideComplicity`
   or `GSAllComplicity` so the hint text can render "PA + FM" instead
   of "PA + other". The retag affects only `givenBy` — `contributors`
   still holds the specific instances.
