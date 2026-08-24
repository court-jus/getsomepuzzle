# Forbidden Motif Constraint

The Forbidden Motif constraint (`FM`) forbids a given 2D pattern of colours from
appearing anywhere in the solved grid. Any placement of the motif — at any
position, without rotation or mirroring — makes the puzzle invalid.

It is a *local* rule: like `DF`, `NC` and `EY` it reasons about a small
neighbourhood, not a whole line or group. `families.dart` maps
`'FM' → 'local'`.

## Syntax

`FM:12.21` — a 2×2 motif, first row `12`, second row `21` (black over white /
white over black). Rows are joined with `.`; each cell is a single digit
(`1` = black, `2` = white, `3` = purple, `0` = wildcard / any colour).

`FM:101` — a 1×3 motif, black cells at both ends with any-colour cell between:
forbids the pattern black-anything-black in any 3-wide window.

`0` wildcards match any value, so `FM:10` forbids black in any non-last column
entirely.

## Semantics

The motif is matched **as-is** — there is no rotation or mirroring applied at
verify time. A puzzle is valid when no sliding-window placement of the exact
motif exists (`verify` returns `!isPresent(puzzle)`).

`isPresent` is a regex scan (`Motif.isPresent`, base class in
`lib/getsomepuzzle/constraints/constraint.dart`): the motif's rows are joined
with a `.`-per-trailing-column separator (`'.' * (width - motifWidth)`) and
`matchAsPrefix` is tried at every index that leaves room for the motif width.

### Completion and verification

- **`isCompleteFor(Puzzle)`** — `verify` holds **and** no window can still
  place the motif: for every motif-sized window, either a filled cell differs
  from the motif cell, or a free cell has had the motif value pruned from its
  options. When the motif is genuinely impossible, the constraint is complete.
- **`apply(Puzzle)`** — wildcard-substitution deduction: for each non-wildcard
  cell of the motif, a submotif with that cell replaced by a wildcard is
  scanned for (via `Motif.findMotifPositions`). At every found position the
  corresponding grid cell is examined:
  - already the motif colour → `Impossible` (the full motif is present);
  - free with that colour still in its options → `RemoveOption` of the colour.
  Complexity weight grows with motif size:
  `(motif.length * motif[0].length - 2).clamp(0, 3)` — a wildcard inside a
  1×2/2×1 motif is trivial, the same wildcard inside a 3×3 motif needs real
  visual scanning.

### referencedColors

Non-wildcard motif values (`Motif.referencedColors`), so the auto-shrink pass
can drop a colour absent from the solution without orphaning the FM.

## Parameter generation

`generateAllParameters` enumerates motifs of size 1×1, 1×2, 2×1, 2×2, plus
1×3 (when `width > 2`) and 3×1 (when `height > 2`), over the domain colours
plus the `0` wildcard. Larger shapes are gated behind
`_allowBigMotifs = false` and are not generated. Motifs with an entirely
empty edge row/column (all `0`) are filtered out — they would match trivially
and add no constraint.

## Rotation

`rotated` rotates the motif matrix 90° clockwise (`rotate2D90CW`) and
re-serialises it. Rotation only changes the pattern's orientation; the slug
stays `FM` (unlike line constraints, which swap row/column slugs).

## Complicities

- **FMFMComplicity** — two adjacent FMs synthesise composite forbidden
  motifs (e.g. `FM:2.2.1` + `FM:1.2.1` → `FM:0.2.1`). The synthesised motifs
  never appear in `puzzle.constraints`; the apply must list all original FM
  instances as contributors.
- **GSAllComplicity** — when every rejected sealing of a GS move is rejected
  by the same FM, the move carries `slugs = ('GS', 'FM')` so the hint UI can
  say "Group Size + Forbidden Pattern".
- **PABalancedSideComplicity** — PA + FM partial filtering fires on empty
  cells; the move carries `slugs = ('PA', 'FM')`.
- **SYFMComplicity** — symmetry plus FM reasoning (colouring a symmetric pair
  would create the forbidden motif).

## Implementation

**Location**: `lib/getsomepuzzle/constraints/motif.dart`

`ForbiddenMotif extends Motif`. Constructor parses `strMotif` by splitting on
`.` then mapping each row's characters with `cellRepresentationToValue`.

- **`slug`** → `'FM'`
- **`serialize()`** → `'FM:${rows joined with "."}'`
- **`toString()`** → the bare motif string (no slug prefix).

Registered in `constraintRegistry` (`lib/getsomepuzzle/constraints/registry.dart`)
with `fromParams: ForbiddenMotif.new` and `generateAllParameters` pointing at
the static method. `FM` is the first onboarding introducer
(`OnboardingPhase(index: 0, introducing: 'FM', allowed: {'FM'})`).

## Display

`MotifWidget` (`lib/widgets/constraints/motif.dart`) renders the motif as a
mini-grid. Because `FM` is *global* (no anchor cell), it is rendered in the
**top bar above the grid** (`lib/widgets/puzzle.dart`), like `GC`, `SH`,
`Quantity` and `BB` — not inside a cell. The `to_flutter.dart` mapping routes
`ForbiddenMotif` to `MotifWidget`.

l10n: `constraintForbiddenPattern` (name), `constraintExplainFM`
(first-contact help). Editor entry: `showForbiddenMotifDialog`
(`lib/widgets/create_page/dialogs/motif_dialog.dart`), wired in
`create_page.dart`.

## Tests

- `test/constraints_test.dart` — `ForbiddenMotif.verify` (motif absent /
  present / wildcards / 1×3), `DifferentFrom.apply` no-op guards.
- `test/is_complete_test.dart` — `ForbiddenMotif.isCompleteFor` (not complete
  while a placement is still possible).
- `test/rotation_test.dart` — a 2×3 asymmetric motif rotates back to itself
  after four 90° rotations.
- `test/complicities_test.dart` — FM+FM synthesis, FM+GS tagging,
  FM+PA side balancing, wildcard slug fallback.
- `test/contributors_test.dart` — synthesized-motif moves list both original
  FMs as contributors.
- `test/remove_useless_rules_test.dart` — deductive-uniqueness filtering.
