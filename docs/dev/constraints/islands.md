# Islands Constraint

The Islands constraint (`IS`) requires every connected group of a given color
to be **isolated from every other group of that color** — including
diagonally. No two distinct groups of the color may touch, even at a corner.

Serialized as `IS:<color>`. `IS:1` means "black islands": all black groups
must be pairwise separated, 8-connectivity-wise.

This is the classic Nurikabe island-separation rule adapted as a global
constraint. It complements `GC` (which counts groups) and `BB`/`SH` (which
constrain their extent/shape) by constraining their **mutual spacing** — a
dimension no other rule touches, since all other constraints reason over
4-connectivity only.

## Syntax

- `IS:1` — every black group must be diagonally isolated from every other
  black group.
- `IS:2` — same rule for white groups.

**Orthogonal contact is not expressible** — two 4-adjacent cells of the same
color are by definition the same group. The operative content of the rule is
therefore exclusively **diagonal contact** between *final* distinct groups.

### Formal violation

The rule constrains the **final** grid: in the solved puzzle, no two cells of
`color` belonging to different connected groups may share a corner.

Judging *open* states relies on **capable cells**: a cell is capable if it
can still host `color` in some future state — it is already coloured, or free
with `color` among its remaining options. Two colour groups end up merged in
some completion iff they are connected through a path of capable cells
(4-connectivity). The capable-component partition only ever **refines** under
forward play: a cell leaves the set when coloured another colour or when an
option is pruned, and nothing ever joins it — so "different component today"
proves permanent separation, while "same component" leaves the state
undecided.

The state is *violated* iff two coloured cells `a`, `b` exist such that:

- `value[a] == value[b] == color`;
- `a` and `b` are diagonal neighbours (`|Δrow| == 1 && |Δcol| == 1`);
- `a` and `b` are in different **capable components** — the contact can
  never be merged away.

Examples bounding the definition (colour = black):

- `_1_ / 1__` — two islands corner-touch but every cell around them is
  free: one capable component, colouring the corner merges everything →
  **not violated**;
- `21_ / 12_` — the corner-touching blacks are walled in by committed
  whites; no future move can merge them → **violated**, even though free
  cells remain elsewhere.

## Implementation

**Location**: `lib/getsomepuzzle/constraints/islands.dart`

`IslandsConstraint extends Constraint`. Field: `color` (CellValue).

- **`slug`** → `'IS'`; **`referencedColors`** → `{color}`;
- **`serialize()`** → `'IS:${cellValueToString(color)}'`;
- **`toString()`** → `'<color> islands'`; **`toHuman(Puzzle)`** → human
  description used by hint messages;
- **`rotated(...)`** → identity clone, like `QA` (colour and rule are
  position-independent);
- no `conflictsWith` override.

Shared helpers: `diagonalNeighbors(puzzle, idx)` lives in
`lib/getsomepuzzle/utils/groups.dart` next to the connectivity utilities;
the capable-set machinery is private to the class.

### verify(Puzzle)

```
comps = capable components (flood over value==color ∪ free-with-color-option)
for each cell a with value == color:
  for each diagonal neighbour b of a:
    if value[b] == color && comps[b] != comps[a]:
      return false
return true
```

Only *permanent* diagonal contact counts — corner-touching coloured cells
whose groups share no capable component can never merge, so the state is
already condemned. Contact between still-connectable groups is legal: the
player can colour the bridge and fuse them into one island.

On a complete puzzle there are no free cells, so the components collapse to
the actual colour groups and this degenerates to the exact final check.
Complexity is `O(cells)` per call (one flood + one scan).

There is no "unreachable-incomplete" category: a state either already
violates the rule or can still be completed by painting the remaining free
cells another colour.

### apply(Puzzle)

Three deduction branches, checked in order:

1. **Impossible** — `!verify(puzzle)` → `Move(..., isImpossible: this)`.

2. **Diagonal-contact prune** (`complexity 1`) — compute the capable
   components once. For every free cell `f` with `color` still in its
   options: if some coloured diagonal neighbour `d` of `f` satisfies
   `comps[d] != comps[f]`, prune `color` from `f` (`RemoveOption`).

   Soundness needs no simulation. Colouring `f` makes `(f, d)` a coloured
   diagonal pair; since components only refine over time, cross-component
   today means cross-component forever, i.e. a permanent violation exactly
   matching `verify`'s criterion. Note `f` itself is always capable, so its
   component is well-defined, and colouring `f` automatically drags every
   group it touches 4-adjacently into one merged region — bridged cases are
   subsumed.

   Guard against the 3-colour no-op livelock: the prune is emitted only when
   `color` is still present in `f`'s options (same convention as `DF`, `GS`).

3. **Mandatory-merge articulation** (`complexity 3`) — list every pair of
   distinct `color` groups that share a corner. Such a pair *must* end up
   merged (branch 1 condemns it otherwise); the rule says the groups must
   merge, not how. If a single free capable cell lies on **every** capable
   path between the pair — detected with `blockingDisconnectsMembers`, the
   same articulation test LT uses — that cell is unavoidable and is forced
   to `color` (`SetValue`). Cells with two disjoint merge routes stay free.

   Reachability precondition: reaching branch 3 means `verify` passed, so
   every touching pair is already same-component and the helper's
   vacuously-true trap cannot fire.

Beyond branch 3's forced merge, IS never guesses placements: it is an
avoidance constraint, like `FM` and `CH` — it forbids placements and lets
counting constraints (`QA`, `GC`, `RC`) do the remaining positive forcing.
The interplay is where the gameplay lives (see Complicities).

### isCompleteFor(Puzzle)

Conservative grayout, same convention as `SH`: `verify(puzzle)` holds **and**
no free cell has `color` among its remaining options.

While free capable cells remain, the capable-component partition keeps
refining — a bridge cell painted the opposite colour splits two components
that used to be one, which can legitimately revive branch-2 prunes or even
create a branch-1 impossibility later. Only a fully resolved capable set
guarantees `apply` can never fire again. The cost is that IS stays lit
longer than strictly necessary on sparse-island boards; correctness wins.

## Parameter generation

`generateAllParameters(width, height, domain, excludedIndices)` yields
`'$color'` for each domain colour — parameter space `O(|domain|)`, the
smallest of any constraint (`CH` is `O(|domain| × 2)`).

Degenerate cases are handled by the generator's standard solution-validity
filter: on grids where the colour forms a single group (or none), `IS` is
vacuously satisfied and non-discriminating; puzzles relying solely on a
vacuous IS are dropped like any other degenerate candidate.

## Rotation

Identity: returns a fresh clone of self, like `QA`. Four rotations round-trip
trivially — covered by `test/rotation_test.dart`.

## Family

`families.dart` maps `'IS' → 'group-topology'` (alongside `GS`, `GC`, `SH`,
`SY`, `MJ`, `BB`). A guard test enforces that the map stays total over every
registered slug.

## Conflicts

No `conflictsWith` override. IS composes cleanly with every same-colour
rule: `GC` bounds how many islands fit, `BB`/`SH` constrain their extent,
`QA` their total mass, `NC:0` locally reinforces isolation. Two IS
constraints on different colours are independent.

## Display

**File**: `lib/widgets/constraints/islands.dart`

Top-bar widget, global scope (no anchor), same slot as `QA`, `GC`, `CH`,
`FM`, `BB`. Renders a square containing a fixed **6×6 virtual mini-grid**
(same device as `ChainWidget`): four islands drawn in the constraint colour
over neutral-grey unfilled cells, visually separated including diagonally —
the icon itself demonstrates the rule. Single fixed pattern: the island
layout never changes; only the tint follows the constraint colour (same
approach as `ChainWidget`'s fixed path).

Index set (row-major, 0–35):

- Island A: `{0, 1, 6}` — top-left L-triomino;
- Island B: `{4, 5, 11}` — top-right L-triomino;
- Island C: `{14, 15}` — centre domino;
- Island D: `{25, 28, 31, 32, 33, 34}` — snaking hexomino along the bottom
  edge (rows `010010` / `011110`).

Every pair of islands is separated by at least one full row/column of grey
(no diagonal corner-touch in the icon — an icon violating its own rule would
be actively misleading).

State colours follow the shared convention: neutral grey background,
green border (valid), deepOrange (invalid), highlightColor (highlighted),
semi-transparent grey on grayout. Hint arrows originate from the widget
toward the pruned or forced cell when an IS move is highlighted.

Since IS renders in the top bar (not inside grid cells), no
`to_flutter.dart` mapping exists (same as `QA`, `GC`, `FM`, `BB`).

## Editor

`showIslandsDialog`
(`lib/widgets/create_page/dialogs/islands_dialog.dart`) offers a colour
picker only — no numeric fields; it reuses the picker half of the shared
`showColorCountDialog` body. `create_page.dart` routes `'IS'` through its
`_pickConstraintParameters` switch.

## UI registry

`lib/widgets/constraints/registry.dart` carries a `constraintUIRegistry`
entry for `'IS'` (with a `buildPreview` callback placed after `IM`),
plus `case 'IS':` arms in `constraintNameForSlug()` (returning
`constraintIslands`) and `constraintExplanationForSlug()` (returning
`constraintExplainIS`). The onboarding dialog, Learning page, help-page
catalogue and generated icons pick the slug up automatically from these
two functions.

## Icons

Website PNGs are exported by `bin/build_constraint_icons.sh`
(see [constraint_icons.md](../constraint_icons.md)); the light and dark
variants live under `assets/constraint_icons/`.

## Localization

ARB keys in `app_en.arb`, `app_fr.arb`, `app_es.arb`:

- `constraintIslands` — EN `"islands"`, FR `"îles"`, ES `"islas"`;
- `constraintExplainIS` — first-contact help text (four-island icon,
  theme-neutral wording).

## Complicities

None implemented. Natural candidates:

- **IS + QA**: quota pressure against barred placements — the count forces
  cells exactly where IS forbids them, pinning islands.
- **IS + GC**: target group count + minimum spacing determines feasible
  island layouts; GC's candidate-based forcing becomes sharper when IS has
  removed candidate cells.
- **IS + CH**: a border-to-border chain cuts the grid; islands cannot sit
  diagonally along both banks in the same corner regions.

Observed-but-parked hypotheses (merge-path feasibility against line quotas)
are recorded in
[constraint_complicity.md](../constraint_complicity.md).

## Generator integration

Enumerated via the registry like every other type — no manual integration.
IS puzzles come from the regular generate-and-filter loop.

### Corpus caveat: pre-fix lines

Lines generated before the mergeability fix of `verify` were validated by a
stricter predicate (any diagonal contact between current groups counted as
violated). That made the generator's uniqueness/solvability filter
over-restrictive during solving: valid alternative completions were rejected
as contradictions, so puzzles whose intended solution was merely one of
several could pass as unique. Concrete example (3×3,
`DF:0.down;NC:8.1.0;CC:1.2.2;IS:2`, prefill cell 4 = white): NC + CC force
cells 5 and 7 white and cell 1 black, DF picks the 0/3 split — but cells 2
and 6 remain genuinely free; all four black/white combinations satisfy every
constraint.

Any IS line generated before the fix is therefore suspect. An audit pass (in
the spirit of the `bin/cleanup_collections.dart` passes) — re-solving every
IS-containing line with the current engine and dropping or regenerating
those without a unique propagation-plus-force solution — closes the gap.

## Not yet implemented

- **Dedicated pre-fill** (`preFillIs`): Nurikabe-style sampling of island
  seeds, bounded growth with mandatory 8-halos, sea flooding, strategic
  reveals and `GC`/`QA` guard rails. The regular loop suffices today because
  random fills frequently satisfy separation on small grids.
- **Diversity sibling treatment**: `IS` and `GC` on the same colour form a
  natural pair (spacing + count = "fit N islands") and could share a
  diversity bucket in the generator's scoring, mirroring the RC+CC note in
  [row_count](row_count.md).
- **Early grayout**: a precise capable-pair criterion was evaluated and
  rejected as unsound (see `isCompleteFor`); a sound cheaper variant than
  the conservative one is unknown.

## Tests

`test/islands_test.dart` follows the canonical contract list:

- Reachable-incomplete state → `verify == true` (multi-island clean grid,
  single snaking group, wrong-colour diagonal contact ignored);
- Mergeability: growable corner contact between two islands →
  `verify == true` (`_1_ / 1__` case); permanent contact across a wall with
  free cells elsewhere → `verify == false` (`21_ / 12_` and the walled
  `120 / 210 / 222` variant);
- Complete-grid violation → `verify == false` (two committed islands
  touching at a corner, both colours);
- `apply` impossible on permanent contradiction;
- `apply` returns `null` when the touched groups are still mergeable —
  centre-diagonal case (`100/000/001`) and the bridged case (`100/000/010`);
- `apply` prunes across a wall: colouring `f` would grow its island into a
  permanent corner-contact (`112/220/221`, prune cell 5);
- `apply` forces the unique merge cell between diagonally-connected
  islands (`222/120/010` → SetValue black on cell 6); no forcing when two
  disjoint merge routes exist (`100/010/000`);
- `apply` returns `null` on safe free cells;
- `apply` no-op guard on already-pruned colour (3-colour livelock
  regression);
- `isCompleteFor` conservative grayout: any free cell still holding the
  colour keeps IS lit;
- serialize round-trip;
- `generateAllParameters` cardinality == `domain.length`;
- rotation identity over four turns.

Secondary coverage:

- `test/is_complete_test.dart` — mirrored grayout group: fixed sea + one
  island + far-apart free corners → **not complete** (conservative rule);
  empty grid → not complete; all free cells stripped of `color` → complete;
- `test/families_test.dart` / `test/equilibrium_test.dart` — family
  mapping totality; IS joins the existing `group-topology` family so the
  composition counts are unchanged.
