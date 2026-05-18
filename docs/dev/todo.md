# TODO

## Solver improvements

### Hint constraint: weight by constraint type simplicity

Candidates are now ranked by descending propagation delta — the
constraint that immediately unlocks the most cells is offered first,
then the rest of the useful ones by decreasing impact, then the
non-useful tail (`scoreCandidate` in
`lib/getsomepuzzle/hint_rank_worker_core.dart`). Remaining refinement:
weight by constraint type simplicity (FM/PA easier to understand than
SY/LT for most players), either as a tie-breaker when deltas are
close, or as a multiplicative factor on the raw delta.

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
