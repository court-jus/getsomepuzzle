# Transition Constraint

Constraint type "Transition" (slugs **RT** / **CT**).

Serialized as `RT:1.3` (slug:lineIdx.transitionCount) or `CT:1.3`, it means the line at
`lineIdx` must contain exactly `transitionCount` color changes (transitions) between adjacent
cells of **any** color. A transition is counted whenever two adjacent filled cells have
different values, regardless of which values they are.

Two separate slugs mirror the RC/CC pattern: **RT** for row transitions, **CT** for column
transitions. Each maps to its own class, both extending `LineCentricConstraint`.

## Syntax

`RT:2.3` — row index 2 (third row) must have exactly 3 transitions between different
filled cells.
`CT:0.0` — column index 0 (first column) must have zero transitions → all cells in
the column are the same value (or at most one value appears more than once).

**Valid range**: `transitionCount` ranges from 0 to `lineLength - 1`. A value of
`lineLength - 1` forces strict alternation (checkerboard). The generator must enforce
`transitionCount ≤ lineLength - 1`.

**No color scope**: the transition constraint does **not** attach to a specific color.
It counts every transition between any two different filled values.

### Definition

For a line `L` of length `n`:

```
transitions = count of i in [0, n-2] where L[i] != L[i+1] and L[i] != 0 and L[i+1] != 0
```

Equivalently: count adjacent pairs of filled cells that differ.

## Display

RT/CT is a line-level constraint, displayed in the same peripheral bars as RC and CC,
inside a greyed rounded square. The square shape visually distinguishes RT/CT from RC/CC
(which use a circle). Inside the square a **square-wave glyph** is drawn together with the
count digit: the number of vertical edges (steps) of the wave equals the transition count,
making explicit that the constraint counts colour *changes* between adjacent cells.

- **Row RT**: displayed to the **left** of the row. The wave runs **horizontally** (plateaus
  along the row), sitting above the digit. `count == 0` collapses to a flat horizontal line
  (monochrome row); `count == lineLength - 1` is a tight alternation (checkerboard).
- **Column CT**: displayed **above** the column. The wave runs **vertically** (plateaus along
  the column), sitting to the left of the digit.
- **Color**: neutral black glyph and digit (no colour association); greyed out when the
  constraint is complete, red border when violated.

The wave orientation is supplied by `to_flutter.dart`, which passes `Axis.horizontal` for
`RowTransitionConstraint` and `Axis.vertical` for `ColumnTransitionConstraint` to
`TransitionWidget`.

When both RC and RT are present on the same row, stack them vertically in the left bar:
RT indicator above or below RC, with a smaller font size to fit both.

RT and RC **cannot** both be placed on the same row — they are declared mutually exclusive
via `conflictsWith` (see Conflict rule below). The stacking scenario above exists only
transiently if a puzzle is edited manually; the generator rejects RT+RC on the same row
and CT+CC on the same column.

## Gameplay notes

RT/CT introduces **block-boundary reasoning** — the player counts edges where the fill
value changes, not just cells of a particular color.

**Key deduction patterns:**

### 1. Zero transitions (`count == 0`)

No adjacent filled cells can differ. This means all filled cells in the line must have the
same value. Free cells adjacent to a filled cell are forced to that value. If two filled
cells with different values somehow exist → violation (but the solver catches this early).

### 2. Maximum transitions (`count == lineLength - 1`)

Every adjacent pair must differ. On a 2-color grid this forces strict alternation:
`1, 2, 1, 2, ...` or `2, 1, 2, 1, ...`. One placed cell determines the whole line.

### 3. Intermediate transitions

The player must track how many value changes are possible given the remaining free cells.

**Synergy with RC:** A row with `RC:0.3` (3 black cells) and `RT:0.2` (2 transitions) on a
5-wide row has a unique arrangement: the 3 black cells form a single contiguous block
with 2 boundaries (`[1 1 1 2 2]` or `[2 2 1 1 1]`).

**Complicity with GS:** A group straddling an RT/CT line must have at least 2 transitions
per row/column it crosses (one entry, one exit). If GS constrains the group to a small size,
the group cannot snake across many rows → bounding-box reasoning.

## Implementation

### Shared utilities

**File**: `lib/getsomepuzzle/constraints/transition_utils.dart`

Three shared functions encapsulate all deduction logic, avoiding duplication between
the row and column constraint classes:

```dart
int countTransitions(List<Cell> line)
```

Counts adjacent pairs where both cells are filled and have different values. A transition
involving a free cell is not counted — the free cell might later match its neighbour,
eliminating the transition.

```dart
int countFreePairs(List<Cell> line)
```

Counts adjacent pairs in the line where at least one cell is free.

```dart
bool verifyTransitionLine(Puzzle puzzle, List<Cell> line, int count)
```

Shared `verify`:
- If puzzle is complete: returns `t == count`.
- If `t > count`: return false (already exceeded).
- If `t + freePairs < count`: return false (unreachable).
- Otherwise return true.

```dart
Move? applyTransitionLine(
  Puzzle puzzle,
  List<Cell> line,
  int count,
  CanApply constraint,
)
```

Shared `apply`. Four cases, checked in order:

1. **Already exceeded** — `t > count`: `Move(..., isImpossible: this)`.

2. **Saturated** — `t == count`: all remaining free pairs must **not** create new
   transitions. For each free cell `f` in the line with a filled neighbour `n`:
   - `f` must be `n.value` (to match the neighbour and avoid a new transition).
   - If a free cell has two filled neighbours with conflicting implications → `isImpossible`.
   - Return the first forced cell as a Move (complexity 1).

3. **Unreachable** — `t + freePairs < count`: `Move(..., isImpossible: this)`.

4. **Endpoint parity** — when exactly one endpoint of the line is known and the
   domain has exactly two colours, the transition-count parity determines the
   other endpoint: an even count means both ends are the same colour; an odd
   count means they differ. The free endpoint is forced accordingly.
   - Return the forced Move (complexity 3).

5. **Full need** — `t + freePairs == count`: every free pair **must** produce a transition.
   - For each free cell `f` adjacent to a filled cell `n`: `f` must be
     `domain.firstWhere((v) => v != n.value)` (the other value in the domain, to create a
     transition).
   - If a free cell has conflicting forced values → `isImpossible`.
   - Return the first forced cell as a Move (complexity 2).

Otherwise `null` (constraint active but not yet forcing).

**Domain handling.** The saturated branch (`t == count`) forces a free cell to match its
filled neighbour — that deduction is valid for any domain size, since matching the neighbour
never introduces a transition regardless of how many colours exist. The full-need branch
(`t + freePairs == count`) forces a free cell to **differ** from its neighbour; the
replacement value is only unique when the domain has exactly two colours, so this branch
short-circuits to `null` (no forcing) when `|domain| > 2`.

```dart
List<String> generateAllTransitionParams(int numLines, int maxT)
```

Shared parameter generation. `numLines` is the number of rows (for RT) or columns (for CT).
`maxT` is `lineLength - 1`. No color loop — parameter space is O((width + height) × lineLength).

The range includes `t = 0`, unlike RC/CC which start at 1 (a zero-transition constraint is
meaningful — it forces a monochrome line).

## Complexity weights

| # | Deduction | Weight |
| - | --------- | -----: |
| 1 | Zero transitions (monochrome line) | 0 |
| 2 | Maximum transitions (checkerboard line) | 1 |
| 3 | Intermediate, saturated (`t == count`) | 1 |
| 4 | Intermediate, full need (`t + freePairs == count`) | 2 |
| 5 | Endpoint parity (`t + fp > count` and `t < count`) | 3 |

## Known limitations

- The `freePairs` count in `verify` is an over-approximation. A tighter bound could
  consider that filling a free cell resolves its pair with both neighbours simultaneously.
  The endpoint parity check (same/odd → impossible) partially closes this gap for binary
  domains by catching states where the parity mismatch is already visible from the
  endpoints.
- The full-need branch is binary-only: when `domain.length > 2`, it cannot pick a unique
  "differ from neighbour" value and returns `null`. The saturated branch remains active
  for any domain size.
- RT and RC are natural complicity partners but **cannot share the same line** (conflict).
  The combined deduction "a line with R black cells and T transitions must be arranged as B
  blocks" could be implemented as a future `Complicity` subclass.
