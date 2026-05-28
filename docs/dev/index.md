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

## Individual constraints

One page per non-trivial constraint (simple constraints are described
directly in the code):

- [`chain.md`](chain.md) — `CH`: continuous path of one-colour cells.
- [`column_count.md`](column_count.md) — `CC`: N cells of one colour
  in a given column.
- [`row_count.md`](row_count.md) — `RC`: row equivalent.
- [`transition.md`](transition.md) — `RT`/`CT`: row and column transition counts.
- [`neighbor_count.md`](neighbor_count.md) — `NC`: exact number of
  orthogonal neighbours of one colour.
- [`group_count.md`](group_count.md) — `GC`: number of connected
  groups.
- [`eyes_constraint.md`](eyes_constraint.md) — `EY`: see N cells of
  one colour from a given cell.
- [`majority.md`](majority.md) — `MJ`: strict majority of one colour
  in a rectangle.

## Player & experience

- [`adapt_to_player.md`](adapt_to_player.md) — Player-level inference
  and Gaussian sampling of puzzles around that level.
- [`onboarding.md`](onboarding.md) — Gradual replacement of the
  `tutorial` with a slug-by-slug intro driven by stats.
- [`playlist.md`](playlist.md) — In-memory playlist construction by
  collection type and onboarding state.
- [`puzzle_orientation.md`](puzzle_orientation.md) — Auto-rotation
  keeping the puzzle readable in portrait/landscape.
- [`timers.md`](timers.md) — When the clock runs / when it pauses.

## CLI tools & corpus

- [`collection_management.md`](collection_management.md) — Practical
  reference for the `bin/` scripts that produce, classify, audit and
  prune the collections shipped in `assets/`.

## Roadmap & releases

- [`ready_to_publish.md`](ready_to_publish.md) — Pre-submission
  checklist for Play Store / App Store.
- [`todo.md`](todo.md) — Short list of ongoing tasks.

