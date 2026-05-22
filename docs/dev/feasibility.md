# Infeasibility Blacklist and Attempt Telemetry

The CLI generator (`bin/generate.dart`) records every generation attempt —
success or failure — to `generator_stats.csv` and uses that log to skip
parameter combinations that have proved structurally impossible across
previous runs. This document describes the `AttemptKey` granularity, the CSV
schema, the hybrid blacklist mechanism, and the CLI flags that control it.

Implementation lives in:
- `lib/getsomepuzzle/generator/feasibility.dart` — `AttemptKey`,
  `bucketForArea`, `InfeasibilityTracker`, `readPersistentBlacklist`
- `lib/getsomepuzzle/generator/messages.dart` — `GeneratorAttemptMessage`
- `lib/getsomepuzzle/generator/worker_io.dart` — emission, skip logic,
  `_resolveScenario`
- `bin/generate.dart` — CSV writer helpers (`_statsRow`, `_statsHeader`,
  `_csvField`, `_readCommitHash`), CLI flag parsing, `statsChain`
  serialization

## Motivation

The equilibrium picker can target combinations like `ntypes=1 + slugs={CH}`
that are structurally impossible — CH alone is too weak to force a unique
solution on any grid that fits the size budget. Without detection, the worker
burns through its entire `maxTime` budget retrying the same dead-end.

Detecting this statically from solver properties is impractical for every
possible tuple. Instead, the system learns from empirical failure evidence:
a combo that has been tried many times and never succeeded is treated as
infeasible for the rest of the run, and for subsequent runs too via the CSV.

## Attempt Identity — `AttemptKey`

Two attempts share the same `AttemptKey` when they ask the generator for an
identical task. The key is a 4-tuple:

| Field | Source | Example |
|---|---|---|
| `targetKey` | `Target.key` — the equilibrium axis being pushed | `slug:SY`, `ntypes:3`, `pair:CH+SY`, `profile:pathBased`, `size:10x8`; `'none'` when no target was picked |
| `sortedSlugs` | `preferredSlugs.toList()..sort()` | `['PA', 'QA', 'SY']` |
| `scenario` | Result of `_resolveScenario` | `classic`, `sh`, `pathBased`, `syBased` |
| `sizeBucket` | `bucketForArea(w, h)` | `≤20`, `21-40`, `41-80`, `>80` |

**Why sort slugs?** `{CH, SY}` and `{SY, CH}` describe the same task. Sorting
canonicalizes the set so both map to the same key.

**Why a size bucket rather than exact dimensions?** A combo may be infeasible
only at small grids (e.g. CH needs enough room) while feasible at large ones.
Collapsing exact sizes into four coarse buckets lets the blacklist distinguish
"CH infeasible at ≤20 cells" from "CH feasible at 41–80 cells" without
exploding the key space. The same four buckets are used by `_CollectionStats`
in `bin/generate.dart` and by the dashboard, so all three views stay
consistent.

**Serialized form:** `targetKey|sortedSlugs.join(',')|scenario|sizeBucket`.
Pipe-separated so the inner slug join (comma-separated) nests cleanly.

Example:
```
slug:SY|PA,QA,SY|classic|21-40
ntypes:1|CH|classic|≤20
pair:CH+SY|CH,SY|classic|41-80
none||pathBased|>80
```

## `generator_stats.csv` Schema

One row per attempt, appended at the end of every iteration of the worker's
main loop. The file is opened in `FileMode.append` so re-runs accumulate;
the header row is written only on first creation (detected by checking
`statsFile.existsSync()` before opening).

```
date, commit, worker, phase, target_key, width, height, ntypes_intended,
preferred_slugs, allowed_slugs, scenario, outcome, reason, duration_ms,
level, puzzle_line
```

**Column details:**

| Column | Type | Description |
|---|---|---|
| `date` | ISO-8601 UTC | `DateTime.now().toUtc().toIso8601String()` at write time |
| `commit` | string | Short HEAD hash from `git rev-parse --short HEAD`; `'unknown'` outside a git checkout. Same value on every row of a given CLI run. |
| `worker` | int | Zero-based worker index |
| `phase` | `warmup` / `equilibrium` / `fixed` | Derived from `inWarmup` and whether `targetKey` is non-empty |
| `target_key` | string | `Target.key` or empty when no target (warmup, balanced, or equilibrium disabled) |
| `width` | int | Grid width for the attempt |
| `height` | int | Grid height for the attempt |
| `ntypes_intended` | int or empty | `target.n` for `NTypesTarget`; `preferredSlugs.length` for a soft cap; empty when no slug preference active |
| `preferred_slugs` | pipe-joined | `preferredSlugs.join('|')` — avoids CSV quoting conflicts with the comma-delimited format |
| `allowed_slugs` | pipe-joined | `allowedSlugs.join('|')`; empty when the universe is unrestricted |
| `scenario` | string | `classic`, `sh`, `pathBased`, or `syBased` |
| `outcome` | `success` / `failure` | Whether `generateOne` returned a puzzle |
| `reason` | string | `GenerationRejectReason.name` on failure; `'unknown'` when an exception was caught; empty on success |
| `duration_ms` | int | Wall-clock milliseconds for the attempt |
| `level` | string | `PuzzleLevel.name` on success; empty on failure |
| `puzzle_line` | string | Full v2 puzzle line on success (allows joining with `puzzle_vectors.csv` via canonical key); empty on failure. Only column that can contain commas — wrapped in `"…"` by `_csvField` when needed |

**Column count invariant.** Columns 0–14 (before `puzzle_line`) are guaranteed
to contain no commas or newlines in practice: slugs use `|` as separator,
`target_key` values use `:` and `+`, scenarios and outcomes are word-like. This
property is relied on by `readPersistentBlacklist`, which parses only the first
12 columns using a naive `split(',')` and ignores `puzzle_line`.

**Write serialization.** Multiple workers share the same `statsSink`. The CLI
serializes writes through a `statsChain` Future (in `bin/generate.dart`) so
concurrent `writeln + flush` pairs never interleave on the same `IOSink`.

**`.gitignore`.** `generator_stats.csv` is listed in `.gitignore` so the
telemetry file is not committed to the repository.

### Example rows

```
2026-05-22T14:30:01.123Z,a1b2c3d,0,equilibrium,slug:SY,8,6,3,PA|QA|SY,,classic,success,,842,advanced,"v2_12_8x6_…"
2026-05-22T14:30:02.005Z,a1b2c3d,1,equilibrium,ntypes:1,4,4,1,CH,,classic,failure,notUnique,3201,,
2026-05-22T14:30:02.500Z,a1b2c3d,0,warmup,,,6,5,2,PA|SY,,classic,success,,310,player,"v2_12_6x5_…"
```

## Hybrid Blacklist Mechanism

The blacklist operates at two layers that share the same `AttemptKey`
vocabulary and are checked in union before every attempt.

### Layer 1 — Persistent CSV seed

`readPersistentBlacklist(csvPath, minAttempts)` (in `feasibility.dart`) reads
`generator_stats.csv`, aggregates by `AttemptKey`, and returns the set of
serialized keys where `attempts >= minAttempts && successes == 0`. This set
represents historical evidence: the generator has tried the combo many times
across past runs and never succeeded.

The CLI loads this set once at startup and prints a diagnostic line to stderr
when the seed is non-empty:

```
Blacklist seed: 4 infeasible combo(s) loaded from generator_stats.csv (>=30 tries, 0 success)
```

The set is distributed as `List<String>` to every worker via
`_IsolateParams.seedBlacklist`. Inside the isolate it is converted to a
`Set<String>` for O(1) lookup.

### Layer 2 — In-session adaptive tracking

Each worker owns an `InfeasibilityTracker`, a `Map<String, _ComboStats>` where
`_ComboStats` holds `{attempts, successes}`. After every `generateOne` call
— regardless of outcome — the worker calls:

```dart
tracker.record(attemptKey, success: result != null);
```

A combo is locally blacklisted when `attempts >= adaptiveK && successes == 0`.

The adaptive tracker is per-worker and per-run. It accumulates fresh evidence
within the current CLI execution independently of the CSV seed, which is frozen
at startup.

### Skip decision

Just before the worker sends the `'target'` event for an attempt:

```
attemptKey = AttemptKey(targetKey, sortedSlugs, scenario, sizeBucket)
blacklisted = seedSet.contains(attemptKey.serialized)
              || tracker.isBlacklisted(attemptKey, kThreshold: adaptiveK)

if blacklisted && consecutiveSkips < skipSafety:
  consecutiveSkips++
  log('skip blacklisted combo: …')
  continue          // no 'target', no 'attempt', no CSV row
else if blacklisted:
  log('skip safety triggered — running anyway')
  // fall through and run the attempt

consecutiveSkips = 0
sendPort.send({'type': 'target', …})
```

A skipped iteration has no observable effect on the dashboard (no attempt
counter update, no target label change) and no CSV row. The worker log
records every skip for post-run diagnosis.

### Safety brake

`consecutiveSkips` is reset to zero whenever a non-blacklisted attempt runs.
When it reaches `skipSafety` (default 100), the next blacklisted combo is
allowed through with a warning logged. This prevents a deadlock if every
candidate tuple in the worker's current parameter space has been blacklisted —
for example, after a large number of prior runs that exhausted all combos in a
small configuration.

### Worked example

Suppose `adaptiveK = 3` (illustrative low value) and a worker repeatedly
resolves to `{targetKey='ntypes:1', sortedSlugs=['CH'], scenario='classic',
sizeBucket='≤20'}`:

| Attempt | Outcome | tracker state | Blacklisted? |
|---|---|---|---|
| 1 | failure | `attempts=1, successes=0` | No |
| 2 | failure | `attempts=2, successes=0` | No |
| 3 | failure | `attempts=3, successes=0` | Yes — `3 >= 3 && 0 == 0` |
| 4 | (skipped) | unchanged | — |
| 5 | (skipped) | unchanged | — |

After the skip, the equilibrium picker rolls new slugs or a different target.
If it happens to resolve to the same key again, the skip fires again until
`skipSafety` consecutive skips release it.

## CLI Flags

All flags are in `bin/generate.dart`.

| Flag | Default | Description |
|---|---|---|
| `--no-blacklist` | off | Disables both the CSV seed and the adaptive tracker. Use after a solver fix to give a previously-infeasible combo a fresh chance, or to bypass the filter during debugging. |
| `--blacklist-min-attempts N` | 30 | Minimum number of historical failures (with zero successes) required before a combo enters the CSV seed. Higher values reduce false positives; lower values detect infeasibility earlier. |
| `--blacklist-adaptive-k N` | 20 | In-session failure threshold per worker. A combo is locally blacklisted once `attempts >= N && successes == 0` within the current run. |
| `--blacklist-skip-safety N` | 100 | Consecutive skips tolerated before the safety brake releases the next blacklisted combo. Set lower to get faster detection of a fully-blacklisted parameter space; set higher for more aggressive filtering. |

## Stale-positive caveat

If a combo was marked infeasible in the CSV and the user later fixes the solver,
the CSV still holds the old failure rows. The combo will continue to be seeded
into the blacklist until enough successes accumulate to bring `successes > 0`.

Two workarounds:

1. Run once with `--no-blacklist` — the adaptive tracker starts fresh, and on
   success the new rows will have `outcome=success`. On the *next* run the CSV
   seed re-reads all rows including the successes and the combo will no longer
   be in the seed set.
2. Delete `generator_stats.csv` to reset all persistent learning.

## In-App Generator

`lib/widgets/generate_page.dart` handles `GeneratorAttemptMessage` with a
no-op case — the CSV writer is wired only in `bin/generate.dart`. The
`worker_web.dart` and `worker_stub.dart` platforms never emit attempt messages.
The infeasibility tracker and seed blacklist are also absent from the web/stub
workers (`_IsolateParams` and its blacklist fields only exist in
`worker_io.dart`).
