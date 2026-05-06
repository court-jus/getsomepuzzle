/// Helpers for the puzzle 90° clockwise rotation feature. The rotation
/// maps a cell at column `c`, row `r` of a `(W, H)` grid to column
/// `H-1-r`, row `c` of the new `(H, W)` grid. All constraint
/// implementations must rotate their positional data with these helpers
/// so a rotated puzzle stays logically equivalent.
library;

/// Rotate a 1D cell index of a grid of shape `(width, height)` by 90°
/// clockwise. The returned index is valid in the rotated grid, which
/// has shape `(height, width)`.
int rotateIdx90CW(int idx, int width, int height) {
  final col = idx % width;
  final row = idx ~/ width;
  final newCol = height - 1 - row;
  final newRow = col;
  // newWidth = height in the rotated grid
  return newRow * height + newCol;
}

/// Rotate a 2D pattern (list of rows) by 90° clockwise. New shape:
/// `(rows, cols) -> (cols, rows)` where each new row `c` is the
/// reversed column `c` of the original.
List<List<T>> rotate2D90CW<T>(List<List<T>> grid) {
  if (grid.isEmpty) return [];
  final rows = grid.length;
  final cols = grid[0].length;
  return List.generate(
    cols,
    (c) => List.generate(rows, (r) => grid[rows - 1 - r][c]),
  );
}
