# Puzzle difficulty levels

A six-tier ranking (Beginner → Mad) that groups puzzles by the **type of
reasoning** their resolution demands. The goal: composing a progressive
playlist where each tier introduces a new cognitive skill — simple
propagation, then hard propagation, then complicities, then force.

The batch classification script is `bin/classify_difficulty.dart`, which
consumes the enriched `solveExplained()` trace (`SolveStep` carries
`complexity` and `isComplicity` since commit `7c3020b`).

## Structural criteria

Descending cascade, mutually exclusive (a puzzle lands in the highest
category it matches):

| Category    | Criteria                                                                |
|-------------|-------------------------------------------------------------------------|
| **Beginner**| 0 force, 0 complicity, max propagation ≤ 2                              |
| **Player**  | 0 force, 0 complicity, max propagation ≥ 3                              |
| **Advanced**| 0 force, ≥ 1 complicity, max complicity complexity ≤ 3                  |
| **Strong**  | 0 force, ≥ 1 complicity with complexity ≥ 4                             |
| **Expert**  | 1 FORCE move, `forceDepth ≤ 5`                                          |
| **Mad**     | ≥ 2 FORCE moves, or 1 FORCE move with `forceDepth > 5`                  |
| Undetermined| incomplete trace (timeout / contradiction)                              |

`Move.complexity` scale ∈ 0..5, see `lib/getsomepuzzle/model/cell.dart:74`
and `docs/dev/complexity.md`. Complicity detection = `Move.givenBy is
Complicity`.

The intent behind the Expert tier: **"you had to posit a hypothesis to
see it was wrong"**. That deduction by contradiction (the "force") is
qualitatively different from a hard-but-direct propagation chain; the
two tiers (Player and Expert) are therefore kept separate.

### Design decisions

- **Solve duration is not a tier criterion.** A beginner may well enjoy a
  large grid within reach; an expert may stumble on a small complex one.
  Grid size modulates the feel but doesn't change the cognitive tier.
- **No "emptiness" filter baked into the categories.** Instead: prune
  the corpus of over-prefilled puzzles (uninteresting to play
  regardless of tier), then classify what remains. See next section.

## Prefill threshold

The generator (`lib/getsomepuzzle/generator/generator.dart:103`) picks
`ratio` randomly in `[0.75, 1.0]` — `ratio` being the fraction of cells
**left empty** for the player. So initial prefill is bounded at **25 %**.

> Note: the `0.25` on line 257 (`if (currentRatio > 0.25) return null;`)
> is a different concept — the residual ratio after solve with
> constraints, used to reject "too open" puzzles at the end of
> generation. Unrelated to the initial prefill.

The `bin/classify_difficulty.dart` script accepts `--max-prefill F`
(default `0.30`); puzzles whose `readonly/total > F` fall into the extra
category `Overfilled` (and are written to `overfilled.txt` when
`--split-out` is used).

**Selected threshold: 0.30** — slightly more permissive than the
generator contract (0.25), to retain more legacy puzzles without
including the pathological tail. The observed distribution justifies
the choice (cf. histogram below).

### Prefill histogram

Distribution over the 12 210 corpus puzzles (bins of 5 %):

```
[0.00-0.05)    459   3.76%  █████████
[0.05-0.10)  1 164   9.53%  ███████████████████████
[0.10-0.15)  1 831  15.00%  ████████████████████████████████████
[0.15-0.20)  2 062  16.89%  █████████████████████████████████████████
[0.20-0.25)  1 851  15.16%  █████████████████████████████████████
[0.25-0.30)  1 135   9.30%  ██████████████████████
[0.30-0.35)    827   6.77%  ████████████████
[0.35-0.40)    559   4.58%  ███████████
[0.40-0.45)    636   5.21%  ████████████
[0.45-0.50)    290   2.38%  █████
[0.50-0.55)    430   3.52%  ████████
[0.55-0.60)    272   2.23%  █████
[0.60-0.65)    266   2.18%  █████
[0.65-0.70)    186   1.52%  ███
[0.70-0.75)    103   0.84%  ██
[0.75+]        252   2.07%  (tail up to 0.96)
```

Cumulative at round thresholds:

| Threshold ≤ | Kept     | %       |
|-------------|---------:|--------:|
| 0.20        |   5 516  |  45.2 % |
| 0.25        |   7 367  |  60.3 % |
| 0.30        |   8 502  |  69.6 % |
| 0.40        |   9 888  |  81.0 % |
| 0.50        |  10 814  |  88.6 % |

**Unimodal distribution**, mode at `[0.15-0.20)`. The distribution is
continuous; neither 0.20 nor 0.25 is a natural breakpoint. To retain
more legacy puzzles we keep **0.30** as the practical threshold: 8 502
puzzles pass (69.6 %) versus 7 367 at 0.25 (60.3 %). Beyond 0.50 the
tail (~11 %, 1 396 puzzles) groups pathological cases like `LT:A.8.23`
at 88 % prefill — clearly to be pruned.

### Pathological case

`v2_12_5x5_1222121202211112210121202_LT:A.8.23_..._11` has 22 readonly
cells out of 25 = **88 %** prefill. Not a recently generated puzzle; to
be removed from the corpus.

### Tutorial

On 23 puzzles from `tutorial.txt`, 8 (35 %) exceed the 0.25 threshold.
This is **expected and intended**: tutorial puzzles are deliberately
heavily pre-filled to guide the player toward the rule being taught.
They don't participate in difficulty classification but stay in the
collection.

## Distribution over 100 % of the corpus

Run on the 12 187 puzzles in `assets/default.txt` (collection2 and
collection3 merged in), `--max-prefill 0.30` filter:

| Category          | Output file        | Total  | % global | % filtered |
|-------------------|--------------------|-------:|---------:|-----------:|
| Beginner          | `1-easy.txt`       |  1 750 |   14.4 % |    20.3 %  |
| Player            | `2-player.txt`     |  1 147 |    9.4 % |    13.3 %  |
| Advanced          | `3-advanced.txt`   |  1 749 |   14.4 % |    20.2 %  |
| Strong            | `4-strong.txt`     |  2 291 |   18.8 % |    26.5 %  |
| Expert            | `5-expert.txt`     |    728 |    6.0 % |     8.4 %  |
| Mad               | `6-mad.txt`        |    975 |    8.0 % |    11.3 %  |
| Overfilled > 30 % | `overfilled.txt`   |  3 542 |   29.1 % |        —   |
| Undetermined      | `undetermined.txt` |      5 |    0.0 % |     0.06 % |
| **Total**         |                    | 12 187 |    100 % |     100 %  |

```
Beginner   ████████████████          20.3 %
Player     ██████████                13.3 %
Advanced   ████████████████          20.2 %
Strong     █████████████████████     26.5 %
Expert     ██████                     8.4 %
Mad        █████████                 11.3 %
```

## Summary

The distribution reflects **a monotonic cognitive progression**:

| Tier      | Required skill                                          | % filtered |
|-----------|---------------------------------------------------------|-----------:|
| Beginner  | simple propagation (saturation, local counting)         |    20.3 %  |
| Player    | hard propagation (articulation, enumeration)            |    13.3 %  |
| Advanced  | simple complicities (2-constraint interactions)         |    20.2 %  |
| Strong    | hard complicities (multi-constraint enumeration)        |    26.5 %  |
| Expert    | hypothesis + contradiction (force, depth ≤ 5)           |     8.4 %  |
| Mad       | heavy force (long chains or multiple hypotheses)        |    11.3 %  |

The Expert tier is deliberately narrower than the others because it
corresponds to a major qualitative jump in reasoning (hypothesis vs.
deduction). Its rarity is expected, not an anomaly.

29 % of the corpus is over-prefilled (> 30 %) and isolated in
`overfilled.txt`. Those puzzles violate the generator contract (`ratio`
∈ [0.75, 1.0], so max 25 % prefill) and are candidates for a later
cleanup.

## Generator integration

Level computation is wired directly into `PuzzleGenerator.generateOne`
(`lib/getsomepuzzle/generator/generator.dart`) which now returns
`(line, level)` instead of `String?`. No extra solve is required: the
`solveExplained()` that validates the puzzle's deducibility is also the
one used to classify.

The tier travels up to `bin/generate.dart` via the `level` field on
`GeneratorPuzzleMessage`. The CLI has two modes:

- `--output FILE`: every puzzle is appended to the file (legacy).
- *without `--output`*: automatic routing per tier to
  `assets/<level>.txt` (`1-easy.txt` … `6-mad.txt`). Out-of-cascade
  tiers `Overfilled` and `Undetermined` are never emitted by the live
  generator, so no file is opened for them in that mode.

## UI integration

On the player side, the six tier files replace the legacy `default` /
`collection2` / `collection3` collections (merged then re-split in
early 2026-05). The changes:

- **`pubspec.yaml`**: the six `assets/<level>.txt` + `tutorial.txt` +
  `overfilled.txt` (kept for future audits) are declared.
- **`Database._builtInCollectionKeys`**
  (`lib/getsomepuzzle/model/database.dart`) lists the new keys:
  `tutorial`, `1-easy`, `2-player`, `3-advanced`, `4-strong`,
  `5-expert`, `6-mad`, `custom`.
- **`Database.entryCollectionKey = '1-easy'`** is used as default
  target in `open_page.dart` (end of tutorial) and `main.dart`
  (primary "Start playing" button).
- **Legacy migration**: if `SharedPreferences` still holds
  `collectionToLoad = "default"` (or `collection2`/`collection3`),
  `loadPuzzlesFile` automatically redirects to `1-easy` rather than
  falling back to `tutorial`.
- **Translated labels** in `lib/l10n/app_{en,fr,es}.arb`:
  `collectionTutorial`, `collectionEasy`, `collectionPlayer`,
  `collectionAdvanced`, `collectionStrong`, `collectionExpert`,
  `collectionMad`. Bundle exposed via the `CollectionLabels` class so
  `Database` isn't coupled to l10n.
- **Icons** (`UniconsLine`) follow a cognitive progression:
  `smile` → `brain` → `graduation_cap` → `medal` → `trophy` → `fire`.
  Tutorial keeps `baby_carriage` and `custom` keeps `Icons.build`.

### Player adaptation

The six tiers tie into the adaptation system described in
`docs/dev/adapt_to_player.md`:

- **Batch cap**: `preparePlaylist()` truncates each tier playlist to 20
  puzzles (`Database.playlistBatchSize`). `tutorial`, `custom`, and
  user playlists are not capped.
- **Recommendation**: `Database.recommendedCollectionKey` maps
  `playerLevel` (0..100, anchored at 50) to a tier via fixed thresholds
  (`recommendedLevelFor` in `level.dart`). Surfaced as a star in the
  `open_page` dropdown and as a "Try X" button in `EndOfPlaylist`.
- **Continue / Switch**: at every batch end, `EndOfPlaylist` offers
  continuing in the current collection (a new batch of 20) or
  switching to the recommended one. The player keeps control — the app
  never changes tier on its own.
