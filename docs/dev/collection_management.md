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
| `assets/overfilled-easy.txt`  | Beginner-by-trace puzzles whose prefill ratio > 30 %              |
| `assets/overfilled.txt`       | Higher-tier puzzles whose prefill ratio > 30 %                    |

Routing is by `classifyTrace` (`lib/getsomepuzzle/level.dart`), not by
declared slugs. See `levels.md` for the cascade.

## Tool index

| Tool                                  | Purpose                                                      |
|---------------------------------------|--------------------------------------------------------------|
| `bin/generate.dart`                   | Generate new puzzles, validate / re-validate existing ones   |
| `bin/maintain.dart`                   | Full periodic-maintenance pipeline (6 steps, apply mode)     |
| `bin/recompute.dart`                  | Re-sort constraints, refresh stored cplx, re-route by level  |
| `bin/dedup_puzzles.dart`              | Drop puzzles that are exact duplicates (canonical key match) |
| `bin/cleanup_collections.dart`        | Drop disliked / trivial-FM-dominated puzzles                 |
| `bin/vectorize_puzzles.dart`          | Produce per-puzzle feature vector CSV                        |
| `bin/cluster_puzzles.dart`            | Find near-duplicate pairs/clusters (report or --apply mode)  |
| `bin/extract_onboarding.dart`         | Build a diverse onboarding bank from 1-easy                  |
| `bin/classify_difficulty.dart`        | Classify each puzzle into the level cascade                  |
| `bin/aggregate_player_stats.dart`     | Merge per-player stats files, dedup, refresh cplx            |
| `bin/analyze_stats.dart`              | OLS regression on log(duration), per-bucket stats            |
| `bin/plot_vectors.py`                 | 2-D PCA projection of the vectors (matplotlib + numpy)       |

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

* **With positional args** — those files replace the source set.
  Useful to ventilate an unsorted feed (e.g. a fresh `/tmp/path6.txt`
  produced by an experimental generator) into the existing cascade
  without merging it into `assets/` first. Verbatim noise (blanks,
  comments, parse failures) is dropped silently in this mode — the
  feed is an input, not a destination we want to mirror.

  ```bash
  dart run bin/recompute.dart --route /tmp/path6.txt
  ```

Both modes write to `<dest>.tmp` in append mode and never touch the
source files; the user migrates with `mv assets/<lvl>.txt.tmp
assets/<lvl>.txt` when satisfied. Re-runs are idempotent: puzzles
already emitted to a `.tmp` (by `canonicalPuzzleKey`) are skipped,
so an interrupted `--route` can be resumed by simply re-launching.

`--dry-run` reports the level transitions without writing any file —
useful to see how a new complexity tweak would shift the cascade
before committing to it.

## Pruning the corpus

The cleanup pipeline has three layers, each independent.

### 1. Drop exact duplicates

`bin/dedup_puzzles.dart` drops lines whose `canonicalPuzzleKey`
matches a previously-seen puzzle (rotation-invariant, constraint-set
canonicalised). Catches reruns of the generator that hit the same
identity.

```bash
dart run bin/dedup_puzzles.dart -o deduped.txt assets/1-easy.txt
```

### 2. Drop disliked or trivial-FM-dominated puzzles

`bin/cleanup_collections.dart` runs two passes (both gated by
their own flag, both run when neither is passed):

* `--disliked` — cross-reference `stats_aggregated/*.txt` and flag
  puzzles that appear with a `__D` (disliked) marker.
* `--boring` — solve each puzzle, flag those where ≥ 90 % of moves
  are deduced by 1×2 / 2×1 FM constraints (the trivial-saturation
  variants, weight 0 in `complexity.md`). 1-easy and overfilled-easy
  are exempt — the trivial saturation is *the lesson* there.

```bash
# Dry-run report
dart run bin/cleanup_collections.dart -v

# Apply (writes <file>.cleanup files for the user to mv into place)
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
n_constraints, cells, and prefill_ratio. Z-scored across the pool,
clipped at ±5.

The clustering empirically concentrates on `1-easy.txt` (~10 % at
ε = 0.3) and `overfilled-easy.txt` (~5 %), with NC-only and
FM-only puzzles dominating the dropped clusters — see the
"Why redundancy concentrates in the easy tier" section below.

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

## Visual diagnostics

```bash
# 2D PCA scatter, colored by source collection.
python3 bin/plot_vectors.py

# Same data, colored by dominant slug in the trace.
python3 bin/plot_vectors.py --color-by dominant_slug -o puzzle_pca_slugs.png

# Continuous gradient on complexity.
python3 bin/plot_vectors.py --color-by complexity -o puzzle_pca_cplx.png
```

Reads `puzzle_vectors.csv`. Linear PCA via numpy SVD — no sklearn
dependency. Used to sanity-check that the level cascade carves the
corpus into visually-distinct lobes (it does, modulo overlap in the
middle tiers).

## Player stats

```bash
# Merge raw per-player stats into stats_aggregated/<player>.txt,
# dedup by (timestamp | canonical puzzle key), refresh cplx.
dart run bin/aggregate_player_stats.dart stats_gle/ -o stats_aggregated/gle.txt

# OLS on log(dur) vs (cplx, cells, …) — yields the regression
# constants used by Database.computePlayerLevel.
dart run bin/analyze_stats.dart stats_aggregated/gle.txt
```

## Periodic maintenance

`bin/maintain.dart` chains the six routine maintenance tools into a
single fail-fast pipeline that applies as it goes. Run it from the
project root whenever the corpus needs a refresh — typically after a
formula tweak, a new constraint, or just on a periodic cadence:

```bash
dart run bin/maintain.dart
```

Pipeline (each step applies directly; the next step sees the updated
`assets/`):

1. **`recompute --route`** — refresh stored cplx, re-sort
   constraints, redistribute each puzzle to its classified level.
2. **`dedup_puzzles`** — drop exact duplicates per file
   (defence-in-depth: `--route` already enforces canonical-key
   uniqueness, but this catches anything that slipped through).
3. **`cleanup_collections --apply`** — drop disliked and boring
   (≥ 90 % trivial-FM) puzzles.
4. **`vectorize_puzzles`** — refresh `puzzle_vectors.csv` from the
   cleaned corpus.
5. **`cluster_puzzles --apply`** — drop near-duplicates
   (`--max-distance 0.15`, `--keep-per-cluster 1`), protecting the
   current onboarding bank.
6. **`extract_onboarding`** — refresh `assets/1-easy_onboarding.txt`
   (300 per phase) from the post-cleanup corpus.

The pipeline never commits — every change lands in `assets/*.txt`
directly, so `git diff` is the canonical "what just happened?" view.
At the end the orchestrator prints a per-step status, the per-file
line-count delta, and total wall time. The first failing step aborts
the rest; subsequent steps can be resumed by re-running the script
after fixing the issue (each step independently snapshots and applies).

Wall time on a 26 k-puzzle corpus is dominated by step 4
(vectorize, ~20-30 min) and step 5 (cluster, a few minutes).

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
dart run bin/recompute.dart --route

# 4. Drop the inevitable near-duplicates
dart run bin/vectorize_puzzles.dart
dart run bin/cluster_puzzles.dart --apply --max-distance 0.15 \
  --protect-from assets/1-easy_onboarding.txt -v
for f in assets/*.cleanup; do mv "$f" "${f%.cleanup}"; done
```

### "The complexity formula changed, refresh the corpus"

```bash
dart run bin/recompute.dart --route -v
for f in assets/*.txt.new; do mv "$f" "${f%.new}"; done
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
1-easy and 5 % of overfilled-easy, while every other collection
loses well under 1 %. 4-strong has *zero* removals.

The cause is structural, not a generator bug. The slug-axis target
in `equilibrium.dart` aims at corpus-wide balance, and the
corpus-wide slug shares are dominated by FM (60 %), PA (57 %),
GS (52 %) and NC (49 %) — NC is fourth, not the worst. But:

* NC produces only tier-0 moves (counting neighbours is local), so
  every NC-heavy puzzle has an "easy" trace and is routed to
  1-easy / overfilled-easy.
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
