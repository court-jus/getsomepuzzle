---
name: solve-puzzle
description: Solve a puzzle URL or v2 line and walk through deduction
  steps. Use when the user wants to see how a puzzle is solved, understand
  the solver's reasoning, or check whether a puzzle is solvable. The agent
  runs "dart run bin/solve.dart" on the input and interprets each step.
---

# Solve Puzzle

Solve a puzzle step by step, showing each deduction and its source.

## Quick solve

When the user gives you a puzzle URL (contains `?puzzle=`) or a v2 line
(starts with `v2_`), run:

```bash
dart run bin/solve.dart "<url_or_line>"
```

The script outputs several sections:

### 1. Initial state

```
Puzzle: v2_12_7x8_0000000...  (the raw puzzle line)

Domain: black, white (2 colors)

Grid 7x8:
     0  1  2  3  4  5  6
  0  #  .  .  .  o  .  .
  1  .  .  .  .  .  .  .
  ...

Constraints (4):
  CC (2):
    CC:1.1.2  -- Col 1: 2 black
    CC:3.2.3  -- Col 4: 3 white
  ...
```

- **Domain**: colour set (e.g., "black, white (2 colors)").
- **Grid**: character-art grid with row/col headers. `#` = black, `o` = white,
  `¤` = purple, `.` = free.
- **Constraints**: grouped by slug with serialised form and human description.
  See the constraint slug reference in `decode-puzzle` for meanings.

### 2. Solving steps

```
--- Solving steps ---
Step 1: (0,0) = black  [constraint - CC:1.1.2]
Step 2: (2,3) != white  [complicity - CPL:...]
Step 3: (1,1) = white  [findAMove - FM:...]
```

- Each step shows the cell coordinate `(row,col)`, what was deduced
  (`= colour` for an assignment, `!= colour` for an elimination), and the
  source of the deduction.
- **Sources**:
  - `constraint - <slug:params>` — deduced by a constraint rule.
  - `complicity - CPL:<params>` — deduced by a complicity
    (cross-constraint interaction).
  - `findAMove - <slug:params>` — brute-force probe (trial-and-error).
    This is used when no purely deductive move is available.
- If the solver gets stuck: `Stuck — no deduction possible` (no purely
  deductive or trial move succeeds; the puzzle may be unsolvable or require
  deeper search).

### 3. Final state

When solved:
```
Solution:
     0  1  2  3  4  5  6
  0  #  .  .  .  o  .  .
  1  #  o  .  .  .  .  .
  ...
VALID
```

- **VALID**: all constraints satisfied.
- **INVALID**: constraints violated (with list).

When stuck:
```
Final state (incomplete):
     0  1  2  3  4  5  6
  0  #  .  .  .  o  .  .
  ...
```

- The grid shows whatever was deduced before getting stuck.

## Deep dive (solver internals)

### Solving strategy

The solver (`lib/getsomepuzzle/model/puzzle.dart`) uses three tiers in order:

1. **Constraints** (`p.apply()` → constraint phase) — each constraint's
   `apply()` method fills cells or eliminates options using its own rule
   logic (e.g., row count fills remaining cells, parity ensures even
   distribution). These are purely deductive.

2. **Complicities** (`p.apply()` → complicity phase) — cross-constraint
   interactions. For example, if two constraints together force a cell to
   be a specific colour even though neither alone can deduce it. Each
   `Complicity` has its own `enforce()` method.

3. **findAMove** (`p.findAMove()`) — brute-force: temporarily sets a cell
   to a colour, runs the full deductive solver, and if a contradiction
   results, that colour is eliminated. This is exhaustive but can be
   expensive on large puzzles. Used as a fallback when both constraint
   and complicity phases produce no moves.

### Understanding the step output

When presenting step output to the user, you can explain:

- **What was deduced**: `(r,c) = colour` means the solver proved the cell
  must be that colour. `(r,c) != colour` means that colour was ruled out.
- **Why**: the bracketed source tells you which code deduced it. Look up
  the constraint slug in `describe-puzzle`'s slug reference if needed.
- **What happens at "Stuck"**: the puzzle may be unsolvable, or the solver's
  brute-force heuristics aren't sufficient. A human can try cells the
  solver didn't explore.

### Key source files

| File | Purpose |
|------|---------|
| `bin/solve.dart` | CLI entry point — parses args, iterates lines, calls `_solvePuzzle` |
| `lib/getsomepuzzle/model/puzzle.dart` | `Puzzle.apply()`, `Puzzle.findAMove()`, solver loop |
| `lib/getsomepuzzle/constraints/complicities/complicity.dart` | Complicity base & registry |
| `lib/getsomepuzzle/constraints/<slug>_constraint.dart` | Individual constraint `apply()` logic |
| `lib/getsomepuzzle/model/canonical.dart` | `normalizeToV2Line()` — puzzle input parser |
| `lib/getsomepuzzle/utils/puzzle_display.dart` | `formatGrid`, `describePuzzle` — display helpers |

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
