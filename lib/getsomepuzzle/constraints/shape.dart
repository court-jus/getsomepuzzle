import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/getsomepuzzle/utils/groups.dart';

// ---------------------------------------------------------------------------
// Shape utilities: rotation, mirror, normalization, comparison.
//
// A shape is a 2D grid (List<List<int>>) where non-zero values represent
// occupied cells (1 = black, 2 = white) and 0 = empty. The color is carried
// by the non-zero values themselves.
//
// Two shapes are considered equivalent if one can be obtained from the other
// by any combination of 90° rotations and horizontal mirror (= the 8
// symmetries of a rectangle). We call the lexicographically smallest variant
// the "canonical form".
// ---------------------------------------------------------------------------

/// Rotate a shape 90° clockwise: (r, c) → (c, rows - 1 - r).
List<List<CellValue>> _rotate90(List<List<CellValue>> shape) {
  final rows = shape.length;
  final cols = shape[0].length;
  // After rotation: new dimensions are cols × rows.
  return [
    for (int c = 0; c < cols; c++)
      [for (int r = rows - 1; r >= 0; r--) shape[r][c]],
  ];
}

/// Mirror a shape horizontally: (r, c) → (r, cols - 1 - c).
List<List<CellValue>> _mirror(List<List<CellValue>> shape) {
  return [for (final row in shape) row.reversed.toList()];
}

/// Remove empty rows/columns on all four edges (trim).
List<List<CellValue>> _trim(List<List<CellValue>> shape) {
  // Remove empty top rows.
  var s = shape
      .skipWhile((row) => row.every((v) => v == CellValue.free))
      .toList();
  if (s.isEmpty) return [[]];
  // Remove empty bottom rows.
  while (s.last.every((v) => v == CellValue.free)) {
    s = s.sublist(0, s.length - 1);
  }
  // Find first and last non-empty columns.
  int minCol = s[0].length;
  int maxCol = 0;
  for (final row in s) {
    for (int c = 0; c < row.length; c++) {
      if (row[c] != CellValue.free) {
        if (c < minCol) minCol = c;
        if (c > maxCol) maxCol = c;
      }
    }
  }
  // Slice columns.
  return [for (final row in s) row.sublist(minCol, maxCol + 1)];
}

/// Serialize a shape to a comparable string (e.g. "110.011").
String _shapeToString(List<List<CellValue>> shape) {
  return shape.map((row) => row.map(cellValueToString).join('')).join('.');
}

/// Generate all distinct variants of a shape (up to 8: 4 rotations × 2 for
/// mirror), trimmed and deduplicated.
List<List<List<CellValue>>> allRotations(List<List<CellValue>> shape) {
  final seen = <String>{};
  final result = <List<List<CellValue>>>[];
  var current = _trim(shape);

  // 4 rotations of the original, then 4 rotations of the mirror.
  for (int mirror = 0; mirror < 2; mirror++) {
    for (int rot = 0; rot < 4; rot++) {
      final trimmed = _trim(current);
      final key = _shapeToString(trimmed);
      if (seen.add(key)) {
        result.add(trimmed);
      }
      current = _rotate90(current);
    }
    if (mirror == 0) current = _mirror(_trim(shape));
  }
  return result;
}

/// Return the canonical (normalized) form of a shape: the lexicographically
/// smallest among all its rotation/mirror variants.
List<List<CellValue>> normalizeShape(List<List<CellValue>> shape) {
  final variants = allRotations(shape);
  variants.sort((a, b) => _shapeToString(a).compareTo(_shapeToString(b)));
  return variants.first;
}

/// Check whether two shapes are equivalent under rotation and mirror.
bool shapesAreEquivalent(List<List<CellValue>> a, List<List<CellValue>> b) {
  return _shapeToString(normalizeShape(a)) == _shapeToString(normalizeShape(b));
}

/// Extract the color from a shape (the unique non-zero value).
/// Throws if the shape contains mixed non-zero values.
CellValue shapeColor(List<List<CellValue>> shape) {
  CellValue? color;
  for (final row in shape) {
    for (final v in row) {
      if (v != CellValue.free) {
        if (color == null) {
          color = v;
        } else if (color != v) {
          throw ArgumentError(
            'Shape contains mixed non-zero values: ${cellValueToString(color)} and ${cellValueToString(v)}',
          );
        }
      }
    }
  }
  if (color == null) {
    throw ArgumentError('Shape contains no non-zero values');
  }
  return color;
}

// ---------------------------------------------------------------------------
// ShapeConstraint: "All groups of this color must have this shape."
//
// Format: SH:motif (e.g. SH:111, SH:20.22)
// The color is inferred from the non-zero values in the motif.
// The motif is invariant under rotation (0°/90°/180°/270°) and mirror.
// ---------------------------------------------------------------------------

class ShapeConstraint extends Motif {
  @override
  String get slug => 'SH';

  /// The constrained color, inferred from the motif (1 = black, 2 = white).
  CellValue color = CellValue.free;

  /// All distinct rotation/mirror variants of the motif (for matching).
  List<List<List<CellValue>>> variants = [];

  /// Number of occupied (non-zero) cells in the motif.
  int shapeSize = 0;

  /// Total number of cells in the motif grid (rows × columns, including zeros).
  int motifGridSize = 0;

  /// The original parameter string, preserved for faithful serialization.
  String _originalParams = '';

  ShapeConstraint(String strParams) {
    _originalParams = strParams;
    // Parse exactly like FM: rows separated by '.', each character is a value.
    final parsed = strParams
        .split('.')
        .map((row) => row.split('').map(cellRepresentationToValue).toList())
        .toList();

    color = shapeColor(parsed);
    motif = normalizeShape(parsed);
    variants = allRotations(parsed);
    shapeSize = parsed
        .expand((row) => row)
        .where((v) => v != CellValue.free)
        .length;
    motifGridSize = parsed.length * parsed[0].length;
  }

  @override
  String toString() {
    return motif.map((row) => row.map(cellValueToString).join('')).join('.');
  }

  @override
  String toHuman(Puzzle puzzle) {
    return 'All ${cellValueToString(color)} groups must have shape $this';
  }

  @override
  String serialize() => 'SH:$_originalParams';

  @override
  Constraint rotated(int origWidth, int origHeight) =>
      ShapeConstraint(_originalParams);

  static List<String> generateAllParameters(
    int width,
    int height,
    List<CellValue> domain,
    Set<int>? excludedIndices,
  ) {
    final maxSize = width > height ? width : height;
    final possibleMotifs = [
      "1",
      "11",
      "111",
      "11.10",
      "1111",
      "11.11",
      "111.010",
      "111.100",
      "110.011",
      "11111",
      "1111.1000",
      "1111.0100",
      "1110.0011",
      "010.111.010",
      "111.010.010",
      "100.110.011",
      "111.001.001",
      "110.010.011",
    ];
    final List<String> result = [];
    for (var motif in possibleMotifs) {
      final motifList = motif.split(".");
      if (motifList.length > maxSize || motifList[0].length > maxSize) continue;
      for (var value in domain) {
        result.add(motif.replaceAll("1", cellValueToString(value)));
      }
    }
    return result;
  }

  static const baseWeights = <int, int>{
    1: 1,
    2: 8,
    3: 16,
    4: 10,
    5: 2,
    6: 8,
    8: 3,
    9: 2,
  };

  /// Compute the total cell count (rows × columns, including zeros) of a
  /// motif string without going through the full constructor — which would
  /// parse, rotate, mirror, and normalize the shape. Useful when only the
  /// bounding-box size is needed (e.g. for weighting candidate motifs).
  static int motifGridSizeOf(String strParams) {
    final firstDot = strParams.indexOf('.');
    final cols = firstDot < 0 ? strParams.length : firstDot;
    final rows = firstDot < 0 ? 1 : strParams.split('.').length;
    return rows * cols;
  }

  // -------------------------------------------------------------------------
  // apply(): deduce cell values from this constraint.
  //
  // Six levels of deduction, from cheapest to most expensive:
  //   1. Closed group doesn't match any variant         → impossible
  //   2. Open group already matches (correct shape+size) → close borders
  //   3. Open group can't fit in any variant             → impossible
  //   4. Extending group by a neighbor breaks fit        → block neighbor
  //   5. Enumerate all grid completions of a group:
  //      - cell in ALL completions                       → force color
  //      - neighbor in NO completion                     → block neighbor
  //   6. Free cell would merge groups into invalid shape → block cell
  // -------------------------------------------------------------------------
  @override
  Move? apply(Puzzle puzzle) {
    final groups = getGroups(puzzle);

    for (final group in groups) {
      if (puzzle.cellValues[group.first] != color) continue;

      final freeNeighbors = _groupFreeNeighbors(group, puzzle);
      final isOpen = freeNeighbors.isNotEmpty;

      // --- Level 1: closed group must match exactly ---
      if (!isOpen) {
        if (!_groupMatchesAVariant(group, puzzle)) {
          return Move(0, this, isImpossible: this);
        }
        continue;
      }

      // --- Level 2: open group already has the right shape → close borders ---
      // Example: SH:111 and group is [0,1,2] (a line of 3) with cell 3 free.
      //   → cell 3 must be an opposite color.
      if (group.length == shapeSize && _groupMatchesAVariant(group, puzzle)) {
        for (var freeNeighbor in freeNeighbors) {
          if (puzzle.cells[freeNeighbor].options.contains(color)) {
            return Move(freeNeighbor, removeOption: color, this, complexity: 0);
          }
        }
        // No free neighbor still has `color` as an option — borders are
        // already closed. The constraint is satisfied for this group; move on
        // to the next group instead of reporting an impossibility. (In domain
        // 2, removeOption auto-sets the only remaining value so the neighbor
        // stops being "free" — this branch was unreachable. In domain 3+,
        // removing one colour leaves two options, so the cell stays free and
        // we loop back here without anything to do.)
        continue;
      }

      // --- Level 3: open group can't fit in any variant → impossible ---
      // Reuses the same 3-level check as verify() (cell count, bbox, geometry).
      if (!_groupCanFitInSomeVariant(group, puzzle)) {
        return Move(0, this, isImpossible: this);
      }

      // --- Level 4: extending by a neighbor breaks compatibility → block ---
      // For each free neighbor, simulate adding it to the group and recheck.
      // Example: SH:111 (line of 3), group is [0,1] (horizontal pair).
      //   Adding cell 4 (below cell 0) would create an L → can't fit in any
      //   line variant → cell 4 must be opposite.
      for (final neighbor in freeNeighbors) {
        if (!_groupCanFitInSomeVariant([...group, neighbor], puzzle) &&
            puzzle.cells[neighbor].options.contains(color)) {
          return Move(neighbor, removeOption: color, this, complexity: 2);
        }
      }

      // --- Level 5: enumerate all valid completions on the grid ---
      // A "completion" is a placement of a variant on the grid that covers all
      // current group cells and only needs free cells to fill the rest.
      final completions = findAllCompletions(group, puzzle);
      if (completions.isEmpty) {
        // No variant can be placed to complete this group → impossible.
        // (More precise than level 3: accounts for grid edges and obstacles.)
        return Move(0, this, isImpossible: this);
      }
      // Cell that appears in ALL completions → must be color. If options
      // exclude `color` (3-colour puzzles), no completion is actually
      // viable so the constraint is impossible.
      final mandatory = completions.reduce((a, b) => a.intersection(b));
      for (final idx in mandatory) {
        if (puzzle.cellValues[idx] == CellValue.free) {
          if (!puzzle.cells[idx].options.contains(color)) {
            return Move(0, this, isImpossible: this);
          }
          return Move(idx, value: color, this, complexity: 4);
        }
      }
      // Free neighbor that appears in NO completion → must be opposite.
      final anyCompletion = completions.expand((c) => c).toSet();
      for (final neighbor in freeNeighbors) {
        if (!anyCompletion.contains(neighbor) &&
            puzzle.cells[neighbor].options.contains(color)) {
          return Move(neighbor, removeOption: color, this, complexity: 4);
        }
      }
    }

    // --- Level 6: free cell that would merge groups into invalid shape ---
    // If placing color on a free cell merges 2+ existing groups of that color,
    // check whether the resulting combined group can still fit in a variant.
    // Example: SH:111 (line of 3), two separate groups [0] and [2] with cell 1
    //   free between them. Merging gives [0,1,2] = line of 3 → ok. But if the
    //   merge would create 4+ cells or a wrong shape → block.
    final colorGroups = groups
        .where((g) => puzzle.cellValues[g.first] == color)
        .toList();
    if (colorGroups.length >= 2) {
      final cellToGroup = <int, int>{};
      for (int gi = 0; gi < colorGroups.length; gi++) {
        for (final cell in colorGroups[gi]) {
          cellToGroup[cell] = gi;
        }
      }
      for (int idx = 0; idx < puzzle.cellValues.length; idx++) {
        if (puzzle.cellValues[idx] != CellValue.free) continue;
        final neighborGroupIndices = <int>{};
        for (final nei in puzzle.getNeighbors(idx)) {
          final gi = cellToGroup[nei];
          if (gi != null) neighborGroupIndices.add(gi);
        }
        if (neighborGroupIndices.length < 2) continue;
        // This cell would merge multiple groups. Build the merged group.
        final merged = [idx];
        for (final gi in neighborGroupIndices) {
          merged.addAll(colorGroups[gi]);
        }
        if (!_groupCanFitInSomeVariant(merged, puzzle) &&
            puzzle.cells[idx].options.contains(color)) {
          return Move(idx, removeOption: color, this, complexity: 3);
        }
      }
    }

    return null;
  }

  /// Collect free (empty) cells adjacent to any cell in the group.
  Set<int> _groupFreeNeighbors(List<int> group, Puzzle puzzle) {
    final groupSet = group.toSet();
    final result = <int>{};
    for (final idx in group) {
      for (final nei in puzzle.getNeighbors(idx)) {
        if (puzzle.cellValues[nei] == CellValue.free &&
            !groupSet.contains(nei)) {
          result.add(nei);
        }
      }
    }
    return result;
  }

  /// Enumerate all valid ways to complete a group into a full shape variant,
  /// considering grid boundaries and opposite-color obstacles.
  /// Each returned set contains the free cell indices that would need to be
  /// filled to complete the group into that particular variant placement.
  List<Set<int>> findAllCompletions(List<int> group, Puzzle puzzle) {
    final groupSet = group.toSet();
    final completions = <Set<int>>[];

    // Pre-compute cell→group index so we can look up the host group of any
    // same-color cell that lands on a variant placement.
    final cellToGroup = <int, List<int>>{};
    for (final g in getGroups(puzzle)) {
      for (final idx in g) {
        cellToGroup[idx] = g;
      }
    }

    // Bounding box of the current group. Any variant placement must include
    // this bbox, so we can tightly restrict the (topRow, topCol) ranges below.
    final bbox = _bbox(group, puzzle.width);

    for (final variant in variants) {
      final varH = variant.length;
      final varW = variant[0].length;

      // topRow/topCol must satisfy: topRow ≤ bbox.minRow and
      // topRow + varH − 1 ≥ bbox.maxRow (idem for columns). Placements outside
      // that range can't cover the group, so we don't even iterate them.
      final rowStart = _max(0, bbox.maxRow - varH + 1);
      final rowEnd = _min(puzzle.height - varH, bbox.minRow);
      final colStart = _max(0, bbox.maxCol - varW + 1);
      final colEnd = _min(puzzle.width - varW, bbox.minCol);

      for (int topRow = rowStart; topRow <= rowEnd; topRow++) {
        for (int topCol = colStart; topCol <= colEnd; topCol++) {
          final variantCells = _variantCellsAt(
            variant,
            topRow,
            topCol,
            puzzle.width,
          );

          // Bbox guarantees the group's bounding rectangle fits, but the
          // variant shape may have holes — cell-level coverage is still needed.
          if (!groupSet.every(variantCells.contains)) continue;

          if (!_placementIsCompatible(
            variantCells,
            groupSet,
            group,
            cellToGroup,
            puzzle,
          )) {
            continue;
          }

          final toFill = variantCells
              .where(
                (idx) =>
                    !groupSet.contains(idx) &&
                    puzzle.cellValues[idx] == CellValue.free,
              )
              .toSet();

          if (_mergesOutsidePlacement(toFill, variantCells, groupSet, puzzle)) {
            continue;
          }

          completions.add(toFill);
        }
      }
    }
    return completions;
  }

  /// Grid indices occupied by `variant` (non-zero cells) when placed with its
  /// top-left corner at (`topRow`, `topCol`).
  Set<int> _variantCellsAt(
    List<List<CellValue>> variant,
    int topRow,
    int topCol,
    int width,
  ) {
    final cells = <int>{};
    for (int r = 0; r < variant.length; r++) {
      final row = variant[r];
      for (int c = 0; c < row.length; c++) {
        if (row[c] == CellValue.free) continue;
        cells.add((topRow + r) * width + (topCol + c));
      }
    }
    return cells;
  }

  /// A placement is compatible iff every cell it occupies (that isn't already
  /// in the current group) is either empty or a same-color cell whose host
  /// group could still fit in the shape after merging with ours.
  /// Any opposite-color cell immediately rejects the placement.
  bool _placementIsCompatible(
    Set<int> variantCells,
    Set<int> groupSet,
    List<int> group,
    Map<int, List<int>> cellToGroup,
    Puzzle puzzle,
  ) {
    for (final idx in variantCells) {
      if (groupSet.contains(idx)) continue;
      final v = puzzle.cellValues[idx];
      if (v == CellValue.free) continue;
      if (v != color) return false;
      final other = cellToGroup[idx];
      if (other == null || other.isEmpty) continue;
      if (!_groupCanFitInSomeVariant([...group, ...other], puzzle)) {
        return false;
      }
    }
    return true;
  }

  /// True iff filling any cell of `toFill` would make the completed group
  /// adjacent to another same-color group that isn't part of the placement —
  /// which would create a merged group bigger than the shape.
  bool _mergesOutsidePlacement(
    Set<int> toFill,
    Set<int> variantCells,
    Set<int> groupSet,
    Puzzle puzzle,
  ) {
    for (final fillIdx in toFill) {
      for (final nei in puzzle.getNeighbors(fillIdx)) {
        if (puzzle.cellValues[nei] == color &&
            !groupSet.contains(nei) &&
            !variantCells.contains(nei)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Bounding box of a group, in grid coordinates.
  _Bbox _bbox(List<int> group, int width) {
    int minRow = 1 << 30;
    int maxRow = -1;
    int minCol = 1 << 30;
    int maxCol = -1;
    for (final idx in group) {
      final r = idx ~/ width;
      final c = idx % width;
      if (r < minRow) minRow = r;
      if (r > maxRow) maxRow = r;
      if (c < minCol) minCol = c;
      if (c > maxCol) maxCol = c;
    }
    return _Bbox(minRow, minCol, maxRow, maxCol);
  }

  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;

  @override
  bool verify(Puzzle puzzle) {
    final groups = getGroups(puzzle);

    for (final group in groups) {
      // Only check groups of the constrained color.
      if (puzzle.cellValues[group.first] != color) continue;

      // Does this group have free (empty) neighbors? If so it can still grow.
      final bool isOpen = group.any(
        (idx) => puzzle
            .getNeighbors(idx)
            .any((n) => puzzle.cellValues[n] == CellValue.free),
      );

      if (isOpen) {
        // The group is still growing. Check for early violations only.
        if (!_groupCanFitInSomeVariant(group, puzzle)) return false;
      } else {
        // The group is closed — it must match a variant exactly.
        if (!_groupMatchesAVariant(group, puzzle)) return false;
      }
    }
    return true;
  }

  /// Check whether a closed group matches one of the shape variants exactly.
  bool _groupMatchesAVariant(List<int> group, Puzzle puzzle) {
    final matrix = _groupToMatrix(group, puzzle);
    for (final variant in variants) {
      if (_matricesEqual(matrix, variant)) return true;
    }
    return false;
  }

  /// Check whether a partial (open) group can still grow into a valid shape.
  /// Three levels of pre-filtering, from cheapest to most expensive:
  ///   (a) cell count: group can't already exceed shape size
  ///   (b) bounding box: group's bbox must fit inside some variant's bbox
  ///   (c) sub-shape: group cells must map onto occupied cells of some variant
  bool _groupCanFitInSomeVariant(List<int> group, Puzzle puzzle) {
    // (a) Cell count check.
    if (group.length > shapeSize) return false;

    // Compute group bounding box (in grid coordinates).
    int minRow = puzzle.height, maxRow = 0, minCol = puzzle.width, maxCol = 0;
    for (final idx in group) {
      final r = idx ~/ puzzle.width;
      final c = idx % puzzle.width;
      if (r < minRow) minRow = r;
      if (r > maxRow) maxRow = r;
      if (c < minCol) minCol = c;
      if (c > maxCol) maxCol = c;
    }
    final groupH = maxRow - minRow + 1;
    final groupW = maxCol - minCol + 1;

    // Normalize group cell positions to (0,0)-based offsets.
    final groupOffsets = <(int, int)>{
      for (final idx in group)
        (idx ~/ puzzle.width - minRow, idx % puzzle.width - minCol),
    };

    for (final variant in variants) {
      final varH = variant.length;
      final varW = variant[0].length;

      // (b) Bounding box check: group bbox must fit inside variant bbox.
      if (groupH > varH || groupW > varW) continue;

      // (c) Sub-shape check: try every translation of the group within the
      //     variant. For each offset (dr, dc), verify that every group cell
      //     lands on an occupied cell of the variant.
      final found = _groupOffsetsExistInVariant(
        groupOffsets,
        variant,
        groupH,
        groupW,
      );
      if (found) return true;
    }
    return false;
  }

  static List<((int, int), List<List<CellValue>>)> findAdditionalPositions(
    Puzzle solved,
  ) {
    final width = solved.width;
    final height = solved.height;
    final sc = solved.constraints.whereType<ShapeConstraint>().first;
    final motifValue = sc.color;
    final oppositeColor = solved.domain.whereNot((i) => i == motifValue).first;

    final List<((int, int), List<List<CellValue>>)> results = [];

    for (final variant in sc.variants) {
      final variantHeight = variant.length;
      final variantWidth = variant.first.length;

      for (int row = 0; row <= height - variantHeight; row++) {
        for (int col = 0; col <= width - variantWidth; col++) {
          bool canPlace = true;
          for (int vr = 0; vr < variantHeight && canPlace; vr++) {
            for (int vc = 0; vc < variantWidth && canPlace; vc++) {
              final cellValue =
                  solved.cells[(row + vr) * width + (col + vc)].value;
              if (cellValue != CellValue.free && cellValue != oppositeColor) {
                canPlace = false;
              }
            }
          }

          if (!canPlace) continue;

          final testPuzzle = solved.clone();
          for (int vr = 0; vr < variantHeight; vr++) {
            for (int vc = 0; vc < variantWidth; vc++) {
              final value = variant[vr][vc];
              if (value != CellValue.free) {
                testPuzzle.cells[(row + vr) * width + (col + vc)].setForSolver(
                  value,
                );
              }
            }
          }

          if (sc.verify(testPuzzle)) {
            results.add(((row, col), variant));
          }
        }
      }
    }

    return results;
  }

  @override
  bool isCompleteFor(Puzzle puzzle) {
    if (!verify(puzzle)) return false;
    // Complete only when no future play can ever trigger `apply()` again.
    // Even if all current color groups are closed and no valid variant
    // placement remains, colouring any free cell with `color` creates a
    // 1-cell group that fails the shape check → apply level 1 fires. So
    // the only truly permanent state is a fully filled grid.
    return puzzle.cellValues.every((v) => v != CellValue.free);
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Convert a group (list of cell indices) into a 2D matrix within its bounding
/// box. Occupied cells get [color], empty cells get 0.
List<List<CellValue>> _groupToMatrix(List<int> group, Puzzle puzzle) {
  final color = puzzle.cellValues[group.first];
  int minRow = puzzle.height, maxRow = 0, minCol = puzzle.width, maxCol = 0;
  for (final idx in group) {
    final r = idx ~/ puzzle.width;
    final c = idx % puzzle.width;
    if (r < minRow) minRow = r;
    if (r > maxRow) maxRow = r;
    if (c < minCol) minCol = c;
    if (c > maxCol) maxCol = c;
  }
  final h = maxRow - minRow + 1;
  final w = maxCol - minCol + 1;
  final matrix = List.generate(h, (_) => List.filled(w, CellValue.free));
  for (final idx in group) {
    matrix[idx ~/ puzzle.width - minRow][idx % puzzle.width - minCol] = color;
  }
  return matrix;
}

/// Deep-compare two 2D matrices.
bool _matricesEqual(List<List<CellValue>> a, List<List<CellValue>> b) {
  if (a.length != b.length) return false;
  for (int r = 0; r < a.length; r++) {
    if (a[r].length != b[r].length) return false;
    for (int c = 0; c < a[r].length; c++) {
      if (a[r][c] != b[r][c]) return false;
    }
  }
  return true;
}

/// Check whether a set of (row, col) offsets can be placed inside a variant
/// by translation, such that every offset lands on an occupied (non-zero) cell.
bool _groupOffsetsExistInVariant(
  Set<(int, int)> offsets,
  List<List<CellValue>> variant,
  int groupH,
  int groupW,
) {
  final varH = variant.length;
  final varW = variant[0].length;
  // Try every valid translation (dr, dc).
  for (int dr = 0; dr <= varH - groupH; dr++) {
    for (int dc = 0; dc <= varW - groupW; dc++) {
      final allMatch = offsets.every(
        (o) => variant[o.$1 + dr][o.$2 + dc] != CellValue.free,
      );
      if (allMatch) return true;
    }
  }
  return false;
}

/// Small value-type for a bounding box in grid coordinates.
class _Bbox {
  final int minRow;
  final int minCol;
  final int maxRow;
  final int maxCol;
  const _Bbox(this.minRow, this.minCol, this.maxRow, this.maxCol);
}
