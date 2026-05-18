# Majority Constraint

New constraint type "Majority" (slug MJ).

Serialized as `MJ:r0.c0.r1.c1.color` (slug:topRow.leftCol.bottomRow.rightCol.targetColor), it
means the rectangular zone delimited by rows `r0..r1` and columns `c0..c1` must contain a
strict majority of cells of the target color — i.e., more than half the cells in the zone must
be of that color.

A puzzle can have multiple MJ constraints covering overlapping or disjoint zones,
creating a system of local inequalities over the affected cells.

## Syntax

`MJ:0.0.1.2.1` — the 2×3 rectangle (rows 0-1, columns 0-2) must have more black cells (color 1)
than white cells. Since the zone has 6 cells, black must occupy at least 4 cells (floor(6/2) + 1).

`MJ:0.0.2.0.2` — the first column (rows 0-2, column 0 only) must have more white cells (color 2)
than black cells. With 3 cells, white must occupy at least 2 cells.

**Zone size**: MJ zones can be any size, odd or even. The target is always
`floor(zoneSize / 2) + 1` cells of the specified color. This means:
- Even-sized zone (e.g., 6 cells): target = 4 (strict majority over 3 each).
- Odd-sized zone (e.g., 5 cells): target = 3 (majority of 5, since 3 > 2).

## Display

MJ is a zone-level constraint rendered as a **dotted rectangle border** inset slightly inside
the zone's bounding box. No icon or digit is displayed — the dotted border alone identifies
the constrained zone.

### Zone border

- **Style**: dotted (dashed) rectangle, same stroke thickness as the readonly cell border.
- **Position**: inset by **6 px** from the zone's outer edge so the border sits *inside*
  the zone rather than overlapping cell borders. The inset avoids visual conflict with
  cell grid lines and readonly cell highlighting.
- **Corners**: square (not rounded) to match the grid's rectilinear aesthetic. The sharp
  corners also distinguish MJ from readonly cell highlights which use rounded borders.
- **Fill**: none — just the border. The underlying cells remain fully visible. (A faint
  tinted fill is reserved for the highlighted state only, see below.)
- **Color** encodes constraint state:
  - **Neutral**: `targetColor` (black for color 1, white for color 2) — the border
    colour itself tells the player which colour must dominate.
  - **Valid**: green (zone complete and majority holds).
  - **Invalid**: red (zone complete but majority violated, or impossible state).
  - **Highlighted**: `highlightColor` (constraint being hinted at; a low-opacity tinted
    fill appears behind the cells during highlight).
  - **Grayout**: grey / semi-transparent (constraint complete, no further deductions).

### No icon

The target color is encoded directly by the **border colour** in its
neutral state (black for color 1, white for color 2), replacing the need for any icon.

The dotted border alone identifies the constrained region, and its colour tells the player
which colour must dominate.

### Constraint type picker preview

In the editor's constraint type picker (`lib/widgets/create_page/dialogs/constraint_type_picker.dart`),
the MJ entry is previewed as a **single cell with a dotted border** — a size-1 majority zone —
rather than a text label. The `_MajorityPreviewPainter` (CustomPainter, defined at the bottom of
the same file) mirrors the dash/gap logic from `MajorityZonePainter`:
- Inset of 6 px, dashed rectangle matching the game's zone rendering.
- Border width, dash length, and gap length computed using the same formulas.
- Colour follows `fgcolor` (the dialog's icon/foreground colour).

### No top-bar indicator
MJ is rendered exclusively as a grid overlay — it does **not** appear in the top
constraint bar. The zone border is its own indicator, always visible in context.

### Hint anchor

When the hint system highlights an MJ deduction, the arrow originates from the **centre
of the zone** (not from a specific cell or icon). This is consistent with zone-level
constraints: the player sees the zone pulsing and the arrow flying from its centre to the
target cell.

## Gameplay notes

MJ tracks "this color must hold at least `target`" inside the zone. Deductions arise
when the remaining free cells exactly match the gap to majority, or when the opposite
colour has already taken too many slots inside the zone.

### Key deduction patterns

#### 1. Free cells == remaining need

If `freeCount == target - currentCount` (just enough free cells to reach majority),
all free cells must be the target color. Every free cell is needed to secure the majority.

This is the **only** deduction MJ produces on its own.

#### 2. Opposite color takes the lead

If `oppositeCount > zoneSize - target` (i.e., the opposite color reaches `floor(zoneSize/2) + 1`),
the state is impossible — the target color can never achieve majority.

Equivalently: `oppositeCount > zoneSize - target` → `isImpossible`.

### Undeduced states

Two common states produce **no deduction**:

1. **Target already has majority** (`currentCount >= target`): the target colour already
   holds more than half the zone. Adding more cells of either colour preserves the
   majority. No cell can be forced.

2. **More than enough space** (`currentCount + freeCount > target`): the target colour
   has sufficient room to grow without every free cell being forced. No single cell can
   be deduced.

### Overlapping zones

Two MJ zones overlapping create rich interaction patterns. For example:
- Zone A requires black majority in `{cells 0-5}`.
- Zone B requires white majority in `{cells 3-8}`.
- The overlap `{cells 3-5}` is contested: both colors claim majority there.
- The player must allocate the overlap such that both zones' inequality constraints hold,
  which often forces specific cells outside the overlap to compensate.

Because each MJ zone is an inequality with slack, the solver (and the player) must
reason about worst-case bounds when overlaps are present rather than solving a linear
system.

### Synergy with QA

QA (global quantity) constrains the total count of a color across the entire grid. An MJ
zone that covers part of the grid constrains the local count. Together they bound the count
everywhere else: `globalTarget - zoneTarget` cells of the target color must go outside the
zone, and the free cells outside must accommodate them.

## Implementation

### Constraint class

**File**: `lib/getsomepuzzle/constraints/majority.dart`

`MajorityConstraint` extends `Constraint`.

Fields: `r0` (int), `c0` (int), `r1` (int), `c1` (int), `targetColor` (int).

Derived (computed lazily, cached after first call): `indicesFor(int width)` — public
method returning the sorted list of cell indices inside the rectangle in row-major order.

```dart
List<int> indicesFor(int width) {
  _zoneIndices ??= [
    for (int r = r0; r <= r1; r++)
      for (int c = c0; c <= c1; c++)
        r * width + c,
  ];
  return _zoneIndices!;
}
```

Used internally by `verify`, `apply`, `isCompleteFor` and externally by the game widget
to highlight the zone when MJ is hinted (`lib/widgets/puzzle.dart`).

- **`slug`** → `'MJ'`
- **`serialize()`** → `'MJ:$r0.$c0.$r1.$c1.$targetColor'`
- **`toString()`** → `'MJ'`
- **`toHuman(Puzzle)`** → `'Zone (R,C)-(R,C) : majority of $targetColor'`

#### Helper: zoneSize

```dart
int get zoneSize => (r1 - r0 + 1) * (c1 - c0 + 1);
int get target => (zoneSize ~/ 2) + 1;
```

The target is always `floor(zoneSize / 2) + 1`, regardless of parity.

#### verify(Puzzle)

```
targetColorCount = zoneIndices.where((i) => puzzle.cellValues[i] == targetColor).length
oppositeColor    = puzzle.domain.firstWhere((v) => v != targetColor)
oppositeCount    = zoneIndices.where((i) => puzzle.cellValues[i] == oppositeColor).length
freeCount        = zoneIndices.where((i) => puzzle.cellValues[i] == 0).length

if puzzle is complete (freeCount == 0):
  return targetColorCount >= target   // strictly > zoneSize/2

// Incomplete: still achievable?
// Maximum possible target-color cells = targetColorCount + freeCount
// Minimum possible opposite cells = oppositeCount (already placed, cannot un-place)
// The target color must be able to reach `target` while the opposite color does
// not exceed `zoneSize - target`.
if targetColorCount + freeCount < target:   return false   // can never reach majority
if oppositeCount > zoneSize - target:        return false   // opposite already has majority
return true
```

Note: `zoneSize - target = zoneSize - (floor(zoneSize/2) + 1) = floor((zoneSize - 1) / 2)`.
This is the maximum number of opposite-color cells that still allows target-color majority.

#### apply(Puzzle)

```
oppositeColor = puzzle.domain.firstWhere((v) => v != targetColor)

currentCount = count of targetColor in zoneIndices
oppositeCount    = count of oppositeColor in zoneIndices
freeCells        = indices in zoneIndices where value == 0

if freeCells.isEmpty: return null

// Case 1: opposite color already too strong
if oppositeCount > zoneSize - target:
  return Move(0, 0, this, isImpossible: this)

// Case 2: not enough space to grow
if currentCount + freeCells.length < target:
  return Move(0, 0, this, isImpossible: this)

// Case 3: just enough free cells to reach majority
if currentCount + freeCells.length == target:
  // All free cells must be target color
  return Move(freeCells.first, targetColor, this, complexity: 0)

return null
```

Three cases only: two impossibility returns, one deduction, one fallback null.
No case for "target already saturated" (returns null — the constraint is already satisfied
and cannot be violated). No case for "opposite at brink" (algebraically equivalent to
case 3 — `oppositeCount == zoneSize - target` ⇔ `currentCount + freeCells.length == target`).

#### isCompleteFor(Puzzle)

```dart
@override
bool isCompleteFor(Puzzle puzzle) {
  if (!verify(puzzle)) return false;
  // Monotone: once the zone is fully filled, no future move can change it.
  return zoneIndices.every((i) => puzzle.cellValues[i] != 0);
}
```

#### generateAllParameters(width, height, domain, excludedIndices)

Enumerate all axis-aligned rectangles within the grid, for each target color. Three filters
are applied up-front so the generator never sees uninteresting shapes:

- `zoneSize < 3` → excluded (a strict majority cannot exist with only 1 or 2 cells).
- Single-row or single-column zones (`h == 1 || w == 1`) → excluded; they overlap too much
  with RC/CC and add little variety.
- Zones covering more than 60 % of the grid → excluded; they overlap too much with QA.
  This filter also subsumes the full-grid case (since `w·h > 0.6·w·h` is always true), so
  no separate full-grid exclusion is needed.

```
for r0 in 0..height-1:
  for r1 in r0..height-1:
    for c0 in 0..width-1:
      for c1 in c0..width-1:
        h = r1 - r0 + 1
        w = c1 - c0 + 1
        zoneSize = h × w
        if zoneSize < 3:                                      continue
        if h == 1 || w == 1:                                  continue
        if zoneSize > (width × height) × 0.6:                 continue
        for color in domain:
          yield '$r0.$c0.$r1.$c1.$color'
```

There is no parity constraint on zone size — odd-sized zones are valid (e.g., a 3×3
zone with target = 5 of the specified color).

**Parameter space**: O(height² × width² × |domain|) before filters, much smaller after.
No further pruning needed.

### Registry

**File**: `lib/getsomepuzzle/constraints/registry.dart`

```dart
(slug: 'MJ', label: 'Majority', fromParams: MajorityConstraint.new,
    generateAllParameters: MajorityConstraint.generateAllParameters),
```

Insert in alphabetical order (between LT and PA, or wherever fits).

### Generator integration

**File**: `lib/getsomepuzzle/generator/generator.dart`

No manual integration needed — the generator uses `generateAllParameters()` from the
registry dynamically.

**Generator guidance**: the three filters above already trim MJ zones that are too large
(`> 60 %` of cells, which also covers the full-grid case), single-row/column (subsumed by
RC/CC), or too small (`< 3` cells). Sweet spots that survive: 2×2, 2×3, 3×3, 3×4
rectangles.

Overlapping zones with different constraint types (e.g., MJ over an LT group, MJ over
an FM-affected area) are encouraged — they create richer cross-constraint reasoning
without conflicting with the inequality.

### Display widget — zone border overlay

**File**: `lib/widgets/majority.dart`

`MajorityZonePainter` (a `CustomPainter`) renders a dotted rectangle border via `CustomPaint`:

- **Position and size**: computed from `(r0, c0, r1, c1)` and `adjustedCellSize`.
  - `left = c0 × adjustedCellSize + 6` (6 px inset)
  - `top = r0 × adjustedCellSize + 6`
  - `width = (c1 - c0 + 1) × adjustedCellSize - 12`
  - `height = (r1 - r0 + 1) × adjustedCellSize - 12`
- **Rendering**: `CustomPaint` with a `Paint` using a dashed path effect and a
  `strokeWidth` matching the readonly cell border thickness.
- **Color**: `targetColor` for neutral, green (valid), red (invalid), `highlightColor` (highlighted).
- **Fill**: none by default. When highlighted, a low-opacity tinted fill is drawn.

**File**: `lib/widgets/puzzle.dart`

MJ zone widgets are rendered in the grid's `Stack` layer, on top of the grid but below
cell tap targets. Collect all `MajorityConstraint` instances from `puzzle.constraints` and
build one `MajorityZoneWidget` per constraint, positioned using `Positioned` inside the
stack.

**Overlapping zones**: each zone keeps its own independent dotted rectangle border. When
two MJ zones overlap, their borders cross visually. This is the simplest approach and keeps
each zone individually identifiable.

**No top-bar indicator**: MJ is rendered exclusively as a grid overlay (no pastille in the
top bar). The zone border is its own indicator.

**No direct click interaction**: the zone border is not tappable. The
constraint can only be selected/highlighted via the hint system (since MJ
doesn't appear in the top bar). This keeps
the overlay purely informational.

**Grayout**: when the constraint is complete (zone fully filled and majority verified),
the border becomes grey / semi-transparent to signal completion, matching the grayout
behavior of other constraints (see `docs/dev/grayout.md`).

This approach does not require changes to `constraintIsInTopBar` or `numberOfTopBarConstraints`
since MJ is rendered directly on the grid (same pattern as NC crosses and GS indicators).

### to_flutter.dart mapping

**File**: `lib/getsomepuzzle/constraints/to_flutter.dart`

```dart
if (constraint is MajorityConstraint) return _majorityOverlay(...);
```

### Highlight and hint arrow

**File**: `lib/widgets/puzzle.dart`

When an MJ constraint is highlighted (via hint mode), all cells in its zone are subtly
highlighted (light background tint). The hint arrow originates from the **centre of the
zone** and points to the specific free cell being forced.

### Help text (localization)

**Files**: `lib/l10n/app_en.arb`, `app_fr.arb`, `app_es.arb`

English:
```json
"constraintMajority": "majority zone",
"constraintExplainMJ": "A dotted rectangle border in black or white indicates that most cells inside must be of that colour (more than half). The border colour itself encodes which colour must dominate."
```

### Editor integration

**File**: `lib/widgets/create_page/create_page.dart`

MJ zones are created via a **two-tap mode** (analogous to LetterGroup):

1. **First tap** on a cell → opens a colour dialog (black/white). The chosen colour becomes
   `_majorityZoneColor`, and the editor enters `_majorityZoneMode = true`.
2. **Second tap** on any cell → the rectangle spanning both corners is computed and the
   `MajorityConstraint` is created via `_addConstraint()`.
3. **Minimum size check**: if the rectangle has fewer than 3 cells (`area < 3`), the zone
   is rejected with a `SnackBar` using the `createZoneTooSmall` translation.
4. **AppBar title**: during zone mode, the title shows `createSecondCorner`.
5. **Cancel button**: a close (`X`) icon in the AppBar exits zone mode without creating.
6. **Zone deletion**: tapping a cell that lies inside existing MJ zones triggers
   `_showMjDeletePicker`, listing each overlapping zone by its `serialize()` string.

**Rendering**: the overlay uses `_buildMjZoneOverlay()` which returns `MajorityZonePainter`
(a `CustomPainter` in `create_page.dart`, mirroring the game's `MajorityZonePainter` in
`lib/widgets/majority.dart`). The painter renders the dotted borders for all MJ zones
directly on the grid canvas.

**No `to_flutter.dart` mapping**: MJ constraints are overlay-only and do not appear in the
top constraint bar. The `Constraint` default `toString()` fallback in `to_flutter.dart`
(which would render `'MJ'`) is never reached during gameplay or editor use.

**Localisation keys added**:
| Key | English | French |
|-----|---------|--------|
| `createSecondCorner` | Tap second corner of MJ zone | Tapez le second coin de la zone MJ |
| `createZoneTooSmall` | Zone must be at least 3 cells | La zone doit contenir au moins 3 cellules |

## Tests

**File**: `test/majority_test.dart` — 31 tests, all passing.

- **verify complete — majority holds**: zone filled, target has majority → true.
- **verify complete — tied**: even-sized zone, equal counts → false.
- **verify complete — minority**: target has fewer cells than opposite → false.
- **verify partial — still achievable**: target under target, free available → true.
- **verify partial — not enough space**: `currentCount + freeCells < target` → false.
- **verify partial — opposite blocking**: `oppositeCount > zoneSize - target` → false.
- **verify partial — all empty**: reachable → true.
- **apply — opposite too strong**: → isImpossible.
- **apply — not enough space**: → isImpossible.
- **apply — just enough space**: → force target color on first free cell.
- **apply — more than enough space**: → null.
- **apply — no free cells**: → null.
- **apply — intermediate, nothing to force**: → null.
- **isCompleteFor — zone has empty cells**: → false.
- **isCompleteFor — zone full + majority**: → true.
- **isCompleteFor — zone full but verify fails**: → false.
- **isCompleteFor — other cells empty but zone full**: → true.
- **serialize round-trip**: standard and odd-sized zone.
- **rotated 90° CW**: rectangle remapped via `(c, height-1-r)`.
- **generateAllParameters**: correct count for 3×3 grid (only 2×2 zones survive → 8 entries).
- **generateAllParameters**: correct count for 2×2 grid (all rectangles excluded → 0).
- **generateAllParameters**: zones have at least 3 cells.
- **generateAllParameters**: full grid excluded.
- **generateAllParameters**: single-row zones excluded.
- **generateAllParameters**: single-column zones excluded.
- **generateAllParameters**: zones > 60 % of grid excluded.
- **generateAllParameters**: sweet spots kept on 4×4 grid (2×2, 2×3, 3×3 all present).
- **target calculation**: even zone, odd zone, single column.

## Complexity weights

| # | Deduction | Weight |
| - | --------- | -----: |
| 1 | Free cells == remaining need → force target | 0 |
| 2 | Overlapping zone reasoning (requires cross-zone inference) | 3 |

MJ has a single native deduction (free cells == remaining need), weight 0 — a
direct counting check. Overlapping MJ zones and MJ+QA interaction require
cross-constraint reasoning and should be handled as future complicity subclasses
(weight 3, typical for multi-constraint deductions).

## Recommended implementation order

1. ~~Constraint class~~ **DONE** — `MajorityConstraint` with `verify`, `apply`, `isCompleteFor`,
   `serialize`, `generateAllParameters`.
2. ~~Tests~~ **DONE** — cover all apply/verify branches, parity-independence, serialization.
3. ~~Registry + generator~~ **DONE** — registered and verified generation works.
4. **Display widget** — zone overlay (dotted border) in `lib/widgets/majority.dart`.
5. **to_flutter.dart** mapping + highlight/arrow.
6. **Help text** + `flutter gen-l10n`.

## Future work: Complicity with QA

When an MJ zone covers a subset of the grid, the global QA count constrains the remaining
cells. A future `MJQAComplicity` could:

- Compute `slack = globalQA.target - zoneTarget`: how many target-color cells must go
  outside the zone.
- If `slack > freeCellsOutside`: contradiction (not enough space outside for the
  remaining target cells).
- If `slack == freeCellsOutside`: all cells outside the zone are forced to the target color.
- If `slack == 0`: all cells outside the zone must be the opposite color.

## Design note: `indicesFor(width)` vs `CellsCentricConstraint`

`MajorityConstraint` exposes its zone cell indices via the public method
`indicesFor(int width)` (cached on first call). The game widget reuses it:

```dart
mjZoneHighlightIndices =
    highlightedConstraint.indicesFor(puzzle.width).toSet();
```

MJ deliberately does **not** extend `CellsCentricConstraint`:

- MJ has no per-cell rendering (it's a zone overlay, not a glyph inside each cell).
  If MJ were a `CellsCentricConstraint`, `Puzzle.cellConstraints[idx]` would include
  it, and `CellWidget` would call `constraintToFlutter(mj, …)` for each cell of the
  zone — which falls back to `Text('MJ')` and renders "MJ" inside every cell of the
  zone. Avoiding that requires filtering MJ out at every consumer of
  `cellConstraints`, which is uglier than just not inheriting in the first place.
- Future complicities (`MJQAComplicity`, …) can still obtain indices through
  `indicesFor(puzzle.width)`. They do not need MJ to be a `CellsCentricConstraint`
  to access its zone.

If a future feature genuinely needs MJ to appear in `Puzzle.cellConstraints`, the
inheritance change is doable but requires changing the registry contract so that
`fromParams` receives the grid width, or adding a `populate(int width)` hook called
by `Puzzle` after parsing — both heavier than the current approach.

## Implementation status

- [x] Constraint class (`majority.dart`) — `verify`, `apply`, `isCompleteFor`, `serialize`,
      `generateAllParameters` with correct logic (3-case apply, strict majority target).
- [x] Tests (`test/majority_test.dart`) — 31 tests covering all apply/verify branches,
      parity-independence, serialization, generation parameters, min-zone-size filter,
      rotation.
- [x] Registry (`registry.dart`) — registered between GC and NC.
- [x] Display widget (`lib/widgets/majority.dart`) — `MajorityZonePainter` (CustomPainter)
      dotted border overlay with target-color neutral state, valid/invalid/grayout colours.
- [x] `to_flutter.dart` — not mapped (MJ is overlay-only, no top-bar indicator).
      Hint arrow originates from zone centre in `puzzle.dart`.
- [x] Help text (`l10n/*.arb`) — `constraintMajority` and `constraintExplainMJ` keys present
      in all three languages.
- [x] Editor integration (`create_page.dart`) — MJ zone mode with two-tap creation,
      `MajorityZonePainter` overlay in `_buildGrid`, zone deletion dialog, min-size check.
- [x] Editor localisation — `createSecondCorner` (AppBar title during zone selection),
      `createZoneTooSmall` (SnackBar when zone < 3 cells).
