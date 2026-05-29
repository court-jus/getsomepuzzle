# Constraint families & the equilibrium "composition" axis

> Spec + implementation plan. The taxonomy module (`families.dart`) and its
> tests are in place; the equilibrium axis, dashboard panel and `query_corpus`
> wiring are **not yet implemented** (see *Implementation status* at the end).

## Motivation

The generator's equilibrium balances generation across five independent axes
(slug, ntypes, pair, size, profile — see `equilibrium.md`). Since MJ/CH/RT/CT
were added, it tends to emit "kitchen-sink" puzzles that pile on many
constraints: the per-slug marginals stay balanced while the **variety of
thematic assemblages** collapses onto a handful of everything-at-once
slug-sets (visible via `query_corpus --buckets`).

The fix is a **constraint-family taxonomy** plus a new equilibrium axis,
**composition**, that balances the *blend of families* a puzzle is built from
rather than individual slugs.

## Taxonomy

The 17 player-facing slugs (`constraints/registry.dart`) are partitioned into
five families by **deduction strategy** (orthogonal to the `Constraint` class
hierarchy):

| Family (key)     | Slugs                | Common deduction strategy                              |
|------------------|----------------------|--------------------------------------------------------|
| `line-centric`   | RC, RT, CC, CT, PA   | reasons about a whole row/column line (count / transition / parity) |
| `local`          | FM, DF, NC, EY       | forbidden motif / adjacency / immediate-neighbourhood count |
| `path`           | LT, CH               | connectivity: shared connected group / border-to-border chain |
| `group-topology` | GS, GC, SH, SY, MJ   | connected-component size/count/shape, symmetry, rectangular-zone majority |
| `global`         | QA                   | whole-grid quantity                                    |

It is a strict partition: every slug belongs to exactly one family, and a
guard test fails if a registry slug is left unmapped.

## Composition of a puzzle

A puzzle's **composition** is the ordered triple of its three principal
families:

1. **Count constraint instances per family** — parse the constraint field
   (`parts[4].split(';')`) **without** deduplicating; map each token's slug to
   its family and tally. Example: `3×LT, 2×PA, 1×FM` → `path=3`,
   `line-centric=2`, `local=1`.
2. **Rank** real families by `(count desc, kConstraintFamilies index asc)` —
   the fixed family order is the deterministic tie-break.
3. Keep the **top three**; pad with the **virtual empty family `none`** when a
   puzzle spans fewer than three real families.

So the example yields `(path, line-centric, local)`; a pure line puzzle yields
`(line-centric, none, none)`; a two-family puzzle yields `(f1, f2, none)`.

`none` always sorts last and the first slot is always real (every puzzle has
≥ 1 constraint). For `m` real families in play the number of distinct
compositions is

```
P(m,3) + P(m,2) + m       # m=5 → 60 + 20 + 5 = 85
```

The axis target is **uniform** (`1/85` for the full universe). Crucially,
the focused buckets (`(f, none, none)`, `(f1, f2, none)` — 25 of the 85) are
balanced at the same level as the full triples, so the axis pushes both
*combination variety* and *thematic / focused* puzzles — which recovers the
anti-kitchen-sink effect from the composition angle.

## Shared module — `lib/getsomepuzzle/constraints/families.dart` *(implemented)*

Pure Dart, no imports, so both the generator and the `bin/` tools can use it
as the single source of truth:

- `const Map<String,String> kConstraintFamily` — slug → family (17 entries).
- `const List<String> kConstraintFamilies` — fixed family order
  (`line-centric, local, path, group-topology, global`); drives the tie-break
  and display order.
- `const String kEmptyFamily = 'none'`.
- `String? familyOf(String slug)`.
- `List<String> familiesOf(Iterable<String> slugs)` — distinct families
  (deduplicated), in family order.
- `List<String> compositionOf(Iterable<String> slugInstances)` — the algorithm
  above; takes slugs **with repeats**, returns a length-3 list.
- `List<List<String>> allCompositions(List<String> families)` — enumerates the
  valid ordered triples for a set of real families (85 for the full five).

## Equilibrium axis — `lib/getsomepuzzle/generator/equilibrium.dart`

Modelled on the `size` axis (atomic, single-valued category, uniform share):

1. `import '…/constraints/families.dart'`.
2. `enum Axis` → add `composition`.
3. `CompositionTarget(List<String> families)` — `key = 'comp:a+b+c'`,
   `label = 'comp=a+b+c'`, `axis => Axis.composition`. Model on `SizeTarget`.
4. `EquilibriumStats` — add `compositionCounts` (`Map<String,int>`, key = the
   joined triple). Populate in `empty()`, the constructor, `fromLines` and
   `withPuzzle` via `compositionOf(...)` — **one** increment per puzzle. In
   `fromLines`, feed the **non-deduplicated** token slugs (the existing slug
   `Set` stays for the other axes).
5. `TargetUniverse` — add `allowedCompositions =
   allCompositions(familiesOf(allowedSlugs))`; the domain and normalisation
   denominator.
6. `targetShare` — `Axis.composition` → `1/categoryCount`.
7. `_scoreAll` — a **Composition** section: loop over `allowedCompositions`,
   `gap = _gap(_share(count, total), 1/n)`.
8. `parseTargetKey` — a `comp` case (`rest.split('+')`).
9. No `pickWeighted…` helper needed: the axis is single-valued, so the global
   argmax in `_scoreAll` selects it (like `size`).

## Worker — `lib/getsomepuzzle/generator/worker_io.dart`

`_resolveTarget` — a `CompositionTarget(families)` case:

- Real families = `families` minus `none`.
- `allowedSlugs` = union of the universe's slugs in those families → no other
  family can appear, so the `none` padding matches and the realized
  composition equals the target.
- `preferredSlugs` = gap-weighted slugs **biased toward dominance** (more
  preferred slugs from the 1st family than the 2nd, etc.). A bias, not a hard
  quota — same spirit as `ntypes`/`pair`. Size is then filled by the worker
  loop.

## Generator dashboard — `bin/generate.dart`

- `_CollectionStats` — add `compositions` (`Map<String,int>`) filled via
  `compositionOf` in `fromLines`.
- `_computeAxisTargets` — add the uniform `composition` target.
- `_renderDashboard` — 85 rows is too many for a full histogram; render a
  compact **"Compositions (top deficit)"** panel = the ~12 largest-gap
  buckets, folded into the shared `globalMaxGap`.

## query_corpus — `bin/query_corpus.dart`

Import `package:getsomepuzzle/getsomepuzzle/constraints/families.dart` (still
no Flutter dependency). Add a single-valued **`composition`** axis (key = the
joined triple):

- in `_keysFor` + `validAxes` (so `--group-by` / `--cross` accept it),
- in `validBucketDims` + `_bucketField`.

Because `_Puzzle.slugs` is a deduplicated `Set`, `_parseLine` must also keep
the raw per-instance slug list (or precompute the composition) so the ranking
matches the equilibrium's instance-count definition exactly.

Then `query_corpus --group-by composition --sort count` lists the populated
buckets and `--reverse --top N` the rarest — a direct audit of the 85 buckets
the equilibrium is filling.

## Tests

- `test/families_test.dart` *(implemented)* — guard that every registry slug
  has a family; values ⊆ `kConstraintFamilies`; `compositionOf` ranking, empty
  padding and deterministic tie-break; `allCompositions` size = 85 and shape.
- `test/equilibrium_test.dart` *(to add)* — `compositionCounts` from
  `fromLines`/`withPuzzle`; `allowedCompositions.length == 85` on the full
  universe; `_scoreAll` emits `CompositionTarget`s; `parseTargetKey('comp:…')`
  round-trip; `targetShare(Axis.composition, …)`.

## Verification

```bash
flutter analyze
flutter test test/families_test.dart test/equilibrium_test.dart

dart run bin/query_corpus.dart --group-by composition --sort count
dart run bin/query_corpus.dart --group-by composition --reverse --top 20
dart run bin/query_corpus.dart --cross composition,collection
```

The equilibrium effect is validated by unit tests plus a generation pass run
by the maintainer (not from this tooling). After generation,
`--group-by composition` should trend toward uniform across the 85 buckets.

## Implementation status

- **Done:** `families.dart` (taxonomy + `compositionOf` + `allCompositions`)
  and `families_test.dart` (passing).
- **Remaining:** the equilibrium axis, the worker resolution, the dashboard
  panel, the `query_corpus` axis, the equilibrium tests, and the doc updates
  to `equilibrium.md` / `collection_management.md`.

Suggested commit breakdown:

1. `Add constraint-family taxonomy + composition helper (families.dart) + tests` *(done)*
2. `Equilibrium: add composition axis (top-3 ordered families, 85 buckets)`
3. `Generator dashboard: composition deficit panel`
4. `query_corpus: composition axis (group-by / cross / buckets)`
5. `Docs: constraint families + composition axis`
