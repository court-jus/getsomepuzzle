# Collection management

Practical reference for the CLI tooling that produces, classifies, audits
and prunes the puzzle collections shipped in `assets/`. Each tool here is
a single-purpose Dart script with a clear `--help` of its own; this doc
explains *when* to reach for which one, how they chain together, and
records design decisions about the corpus as a whole.

## Collections

| File                          | Role                                                              |
|-------------------------------|-------------------------------------------------------------------|
| `assets/1-easy.txt`           | Beginner — trivial saturation, single-constraint deductions       |
| `assets/2-player.txt`         | Player — harder propagation, no force, no complicity              |
| `assets/3-advanced.txt`       | Advanced — simple complicities (tier ≤ 3)                         |
| `assets/4-strong.txt`         | Strong — complex complicities (tier ≥ 4), no force                |
| `assets/5-expert.txt`         | Expert — exactly 1 force round, depth ≤ 5                         |
| `assets/6-mad.txt`            | Mad — ≥ 2 force rounds or depth > 5                               |
| `assets/1-easy-overfilled.txt`     | Beginner-by-trace puzzles whose prefill ratio > 30 %         |
| `assets/2-player-overfilled.txt`   | Player-by-trace, prefill > 30 %                              |
| `assets/3-advanced-overfilled.txt` | Advanced-by-trace, prefill > 30 %                            |
| `assets/4-strong-overfilled.txt`   | Strong-by-trace, prefill > 30 %                              |
| `assets/5-expert-overfilled.txt`   | Expert-by-trace, prefill > 30 %                              |
| `assets/6-mad-overfilled.txt`      | Mad-by-trace, prefill > 30 %                                 |
| `assets/overfilled.txt`            | Legacy bucket (pre-split); redistributed by `--route`        |

Routing is by `classifyTrace` (`lib/getsomepuzzle/level.dart`), not by
declared slugs. See `levels.md` for the cascade.

## Tool index

| Tool                                  | Purpose                                                      |
|---------------------------------------|--------------------------------------------------------------|
| `bin/generate.dart`                   | Generate new puzzles, validate / re-validate existing ones   |
| `bin/maintain.dart`                   | Full periodic-maintenance pipeline (6 steps, apply mode)     |
| `bin/recompute.dart`                  | Re-sort constraints, refresh stored cplx, re-route by level; writes `solve_traces.tsv` |
| `bin/dedup_puzzles.dart`              | Drop puzzles that are exact duplicates (canonical key match) |
| `bin/cleanup_collections.dart`        | Drop disliked / trivial-FM-dominated / MJ-border-conflict / regular-pattern puzzles |
| `bin/vectorize_puzzles.dart`          | Produce per-puzzle feature vector CSV (reads `solve_traces.tsv`; thin driver over `lib/getsomepuzzle/vector.dart`) |
| `bin/cluster_puzzles.dart`            | Near-duplicate pairs/clusters (cluster) or FPS prune-to-count recycle (report or `--apply` mode) |
| `bin/extract_onboarding.dart`         | Build a diverse onboarding bank from 1-easy                  |
| `bin/classify_difficulty.dart`        | Classify each puzzle into the level cascade (reads `solve_traces.tsv`) |
| `bin/aggregate_player_stats.dart`     | Merge per-player stats files, dedup, refresh cplx            |
| `bin/analyze_stats.dart`              | OLS regression on log(duration), per-bucket stats            |
| `bin/remark_scenarios.dart`           | Tag legacy v2 lines with `_scenario:<name>` (reads `solve_traces.tsv`) |
| `bin/trace_score.dart`                | Score puzzles by trace quality (reads `solve_traces.tsv`)    |
| `bin/query_corpus.dart`               | Ad-hoc filtered queries over `assets/*.txt` (read-only)      |
| `bin/plot_vectors.py`                 | 2-D PCA projection + supervised separability of the vectors (matplotlib + numpy) |
| `bin/detect_regular_solutions.dart`   | Diagnose globally-regular solutions (damier / colour bars) over-rated by the trace (read-only report + optional CSV) |
| `bin/find_single_path_puzzles.dart`   | Filter puzzles that have a unique deduction path (exactly one move at every step) — no branching, no backtracking needed |
| `bin/pilot_recycle.dart`              | Pilot: does `Puzzle.simplify()` convert mad puzzles into advanced/strong, and at what cost? (see "Collection orchestrator and puzzle recycling") |
| `bin/pilot_readonly.dart`             | Pilot: does fixing readonly cells (instead of adding constraints) convert mad puzzles into advanced/strong, and is there prefill headroom? Thin sampler/reporter over `lib/getsomepuzzle/recycle.dart` |
| `bin/experiment_landing.dart`         | Landing experiment: can readonly-easing deliberately land a mad puzzle in a specific level (player/expert/strong)? Uses `recycle.dart`'s `targetLevel` objective (see "Collection orchestrator and puzzle recycling") |
| `bin/recycle_mad.dart`                | Recycling step: ease a mad-overflow feed into the deficient collections via target-level readonly-easing; routes landed lines by final level and consumes them from the feed (see "Collection orchestrator and puzzle recycling") |
| `bin/balance_collections.dart`        | Orchestrator: endless generate→recycle→recycle_mad loop toward a common target size; full `maintain` on a cadence (see "Collection orchestrator and puzzle recycling") |

## Generation

### Make new puzzles

```bash
# Generate 1000 puzzles, write to a side file, default range and equilibrium.
dart run bin/generate.dart -n 1000 -o new.txt
```

The equilibrium engine
(`lib/getsomepuzzle/generator/equilibrium.dart`, see `equilibrium.md`)
picks each puzzle's target slug / ntypes / pair / size from the most
under-represented bin in the existing corpus.

### Validate an existing file

`--check` runs the in-game solver on every puzzle: a puzzle is "valid"
iff `solve()` reaches the unique completion via propagation + force
(no backtracking). Valid lines are written to `<file>.good.txt`, invalid
to `<file>.bad.txt`.

```bash
dart run bin/generate.dart --check assets/1-easy.txt
```

`--check-detailed` adds a categorical breakdown for each rejection
(`UNSOLVABLE` / `NON-UNIQUE` / `NEEDS-BACKTRACK`) plus a `CACHED MISMATCH`
check on accepted puzzles (the v2 line's `_1:xxx` solution field doesn't
match what the deductive solver finds). The detailed pass runs a
brute-force backtracking enumeration on each reject, so it's
exponentially slower on big-grid puzzles — use when investigating
suspicious rejects, not for routine cleanup.

```bash
dart run bin/generate.dart --check-detailed assets/1-easy.txt
```

## Recompute and route

`bin/recompute.dart` re-derives metadata that drifts when the solver,
the complexity formula, or the constraint sort changes:

```bash
# Re-sort constraints, refresh cached cplx and solution in field 6/5.
# Writes <file>.new for diff review.
dart run bin/recompute.dart assets/1-easy.txt
```

`--route` redistributes puzzles into `<dest>.tmp` files matching
their post-sort classification. Two modes:

* **No positional args** — sources are the six playable-level files
  plus the two out-of-cascade buckets (`overfilled*`). Any puzzle
  whose `classifyTrace` changed lands in its new home; nothing is
  duplicated or lost.

  ```bash
  dart run bin/recompute.dart --route
  ```

* **With positional args** — those files are used as the feed
  instead of the level files. Useful to ventilate an unsorted feed
  (e.g. a fresh `/tmp/path6.txt` produced by an experimental
  generator) into the existing cascade. The existing destination
  content is **preserved**: each touched destination's current content
  is seeded into its `.tmp` before the feed is appended, so the final
  rename adds the feed to the corpus rather than replacing it. Feed
  puzzles already present (by `canonicalPuzzleKey`) are deduped and
  skipped, so re-running the same feed is a no-op. The feed's own
  verbatim noise (blanks, comments, parse failures) is dropped
  silently — the feed is an input, not a destination we mirror.

  ```bash
  dart run bin/recompute.dart --route /tmp/path6.txt
  ```

Both modes accumulate output into `<dest>.tmp` (append mode,
idempotent via `canonicalPuzzleKey`) and rename each `.tmp` →
original in-place at the very end, once all writes have succeeded.
An interrupted `--route` leaves `.tmp` files on disk; simply
re-launch to resume — already-processed puzzles are skipped.

`--dry-run` reports the level transitions without writing any file —
useful to see how a new complexity tweak would shift the cascade
before committing to it.

## Solve trace cache (`solve_traces.tsv`)

Running `solveExplained()` is the most expensive operation in the maintenance
pipeline — it is called once per puzzle per tool, adding up to 6× per full
`bin/maintain.dart` run. `solve_traces.tsv` is a local sidecar file that
caches the post-sort solving trace of every puzzle so that all consumer tools
can skip the solver entirely.

### Format

Tab-separated, three columns, no header:

```
puzzle_hash<TAB>canonical_key<TAB>trace
```

* **`puzzle_hash`** — FNV-1a 32-bit hash (7 base-36 chars) of
  `domain_dims_prefill_sortedConstraints`. Changes automatically when the
  puzzle identity or constraint set changes, invalidating the cached trace.
* **`canonical_key`** — human-readable label (the `canonicalPuzzleKey` of the
  post-sort v2 line). Not used for lookup; kept for debugging.
* **`trace`** — semicolon-separated steps. Each step:
  `type|cellIdx|val|tier|cp|fd|constraint`  
  where `type ∈ {S, R, s, r}` (uppercase = propagation, lowercase = force;
  S/s = SetValue, R/r = RemoveOption).

### Writer: `bin/recompute.dart`

`recompute` is the **only** writer of `solve_traces.tsv`. After sorting a
puzzle's constraints it computes the hash and either reads the cached trace
(cache hit → second `solveExplained()` skipped) or runs the solver and stores
the result. The file is saved atomically once per run.

### Consumers (read-only)

`bin/vectorize_puzzles.dart`, `bin/cleanup_collections.dart` (`--boring`),
`bin/classify_difficulty.dart`, `bin/remark_scenarios.dart`,
`bin/trace_score.dart`, and `bin/dedup_puzzles.dart` all read the cache at
startup. On a cache hit, `solveExplained()` is skipped entirely. On a miss
they fall back to solving (except `dedup_puzzles.dart`, which trusts that
`recompute` ran first and keeps the line verbatim with a warning).

### Lifecycle

The file is gitignored. Delete it to force a full re-solve:

```bash
rm -f solve_traces.tsv
dart run bin/recompute.dart assets/*.txt   # repopulate
```

After a code change that alters the solver or complexity formula, deleting
the cache ensures fresh traces. The hash-based invalidation handles
per-puzzle identity changes automatically, but does **not** detect global
formula changes — those require a manual `rm`.

## Pruning the corpus

The cleanup pipeline has three layers, each independent.

### 1. Drop exact duplicates

`bin/dedup_puzzles.dart` drops lines whose `canonicalPuzzleKey`
matches a previously-seen puzzle (rotation-invariant, constraint-set
canonicalised). Catches reruns of the generator that hit the same
identity.

```bash
# In-place (default — overwrites the file directly)
dart run bin/dedup_puzzles.dart assets/1-easy.txt

# Explicit output path (preserves the original)
dart run bin/dedup_puzzles.dart -o deduped.txt assets/1-easy.txt
```

### 2. Drop disliked, trivial-FM-dominated, MJ-border-conflict, or regular-pattern puzzles

`bin/cleanup_collections.dart` runs four passes (each gated by
its own flag, all run when none is passed):

* `--disliked` — cross-reference `stats_aggregated/*.txt` and flag
  puzzles that appear with a `__D` (disliked) marker.
* `--boring` — solve each puzzle, flag those where ≥ 90 % of moves
  are deduced by 1×2 / 2×1 FM constraints (the trivial-saturation
  variants, weight 0 in `complexity.md`). 1-easy and 1-easy-overfilled
  are exempt — the trivial saturation is *the lesson* there.
* `--mj-conflict` — flag puzzles with two Majority (MJ) zones whose
  dashed borders would overlap visually (a shared flush edge with
  overlapping perpendicular extent — see `MajorityConstraint.conflictsWith`
  and `majority.md`). Cheap pre-filter (≥ 2 `MJ:` tokens) gates the parse.
  The generator already refuses such pairs, so this only catches legacy
  corpus puzzles.
* `--regular-patterns` — flag puzzles whose solved grid is a globally-regular
  geometry the local trace over-rates, using the designer-confirmed predicates
  (working doc §6.1/§8.1): a perfect damier (`checker_block_k > 0`) or colour
  bars (one axis fully constant, `period_x == 1 || period_y == 1`). These are
  exact structural predicates — unlike an `auto_band` magnitude threshold they
  never flag low-ink / sparse solutions. Reads `checker_block_k` / `period_x` /
  `period_y` from `puzzle_vectors.csv` (`--vectors-file`); skips silently if the
  file or those columns are absent. Of the flagged puzzles only a random
  `--keep-ratio` (default 0.1) is kept — selection seeded by `--random-seed`
  for reproducibility.

```bash
# Dry-run report
dart run bin/cleanup_collections.dart -v

# Apply — overwrites each modified collection in-place
dart run bin/cleanup_collections.dart --apply
```

### 3. Drop near-duplicate puzzles via vector clustering

The most expensive but most effective pass. It works on the CSV
produced by `bin/vectorize_puzzles.dart` so the heavy solver work
runs once.

```bash
# Build the per-puzzle vector (≈ 20-30 min full corpus).
dart run bin/vectorize_puzzles.dart

# Report mode — Top-K closest pairs, no writes.
dart run bin/cluster_puzzles.dart --top-k 3000 --output similar_pairs.txt

# Apply mode — collect all pairs ≤ ε, cluster, keep N representatives
# per cluster via farthest-point sampling. Onboarding puzzles can be
# protected with --protect-from so they never get dropped.
dart run bin/extract_onboarding.dart
dart run bin/cluster_puzzles.dart \
  --apply --max-distance 0.15 --keep-per-cluster 1 \
  --protect-from assets/1-easy_onboarding.txt \
  --output apply_report.txt -v
```

The vector includes 78 trace-share columns (`share_<slug>_t<tier>`
for the 13 slugs × 6 complexity tiers) plus complexity, force_rounds,
max_force_depth, avg_move_complexity, distinct_constraints_used,
n_constraints, cells, and prefill_ratio. It also carries 13
solution-geometry columns — the geometry of the solved grid, so
globally-regular solutions (damier, colour bars) the trace shares cannot
tell apart become separable. Eight are translation- and colour-swap-invariant
transforms: five from the power spectrum |F(u,v)|² (`spec_peak_frac`,
`spec_xbars_frac`, `spec_ybars_frac`, `spec_checker_frac`,
`spec_concentration`) and three from its parity-robust autocorrelation dual
(`auto_band`, `auto_checker`, `auto_tile`), which catch a 2×2 damier even
on odd block counts (4×6, 6×6) where the fixed Nyquist spectral bin
collapses. Five are interpretable scalars (the designer-confirmed predicates):
`period_x` / `period_y` (smallest translation period per axis — period 1 = a
fully constant axis ⇒ colour bars), `checker_block_k` (smallest k for a k×k
alternating damier, 0 if none), `n_symmetries` (dihedral invariances), and
`rle_ratio` (run density, a low-ink proxy). All thirteen are defined in
`bin/_solution_geometry.dart`. Z-scored across the pool, clipped at ±5.

The clustering empirically concentrates on `1-easy.txt` (~10 % at
ε = 0.3) and `1-easy-overfilled.txt` (~5 %), with NC-only and
FM-only puzzles dominating the dropped clusters — see the
"Why redundancy concentrates in the easy tier" section below.

### 4. Recycle over-full collections (FPS prune-to-count)

`cluster_puzzles.dart --mode recycle` implements the collection
orchestrator's "too similar" = farthest-point-sampling prune-to-count
decision (see "Collection orchestrator and puzzle recycling"): it needs
**no ε threshold**, so it works uniformly on the easy tier *and* on
6-mad, where near-duplicate ε-clustering finds almost nothing.

For each collection with more than `--target-count` puzzles (default
20 000), the tool keeps the `--target-count` **most-diverse** puzzles in
place (farthest-point sampling on the per-collection z-scored vector,
`--protect-from` keys as forced seeds) and **moves** the excess to
`<file>-recycled.txt` — e.g. `assets/6-mad-recycled.txt`, which is the
default feed of `bin/recycle_mad.dart`. The move is idempotent: the
collection is rewritten in place and the recycled feed is *appended*,
deduped by canonical key, so a partially-consumed feed is never lost or
duplicated across runs. Default scope is the six playable level files
(the overfilled buckets stay out).

```bash
# Dry-run report (what would move, no writes)
dart run bin/cluster_puzzles.dart --mode recycle -v

# Apply — prune the six playable collections down to 20k each, moving the
# excess of 6-mad into assets/6-mad-recycled.txt
dart run bin/cluster_puzzles.dart --mode recycle --apply -v
```

## Onboarding bank

`bin/extract_onboarding.dart` builds a diverse pool of puzzles for
each `OnboardingPhase` (see `onboarding.md`):

```bash
dart run bin/extract_onboarding.dart \
  --per-phase 300 \
  --output assets/1-easy_onboarding.txt -v
```

The script reads `OnboardingPhase.phases` for the 6 strict phases
(FM → NC → PA → CC → RC → GS), then derives 7 synthetic phases for
the remaining slugs (LT, QA, SY, DF, SH, GC, EY) with
`allowed = baseline ∪ {newSlug}`. For each phase it filters
eligible puzzles from 1-easy.txt and farthest-point-samples N of
them so the player sees varied examples of each freshly-introduced
constraint.

## Querying the corpus

`bin/query_corpus.dart` is a read-only ad-hoc query tool over the on-disk
`assets/*.txt` files. It parses every v2 line, applies cumulative filters,
and prints an aggregate table grouped by the axis of your choice. Useful
when you want a quick answer like *« how many mono-slug puzzles are
there, and which slugs dominate? »* without writing one-off `awk`.

```bash
# Mono-slug puzzles per slug across the six difficulty files.
dart run bin/query_corpus.dart --ntypes 1

# Distribution of ntypes among puzzles that contain CH but not SH.
dart run bin/query_corpus.dart --include-slug CH --exclude-slug SH \
    --group-by ntypes

# Where does mono-FM thrive? Group by grid size, sort by key.
dart run bin/query_corpus.dart --ntypes 1 --include-slug FM \
    --group-by size --sort key
```

Filters compose with **AND** (e.g. `--include-slug FM --exclude-slug PA`
keeps puzzles that have FM but no PA). `--include-slug` is repeatable
(all must be present); `--exclude-slug` is repeatable (none may be
present). `--width`, `--height`, `--min-area`, `--max-area` constrain
the grid dimensions.

`--in` selects the collections to scan. Three keywords are recognised:

| Keyword       | Meaning                                                         |
|---------------|-----------------------------------------------------------------|
| `published`   | The six difficulty files (default).                             |
| `rejects`     | `cancelled`, `noCandidates`, `notUnique`, `overfilled[-easy]`, `ratioTooHigh`. |
| `all`         | Both groups concatenated.                                       |

Explicit file paths also work and can be mixed with keywords:
`--in published --in path/to/extra.txt`.

`--group-by` accepts `slug` (default), `ntypes`, `size`, `scenario`,
`collection`, `composition`. Note that `slug` grouping counts puzzle
coverage — a multi-slug puzzle contributes once per slug — so the per-row
share can sum to more than 100 % (the script prints a reminder when this
happens). Other axes are exclusive: one puzzle, one row. The `size` axis is
orientation-agnostic (`4x5` and `5x4` collapse to a single `4x5` bin),
matching the generator's equilibrium size axis (`canonicalSize` in
`equilibrium.dart`, see `equilibrium.md`). The `composition` axis groups
by the ordered top-3 family triple (e.g. `path+line-centric+local`), using
the same instance-count ranking as `compositionOf` in `families.dart` and
the generator's equilibrium `CompositionTarget`. See `families.md`.

```bash
# Which composition triples are most/least populated?
dart run bin/query_corpus.dart --group-by composition --sort count
dart run bin/query_corpus.dart --group-by composition --reverse --top 20

# Composition vs. difficulty level — where does each triple land?
dart run bin/query_corpus.dart --cross composition,collection

# Focused puzzles: how many span only one family?
dart run bin/query_corpus.dart --group-by composition --ntypes 1

# Composition in the buckets view: joint audit with slug-set and size
dart run bin/query_corpus.dart --buckets size,slugs,composition
```

### Cross-tabulation (two axes)

`--cross AXIS1,AXIS2` swaps the 1-D table for a two-entry matrix: `AXIS1`
on rows, `AXIS2` on columns (same axis names as `--group-by`; the two may
be equal). It is mutually exclusive with `--group-by`. Each cell shows the
count and its share of the **row** total, with a `total` margin on the
right (per row), a `total` row at the bottom (per column), and a grand
total in the corner. `--sort count` (default) orders rows and columns by
their marginal total; `--sort key` orders both alphanumerically. `--top N`
keeps the N largest rows **and** N largest columns (a note flags the
truncation; the margins then cover only the displayed cells). `--reverse`
flips the order — combined with `--top` it surfaces the *bottom* of the
ranking, e.g. the least-represented slug pairs.

```bash
# Which slugs dominate each difficulty file?
dart run bin/query_corpus.dart --cross slug,collection

# Slug co-occurrence among two-slug puzzles (symmetric matrix; the
# diagonal is the per-slug coverage).
dart run bin/query_corpus.dart --cross slug,slug --ntypes 2
```

When either axis is `slug`, the same coverage caveat applies — a
multi-slug puzzle lands in several cells, so the grand total can exceed
the filtered-puzzle count (the script prints a reminder).

### Joint buckets (variety audit)

`--buckets [DIMS]` lists every distinct **joint** category present in the
filtered corpus, with its population — not the independent marginals that
`equilibrium.dart` steers on (see `equilibrium.md`), but their full
Cartesian product. `DIMS` is a comma list over `{size, ntypes, slugs,
scenario}` (default `size,slugs,scenario`); `slugs` is the whole sorted
constraint set as **one atomic key** (e.g. `slugs=CC,DF,EY,FM,GS`), so
two puzzles share a bucket only when their size, full slug-set and
scenario all match. It is mutually exclusive with `--group-by`/`--cross`.

This is the lens for variety regressions the marginals hide. Because the
equilibrium picker biases each axis independently, a freshly-added
constraint can get over-targeted on its own axis and end up glued onto
every large puzzle — so the slug *marginals* look balanced while the
*joint* distribution collapses onto a handful of "everything-but-the-
kitchen-sink" slug-sets repeated across sizes.

```bash
# Most over-populated (size, slug-set, scenario) tuples.
dart run bin/query_corpus.dart --buckets --top 20

# Rarest joint buckets — the long tail equilibrium under-produces.
dart run bin/query_corpus.dart --buckets --reverse --top 20

# How many distinct slug-sets exist among puzzles carrying every new
# constraint? Narrow with filters, then inspect the bucket list.
dart run bin/query_corpus.dart --buckets slugs \
    --include-slug MJ --include-slug CH --include-slug RT --include-slug CT
```

Each puzzle lands in exactly one bucket, so shares sum to 100 %. The
header line reports the number of distinct buckets.

The script never writes to disk and emits nothing to `stdout` other than
the table; warnings (missing files, parse errors) go to `stderr`.

## Single-path puzzles

`bin/find_single_path_puzzles.dart` filters a collection down to puzzles that
have a **single deduction path**: at every step of the solving loop there is
exactly one available move. These puzzles are uniquely determined by propagation
alone — no player needs to consider alternative options, and no branching occurs
in the solver.

```bash
# Default: reads assets/2-player.txt, writes single_path_puzzles.txt
dart run bin/find_single_path_puzzles.dart

# Custom source and destination
dart run bin/find_single_path_puzzles.dart -i assets/3-advanced.txt -o single_path.txt

# Verbose: print a KEPT / REJECTED line per puzzle with the rejection reason
dart run bin/find_single_path_puzzles.dart -i assets/2-player.txt --verbose
```

The script uses `Puzzle.findAllMoves()` at each step and rejects any puzzle
where more than one move is available, or where no move exists before completion
(stuck), or where a contradiction is reached. After exhausting the path it
verifies every constraint via `verify()` on the completed grid so constraints
that only fire at completion (e.g. `QA`, `GC`) are not silently missed.

Rejection reasons are collected and printed as a breakdown table at the end.
Progress is emitted on `stderr`; results go to the output file.

**Typical uses:**

- Build a curated study set where the logic is purely linear — no "what-if"
  enumeration required from the player.
- Audit whether a newly introduced constraint type tends to produce
  single-path or branching puzzles.

## Visual diagnostics

```bash
# 2D PCA scatter, colored by source collection.
python3 bin/plot_vectors.py

# Same data, colored by dominant slug in the trace.
python3 bin/plot_vectors.py --color-by dominant_slug -o puzzle_pca_slugs.png

# Continuous gradient on complexity.
python3 bin/plot_vectors.py --color-by complexity -o puzzle_pca_cplx.png

# Highlight a sub-population: by constraint (regex on canonical_key) …
python3 bin/plot_vectors.py --color-by labeled \
    --label-regex '(?=.*SH:11\.11)(?=.*SH:22\.22)' --even-only

# … or by solution geometry (numeric column ≥ threshold).
python3 bin/plot_vectors.py --color-by labeled \
    --label-col auto_checker --label-threshold 0.9

# Supervised separability: is the highlighted group actually separable?
python3 bin/plot_vectors.py --separation \
    --label-regex '(?=.*SH:11\.11)(?=.*SH:22\.22)' --even-only
```

Reads `puzzle_vectors.csv`. Linear PCA via numpy SVD — no sklearn
dependency. Used to sanity-check that the level cascade carves the
corpus into visually-distinct lobes (it does, modulo overlap in the
middle tiers).

`--color-by labeled` highlights a sub-population — chosen by `--label-regex`
(matched against `canonical_key`) or by a numeric `--label-col ≥
--label-threshold` (e.g. colour by the `auto_checker` geometry rather than the
constraint that encodes it) — and prints a per-feature discrimination report
(mean z-score gap + univariate AUC). Because PCA is unsupervised, a 0.1%
minority never drives a top component, so a flat scatter is **not** evidence of
inseparability. `--separation` answers that question directly: a shrinkage-
regularized Fisher LDA, cross-validated (both needed since features ≫
positives), reporting the out-of-fold ROC-AUC and a score-distribution figure.

## Player stats

```bash
# Merge raw per-player stats into stats_aggregated/<player>.txt,
# dedup by (timestamp | canonical puzzle key), refresh cplx.
dart run bin/aggregate_player_stats.dart stats_gle/ -o stats_aggregated/gle.txt

# OLS on log(dur) vs (cplx, cells, …) — yields the regression
# constants used by Database.computePlayerLevel.
dart run bin/analyze_stats.dart stats_aggregated/gle.txt
```

## Tagging legacy puzzles with their scenario

Since the `scenario:<name>` v2 suffix became authoritative (see
`docs/dev/prefill_sy.md` and the `detectPuzzleProfile` entry in
`equilibrium.dart`), every puzzle generated by the regular flow is
stamped at emission time — but the historical corpus (~26 k puzzles
shipped in `assets/`) predates this and carries no marker. Unmarked
lines are read as `classic` at runtime, which is correct for the vast
majority but mis-attributes the `sh` / `pathBased` / `syBased`
puzzles that the equilibrium loop did produce, leaving the profile
histogram skewed toward `classic`.

`bin/remark_scenarios.dart` infers the scenario from each unmarked
line and appends `_scenario:<name>` only for non-classic conclusions.
`classic` puzzles are left untouched — the absence of the suffix is
the canonical encoding for that case, and re-runs are idempotent
(lines that already carry `_scenario:` are pass-through).

The detection is the **same trace-based algorithm** used by
`bin/extract_path_like.dart` (and extended symmetrically to SY), so a
puzzle is only tagged `pathBased` / `syBased` when the solver's
deduction trace actually behaves that way — not just because the
constraint list happens to contain a few `LT:` / `SY:` entries.

| Priority | Trigger                                                                                                                                       | Tag         |
|----------|-----------------------------------------------------------------------------------------------------------------------------------------------|-------------|
| 1        | any `SH:` constraint                                                                                                                          | `sh`        |
| 2/3      | trace's `LT:` propagation share ≥ `--min-lt-share` **and** ≥ `--min-lt-interesting` LT steps at complexity ≥ 2 (after the LT topo pre-filter) | `pathBased` |
| 2/3      | same for `SY:` (after the SY topo pre-filter)                                                                                                 | `syBased`   |
| 4        | otherwise                                                                                                                                     | *(none)*    |

Step by step:

1. `SH:` is unambiguous (only `preFillSh` emits it), so any line
   carrying one is tagged `sh` without ever running the solver.
2. Otherwise the script applies two cheap **topological pre-filters**
   to gate the expensive trace step:
   - PATH_TOPO: ≥ `--min-letters` distinct LT letters, each with its
     own anchors at Manhattan distance ≥ `--min-anchor-distance`.
   - SY_TOPO:   ≥ `--min-sy-seeds` distinct SY anchors.
   If neither passes, the line is left as classic.
3. If either passes, the solver runs once via `solveExplained` and the
   script aggregates, on the propagation steps only:
   - `lt-share` / `sy-share` — fraction of steps issued by an LT / SY
     constraint;
   - `lt-interesting` / `sy-interesting` — number of those steps with
     `complexity ≥ 2`.
4. A scenario "qualifies" iff its topo pre-filter passed **and** its
   share ≥ threshold **and** its interesting count ≥ threshold. If
   both LT and SY qualify (rare — the two generators exclude each
   other's dominant slug), the larger share wins (LT on exact ties).
   Puzzles whose `solve()` requires backtracking are recorded as
   `trace_failed` and left as classic (same gate as
   `bin/extract_path_like.dart:_traceMetrics`). The shipped corpora
   are filtered by `--check` against backtracking puzzles, so a hit
   here is anomalous — `-v` prints the full v2 line for inspection.

Defaults match `extract_path_like.dart`: `--min-letters 2`,
`--min-anchor-distance 2`, `--min-sy-seeds 2`, `--min-lt-share 0.5`,
`--min-lt-interesting 1`, `--min-sy-share 0.5`,
`--min-sy-interesting 1`, `--timeout-ms 15000`.

Usage:

```bash
# No argument → processes the eight standard collections in `assets/`.
# Dry-run reports counts without writing anything; expensive but safe.
dart run bin/remark_scenarios.dart --dry-run -v

# Single file, custom output path.
dart run bin/remark_scenarios.dart assets/1-easy.txt -o /tmp/out.txt -v

# Apply — writes `<file>.remarked.txt` per input. Migrate manually:
dart run bin/remark_scenarios.dart -v
for f in assets/*.remarked.txt; do mv "$f" "${f%.remarked.txt}"; done
```

The trace step is expensive (a solver run per qualifying puzzle, up
to `--timeout-ms`); the topological pre-filter eliminates the bulk of
the corpus before that. Still, plan for ~10–20 min on the standard
collections — run a `--dry-run` first to estimate.

Run once across the standard collections after merging the
`scenario:` marker work into the main branch. Subsequent corpora
produced by `bin/generate.dart` already carry the tag, so the script
is a one-shot migration tool — not a step in the periodic maintenance
pipeline.

## Periodic maintenance

`bin/maintain.dart` chains the eight routine maintenance tools into a
single fail-fast pipeline that applies as it goes. Run it from the
project root whenever the corpus needs a refresh — typically after a
formula tweak, a new constraint, or just on a periodic cadence:

```bash
dart run bin/maintain.dart
```

Pipeline (each step applies directly; the next step sees the updated
`assets/`):

1. **`recompute --route`** — refresh stored cplx + cached solutions,
   re-sort constraints, redistribute each puzzle to its classified level.
2. **`vectorize_puzzles`** — build `puzzle_vectors.csv` from the freshly
   recomputed corpus (trace shares + solution geometry). Runs early so the
   later passes that consume the CSV — `cleanup` (regular patterns) and
   `cluster` — see geometry computed from the current solutions.
3. **`dedup_puzzles`** — drop exact duplicates per file
   (defence-in-depth: `--route` already enforces canonical-key
   uniqueness, but this catches anything that slipped through).
4. **`cleanup_collections --apply`** — drop disliked, boring
   (≥ 90 % trivial-FM), overlapping-MJ-border, and regular-pattern
   (damier / colour-bar) puzzles. The regular-patterns pass reads the
   geometry columns from `puzzle_vectors.csv`.
5. **`cluster_puzzles --apply`** — drop near-duplicates
   (`--max-distance 0.15`, `--keep-per-cluster 1`), protecting the
   current onboarding bank. Because the vector predates steps 3-4, it
   first drops CSV rows whose puzzle is no longer in any collection, so a
   stale row can never be picked as the representative that survives.
6. **`cluster_puzzles --mode recycle --apply`** — FPS prune-to-count.
   Any collection above the 20 k balance target keeps its
   `--target-count` most-diverse puzzles; the excess is moved to
   `<file>-recycled.txt` (see "Pruning the corpus" §4). Today this shrinks
   6-mad down to 20 k and feeds `assets/6-mad-recycled.txt`.
7. **`recycle_mad --apply`** — ease the recycled mad feed down into the
   deficient collections (targets `player,expert,strong`, cap 20 k),
   routing each landed line into its `classifyTrace` collection, and
   consume (remove) the routed lines from the feed so it converges to just
   the not-yet-easable hard cases.
8. **`extract_onboarding`** — refresh `assets/1-easy_onboarding.txt`
   (300 per phase) from the post-cleanup corpus.

The pipeline never commits — every change lands in `assets/*.txt`
directly, so `git diff` is the canonical "what just happened?" view.
At the end the orchestrator prints a per-step status, the per-file
line-count delta, and total wall time. The first failing step aborts
the rest; subsequent steps can be resumed by re-running the script
after fixing the issue (each step independently snapshots and applies).

Wall time on a 26 k-puzzle corpus is dominated by step 2
(vectorize, ~20-30 min) and step 5 (cluster, a few minutes); step 6
(FPS prune-to-count over 6-mad) takes a few minutes, and step 7
(recycle_mad easing) a few seconds per feed line.

## Typical workflows

### "I generated 5000 fresh puzzles, prepare them for shipping"

```bash
# 1. Validate — drops puzzles that need backtracking or are non-unique
dart run bin/generate.dart --check new.txt
mv new.good.txt new.txt && rm new.bad.txt

# 2. Sort constraints by trace-min cplx, refresh cached cplx/solution
dart run bin/recompute.dart new.txt
mv new.txt.new new.txt

# 3. Merge into the existing files via classification routing
cat new.txt >> assets/undetermined.txt
dart run bin/recompute.dart --route   # renames in-place at the end

# 4. Drop the inevitable near-duplicates
dart run bin/vectorize_puzzles.dart
dart run bin/cluster_puzzles.dart --apply --max-distance 0.15 \
  --protect-from assets/1-easy_onboarding.txt -v
```

### "The complexity formula changed, refresh the corpus"

```bash
dart run bin/recompute.dart --route -v
```

`--route` re-classifies every puzzle through `classifyTrace`, so a
formula change that shifts cplx scores or moves the cascade
boundaries automatically reshuffles the files.

### "A new constraint was added, audit the corpus"

```bash
# Refresh stored cplx + sort constraints (the new constraint may
# have changed the sort order or trace cplx of some puzzles).
dart run bin/recompute.dart -v
for f in assets/*.txt.new; do mv "$f" "${f%.new}"; done

# Re-vectorize and re-cluster (the new slug introduces share_X_tY
# columns the CSV didn't have before).
dart run bin/vectorize_puzzles.dart
dart run bin/cluster_puzzles.dart --top-k 1000 --output similar_pairs.txt
```

## Why redundancy concentrates in the easy tier

Empirically, `--apply --max-distance 0.3` removes about 9 % of
1-easy and 5 % of 1-easy-overfilled, while every other collection
loses well under 1 %. 4-strong has *zero* removals.

The cause is structural, not a generator bug. The slug-axis target
in `equilibrium.dart` aims at corpus-wide balance, and the
corpus-wide slug shares are dominated by FM (60 %), PA (57 %),
GS (52 %) and NC (49 %) — NC is fourth, not the worst. But:

* NC produces only tier-0 moves (counting neighbours is local), so
  every NC-heavy puzzle has an "easy" trace and is routed to
  1-easy / 1-easy-overfilled.
* A puzzle with one slug and tier-0 moves has a sparse vector — 1
  non-zero share out of 78. With many similar puzzles, the few
  non-zero dimensions can't keep them apart.
* In 4-strong, every accepted puzzle uses a complicity at tier ≥ 4,
  so the vector lights up many more dimensions and each puzzle
  lives in a near-unique cell of the feature space.

The corpus-level equilibrium target therefore *does* what it
promises — but the consequence at the easy end is more redundancy.
Reducing NC's share in the equilibrium target would push the
problem onto FM-only or PA-only puzzles with the same effect.

## Collection orchestrator and puzzle recycling

Forward-looking design for balancing the six playable collections around
a common target size. Status: implemented in `bin/balance_collections.dart`
(see decision 5). This section records what we are trying to achieve, the
decisions made, and the questions still open.

### What we are trying to achieve

The six playable collections are badly skewed: 1-easy (~15 k puzzles) and
6-mad (~23 k) dwarf the middle tiers (3-advanced ~0.4 k, 4-strong ~1.1 k,
2-player ~9 k, 5-expert ~4.5 k). The goal is to bring **all six to ~20 000
puzzles each** (± 10 %: floor 18 k, ceiling 22 k) with **one background
command that alternates generation and pruning** until the whole corpus is
in range.

Two structural facts drive the design:

* **Equilibrium does not steer difficulty.** The equilibrium engine
  (`equilibrium.dart`) biases the slug / ntypes / pair / size / profile /
  composition / domain axes — never the `classifyTrace` level. A free
  generation run keeps over-producing 1-easy and 6-mad (the cascade's two
  wide ends) while 3-advanced / 4-strong trickle in: `advanced` requires
  `forceMoves == 0` **and** a complicity at tier 1-3, `strong` requires
  `forceMoves == 0` **and** a complicity at tier ≥ 4 — randomly-produced
  puzzles almost always either solve by pure propagation (beginner/player)
  or need a force round (expert/mad).
* **Similarity pruning only bites on the easy tier.** `cluster_puzzles`
  removes ~10 % of 1-easy at ε = 0.3 but ~0 % of the high tiers (see
  "Why redundancy concentrates in the easy tier"): 6-mad puzzles are
  near-unique in the 91-dim feature space, so "drop the too-similar ones"
  cannot shrink 6-mad on its own.

### Decisions made

1. **Targets.** ~20 000 per collection, tolerance ±10 % → floor 18 000,
   ceiling 22 000. Main six collections only; the overfilled buckets are
   deferred (possible future lever: raise the per-collection prefill cap to
   borrow from them).
2. **"Too similar" = farthest-point sampling prune-to-count**, not the
   ε-threshold clustering. FPS keeps the `target` most-diverse puzzles of
   an over-full collection (maximising mutual vector distance) and moves
   the rest to the per-collection recycled feed (`<file>-recycled.txt`).
   Implemented as `cluster_puzzles.dart --mode recycle` (see "Pruning the
   corpus" §4); unlike ε-clustering it needs no threshold, so it works
   uniformly on 1-easy **and** 6-mad.
3. **Pruned 6-mad puzzles are recycled, not deleted.** The pruned
   `count − target` lines are moved to a staging file
   (`assets/6-mad-recycled.txt`) by `cluster_puzzles --mode recycle`
   and fed to `Puzzle.simplify`
   (`lib/getsomepuzzle/model/puzzle.dart`) — the same "add constraints
   until the trace cascades into the target" routine the generator's
   `--target-collection` easing loop uses. A mad puzzle with extra
   constraints grafted on loses its force rounds and re-classifies into
   3-advanced / 4-strong (or lower — any in-cascade level below mad is
   salvageable). Uniqueness is preserved by construction: `simplify` only
   adds constraints that verify against the unique solution.
4. **Vector freshness via inline emission.** The prune step reads
   `puzzle_vectors.csv`, which must cover newly generated puzzles. Instead
   of re-running the 20-30 min `vectorize_puzzles` every loop iteration,
   the generator appends one vector row per emitted puzzle during asset
   routing (`GeneratorConfig.computeVector`, always on in the CLI; off for
   the in-app/web generator). The vector logic lives in the shared
   `lib/getsomepuzzle/vector.dart` (+ `lib/getsomepuzzle/solution_geometry.dart`,
   re-exported by `bin/_solution_geometry.dart`), used by both
   `bin/vectorize_puzzles.dart` and the generator's `_finalize`. The inline
   vector uses the **post-sort** trace (a re-solve that replaces the hidden
   solve inside `lineExport`'s `computeComplexity`, so the per-puzzle solve
   count is unchanged) and is identical to what a batch `vectorize_puzzles`
   run produces for the same line. One bootstrap `vectorize_puzzles` run
   covers the existing corpus.
5. **Orchestrator as one background command.** `bin/balance_collections.dart`
   (built) loops: count the six files → generate a batch → FPS-prune + recycle
   any over-target collection (`cluster_puzzles --mode recycle --apply`) → ease
   the recycled feed into the deficient collections (`recycle_mad --apply`) →
   full `maintain.dart` every `--maintain-every` iterations → repeat until all
   *fillable* collections (1-easy, 2-player, 5-expert, 6-mad) ∈ [18 000, 22 000],
   with `--dry-run` and `--max-iterations` guards. Because the generator emits
   inline vectors, the cheap loop needs no full re-vectorize; `maintain.dart`
   re-vectorizes authoritatively on a cadence. 3-advanced and 4-strong are
   tracked best-effort (4-strong gets `--target-collection 4-strong` batches
   every `--strong-every` iterations) but do not block convergence.
6. **Pilot first.** `bin/pilot_recycle.dart` measures whether `simplify()`
   can actually convert mad → advanced/strong and at what cost before the
   orchestrator commits to recycling as a primary source.

### Pilot: `bin/pilot_recycle.dart`

Samples lines from a collection (default `assets/6-mad.txt`), runs
`simplify(targetLevel)` on each, and reports:

* success rate to `strong` (index ≤ 3) and `advanced` (index ≤ 2), overall
  and restricted to initial-mad rows;
* final-level distribution (how many plateaued at mad vs reached the
  targets vs overshot below them);
* cost: constraint additions (bloat) and wall time;
* re-classification of the exported lines — the same sort +
  `autoShrinkDomain` + `lineExport` tail the generator's `_finalize` uses —
  with `--emit-out` writing the salvageable v2 lines for inspection.

```bash
dart run bin/pilot_recycle.dart --sample 200 --target strong
dart run bin/pilot_recycle.dart --sample 200 --target advanced --emit-out /tmp/recycled.txt
```

### Readonly-cell easing (`bin/pilot_readonly.dart`)

`simplify()` lowers a puzzle's level by grafting *constraints* onto it
(decision 3 above). An alternative lever, implemented in
`bin/pilot_readonly.dart`, is to pre-fill more cells as readonly givens
instead: removing unknowns
from the grid can shorten the deduction chain and drop force rounds, which
would re-classify a mad puzzle into 3-advanced / 4-strong without adding a
single constraint.

Two caveats make this trickier than constraint-adding:

* **Prefill routing.** `classifyTrace` routes any puzzle with
  `prefillRatio > 0.30` into the per-level `*-overfilled` buckets regardless
  of the trace. Adding readonly cells therefore *raises* the very ratio that
  can eject a puzzle out of the playable cascade — this lever only works
  while staying under ~30 % prefill. Constraint-adding has no such ceiling
  (it never touches prefill).
* **Correctness.** Every new readonly value must come from the puzzle's
  unique solution, and the cache / solution field on the line must be
  refreshed, or the result is unsolvable / the stored solution goes stale.

The easing core lives in `lib/getsomepuzzle/recycle.dart` (`easePuzzle`),
shared by `bin/pilot_readonly.dart` (a thin sampler/reporter exposing the
`min-level` and `hit-band` objectives) and `bin/experiment_landing.dart`
(which uses the generalised `target-level` objective to test whether easing
can deliberately land in a specific collection — player/expert/strong — for
the recycling step). Results are in "Pilot results" below.

### Pilot results

Run on a 200-puzzle sample of `assets/6-mad.txt` (all initial-mad), target
`strong`, per-puzzle timeout 15 s.

**Constraint-grafting (`bin/pilot_recycle.dart`).**

| Metric | Value |
|---|---|
| leaves mad | 82.5 % (165/200) |
| → strong / advanced | 19 / **1** |
| → expert / player / beginner | 5 / 123 / 17 |
| stays mad | 35 (19 immediate plateau) |
| cost | +2.5 constraints (max 8), 5.2 s mean |
| export mismatches | 5 / 165 |

Overshoots: one indispensable constraint usually collapses `mad` all the way
to `player`, because the added constraint also shortcuts the complicity
deduction.

**Readonly-easing (`bin/pilot_readonly.dart`).** Initial prefill 2.8 % →
28.6 % (median 15 %), so the 30 % cap is not the blocker.

| Metric | `min-level` | `hit-band` |
|---|---|---|
| leaves mad | 46 % | **69.5 %** |
| → strong / advanced | 13 / 0 | 16 / 0 |
| → expert / player / beginner | 5 / 54 / 20 | 19 / 98 / 25 |
| stays mad | 108 | 37 |
| readonly cells added | 0.59 mean | 2.13 mean (max 9) |
| wall time | 1.3 s mean | ~3 s mean (1 outlier ≈ 180 s) |
| export mismatches | 0 | 0 |

`min-level` plateaus early (0.59 cells added on average): it only commits a
fix that *lowers the level*, so a cell that merely reduces force 2 → 1 is
skipped. `hit-band` commits any force-reducing fix and scores candidates by
"kill force while keeping a complicity", more than doubling the salvage rate.

**Conclusions.**

1. **The recycling lever is settled: `hit-band` readonly-easing.** Highest
   salvage, no early plateau, and it feeds real shares to `2-player` (bulk),
   `5-expert` (19) and `4-strong` (16). Preferred over constraint-grafting
   and over `min-level`.
2. **`advanced` is unreachable by down-easing mad puzzles** — 0 in every
   200-run (constraint-graft got 1). The `classifyTrace` band for
   `advanced`/`strong` (`forceMoves == 0` **and** a surviving complicity) is
   skipped past because eliminating force also shortcuts the complicity.
3. So recycling can balance `1/2/5` (and partially `4`), but `3-advanced`
   (and reaching 20 k for `4-strong`) needs either a generator feature that
   produces complicity-without-force puzzles directly, or a recalibrated
   target.

**Notes found while running.**

* `--target-collection`'s easing loop accepts `reachedTarget == finalLevel <=
  target` and emits the result at that lower level (a too-hard puzzle eased
  past the target is routed to the lower file), so it does not reliably fill
  the target collection on its own.
* A prefill-headroom bug (a `1e-9` epsilon in `pilot_readonly.dart`'s cap
  check) let a few puzzles be mis-routed to overfilled buckets by a sub-percent
  overshoot; fixed with exact integer arithmetic.

### Landing experiment and the recycling step

The recycling step needs to AIM the easing at a specific deficient collection.
`bin/experiment_landing.dart` validated that with a generalised
`target-level` objective. A pure level-distance score plateaued (~64 % of mad
puzzles stuck: a fix that merely lowers force 2 → 1 keeps the same level, so
it was never committed); adding a `forceMoves × 1000` reward fixed it. Final
100-puzzle sample (seed 42, `assets/6-mad.txt`):

| target | lands exactly | stays mad | notable fallout |
|---|---|---|---|
| `player` | 58 % | 20 % | beginner 11 %, expert 11 % |
| `expert` | 54 % | 20 % | player 16 % |
| `strong` | 4 % | 20 % | player 54 % (force-kill overshoot) |

`player` and `expert` are therefore deliberately fillable (~55 % exact, 80 %
salvage, ~4 s/puzzle); `strong`/`advanced` remain structurally hard, as
before.

`bin/recycle_mad.dart` is the production recycling step built on this: it
reads a mad-overflow feed (default `assets/6-mad-recycled.txt`), eases each
line with `EaseObjective.targetLevel` toward the first open target (by current
collection count vs `--cap`, live-balanced as lines route), and routes the
landed line into `assets/<level>.txt` by its actual final level
(`--apply`; dry-run by default). Canonical-key duplicates are skipped against
the destination file; stayed-mad lines can be dumped with `--emit-mad`.


### Open questions

* **advanced/strong path.** 3-advanced (and reaching 20 k for 4-strong)
  cannot be filled by recycling: both down-easing levers produce ~0 advanced
  (see "Pilot results"). The two routes are (a) a generator feature that
  produces complicity-without-force puzzles directly, or (b) recalibrating
  those collections' targets to their natural production rates. Not yet
  decided.
* **Per-level generation rates.** Reading the `level` column of
  `generator_stats.csv` shows how starved advanced/strong really are under
  free generation, and decides how much "mad-as-feeder" over-production is
  needed to feed `2-player` / `5-expert` / `4-strong` via `bin/recycle_mad.dart`.
* **Quality of eased puzzles.** A recycled puzzle carries more readonly cells
  than a natively generated one. Whether that reads as "denser" or "bloated"
  to a player needs human judgement before shipping recycled puzzles into the
  main collections.
* **Recycling feed.** `bin/recycle_mad.dart` consumes the FPS-pruned 6-mad
  excess, produced by `cluster_puzzles --mode recycle` (writes
  `assets/6-mad-recycled.txt`; append + canonical-key dedup, so re-running
  after a partial consumption never loses or duplicates lines). After an
  `--apply` run, `recycle_mad` removes the successfully-routed lines from the
  feed, so it converges to just the not-yet-easable (stayed-mad / unparsable)
  hard cases. Keeping it topped-up and drained is automated by
  `bin/balance_collections.dart` (generate → recycle → recycle_mad per
  iteration).
* **Fate of un-simplifiable puzzles.** Mad puzzles that stay mad after easing
  (~20 %): keep them in 6-mad, or discard?
* **Overfilled buckets.** Eventually the `*-overfilled.txt` collections could
  "help" the under-filled ones by raising their prefill cap — `classifyTrace`
  routing already keeps them separated per level. Deferred.

## Open work: reject-on-near-duplicate at generation time

The cleanup pipeline above runs *after* the generator has burned
CPU producing puzzles that we then drop. The natural alternative
is to refuse near-duplicates at generation time, so they never
land in the corpus.

**Sketch:**

1. Keep a running "fingerprint index" alongside the generation
   loop. Each accepted puzzle contributes a short feature vector
   — the same family as `bin/vectorize_puzzles.dart` produces, but
   the trace is already computed during generation so the
   per-puzzle overhead is negligible.
2. After the generator accepts a candidate (post-`isDeductivelyUnique`),
   compute its vector and check it against the existing index
   (bucketed by domain + dominant slug, KD-tree or just linear
   inside each bucket — the index is small per bucket).
3. If `min distance < ε` to an existing accepted puzzle, **reject**
   the candidate; bump a per-target failure counter so the
   equilibrium loop knows to move to another target faster.
4. Otherwise insert the vector into the index and persist as today.

**Why this is the right move:**

* Reuses our existing distance metric — already validated by the
  cleanup runs against human judgement on edge pairs.
* Doesn't touch the equilibrium targets, so the existing axis
  balance is preserved.
* Prevents the problem at the source instead of papering over it
  via periodic cleanup. The generator stops spending CPU on
  near-duplicates and converges on novel sub-regions faster.

**Tradeoffs / risks:**

* For tight targets (rare slug or rare ntypes) the index may
  reject *every* candidate within reasonable wall time. Need a
  fallback: relax ε after K consecutive rejects so the generator
  doesn't deadlock.
* The index grows over time; for 26 k+ corpora bucketing by
  `(domain, dominant_slug)` keeps lookup fast (≈ 2 k puzzles per
  bucket, linear scan in ~µs).
* Initial bootstrap from the existing corpus needs the full
  vectorisation pass (the `puzzle_vectors.csv` we already
  produce). After that, each new puzzle just adds one row to the
  in-memory index.

**When to do it:** when the next periodic cleanup feels like
re-doing the same work. Until then, the current
vectorize → cluster → apply pipeline absorbs the slack at a
predictable cost.
