# Get Some Puzzle

> A logical grid-based puzzle game.

A grid full of cells

Some obscure rules to follow

No time to rest

The grid must be filled

[Play in your browser](https://court-jus.github.io/getsomepuzzle/)

## Description

In this game, your aim is to color the cells of the grid in black or white.

To know which cell has to be which color, you have to follow some constraints, represented visually in the grid or above it.

Some cells are already filled and can't be changed.

Click or touch the cells to change their color, until the gris is fully colored.

You will not be shown when you make a mistake but when the grid is filled, your solution is checked.

If you are correct, another puzzle will start immediately. If you made a mistake, the corresponding constraint will be highlighted and you will be able to change your solution.

If you are stuck, you can reset the puzzle to its initial state.

There are about 10k puzzles bundled within the app. You can also generate new puzzles from the app or from the command line.

## Constraints

### Forbidden pattern

If you see a pattern above the puzzles that has a purple background, you must fill your grid so that this pattern does NOT appear anywhere.

### Group size

If a cell contains a number, it must be part of a group of orthogonally connected cells of the same color and that group's size much match the number.

### Parity

If you see an arrow in a cell, there must be the same number of black and white cells in the direction face by the arrow. A cell can contain a double-headed arrow, this means that both sides of the cell must respect the parity rule.

### Letter group

Cells containing the same letter should be part of the same group. A group must not contain different letters.

### Quantity

A black or white number over the puzzle, on a blue background indicates that the
total number of cells of that color should match that number.

## Generating puzzles

### From the app

Open the menu and tap **Generate**. You can configure the grid size, which constraint types to include or exclude, the number of puzzles and a time limit. Generated puzzles are saved to the **My puzzles** collection.

### From the command line

```bash
dart run bin/generate.dart [options]
```

Options:

| Flag | Description | Default |
|------|-------------|---------|
| `-n, --count` | Number of puzzles to generate | 10 |
| `-W, --min-width` | Minimum grid width | 4 |
| `--max-width` | Maximum grid width | 7 |
| `-H, --min-height` | Minimum grid height | 4 |
| `--max-height` | Maximum grid height | 8 |
| `-o, --output` | Output file (default: stdout) | |
| `--ban` | Comma-separated rules to exclude | |
| `--require` | Comma-separated rules to require | |

Rule slugs: `FM` (forbidden motif), `PA` (parity), `GS` (group size), `LT` (letter group), `QA` (quantity),
`SY` (symmetry), `DF` (different from), `CC` (column count), `GC` (group count).

Examples:

```bash
# Generate 100 puzzles into a file
dart run bin/generate.dart -n 100 -o puzzles.txt

# Small puzzles only
dart run bin/generate.dart -n 50 -W 3 --max-width 5 -H 3 --max-height 5

# Generate puzzles without some rules
dart run bin/generate.dart -n 20 --ban LT,SY,GS,QA
```

The CLI shows progress on stderr and outputs puzzle lines to stdout (or the file specified with `-o`). You can interrupt with Ctrl+C without losing already generated puzzles.
