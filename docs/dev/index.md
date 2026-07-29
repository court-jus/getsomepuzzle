# Developer documentation — index

Entry point to `docs/dev/`. Every file below is a targeted reference:
read the relevant page before touching the corresponding subsystem.

## Overview

- [`algorithm.md`](algorithm.md) — High-level algorithmic architecture
  (puzzle format, slug table, solving loop, complexity scoring). Read
  this first.

## Puzzle generation

- [`generator.md`](generator.md) — Full pipeline: greedy
  "grid → constraints" algorithm, post-generation polish, easing loop.
- [`equilibrium.md`](equilibrium.md) — Multi-axis bias (slug, n-types,
  pair, size, profile) driving `pickTarget` at every iteration.
- [`feasibility.md`](feasibility.md) — Persistent infeasibility
  blacklist (`generator_stats.csv`) + in-session adaptive tracker.
- [`path_based.md`](path_based.md) — Pre-fill by routing for puzzles
  dominated by `LT` (topology + bipartite disambiguation).
- [`prefill_sy.md`](prefill_sy.md) — Pre-fill by symmetric island
  growth for `SY` puzzles.
- [`prefill_bb.md`](prefill_bb.md) — Pre-fill by bounding-box islands
  for `BB` puzzles.

## Solving & reasoning

- [`complexity.md`](complexity.md) — Complexity scoring (0–100):
  per-constraint weights, force-step contribution, diversity bonus.
- [`levels.md`](levels.md) — Six-tier ranking (Beginner → Mad) built
  from the type of reasoning required.
- [`hints.md`](hints.md) — The two hint modes
  (`deducibleCell` vs `addConstraint`) and how they're ranked.
- [`constraint_complicity.md`](constraint_complicity.md) —
  Cross-constraint complicity system (deductions that combine
  multiple rules) + full catalogue.
- [`grayout.md`](grayout.md) — When and how a constraint is
  considered "done" and greyed out.
- [`grayout_shape.md`](grayout_shape.md) — `SH`-specific variant.
- [`group_utilities.md`](group_utilities.md) — Shared connectivity
  helpers (`floodFill`/`canReach`, same-colour groups, merge-graph
  reachability) underpinning `GS`, `LT`, `GC`, `SY`, `CH`.

## Individual constraints

One page per non-trivial constraint (simple constraints are described
directly in the code):

- [`letter_group.md`](constraints/letter_group.md) — `LT`: cells sharing
  a letter must form one same-colour group (`I` excluded from labels).
- [`chain.md`](constraints/chain.md) — `CH`: continuous path of one-colour cells.
- [`column_count.md`](constraints/column_count.md) — `CC`: N cells of one colour
  in a given column.
- [`row_count.md`](constraints/row_count.md) — `RC`: row equivalent.
- [`transition.md`](constraints/transition.md) — `RT`/`CT`: row and column transition counts.
- [`neighbor_count.md`](constraints/neighbor_count.md) — `NC`: exact number of
  orthogonal neighbours of one colour.
- [`group_count.md`](constraints/group_count.md) — `GC`: number of connected
  groups.
- [`eyes.md`](constraints/eyes.md) — `EY`: see N cells of
  one colour from a given cell.
- [`parity.md`](constraints/parity.md) — `PA`: balanced even/odd counts on
  a side of the anchor; same-axis constraints merge per anchor.
- [`majority.md`](constraints/majority.md) — `MJ`: strict majority of one colour
  in a rectangle.
- [`implication.md`](constraints/implication.md) — `IM`: if the source cell is a
  colour, the target cell must be too (directional, with contrapositive).
- [`bounding_box.md`](constraints/bounding_box.md) — `BB`: every group of a colour
  must have a bounding box of exactly W×H (extent, not fill; global).

## Adding a new constraint

Checklist of every file to touch when introducing a new constraint
slug. Steps marked **auto** require no manual action but are listed
for completeness.

1. **Constraint class** → `lib/getsomepuzzle/constraints/<name>.dart`
   - Extend the appropriate base (`CellsCentricConstraint`,
     `LineCentricConstraint`, or `Constraint` directly).
   - Implement `slug`, `verify()`, `apply()`, `isCompleteFor()`,
     `serialize()`, `toHuman()`, `rotated()`, `conflictsWith()`
     if needed, and static `generateAllParameters()`.

2. **Engine registry** → `lib/getsomepuzzle/constraints/registry.dart`
   - Import the new class and add an entry to `constraintRegistry`
     (alphabetical order by slug).

3. **Family mapping** → `lib/getsomepuzzle/constraints/families.dart`
   - Add the slug → family entry in `kConstraintFamily`.

4. **Rotation coverage** → **auto** — `test/rotation_test.dart`
   will fail if `rotated()` is missing or broken.

5. **Constraint widget** → `lib/widgets/constraints/<name>.dart`
   - Create a widget that renders the constraint indicator. Used in
     the UI registry for previews and by `to_flutter.dart` / `puzzle.dart`
     for in-grid rendering.

6. **UI registry** → `lib/widgets/constraints/registry.dart`
   - Import the widget and add an entry to `constraintUIRegistry`
     with a `buildPreview` callback.
   - Add a `case 'XX':` to `constraintNameForSlug()` returning the
     localized name from `AppLocalizations`.

7. **Flutter bridge** → `lib/getsomepuzzle/constraints/to_flutter.dart`
   - If the constraint renders inside grid cells, add
     `if (constraint is MyConstraint) return _myWidget(...)`.

8. **Grid widget** → `lib/widgets/puzzle.dart`
   - If the constraint has a sidebar or overlay display (e.g. left-side
     bar for RC), add the rendering here.

9. **Editor switch** → `lib/widgets/create_page/create_page.dart`
   - Add `case 'XX':` to the `_pickConstraintParameters` switch.

10. **Explanation text** → `lib/widgets/new_constraint_dialog.dart`
    - Add a `case 'XX':` to `constraintExplanationForSlug()`.

11. **Localization** → `lib/l10n/app_en.arb`, `app_fr.arb`, `app_es.arb`
    - Add a `"constraint<Name>"` key for the localized display name
      (or reuse an existing one if the constraint is an alias like
      RC → `constraintLineCount`).
    - Add `"constraintExplain<Slug>"` key for help text.
    - Run `flutter gen-l10n` to regenerate bindings.

12. **Generator** → **auto** — the generator calls
    `generateAllParameters` through the registry; no manual step
    needed.

13. **Tests** → `test/<name>_test.dart`
    - Reachable-incomplete state → `verify == true`.
    - Unreachable-incomplete state → `verify == false`.
    - `apply` forces cells when remaining count matches need.
    - `apply` returns `isImpossible` on contradiction.
    - `isCompleteFor` returns `true` when satisfied.
    - `serialize` round-trips correctly.
    - `generateAllParameters` returns valid parameters.

14. **Analyze** → run `flutter analyze` and fix any issues.

Once done, add an entry to `test/constraints_test.dart` if the new
constraint introduces a novel `verify` contract pattern.

## Player & experience

- [`editor.md`](editor.md) — In-app puzzle editor (`CreatePage`): fix
  cells, attach constraints via per-slug dialogs, on-demand solver
  validation, test/save. Renders its grid through the shared
  `PuzzleGridStack`.
- [`adapt_to_player.md`](adapt_to_player.md) — Player-level inference
  and Gaussian sampling of puzzles around that level.
- [`onboarding.md`](onboarding.md) — Gradual replacement of the
  `tutorial` with a slug-by-slug intro driven by stats.
- [`playlist.md`](playlist.md) — In-memory playlist construction by
  collection type and onboarding state.
- [`puzzle_orientation.md`](puzzle_orientation.md) — Auto-rotation
  keeping the puzzle readable in portrait/landscape.
- [`timers.md`](timers.md) — When the clock runs / when it pauses.

## Tools & automation

- [`autopilot.md`](autopilot.md) — Autopilot mode (`--scenario=`)
  driving the puzzle UI from a scenario file: actions, file format,
  architecture, fake cursor overlay.
- [`keyboard_shortcuts.md`](keyboard_shortcuts.md) — Desktop keyboard
  control of an in-progress puzzle (`_handleKeyEvent` in `main.dart`).

## CLI tools & corpus

- [`collection_management.md`](collection_management.md) — Practical
  reference for the `bin/` scripts that produce, classify, audit and
  prune the collections shipped in `assets/`.

## Roadmap & releases

- [`ready_to_publish.md`](ready_to_publish.md) — Pre-submission
  checklist for Play Store / App Store.
- [`todo.md`](todo.md) — Short list of ongoing tasks.

