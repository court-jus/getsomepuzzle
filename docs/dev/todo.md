# TODO

## Solver improvements

### Hint constraint: selection strategy refinements

The `addConstraint` hint runs on demand (first hint tap) and returns the
first candidate whose addition lowers `Puzzle.traceEffort()` — enumerated
in registry order (roughly simplest type first, FM/PA before SY/LT), with
each type's parameter list shuffled. If none reduces the effort, a random
valid candidate is offered as a fallback (`pickHintConstraint` in
`lib/getsomepuzzle/hint_worker_core.dart`).

Refinements to explore:

- **Targeting.** We have no way today to know *which constraint touches
  which cell*. With it, the search could enumerate only candidates whose
  zone overlaps the player's actual blockage (the next force/complicity
  step) instead of scanning every type — cheaper and more relevant.
- **Cheaper candidate enumeration for hints.** A `forHint` flag on
  `generateAllParameters` returning a smaller, representative parameter
  set (without changing the constraints' own semantics) would bound the
  worst case (when no candidate reduces the effort and everything is
  enumerated). E.g. `MajorityConstraint.generateAllParameters` is
  O(width²·height²·|domain|) today.
- **Constraint-type simplicity.** Beyond registry order, weight by type
  simplicity so the offered constraint is the easiest to understand among
  those that reduce the effort.

### Planned: human calibration session

Run a session where the solver presents individual deduction steps to a human player who rates their difficulty (easy/medium/hard). Use this data to:
1. Classify which propagation patterns belong to which tier
2. Validate that force rounds correlate with perceived difficulty
3. Tune complexity formula weights accordingly

## Generator: equilibrium failure blacklist

`pickTarget` and `rankTargets` (`lib/getsomepuzzle/generator/equilibrium.dart`)
already accept a `blacklistedKeys` parameter, but the worker
(`worker_io.dart`) currently passes the empty set. When a target is
unreachable in practice (e.g. a complex pair on a `3x3` grid) the loop
keeps retrying until the global `maxTime` budget runs out.

**Plan:** track per-target `failureCount` in the worker. After N consecutive
failures (5 is the value used in early sketches) add the target's `key` to
a session blacklist passed to `pickTarget` so the loop falls back to the
next-deepest gap. Reset on successful generation or on warm-up.

## QOL

* Allow opening the app directly with a puzzle on Android (custom URL scheme intent-filter for `getsomepuzzle://`). Web (query string) and Linux desktop (system handler) are already wired.

## UI

* When showing that a cell can be deduced thanks to a constraint and that constraint is DF, the name of the constraint is not shown.

## Dev docs to be created

Subsystems complex enough to deserve their own page in `docs/dev/`
but currently without one (or only mentioned in passing in other
docs):

- **`verification_gate.md`** — The central invariant "a puzzle is
  valid iff `solveExplained()` completes from its readonly cells"
  deserves its own page: consequences for `verify` vs `apply`, why
  no backtracking, how the replay protects against bogus traces.
  Currently scattered across `algorithm.md`, `generator.md`, and
  `CLAUDE.md`.
- **`stats_persistence.md`** — `stats/stats.txt` format, aggregation
  by `bin/aggregate_player_stats.dart`, full lifecycle (in-app
  Stats → write → `stats.zip` backup → telemetry re-ingestion). No
  dedicated doc today.
- **`database_lifecycle.md`** — The `Database` class (loading
  `default.txt`/`tutorial.txt`/`custom.txt`, `Filters`, stats
  persistence) is central but undocumented. Could be folded into
  `playlist.md` depending on volume.
- **`post_processing.md`** — `bin/trace_score.dart`,
  `bin/filter_score.dart`, `bin/polish.dart` are mentioned in
  `generator.md` § 3 but without detail on `polish`'s mutations, the
  budgets, or the thresholds. Given their complexity they deserve
  their own page — `generator.md` would just point to it.
- **`in_app_generator.md`** — The `generate_page.dart` widget (the
  in-game generator UI) and its dedicated worker are described
  nowhere. Not to be confused with the `bin/generate.dart` CLI.
- **`workers_isolate.md`** — The native worker architecture (Isolate)
  vs web (chunked async) is mentioned in passing across several docs
  but never explained end to end. Small doc, big clarity win for
  anyone touching progress callbacks.
- **`i18n_workflow.md`** — ARB → `flutter gen-l10n` → adding a
  locale. Half a page would suffice, but it would spare every new
  contributor from rediscovering the pipeline.
- **`in_app_editor.md`** — `lib/widgets/create_page/` (the integrated
  puzzle editor) is entirely undocumented.

## Stats persistence

- [ ] **Explore Android Auto Backup** to survive APK uninstall/reinstall
  without manual user action. Required changes:
  - `android:allowBackup="true"` and a `fullBackupContent` / `dataExtractionRules`
    XML in `android/app/src/main/AndroidManifest.xml`.
  - Backup rules to include `path_provider`'s documents directory (where
    `stats.txt` and `stats_imported_*.txt` live) and the shared preferences
    XML if we eventually use it for stats.
  - Caveats to validate before shipping: 24-hour backup cooldown, requires
    Google Play services + signed-in account, no effect on emulators
    without GMS, and the user can disable cloud backup system-wide.
  - Decide whether to opt in for *all* app data (simpler) or whitelist
    only the stats subtree (safer in case we ever persist secrets).
