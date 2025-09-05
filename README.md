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

There are about 5k puzzles bundled within the app and there are some python scripts to generate new puzzles.

## Constraints

### Forbidden motif

If you see a motif above the puzzles that has a purple background, you must fill your grid so that this motif does NOT appear anywhere.

### Group size

If a cell contains a number, it must be part of a group of orthogonally adjacent cells of the same color and that group's size much match the number.

### Parity

If you see an arrow in a cell, there must be the same number of black and white cells in the direction face by the arrow. A cell can contain a double-headed arrow, this means that both sides of the cell must respect the parity rule.

### Letter group

Cells containing the same letter should be part of the same group. A group must not contain different letters.
