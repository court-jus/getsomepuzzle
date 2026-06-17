# SH pre-fill — generation by shape motif

Pipeline lives in `lib/getsomepuzzle/generator/prefill/sh.dart`, gated
by `prioritySlugs.contains("SH")` (set by the equilibrium's `profile`
axis picking `ProfileCategory.sh` at 5 %).

Activated **instead of** the regular random-grid prefill
(`preFillRegular`). Returns a solved grid with a single
`ShapeConstraint` already attached; the classic iterative
constraint-adding loop (phase-gated propagation → full solve) runs
after it.

## Pipeline overview

```
preFillSh(width, height, domain, rng):
  1. Pick a shape motif (weighted random from 18 hard-coded motifs)
  2. Place one random variant at a fitting grid position
  3. Fill remaining cells uniformly at random across all non-motif colours
  4. Attach the ShapeConstraint to the solved grid
  5. Sprinkle additional variant positions (50 % chance each)
```

### 1. Motif selection

`_pickShapeMotif` iterates `ShapeConstraint.generateAllParameters` (18
motif strings, colour-instantiated for each domain value), weighted by
bounding-box size (`rows × cols`) raised to `puzzleSize * 0.05`. Base
weights from `ShapeConstraint.baseWeights` provide per-size bias. The
exponent scales preference with puzzle area: small grids get roughly
equal weight, large grids favour big motifs.

### 2. Initial placement

`_placeInitialVariant` shuffles variants, picks the first that fits
within grid bounds, then paints it at a random (row, col) offset.

### 3. Background fill

`_fillRemainingBackground` fills every still-free cell with a
uniformly random choice among all non-motif colours. On domain 2 this
is identical to a single "opposite" colour; on domain 3+ it
distributes across multiple colours, making domain-3 SH puzzles
possible.

### 4. Constraint attachment

`preFillSh` calls `solved.addConstraint(sc)` before returning, so the
`ShapeConstraint` propagates through the main generator loop.

### 5. Additional variants

`_placeAdditionalVariants` calls
`ShapeConstraint.findAdditionalPositions` to locate spots where any
variant fits without breaking `verify()`. Each candidate has 50 %
probability of being accepted; after each paint the position list is
recomputed.

## `findAdditionalPositions`

Located in `lib/getsomepuzzle/constraints/shape.dart:666`. Accepts a
placement whenever every cell in the variant's bounding box is either
free or any non-motif colour (set-based `otherColors` check). This
works correctly on both domain 2 (singleton set → same as old binary
check) and domain 3+ (multiple background colours accepted).

## Domain-3 support

The background fill uses `others = domain.whereNot((c) == color)`,
picking uniformly at random. On domain 3 the third colour naturally
appears on the grid, so `autoShrinkDomain` in the main generator no
longer systematically demotes SH puzzles to domain 2. This was the key
fix over the initial binary-opposite implementation.

## Tests

`test/prefill_sh_test.dart` covers:

- **Domain-3 colour distribution** — verifies that `preFillSh` on a
  3-color palette can produce a solved grid using all three colours.
- **Mixed background in `findAdditionalPositions`** — a bounding box
  containing two different non-motif colours (e.g. white + purple) is
  accepted, where the old binary check rejected it.
- **Domain-2 non-regression** — behaviour with `[black, white]` is
  identical to the original binary implementation.
