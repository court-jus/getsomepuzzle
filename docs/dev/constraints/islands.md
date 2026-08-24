# Islands Constraint

The Islands constraint (`IS`) requires every connected group of a given color
to be **isolated from every other group of that color** — including
diagonally. No two distinct groups of the color may touch, even at a corner.

Serialized as `IS:<color>`. `IS:1` means "black islands": all black groups
must be pairwise separated, 8-connectivity-wise.

This is the classic Nurikabe island-separation rule adapted as a global
constraint. It complements `GC` (which counts groups) and `BB`/`SH` (which
constrain their extent/shape) by constraining their **mutual spacing** — a
dimension nothing else touches, since all existing rules reason over
4-connectivity only and diagonals are currently unconstrained.

## Syntax

- `IS:1` — every black group must be diagonally isolated from every other
  black group.
- `IS:2` — same rule for white groups.

**Orthogonal contact is not expressible** — two 4-adjacent cells of the same
color are by definition the same group. The operative content of the rule is
therefore exclusively **diagonal contact**: two cells of the color that are
8-adjacent (share a corner) but not 4-adjacent can never belong to the same
group.

### Formal violation

The puzzle state is *violated* iff there exist two cells `a`, `b` such that:

- `value[a] == value[b] == color`;
- `a` and `b` are diagonal neighbours (`|Δrow| == 1 && |Δcol| == 1`);
- `a` and `b` are in different 4-connected components of `color`.

Since 4-adjacent same-color cells are always the same component, the third
clause is implied by the first two; it is kept explicit because the
implementation checks per *group pair*, not per cell pair (see `verify`).

## Semantics

### verify(Puzzle)

```
groups = getColorGroups(puzzle, color)
for each ordered pair (G, H) of distinct groups:
  if any cell of G is 8-adjacent to any cell of H:
    return false
return true
```

No reachability analysis is needed, unlike `CH` or `BB`: a violation is
*created* only when a cell is actually coloured, and coloured cells never
change. Any violation-free state is trivially extendable (the player can
always paint the remaining free cells with another colour — the domain has at
least two colours), so `verify` collapses to the single pairwise scan above.
Complexity is `O(groups² × groupSize²)` worst case, tiny in practice.

Reachable-incomplete states → `true`; violated states → `false`; there is no
"unreachable-incomplete" category for this constraint (a state either already
violates the rule or can still be completed by painting everything else).

### apply(Puzzle)

Three deduction branches, checked in order:

1. **Impossible** — `!verify(puzzle)` → `Move(..., isImpossible: this)`.

2. **Diagonal-contact prune** (`complexity 1`) — for every free cell `f`
   with `color` still in its options: compute the *hypothetical group*
   `H(f)` = `{f}` fused with every existing `color` group 4-adjacent to `f`
   (transitively — `getMyColorGroup(puzzle-with-f-colored, f)` gives exactly
   this). If any cell of `H(f)` is 8-adjacent to a cell of a **different**
   existing `color` group, prune `color` from `f` (`RemoveOption`).

   This is sound because the violation `H(f)` ↔ other-group is decided by
   currently coloured cells plus `f` itself: other free cells play no role,
   and groups only ever grow/merge. The prune covers both the direct case
   (`f` sits diagonally between two islands) and the bridged case (`f` is
   4-adjacent to island X, which is diagonal to island Y — colouring `f`
   grows X into Y's corner).

   Guard against the 3-colour no-op livelock: only emit the `RemoveOption`
   when `color` is still present in `f`'s options (same convention as `DF`,
   `GS`).

3. **Pair-starvation prune** (`complexity 2`) — two free cells `f`, `g` that
   are 8-adjacent **to each other**, where colouring either one alone is safe
   (branch 2 passes) but colouring both puts them in different groups (no
   4-path of capable cells joins them), is a latent violation: at least one
   of the two must lose `color`. Emitting a prune requires choosing *which*
   one — unsound in general, so branch 3 is **not implemented initially**
   (documented candidate). The backtracking solver catches these states
   naturally.

**IS never emits `SetValue`.** It is a pure avoidance constraint, like `FM`
and `CH`: it forbids placements and lets counting constraints (`QA`, `GC`,
`RC`) do the positive forcing. This asymmetry is intentional and keeps
`apply` simple; the interplay is where the gameplay lives (see Complicities).

### isCompleteFor(Puzzle)

Let `P` be the *capable set*: cells with `value == color` or (free and
`color ∈ options`). Grayout iff:

1. `verify(puzzle)` holds, **and**
2. every 8-adjacent pair `(a, b)` with both in `P` has `a` and `b` in the
   same current 4-connected component of `value == color` cells.

Intuition: two capable cells sharing a corner across different islands (or
across a not-yet-bridged gap) can still collide once both are coloured;
when no such pair remains, no future move can ever create a violation.
Monotone: `P` only shrinks under forward play, and same-component pairs stay
same-component (components only merge).

A simpler conservative fallback (`verify` holds ∧ no free cell has `color`
in options, i.e. grayout only near grid completion) is acceptable for a
first implementation — it matches the `SH` convention — but greys out much
later than necessary on island-heavy puzzles where IS is the star rule.

## Parameter generation

`generateAllParameters(width, height, domain, excludedIndices)` yields
`'$color'` for each domain colour — parameter space `O(|domain|)`, the
smallest of any constraint (`CH` is `O(|domain| × 2)`).

Degenerate cases are handled by the generator's standard solution-validity
filter: on grids where the colour forms a single group (or none), `IS` is
vacuously satisfied and non-discriminating; puzzles relying solely on a
vacuous IS are dropped like any other degenerate candidate.

## Rotation

Identity: returns a fresh clone of self, like `QA`. Colour and the rule
itself are position-independent. Four rotations round-trip trivially —
covered automatically by `test/rotation_test.dart`.

## Family

`families.dart` maps `'IS' → 'group-topology'` (alongside `GS`, `GC`, `SH`,
`SY`, `MJ`, `BB`). The map must stay total over every registered slug — a
guard test enforces adding the entry.

## Conflicts

No `conflictsWith` override. IS composes cleanly with every same-colour
rule: `GC` bounds how many islands fit, `BB`/`SH` constrain their extent,
`QA` their total mass, `NC:0` locally reinforces isolation. Two IS
constraints on different colours are independent.

Generator diversity consideration (mirroring the RC+CC note in
[row_count](row_count.md)): `IS` and `GC` on the same colour form a natural
pair (spacing + count = "fit N islands"); treat them as siblings in the
diversity score to avoid over-awarding rule_diversity.

## Display

**File**: `lib/widgets/constraints/islands.dart`

Top-bar widget, global scope (no anchor), same slot as `QA`, `GC`, `CH`,
`FM`, `BB`. Renders a square containing a fixed **6×6 virtual mini-grid**
(same device as `ChainWidget`): three islands drawn in the constraint colour
over neutral-grey unfilled cells, visually separated including diagonally —
the icon itself demonstrates the rule.

Illustrative index set (row-major, 0–35):

- Island A: `{0, 1, 6}` — top-left L-triomino;
- Island B: `{4, 5, 11}` — top-right L-triomino;
- Island C: `{14, 15}` — centre domino.

Every pair of islands is separated by at least one full row/column of grey
(no diagonal corner-touch in the icon — an icon violating its own rule would
be actively misleading).

State colours follow the shared convention: neutral grey background,
green border (valid), deepOrange (invalid), highlightColor (highlighted),
semi-transparent grey on grayout. Hint arrows originate from the widget
toward the pruned cell when an IS prune is highlighted.

Since IS renders in the top bar (not inside grid cells), **no
`to_flutter.dart` mapping is needed** (same as `QA`, `GC`, `FM`, `BB`).

## Editor

- `showIslandsDialog`
  (`lib/widgets/create_page/dialogs/islands_dialog.dart`) — a colour picker
  only (no numeric fields); reuses the picker half of the shared
  `showColorCountDialog` body.
- `create_page.dart`: add `case 'IS':` to the
  `_pickConstraintParameters` switch.

## UI registry

`lib/widgets/constraints/registry.dart`:

- import the widget, add a `constraintUIRegistry` entry for `'IS'` with a
  `buildPreview` callback;
- add `case 'IS':` to `constraintNameForSlug()` (returns
  `AppLocalizations` `constraintIslands`);
- add `case 'IS':` to `constraintExplanationForSlug()` (returns
  `constraintExplainIS`).

The onboarding dialog, Learning page, help-page catalogue and generated
icons pick the new slug up automatically from these two functions.

## Icons

Regenerate the website PNGs after the widget exists:
`bin/build_constraint_icons.sh` (see [constraint_icons.md](../constraint_icons.md)).

## Localization

ARB keys in `app_en.arb`, `app_fr.arb`, `app_es.arb`:

- `constraintIslands` — EN `"islands"`, FR `"îles"`, ES `"islas"`;
- `constraintExplainIS` — first-contact help text.

Run `flutter gen-l10n` afterwards.

## Complicities (natural candidates, none initially implemented)

- **IS + QA**: quota pressure against barred placements — the count forces
  cells exactly where IS forbids them, pinning islands.
- **IS + GC**: target group count + minimum spacing determines feasible
  island layouts; GC's candidate-based forcing becomes sharper when IS has
  removed candidate cells.
- **IS + CH**: a border-to-border chain cuts the grid; islands cannot sit
  diagonally along both banks in the same corner regions.
- **PABalancedSide-style partial filtering**: PA sides intersected with
  IS-pruned cells.

## Generator integration

Enumerated via the registry like every type — no manual integration. A
dedicated pre-fill (`preFillIs`, Nurikabe-style: sample island seeds, grow
bounded shapes with mandatory 8-halos, flood the sea with the opposite
colour, attach `IS`, then disambiguate via strategic reveals and `GC`/`QA`
guard rails) is a natural follow-up — **not part of the initial
implementation**. Until then, IS puzzles come from the regular
generate-and-filter loop, which suffices because random fills frequently
satisfy separation on small grids.

## Implementation checklist

Mirror of the "Adding a new constraint" checklist in
[`docs/dev/index.md`](../index.md):

1. **Constraint class** → `lib/getsomepuzzle/constraints/islands.dart`;
   `IslandsConstraint extends Constraint`; field: `color` (CellValue).
   - `slug` → `'IS'`; `referencedColors` → `{color}`;
   - `serialize()` → `'IS:${cellValueToString(color)}'`;
   - `toString()` → `'${cellValueToString(color)} islands'`;
   - `toHuman(Puzzle)` → `'Islands of colour <c>: groups never touch, even
     diagonally'` (or localized equivalent);
   - `rotated(...)` → identity clone; no `conflictsWith` override.
2. **Engine registry** → `registry.dart` entry, alphabetical order
   (between `IM` and `JC`).
3. **Family mapping** → `families.dart`: `'IS': 'group-topology'`.
4. **Rotation coverage** → auto via `test/rotation_test.dart`.
5. **Constraint widget** → `lib/widgets/constraints/islands.dart`.
6. **UI registry** → `buildPreview` + `constraintNameForSlug` +
   `constraintExplanationForSlug` cases (see UI registry section).
7. **Flutter bridge** → not needed (top-bar rendering).
8. **Grid widget** → `puzzle.dart`: ensure `'IS'` is treated as a
   top-bar/global constraint in the `Wrap` of global constraints (same
   list as `GC`/`QA`/`FM`/`BB`).
9. **Editor switch** → `case 'IS':` in `_pickConstraintParameters`.
10. **Icon regeneration** → `bin/build_constraint_icons.sh`.
11. **Localization** → three ARBs + `flutter gen-l10n`.
12. **Generator** → auto via registry.
13. **Tests** → `test/islands_test.dart` (see below).
14. **Analyze** → `flutter analyze`, fix all issues.

## Tests

Primary: `test/islands_test.dart`, following the canonical contract list:

- Reachable-incomplete state → `verify == true` (multi-island clean grid,
  single snaking group, wrong-colour diagonal contact ignored);
- Violated state → `verify == false` (two islands touching at a corner);
- `apply` impossible on contradiction (existing diagonal contact);
- `apply` prunes the direct diagonal-between-islands cell;
- `apply` prunes the bridged case (cell 4-adjacent to island X diagonal
  to island Y);
- `apply` returns `null` on safe free cells;
- `apply` no-op guard on already-pruned colour (3-colour livelock
  regression);
- `isCompleteFor` true/false per the grayout criteria;
- `serialize` round-trip;
- `generateAllParameters` cardinality == `domain.length`;
- rotation identity over four turns.

Secondary additions:

- `test/is_complete_test.dart` — grayout criteria cases (capable pair
  across corners in different components → not complete; same-component
  diagonal pair → complete);
- `test/families_test.dart` / `test/equilibrium_test.dart` — family
  mapping totality; composition counts updated for the new slug.

## Open points

1. **Branch 3 (pair starvation)** — deferred; revisit if generated puzzles
   show backtracking-heavy IS instances.
2. **Grayout precision** — ship the precise capable-pair criterion (more
   code, better UX) or the SH-style conservative one first?
3. **Widget icon** — single fixed pattern vs. per-colour tint only; the
   6×6 three-island icon above assumes one pattern fits all colours.
