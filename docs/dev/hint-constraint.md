# DONE: Constraints as hints

When the player asks for help, `findAMove` is used to see what can be deduced, first by
propagation then by a "force round".

The player is then shown which cell is deducible and, when the deduction came from propagating
a constraint, that constraint is highlighted.

Since puzzles now carry their solution in the text representation, this behavior is extended
with an option that **adds constraints** (more constraints = easier puzzle).

## Implementation (shipped)

### 1. `HintType` setting

A new setting is available in the game menu, named "Hints" (localized EN/ES/FR), with a
`HintType` enum (`lib/getsomepuzzle/settings.dart:12`):

- `deducibleCell` — "Deducible cell" (existing behavior, **default value**)
- `addConstraint` — "Add constraint"

The enum is designed to be extended with other modes later.

Stored in `Settings` / `ChangeableSettings` and persisted via `SharedPreferences`, following
the same pattern as existing settings (`ValidateType`, `LiveCheckType`, etc.).

### 2. Computing valid constraints in the background

When a puzzle is loaded by the player **and the `addConstraint` mode is active**, a background
task runs to compute all the constraints valid for the puzzle solution.

**Method** — same pattern as the generator (`generator.dart:136-154`):
- For each constraint type (FM, PA, GS, LT, QA, SY, DF, SH), call
  `generateAllParameters(width, height, domain)` to get every possible parameter set.
- Instantiate each constraint and check `constraint.verify(solved)`.
- Filter out constraints already present on the puzzle (compare via `serialize()`). Verified:
  the 8 registry types (FM, PA, GS, LT, QA, SY, DF, SH) all implement `serialize()`. The base
  class returns `''`, so any future type that forgets to override will never be filtered —
  keep this in mind when adding a new type.

The result is a `List<Constraint>` kept in memory (no persistent cache).

**Puzzles without a solution** (`0:0`): the feature is skipped for those puzzles. The hint
button is disabled in `addConstraint` mode when the puzzle has no stored solution.

**Architecture**: the computation runs in a dedicated hint Isolate
(`hint_worker_io.dart` / `hint_worker_web.dart`, selected via conditional imports through
`hint_worker.dart` / `hint_worker_stub.dart`). Eventually the existing `findAMove` may move
into the same isolate.

### 3. During gameplay

When `addConstraint` mode is active and the player asks for help:

1. **Selection**: pick a constraint at random from the remaining valid constraints.
2. **Add**: attach it to the puzzle constraints, as if the puzzle had been created with this
   extra constraint. This is effectively a new, easier puzzle.
3. **Display**: the UI is updated so the player sees this new constraint, temporarily
   emphasized with `highlightColor` (same behavior as the current hint — the highlight
   disappears on next tap).
4. **Persistence**: added constraints are saved with the puzzle. It is equivalent to having
   created a different (easier) puzzle.
5. **Exhaustion**: once all valid constraints have been added, the hint button becomes
   disabled.
6. **Stats**: no impact on scoring or statistics.

### 4. Redundancy handling

When a constraint is added, it must bring new information to the player. If it is already
implied by the existing constraints (true, but doesn't help solve), it should not be proposed.

**Implementation**: after loading valid candidates, the list is shuffled. A second background
job (`hint_rank_worker_io.dart` / `hint_rank_worker_web.dart`, selected via conditional
imports) ranks candidates: it runs `applyConstraintsPropagation()` against each one and keeps
the useful ones (those that unlock at least one extra cell) at the front. Non-useful
candidates are moved to the tail of the list. Any player interaction (`tap`, `undo`, etc.)
cancels the current ranking pass and reschedules it with a 300ms debounce.

A more ambitious direction (prioritize the "most useful" constraints) is tracked in
`docs/todo.md` for future exploration.
