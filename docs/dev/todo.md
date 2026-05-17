# TODO

## Solver improvements

### Hint constraint: per-cell constraint contribution score

When the puzzle is already fully solvable by propagation (baseline fills all cells), current ranking reports 0 useful constraints. The button stays enabled and the player can still request a constraint — they just get one from the non-useful tail (a redundant constraint, picked first-come-first-served from the shuffled list).

**Idea:** For each empty cell, trace which constraints participate in its resolution during propagation. A constraint that contributes to resolving many cells is "broadly helpful". A cell that is only resolved through a long chain of deductions could benefit from a more direct constraint. This would replace the random tail-pick with something targeted.

**Challenge:** Propagation is a chain — constraint A deduces cell X, which enables constraint B to deduce cell Y. Attributing credit requires tracing the dependency graph of the propagation loop. This would require modifying `applyConstraintsPropagation()` to record which constraint resolved each cell, then building a dependency graph to compute per-constraint contribution scores.

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

* Allow sharing a puzzle, from scratch or from its current state: need a fix for the web app that is very slow when opening a shared puzzle.

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
