import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

/// Character-art grid with optional row/col headers.
///
/// Characters: `#` = black, `o` = white, `¤` = purple, `.` = free.
String formatGrid(
  List<CellValue> cellValues,
  int width,
  int height, {
  bool showHeaders = true,
}) {
  final sb = StringBuffer();

  if (showHeaders) {
    // Column headers: pad left for the row-number column.
    sb.write('   ');
    for (int c = 0; c < width; c++) {
      sb.write(' $c');
    }
    sb.writeln();
  }

  for (int r = 0; r < height; r++) {
    if (showHeaders) {
      sb.write('${r.toString().padLeft(2)} ');
    }
    for (int c = 0; c < width; c++) {
      sb.write(' ${_cellChar(cellValues[r * width + c])}');
    }
    sb.writeln();
  }

  return sb.toString();
}

/// Human-readable domain description, e.g. "black, white (2 colors)".
String describeDomain(List<CellValue> domain) {
  final names = domain.map((v) => v.name).join(', ');
  final label = domain.length == 1 ? 'color' : 'colors';
  return '$names (${domain.length} $label)';
}

/// Constraints grouped by slug, each with [Constraint.serialize] and
/// [Constraint.toHuman].
///
/// Output:
/// ```
///   CC (2):
///     CC:2.1.5  -- Col 3: 5 black
///     CC:3.2.3  -- Col 4: 3 white
///   CT (3):
///     CT:4.3  -- Col 5: ~3
/// ```
String formatConstraints(Iterable<Constraint> constraints, Puzzle puzzle) {
  final sb = StringBuffer();
  final groups = groupBy(constraints, (c) => c.slug);
  final sortedSlugs = groups.keys.toList()..sort();

  for (final slug in sortedSlugs) {
    final list = groups[slug]!;
    sb.writeln('  $slug (${list.length}):');
    for (final c in list) {
      sb.writeln('    ${c.serialize()}  -- ${c.toHuman(puzzle)}');
    }
  }

  return sb.toString();
}

/// All-in-one: domain, grid (with headers), constraints.
String describePuzzle(Puzzle puzzle) {
  final sb = StringBuffer();
  sb.writeln('Domain: ${describeDomain(puzzle.domain)}');
  sb.writeln();
  sb.writeln('Grid ${puzzle.width}x${puzzle.height}:');
  sb.write(formatGrid(puzzle.cellValues, puzzle.width, puzzle.height));
  sb.writeln();
  sb.writeln('Constraints (${puzzle.constraints.length}):');
  sb.write(formatConstraints(puzzle.constraints, puzzle));
  return sb.toString();
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

String _cellChar(CellValue v) {
  switch (v) {
    case CellValue.free:
      return '.';
    case CellValue.black:
      return '#';
    case CellValue.white:
      return 'o';
    case CellValue.purple:
      return '¤';
  }
}
