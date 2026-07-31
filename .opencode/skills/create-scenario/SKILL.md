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
Each group produces a **three-dialog sequence** — rule → already-known →
deduction — with a mouse movement between the first two dialogs to show the
relevant already-set cells:

1. A `mouseTo <source>` action (to point at the relevant constraint widget)
   — **skip** if the source is a complicity name (e.g.
   `PABalancedSideComplicity`) or `TrialDeduction`, since those have no
   widget — followed by `wait 200`.
2. **Rule dialog**: the constraint rule in one short sentence (title: the
   readable constraint name), `wait 3000`.
3. `dialog` (close), `wait 500`.
4. A **TODO section**: a commented-out skeleton of `# mouse <col>,<row>` +
   `# wait 500` pairs that will show the relevant already-set cells (filled
   in manually by the user; copy the pair for each cell to show).
5. **Already-known dialog**: one short sentence about what is already known
   (title: `"..."`), `wait 3000`.
6. **Deduction dialog**: one short sentence with the conclusion (title:
   `"..."`) — shown immediately after, *replacing* the already-known dialog
   without closing it — `wait 3000`.
7. `dialog` (close), `wait 200`.
8. Each cell assignment in the group as `mouse <col>,<row>` + `wait 100` +
   `setValue` + `wait 1000`.

**Special handling by foundBy type:**

| foundBy | Grouping | Dialog content |
|---------|----------|----------------|
| `constraint` | Group by source (`FM:2`, `GS:0.1`, etc.) | Explain the constraint rule in plain language. Use the constraint slug reference below for explanations. |
| `complicity` | Group by complicity name (`PABalancedSideComplicity`, etc.) | Explain the cross-constraint interaction. Skip `mouseTo` (no widget). |
| `findAMove` | **All** findAMove steps into one group with source `TrialDeduction` | Explain trial-and-error: "The solver tried each possible colour for these cells and ran all rules each time. Only one colour avoided a contradiction for each cell." |

### 6. Generate the scenario file

**Structure:**

```scenario
background bottomBarBg
dialog "Welcome!" "Let's solve a puzzle together"
wait 2000
loadState <v2_line>
wait 500
background transparent
# <source1>
mouseTo <source1>
wait 200
dialog "<Constraint Name>" "<rule, 1 sentence>"
wait 3000
dialog
wait 500
# TODO: Mouse to relevant already-set cells
# mouse <col>,<row>
# wait 500
dialog "..." "<what is already known, 1 sentence>"
wait 3000
dialog "..." "<deduction, 1 sentence>"
wait 3000
dialog
wait 200
mouse <col>,<row>
wait 100
setValue <col>,<row>,<colour>
wait 1000
# <source2>
...
# End
dialog
wait 3000
background bottomBarBg
dialog "Puzzle solved!" "Go try it by yourself at leveque.cc/getsomepuzzle"
wait 2000
dialog
```

**Rules:**
- **Intro block**: the scenario always starts with `background bottomBarBg`,
  a `dialog "Welcome!" "Let's solve a puzzle together"`, `wait 2000`, then
  `loadState <v2_line>` + `wait 500`, then `background transparent` — the
  intro dialog gets a filled background; after the puzzle loads the
  background is removed so the grid is fully visible.
- **Outro block**: the scenario always ends with `dialog` (close any open
  dialog), `wait 3000`, `background bottomBarBg`,
  `dialog "Puzzle solved!" "Go try it by yourself at leveque.cc/getsomepuzzle"`,
  `wait 2000`, `dialog` (close).
- Each group starts with `mouseTo <source>` (skipped for complicity groups)
  + `wait 200`.
- Each group produces **three short dialogs**:
  1. **Rule dialog** — the constraint rule, one sentence. Title: the
     readable constraint name (see slug reference), the complicity readable
     name, or `"Trial Deduction"`.
  2. **Already-known dialog** — one sentence about what was established
     before this group. Title: `"..."`.
  3. **Deduction dialog** — one sentence with the conclusion. Title:
     `"..."`. It is shown immediately after the already-known dialog,
     *replacing* it (no close in between) so the narration flows.
- **TODO section**: between the rule dialog and the already-known dialog,
  insert a commented-out skeleton that the user will fill in manually to
  move the mouse over the relevant already-set cells:
  ```
  # TODO: Mouse to relevant already-set cells
  # mouse <col>,<row>
  # wait 500
  ```
  Repeat the `# mouse` + `# wait` pair once per cell the user needs to show
  (copy-paste).
- Dialog text: **one sentence per dialog**, no `\n` line breaks, no cell
  coordinates — the mouse (or the constraint widget it points to) provides
  the visual context, so use demonstratives ("this cell", "this row", "the
  other cells") instead.
- All dialog read times are **fixed at 3000 ms** (no word-count
  calculation).
- After the last dialog of a group, close it, `wait 200`, then execute the
  assignments: `mouse <col>,<row>` + `wait 100` + `setValue` + `wait 1000`.
  Chain several cells with no extra wait between `setValue` and the next
  `mouse`.
- Group separator comments are simple `# <source>` lines (no descriptive
  text).

**Dialog explanation templates (by slug):**

Each constraint provides three slots — the rule (dialog 1, titled with the
constraint name), what is already known (dialog 2, title `"..."`), and the
deduction (dialog 3, title `"..."`):

| Slug(s) | Dialog 1 title | Rule | Already-known | Deduction |
|---------|----------------|------|---------------|-----------|
| CC, RC | Row/Column Count | "This [row/column] must contain exactly N cells of colour C." | "It already has N cell(s) of this colour." | "So all the other cells must be the opposite colour." |
| FM | Forbidden Pattern | "This pattern is forbidden in the grid." | "These cells already form part of the pattern." | "So this cell cannot be that colour — it must be the opposite." |
| GS | Group Size | "This group must be exactly N cells." | "The group already has N cells." | "So the surrounding cells must be the opposite colour." |
| PA | Parity | "On this side, each colour must appear equally often." | "We already have N of each colour here." | "So the remaining cells must balance the count." |
| LT | Letter Group | "This letter must be a connected group of exactly N cells." | "The group already has N cells." | "So the surrounding cells must be the opposite colour." |
| JR, JC | Majority | "In this [row/column], one colour must outnumber the other." | "The current tally is N-N." | "So this cell must be [colour] to give it the majority." |
| RT, CT | Transition | "This [row/column] must have exactly N colour changes." | "The current pattern already has N changes." | "So this cell must be [colour]." |
| QA | Quantity | "The puzzle must contain exactly N cells of this colour." | "We already have N of them placed." | "So no other cell can be this colour." |
| SY | Symmetry | "This cell mirrors another cell." | "The mirrored cell is [colour]." | "So this cell must be [colour] too." |
| DF | Different From | "This cell must be different from its neighbour." | "We just set this neighbour to [colour]." | "So this cell must be the opposite colour." |
| SH | Shape | "This shape must appear somewhere in the grid." | "The shape is already partly in place." | "So this cell must be [colour] to complete it." |
| CH | Chain | "This chain must follow specific rules." | "The chain already has this configuration." | "So this cell must be [colour]." |
| GC | Group Count | "There must be exactly N groups of this colour." | "We already have N groups." | "So this cell cannot start a new group." |
| MJ | Majority (zone) | "In this zone, one colour must outnumber the other." | "The current tally is N-N." | "So this cell must be [colour]." |
| NC | Neighbour Count | "This cell must have exactly N neighbours of that colour." | "This neighbour is already [colour]." | "So the remaining neighbour must be [colour]." |
| EY | Eyes | "This pattern must have exactly N cells of that colour." | "We already have N in this pattern." | "So this cell must be [colour]." |
| IM | Implication | "One colour forces the other cell's colour." | "This cell is already [colour]." | "So the other cell must be [colour]." |
| BB | Bounding Box | "All cells of this colour must fit in an N×M box." | "The box is already filled." | "So this cell cannot be that colour." |

For **complicity** sources, use this table (same three-dialog split, no
`mouseTo`):

| Complicity name | Dialog 1 title | Rule | Already-known | Deduction |
|-----------------|----------------|------|---------------|-----------|
| `PABalancedSideComplicity` | Parity + Others | "Parity and other rules interact here." | "We already have N cells of each colour." | "So the remaining cell must be the only colour left." |
| `LTFMComplicity` | Letter + Forbidden Pattern | "This letter and a forbidden pattern interact." | "The letter group already has its cells." | "So this cell cannot be that colour." |
| `FMFMComplicity` | Dual Forbidden Patterns | "Two forbidden patterns overlap here." | "Both patterns are already partly in place." | "So this cell must be the only colour left." |
| `SYFMComplicity` | Symmetry + Forbidden Pattern | "Symmetry and a forbidden pattern interact." | "The mirrored cell is already [colour]." | "So this cell must be the only colour left." |
| `GSQAComplicity` | Group Size + Quantity | "Group size and quantity constraints interact." | "The group already has N cells." | "So this cell cannot be that colour." |
| `LTGSComplicity` | Letter + Group Size | "This letter and a group-size rule interact." | "The letter group already has its cells." | "So this cell must be the only colour left." |
| `GSAllComplicity` | Group Size + All Constraints | "Group size interacts with several rules." | "The group already has N cells." | "So this cell must be the only colour left." |
| `SHGSComplicity` | Shape + Group Size | "Shape and group-size constraints interact." | "The group already has N cells." | "So this cell must be the only colour left." |
| `GSGSComplicity` | Dual Group Sizes | "Two group-size constraints interact." | "The neighbouring group already has N cells." | "So this cell must be the only colour left." |

For **findAMove** (one group, no `mouseTo`):

| foundBy | Dialog 1 title | Rule | Already-known | Deduction |
|---------|----------------|------|---------------|-----------|
| `findAMove` | Trial Deduction | "The solver tried every colour for these cells." | "Each wrong colour led to a contradiction." | "So only [colour] was possible for each cell." |

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
background bottomBarBg
dialog "Welcome!" "Let's solve a puzzle together"
wait 2000
loadState v2_12_3x3_010102100_GS:5.1;FM:111_1:121212212
wait 500
background transparent
# GS:5.1
mouseTo GS:5.1
wait 200
dialog "Group Size" "This group must be exactly 1 cell."
wait 3000
dialog
wait 500
# TODO: Mouse to relevant already-set cells
# mouse 2,0
# wait 500
dialog "..." "The group already has its cell."
wait 3000
dialog "..." "So the surrounding cells must be black."
wait 3000
dialog
wait 200
mouse 2,0
wait 100
setValue 2,0,black
wait 1000
mouse 1,1
wait 100
setValue 1,1,black
wait 1000
mouse 2,2
wait 100
setValue 2,2,black
wait 1000
# FM:111
mouseTo FM:111
wait 200
dialog "Forbidden Pattern" "Three black cells in a row are forbidden."
wait 3000
dialog
wait 500
# TODO: Mouse to relevant already-set cells
# mouse 0,1
# wait 500
# mouse 0,2
# wait 500
dialog "..." "This row already has two black cells."
wait 3000
dialog "..." "So this cell cannot be black — it must be white."
wait 3000
dialog
wait 200
mouse 0,0
wait 100
setValue 0,0,white
wait 1000
mouse 1,2
wait 100
setValue 1,2,white
wait 1000
# End
dialog
wait 3000
background bottomBarBg
dialog "Puzzle solved!" "Go try it by yourself at leveque.cc/getsomepuzzle"
wait 2000
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
