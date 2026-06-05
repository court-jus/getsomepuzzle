import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Build a puzzle from a grid string (domain [1,2]).
/// Each digit is a cell value (0=empty, 1=black, 2=white), rows separated
/// by newlines. Leading/trailing whitespace and blank lines are ignored.
Puzzle makePuzzle(String grid) => _makePuzzle(grid, defaultDomain);

/// Same as [makePuzzle] but on the full 3-colour domain, so cells can hold
/// purple (3).
Puzzle makePuzzle3(String grid) => _makePuzzle(grid, fullDomain);

Puzzle _makePuzzle(String grid, List<CellValue> domain) {
  final rows = grid
      .trim()
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  final h = rows.length;
  final w = rows.first.length;
  final p = Puzzle.empty(w, h, domain);
  for (int r = 0; r < h; r++) {
    for (int c = 0; c < w; c++) {
      final v = cellRepresentationToValue(rows[r][c]);
      if (v != CellValue.free) {
        p.cells[r * w + c].setForSolver(v);
      }
    }
  }
  return p;
}
