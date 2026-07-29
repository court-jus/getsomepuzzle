---
name: create-scenario
description: Takes solving steps from the solve-puzzle skill and creates an
  autopilot scenario file (docs/scenario/<name>.txt) with dialog explanations
  for each deduction step. Use this when the user asks to "create a demo",
  "generate a scenario", "make a replay", or "show how to solve" a puzzle.
  The skill runs the solver, parses every deduction step, groups them by
  constraint source, generates dialog explanations, and writes a scenario
  file that the autopilot engine can play back.
---

# Create Scenario

Turns a puzzle's solving steps into an autopilot scenario that replays the
solution with explanatory dialogs at each constraint deduction.

## Workflow

When the user gives you a puzzle URL (contains `?puzzle=`) or a v2 line
(starts with `v2_`):

### 1. Run the solver

```
dart run bin/solve.dart "<url_or_line>"
```

Save the full output — you will need every section.

### 2. Parse the solver output

Extract the following fields from the output text:

| Data | Regex / pattern | Example |
|------|----------------|---------|
| **v2 line** | `Puzzle: (.+)` | `v2_12_3x3_010102100_GS:5.1;FM:111_1:121212212` |
| **Domain** | `Domain: (.+) \(` | `black, white` (extract the colour names) |
| **Domain count** | `\((\d+) colors\)` | `2` |
| **Grid dims** | `Grid (\d+)x(\d+):` | width=7, height=8 |
| **Solving steps** | Between `--- Solving steps ---` and either `Solution:` / `Final state` / `Stuck` / `IMPOSSIBLE` | see below |
| **Each step** | `Step (\d+): \((\d+),(\d+)\) (=|!=) (\w+)  \[(constraint\|complicity\|findAMove) - (.+)\]` | step=1, row=0, col=2, op=!=, colour=black, foundBy=constraint, source=FM:2 |
| **Solved?** | `VALID` at end → complete. `INVALID` or `Final state (incomplete)` → not solved. `Stuck` → stuck. | |

Also capture the **initial-state grid** (the grid printed before `--- Solving steps ---`) so you can later identify which cells are **pre-filled** (i.e. already filled before any solver step). Those cells should never appear as targets of `setValue` in the scenario.

**Pre-filled cells** are the cells in the initial grid that are `.` = free.

### 3. Skip puzzles that are not fully solved

If the solver output does **not** contain `VALID`, abort: inform the user that
the puzzle could not be solved and cannot be turned into a scenario.

### 4. Filter and transform the steps

**Pre-filled check:** skip any step whose `(row,col)` was already non-free
(`#`, `o`, or `¤`) in the initial grid. Those cells were already set before
the solver started.

**3-color domain guard:** if the domain count is 3, log a warning and skip
all steps whose `!=` (elimination) operations — an elimination in a 3-colour
puzzle leaves 2 possibilities, so `setValue` cannot be used. Only `=`
(assignment) steps are included in the scenario.

**2-colour `!=` → `=` conversion:** every `!=` step becomes a `setValue` of
the *other* colour (e.g. `(0,2) != black` → `setValue 2,0,white`).

### 5. Group steps

Group the (filtered) steps by their **source** field (the text after the
`foundBy - ` prefix). Consecutive steps with the same source form one group.
Each group produces:

1. A `mouseTo <source>` action (to point at the relevant constraint widget)
   — **skip** if the source is a complicity name (e.g.
   `PABalancedSideComplicity`) or `TrialDeduction`, since those have no
   widget.
2. A `dialog` explaining the rule and what it deduces.
3. A `wait` for reading time (dynamic, see below).
4. A `dialog` (close).
5. A short `wait` (e.g. 200ms).
6. Each cell assignment in the group as `mouse <col>,<row>` + `setValue`.

**Special handling by foundBy type:**

| foundBy | Grouping | Dialog content |
|---------|----------|----------------|
| `constraint` | Group by source (`FM:2`, `GS:0.1`, etc.) | Explain the constraint rule in plain language, referencing the specific cells in the group. Use the constraint slug reference below for explanations. |
| `complicity` | Group by complicity name (`PABalancedSideComplicity`, etc.) | Explain the cross-constraint interaction. Skip `mouseTo` (no widget). |
| `findAMove` | **All** findAMove steps into one group with source `TrialDeduction` | Explain trial-and-error: "The solver tried each possible colour for these cells and ran all rules each time. Only one colour avoided a contradiction for each cell." |

### 6. Generate the scenario file

**Structure:**

```scenario
loadState <v2_line>
wait 500
# --- Group 1: first constraint ---
mouseTo FM:2
wait 200
dialog "Forbidden Pattern" "The FM:2 pattern is forbidden. Since \
cell (0,2) is adjacent to an existing black cell, setting it to black \
would create the forbidden pattern. Therefore (0,2) must be white."
wait <dynamic_read_time>
dialog
wait 200
mouse 2,0
wait 100
setValue 2,0,white
wait 100
# --- Group 2: next constraint ---
...
# --- Finished ---
mouseTo hint
wait 300
dialog "Solved!" "The puzzle is complete!\nAll constraints are satisfied."
wait 3000
dialog
```

**Rules:**
- `loadState` always first, then `wait 500` for the UI to settle.
- Each group starts with `mouseTo <source>` (skipped for complicity groups).
- Dialog title: the readable constraint name (see slug reference), the
  complicity readable name, or `"Trial Deduction"`.
- Dialog body: natural-language explanation that answers "why does this
  constraint force these cells?". Reference the specific cells in the group
  by coordinate.
- Dialog read time: **dynamic** — count the words in the dialog body,
  multiply by 300 ms, clamp to **min 2000 ms / max 8000 ms**.
- After each dialog, close it, wait 200 ms, then execute the assignments.
- Between mouse and setValue: `wait 100`.
- Between setValue and the next mouse: `wait 100`.
- End with a "Solved!" dialog (fixed 3000 ms read time).

**Dialog explanation templates (by slug):**

| Slug(s) | Dialog title | Explanation template |
|---------|-------------|----------------------|
| CC, RC | Row/Column Count | "Each [row/column] must contain exactly N cells of colour C.\n[List cells from the group:] (r,c) is the last unfilled cell → it must be C." |
| FM | Forbidden Pattern | "The pattern FM:PATTERN is forbidden in the grid. Making (r,c) colour X would complete this pattern — therefore it must be the opposite colour." |
| GS | Group Size | "Cell IDX must belong to a connected group of exactly SIZE cells.\n[List cells from the group:] Since the group is full, surrounding cells must be the opposite colour to isolate it." |
| PA | Parity | "On the [side] side of cell IDX, every colour must appear equally often. Remaining free cells must balance the count → (r,c) = C." |
| LT | Letter Group | "Letter-group constraint: cells sharing letter X must form a specific shape and share the same colour pattern. This forces (r,c) to C." |
| JR, JC | Majority | "In this [row/column], one colour must outnumber the other. The remaining cells must be C to achieve the majority." |
| RT, CT | Transition | "This [row/column] must have exactly N colour changes. The current pattern means (r,c) must be C to reach (or stay within) that limit." |
| QA | Quantity | "The puzzle must contain exactly N colour C cells. Since N are already placed, (r,c) must be C to reach the total (or: cannot be C)." |
| SY | Symmetry | "Symmetry constraint: cell (r,c) mirrors another cell. That cell is C, so this one must be C as well." |
| DF | Different From | "Cell (r,c) must differ from a set of other cells. Those cells are C, so this cell cannot be C → it must be the opposite." |
| SH | Shape | "A shape motif must appear somewhere in the grid. The current arrangement forces (r,c) = C to complete the shape." |
| CH | Chain | "Chain constraint: the chain from cell A to cell B must follow specific rules. This forces (r,c) = C." |
| GC | Group Count | "There must be exactly N groups of colour C in the puzzle. The current group count forces (r,c) = C." |
| MJ | Majority (zone) | "In this zone of the grid, black must outnumber white. This forces (r,c) = C." |
| NC | Neighbour Count | "Cell (r,c) has at most N neighbours of colour C. Given the filled neighbours, this cell must be C (or cannot be C)." |
| EY | Eyes | "Eyes constraint: the pattern formed by these cells must have exactly N of colour C. This forces (r,c) = C." |
| IM | Implication | "If one cell is a certain colour, another must be a different colour. This chain of implications forces (r,c) = C." |
| BB | Bounding Box | "All colour C cells must fit in an N×M box. The current bounding box forces (r,c) = C." |

For **complicity** sources, use this table:

| Complicity name | Dialog title | Explanation |
|-----------------|-------------|-------------|
| `PABalancedSideComplicity` | Parity + Others | "The Parity constraint and other rules interact: on this side, each colour must appear equally, but nearby constraints limit the options. Together they force the only remaining colour." |
| `LTFMComplicity` | Letter + Forbidden Pattern | "A letter-shaped group and a forbidden pattern together eliminate possibilities. The letter group's fixed cells, combined with the banned motif, leave only one valid colour." |
| `FMFMComplicity` | Dual Forbidden Patterns | "Two different forbidden patterns overlap in their effect on this cell. Neither pattern alone forces the cell, but together they cover all but one colour." |
| `SYFMComplicity` | Symmetry + Forbidden Pattern | "A symmetry constraint pairs this cell with another, and a forbidden pattern restricts the colours. Together they force this cell's colour." |
| `GSQAComplicity` | Group Size + Quantity | "The group containing this cell must be exactly N cells, and the puzzle must contain exactly M cells of each colour. These two totals together force the assignment." |
| `LTGSComplicity` | Letter + Group Size | "A letter-shaped group's size constraint and another group-size rule interact. The fixed cells in the letter shape leave only one colour plausible for this cell." |
| `GSAllComplicity` | Group Size + All Constraints | "The group-size rule for this cell interacts with multiple other constraints simultaneously, narrowing down to a single valid colour." |
| `SHGSComplicity` | Shape + Group Size | "A shape constraint and a group-size constraint intersect. The shape limits the arrangement, while the size limits the group, together forcing this cell." |
| `GSGSComplicity` | Dual Group Sizes | "Two different group-size constraints interact. Cell (r,c) belongs to one group of size N, but a neighbouring group of size M limits its colour options — only one remains." |

For **findAMove** (use one group with this single explanation):

| foundBy | Dialog title | Explanation |
|---------|-------------|-------------|
| `findAMove` | Trial Deduction | "The solver ran out of purely deductive rules. It tried each possible colour for these cells and propagated all constraints. Each wrong colour led to a contradiction. Only [colour] remained possible for each cell. This proves the result by exhaustion." |

### 7. Generate the filename

Analyse the **constraint slugs** from all steps (the slug part of the source,
e.g. `FM` from `FM:2`, `GS` from `GS:0.1`):

1. Count the **unique** constraint slugs across all steps.
2. If the steps contain any `findAMove` step, prefix the name with `intricate_`.
3. Pick the name:
   - 1 unique slug → `<slug>_only` (e.g. `FM_only`, `GS_only`)
   - 2 unique slugs → `<slug1>_<slug2>` sorted alphabetically (e.g. `FM_GS`, `LT_PA`)
   - 3+ unique slugs → `mixed_constraints`
4. Check if `<name>.txt` already exists in `docs/scenario/`:
   - If not, use `<name>.txt`.
   - If it exists, try `<name>_1.txt`, `<name>_2.txt`, etc. (increment until
     the file does not exist).

### 8. Write the file

```
docs/scenario/<generated_name>.txt
```

### 9. Present the result

Tell the user:
- The scenario file path.
- How many steps/groups it contains.
- How many cells it sets.
- The constraint types involved.
- How to run it:
  ```
  getsomething --scenario=docs/scenario/<generated_name>.txt
  ```

## Constraint slug reference

See the `decode-puzzle` skill for the full table of slug -> meaning mappings.

## Example

Running the solver on
`v2_12_3x3_010102100_GS:5.1;FM:111_1:121212212` produces steps
like `(2,0)=black  [constraint - GS:5.1]` and `(0,0)=white  [constraint - FM:111]`.

The skill generates `docs/scenario/GS_FM.txt`:

```scenario
loadState v2_12_3x3_010102100_GS:5.1;FM:111_1:121212212
wait 500
# --- Group: GS:5.1 ---
mouseTo GS:5.1
wait 200
dialog "Group Size" "Cell 5 must be in a connected group of exactly 1 cell.\
This means it must be isolated. The cells touching it — (2,0), (1,1), (2,2) —\
must be the opposite colour (black) to ensure the group stays size 1."
wait 3000
dialog
wait 200
mouse 2,0
wait 100
setValue 2,0,black
wait 100
mouse 1,1
wait 100
setValue 1,1,black
wait 100
mouse 2,2
wait 100
setValue 2,2,black
wait 100
# --- Group: FM:111 ---
mouseTo FM:111
wait 200
dialog "Forbidden Pattern" "The pattern FM:111 — three black cells in a row —\
is forbidden. Row 0 already has two black cells at (0,1) and (0,2). Making\
(0,0) black would complete the pattern. Therefore (0,0) must be white."
wait 2500
dialog
wait 200
mouse 0,0
wait 100
setValue 0,0,white
wait 100
mouse 1,2
wait 100
setValue 1,2,white
wait 100
# --- Finished ---
mouseTo hint
wait 300
dialog "Solved!" "The puzzle is complete!\nAll constraints are satisfied."
wait 3000
dialog
```

## Key files

| File | Purpose |
|------|---------|
| `docs/dev/autopilot.md` | Autopilot action reference, format docs |
| `docs/scenario/` | Output directory for generated scenarios |
| `bin/solve.dart` | CLI solver that produces the step output |
| `lib/getsomepuzzle/utils/puzzle_display.dart` | Grid/constraint formatting helpers |
| `lib/getsomepuzzle/model/canonical.dart` | Puzzle line parser |
