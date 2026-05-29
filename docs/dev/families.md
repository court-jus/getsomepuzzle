# Constraint families & the equilibrium "composition" axis

The 17 player-facing constraint slugs are partitioned into five families by
**deduction strategy** — i.e. *how* a constraint narrows the grid, orthogonal
to the `Constraint` class hierarchy in `constraints/`. The taxonomy feeds the
equilibrium engine's **composition** axis, which balances the blend of families
a puzzle is built from rather than individual slugs.

## Taxonomy

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

## Source module — `lib/getsomepuzzle/constraints/families.dart`

Pure Dart, no Flutter imports — usable by both the generator and `bin/` tools:

| Export | Purpose |
|--------|---------|
| `kConstraintFamily` | slug → family mapping (17 entries) |
| `kConstraintFamilies` | fixed display/tie-break order (`line-centric, local, path, group-topology, global`) |
| `kEmptyFamily` | virtual `'none'` family for padding |
| `familyOf(String slug)` | lookup a single slug's family |
| `familiesOf(Iterable<String> slugs)` | distinct families spanned by a set of slugs |
| `compositionOf(Iterable<String> slugInstances)` | compute a puzzle's composition triple (slugs with repeats → length-3 list) |
| `allCompositions(List<String> families)` | enumerate all valid ordered triples for a set of real families (85 for the full five) |

## How the composition axis works in the generator

The equilibrium engine (`lib/getsomepuzzle/generator/equilibrium.dart`) treats
composition like the size axis — atomic, single-valued, uniform target share:

- **`Axis.composition`** — the sixth axis (alongside slug, ntypes, pair, size,
  profile).
- **`CompositionTarget(List<String> families)`** — a target with key
  `'comp:fam1+fam2+fam3'`.
- **`EquilibriumStats.compositionCounts`** — one tally per joined triple,
  populated via `compositionOf(...)` in `fromLines` and `withPuzzle`.
- **`TargetUniverse.allowedCompositions`** — enumerated by `allCompositions`
  over the families present in `allowedSlugs`; forms the normalisation
  denominator.
- **`targetShare`** — uniform: `1 / allowedCompositions.length`.
- **`_scoreAll`** — iterates over every allowed composition, computes its gap,
  and emits `CompositionTarget` candidates. The one with the largest gap is
  picked (same mechanism as the size axis; no `pickWeighted` helper).

When a composition target is resolved (`worker_io.dart`):

1. `allowedSlugs` is restricted to slugs belonging to the target's real
   families — the `none` padding carries no slugs, preventing cross-family
   drift.
2. `preferredSlugs` is biased toward the dominant families in a 3:2:1 ratio
   (most slugs from the first family, fewer from the second, even fewer from
   the third). Within each family, slugs are sorted by their secondary deficit
   score to also advance the slug axis.

The composition deficits are visible on the generator dashboard as a compact
**"Compositions (top deficit)"** panel showing the ~12 largest-gap triples.

## Querying the corpus by composition

`bin/query_corpus.dart` accepts `composition` as a `--group-by` / `--cross`
axis and as a bucket dimension (`--buckets`). The key is the joined triple
(e.g. `path+line-centric+local`). Because the ranking must match the
instance-count definition, `_parseLine` precomputes the composition from raw
(undeduplicated) slug instances:

```bash
# Population of each composition triple
dart run bin/query_corpus.dart --group-by composition --sort count

# Rarest triples
dart run bin/query_corpus.dart --group-by composition --reverse --top 20

# Composition vs. difficulty level
dart run bin/query_corpus.dart --cross composition,collection
```

## Tests

- `test/families_test.dart` — guard that every registry slug has a family;
  values ⊆ `kConstraintFamilies`; `compositionOf` ranking, empty padding and
  deterministic tie-break; `allCompositions` size and shape.
- `test/equilibrium_test.dart` — `compositionCounts` from
  `fromLines`/`withPuzzle`; `allowedCompositions.length == 85` on the full
  universe; `_scoreAll` emits `CompositionTarget`s; `parseTargetKey('comp:…')`
  round-trip; `targetShare(Axis.composition, …)`.
