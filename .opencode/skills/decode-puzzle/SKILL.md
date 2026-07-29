---
name: decode-puzzle
description: Decode a puzzle share URL or v2 line into a visual grid and
  constraint listing. Use ONLY when the user shares a puzzle URL (contains
  ?puzzle=) or a v2 line (starts with v2_). Run
  "dart run bin/describe_puzzle.dart" on the input, then present the output
  to the user.
---

# Decode Puzzle

Decode a puzzle share URL or v2 line into a visual grid and constraint
listing.

## Quick decode

When the user gives you a puzzle URL or v2 line, run:

```bash
dart run bin/describe_puzzle.dart "<url_or_line>"
```

The script outputs:
- **Domain**: colour names and count
- **Grid**: character-art grid with row/col headers
  `#` = black, `o` = white, `¤` = purple, `.` = free
- **Constraints**: grouped by type, each with `slug:params  --  human description`

## Deep dive (when you need more detail)

### Parser

The master parser is `normalizeToV2Line()` in
`lib/getsomepuzzle/model/canonical.dart`. It accepts three forms:

1. **Share URL**: `https://leveque.cc/getsomepuzzle/play/?puzzle=v2_...`
   → extracts the `?puzzle=` query parameter.
2. **Bare canonical**: `domain_wxh_prefill_constraints` (no version prefix)
   → prefixed with `v2_`.
3. **v2 line**: `v2_domain_wxh_prefill_constraints_solution_cplx` → passed
   through verbatim.

`Puzzle(parsedLine)` in `lib/getsomepuzzle/model/puzzle.dart` constructs the
puzzle object.

### Display library

`lib/getsomepuzzle/utils/puzzle_display.dart` exposes three functions you can
import directly when you need programmatic access:

- `formatGrid(cellValues, width, height, {showHeaders})` → grid string
- `describeDomain(domain)` → readable colour names
- `formatConstraints(constraints, puzzle)` → slug-grouped listing
- `describePuzzle(puzzle)` → all of the above combined

### Grid cell indexing

Cells are numbered 0..W×H-1 in row-major order. For a 7×8 grid:

```
     0  1  2  3  4  5  6
  0  0  1  2  3  4  5  6
  1  7  8  9 10 11 12 13
  2 14 15 16 17 18 19 20
  ...
```

A cell's grid coordinates: `row = idx ~/ width`, `col = idx % width`.

## Constraint slug reference

| Slug | Name | Parameter format | Example | Meaning |
|------|------|-----------------|---------|---------|
| PA | Parity | `cellIdx.side` | `PA:10.top` | On the given side of the anchor cell, every colour must appear the same number of times |
| RC | Row count | `row.color.count` | `RC:3.1.5` | Row 3 must contain exactly 5 black cells |
| CC | Column count | `col.color.count` | `CC:2.2.3` | Column 2 must contain exactly 3 white cells |
| RT | Row transition | `row.count` | `RT:4.3` | Row 4 must have exactly 3 colour changes between adjacent cells |
| CT | Column transition | `col.count` | `CT:1.4` | Column 1 must have exactly 4 transitions |
| JR | Row majority | `row.colorOrder` | `JR:0.12` | Row 0: black count > white count (strict) |
| JC | Column majority | `col.colorOrder` | `JC:2.21` | Column 2: white > black (strict) |
| FM | Forbidden motif | pattern | `FM:1.2` | The pattern (motif) may not appear anywhere in the grid |
| GS | Group size | `cellIdx.size` | `GS:0.3` | The connected group containing cell 0 must have exactly 3 cells |
| LT | Letter | `cellIdx.cellIdx.letter` | `LT:0.3.A` | A letter-group constraint (sunflower) |
| QA | Quantity | `color.count` | `QA:1.5` | Exactly 5 black cells across the whole puzzle |
| SY | Symmetry | `cellIdx.cellIdx` | `SY:0.8` | Symmetry relationship between two cells |
| DF | Different from | `cellIdx.color.color` | `DF:5.1.2` | Cell 5 must have a different value from cells 1 and 2 |
| SH | Shape | motif | `SH:11.10` | A shape that must appear somewhere in the grid |
| CH | Chain | `cellIdx.start.end` | `CH:1.top.bottom` | A chain constraint connecting sides |
| GC | Group count | `color.count` | `GC:1.2` | Exactly 2 connected groups of black cells |
| MJ | Majority | zone | `MJ:0.0.1.2` | One region of the grid has more black than white |
| NC | Neighbor count | `cellIdx.color.count` | `NC:3.2.4` | Cell 3's neighbours include at most 4 white cells |
| EY | Eyes | `count.color.cells` | `EY:2.1.5` | An "eyes" constraint on 2 cells |
| IM | Implication | pattern | `IM:0.1.2.3` | If cell 0 is white then cell 1 must be black, etc. |
| BB | Bounding box | `color.size.size` | `BB:1.3.3` | All black cells fit in a 3×3 bounding box |

### Domain encoding

The v2 line's second segment encodes the puzzle's colour set as digits:

| Digit | Colour |
|-------|--------|
| 1 | black |
| 2 | white |
| 3 | purple |

`12` → black & white (2 colours). `123` → black, white & purple (3 colours).

### Prefill encoding

The prefill segment uses the same digits as the domain, plus `0` for free:

| Digit | Meaning |
|-------|---------|
| 0 | free / undecided |
| 1 | pre-filled black |
| 2 | pre-filled white |
| 3 | pre-filled purple |

### Merged rule groups

Some row/column pairs are semantically paired and share a display name: `CC`
covers both `CC` and `RC` as "Line count"; `JC` covers `JC` and `JR` as
"Column majority"; `RT` covers `RT` and `CT` as "Transition".
