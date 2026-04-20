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
List<List<int>> _rotate90(List<List<int>> shape) {
  final rows = shape.length;
  final cols = shape[0].length;
  // After rotation: new dimensions are cols × rows.
  return [
    for (int c = 0; c < cols; c++)
      [for (int r = rows - 1; r >= 0; r--) shape[r][c]],
  ];
}

/// Mirror a shape horizontally: (r, c) → (r, cols - 1 - c).
List<List<int>> _mirror(List<List<int>> shape) {
  return [for (final row in shape) row.reversed.toList()];
}

/// Remove empty rows/columns on all four edges (trim).
List<List<int>> _trim(List<List<int>> shape) {
  // Remove empty top rows.
  var s = shape.skipWhile((row) => row.every((v) => v == 0)).toList();
  if (s.isEmpty) return [[]];
  // Remove empty bottom rows.
  while (s.last.every((v) => v == 0)) {
    s = s.sublist(0, s.length - 1);
  }
  // Find first and last non-empty columns.
  int minCol = s[0].length;
  int maxCol = 0;
  for (final row in s) {
    for (int c = 0; c < row.length; c++) {
      if (row[c] != 0) {
        if (c < minCol) minCol = c;
        if (c > maxCol) maxCol = c;
      }
    }
  }
  // Slice columns.
  return [for (final row in s) row.sublist(minCol, maxCol + 1)];
}

/// Serialize a shape to a comparable string (e.g. "110.011").
String _shapeToString(List<List<int>> shape) {
  return shape.map((row) => row.join('')).join('.');
}

/// Generate all distinct variants of a shape (up to 8: 4 rotations × 2 for
/// mirror), trimmed and deduplicated.
List<List<List<int>>> allRotations(List<List<int>> shape) {
  final seen = <String>{};
  final result = <List<List<int>>>[];
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
List<List<int>> normalizeShape(List<List<int>> shape) {
  final variants = allRotations(shape);
  variants.sort((a, b) => _shapeToString(a).compareTo(_shapeToString(b)));
  return variants.first;
}

/// Check whether two shapes are equivalent under rotation and mirror.
bool shapesAreEquivalent(List<List<int>> a, List<List<int>> b) {
  return _shapeToString(normalizeShape(a)) == _shapeToString(normalizeShape(b));
}

/// Extract the color from a shape (the unique non-zero value).
/// Throws if the shape contains mixed non-zero values.
int shapeColor(List<List<int>> shape) {
  int? color;
  for (final row in shape) {
    for (final v in row) {
      if (v != 0) {
        if (color == null) {
          color = v;
        } else if (color != v) {
          throw ArgumentError(
            'Shape contains mixed non-zero values: $color and $v',
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
  int color = 0;

  /// All distinct rotation/mirror variants of the motif (for matching).
  List<List<List<int>>> variants = [];

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
        .map((row) => row.split('').map(int.parse).toList())
        .toList();

    color = shapeColor(parsed);
    motif = normalizeShape(parsed);
    variants = allRotations(parsed);
    shapeSize = parsed.expand((row) => row).where((v) => v != 0).length;
    motifGridSize = parsed.length * parsed[0].length;
  }

  @override
  String toString() {
    return motif.map((row) => row.join('')).join('.');
  }

  @override
  String toHuman(Puzzle puzzle) {
    final colorName = color == 1 ? 'black' : 'white';
    return 'All $colorName groups must have shape $this';
  }

  @override
  String serialize() => 'SH:$_originalParams';

  static List<String> generateAllParameters(
    int width,
    int height,
    List<int> domain,
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
      result.add(motif);
      result.add(motif.replaceAll("1", "2"));
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
    final opposite = puzzle.domain.whereNot((v) => v == color).first;

    for (final group in groups) {
      if (puzzle.cellValues[group.first] != color) continue;

      final freeNeighbors = _groupFreeNeighbors(group, puzzle);
      final isOpen = freeNeighbors.isNotEmpty;

      // --- Level 1: closed group must match exactly ---
      if (!isOpen) {
        if (!_groupMatchesAVariant(group, puzzle)) {
          return Move(0, 0, this, isImpossible: this);
        }
        continue;
      }

      // --- Level 2: open group already has the right shape → close borders ---
      // Example: SH:111 and group is [0,1,2] (a line of 3) with cell 3 free.
      //   → cell 3 must be the opposite color.
      if (group.length == shapeSize && _groupMatchesAVariant(group, puzzle)) {
        return Move(freeNeighbors.first, opposite, this);
      }

      // --- Level 3: open group can't fit in any variant → impossible ---
      // Reuses the same 3-level check as verify() (cell count, bbox, geometry).
      if (!_groupCanFitInSomeVariant(group, puzzle)) {
        return Move(0, 0, this, isImpossible: this);
      }

      // --- Level 4: extending by a neighbor breaks compatibility → block ---
      // For each free neighbor, simulate adding it to the group and recheck.
      // Example: SH:111 (line of 3), group is [0,1] (horizontal pair).
      //   Adding cell 4 (below cell 0) would create an L → can't fit in any
      //   line variant → cell 4 must be opposite.
      for (final neighbor in freeNeighbors) {
        if (!_groupCanFitInSomeVariant([...group, neighbor], puzzle)) {
          return Move(neighbor, opposite, this);
        }
      }

      // --- Level 5: enumerate all valid completions on the grid ---
      // A "completion" is a placement of a variant on the grid that covers all
      // current group cells and only needs free cells to fill the rest.
      final completions = findAllCompletions(group, puzzle);
      if (completions.isEmpty) {
        // No variant can be placed to complete this group → impossible.
        // (More precise than level 3: accounts for grid edges and obstacles.)
        return Move(0, 0, this, isImpossible: this);
      }
      // Cell that appears in ALL completions → must be color.
      final mandatory = completions.reduce((a, b) => a.intersection(b));
      for (final idx in mandatory) {
        if (puzzle.cellValues[idx] == 0) {
          return Move(idx, color, this);
        }
      }
      // Free neighbor that appears in NO completion → must be opposite.
      final anyCompletion = completions.expand((c) => c).toSet();
      for (final neighbor in freeNeighbors) {
        if (!anyCompletion.contains(neighbor)) {
          return Move(neighbor, opposite, this);
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
        if (puzzle.cellValues[idx] != 0) continue;
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
        if (!_groupCanFitInSomeVariant(merged, puzzle)) {
          return Move(idx, opposite, this);
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
        if (puzzle.cellValues[nei] == 0 && !groupSet.contains(nei)) {
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

    // Pre-compute groups and cell→group index
    final allGroups = getGroups(puzzle);
    final cellToGroup = <int, List<int>>{};
    for (final g in allGroups) {
      for (final idx in g) {
        cellToGroup[idx] = g;
      }
    }

    for (final variant in variants) {
      final varH = variant.length;
      final varW = variant[0].length;

      // Try every grid position where the variant's top-left could be placed.
      for (int topRow = 0; topRow <= puzzle.height - varH; topRow++) {
        for (int topCol = 0; topCol <= puzzle.width - varW; topCol++) {
          // Collect grid indices of the variant's occupied cells and check
          // that each is either already in the group or free.
          final variantCells = <int>{};
          bool valid = true;
          for (int r = 0; r < varH && valid; r++) {
            for (int c = 0; c < varW && valid; c++) {
              if (variant[r][c] == 0) continue;
              final gridIdx = (topRow + r) * puzzle.width + (topCol + c);
              variantCells.add(gridIdx);

              // Check if this cell is outside the current group
              if (!groupSet.contains(gridIdx) &&
                  puzzle.cellValues[gridIdx] != 0) {
                // If same color, check if merge would be valid
                if (puzzle.cellValues[gridIdx] == color) {
                  final otherGroup = cellToGroup[gridIdx] ?? <int>[];
                  if (otherGroup.isNotEmpty) {
                    final mergedGroup = [...group, ...otherGroup];
                    if (!_groupCanFitInSomeVariant(mergedGroup, puzzle)) {
                      valid = false;
                    }
                  }
                } else {
                  // Different color - reject
                  valid = false;
                }
              }
            }
          }
          if (!valid) continue;

          // The placement must cover every cell in the group.
          if (!groupSet.every(variantCells.contains)) continue;

          // toFill should only include FREE cells, not cells that are already colored
          final toFillCandidates = variantCells.difference(groupSet);
          final toFill = toFillCandidates
              .where((idx) => puzzle.cellValues[idx] == 0)
              .toSet();

          // Reject completions that would merge with another same-color group.
          // If any cell we'd fill has a same-color neighbor outside the variant
          // placement (and outside the current group), completing here would
          // create a merged group larger than the shape.
          bool wouldMerge = false;
          for (final fillIdx in toFill) {
            for (final nei in puzzle.getNeighbors(fillIdx)) {
              if (puzzle.cellValues[nei] == color &&
                  !groupSet.contains(nei) &&
                  !variantCells.contains(nei)) {
                wouldMerge = true;
                break;
              }
            }
            if (wouldMerge) break;
          }
          if (wouldMerge) continue;

          completions.add(toFill);
        }
      }
    }
    return completions;
  }

  @override
  bool verify(Puzzle puzzle) {
    final groups = getGroups(puzzle);

    for (final group in groups) {
      // Only check groups of the constrained color.
      if (puzzle.cellValues[group.first] != color) continue;

      // Does this group have free (empty) neighbors? If so it can still grow.
      final bool isOpen = group.any(
        (idx) => puzzle.getNeighbors(idx).any((n) => puzzle.cellValues[n] == 0),
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

  static List<((int, int), List<List<int>>)> findAdditionalPositions(
    Puzzle solved,
  ) {
    final width = solved.width;
    final height = solved.height;
    final sc = solved.constraints.whereType<ShapeConstraint>().first;
    final motifValue = sc.color;
    final oppositeColor = solved.domain.whereNot((i) => i == motifValue).first;

    final List<((int, int), List<List<int>>)> results = [];

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
              if (cellValue != 0 && cellValue != oppositeColor) {
                canPlace = false;
              }
            }
          }

          if (!canPlace) continue;

          final testPuzzle = solved.clone();
          for (int vr = 0; vr < variantHeight; vr++) {
            for (int vc = 0; vc < variantWidth; vc++) {
              final value = variant[vr][vc];
              if (value != 0) {
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
    return puzzle.cellValues.every((v) => v != 0);
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Convert a group (list of cell indices) into a 2D matrix within its bounding
/// box. Occupied cells get [color], empty cells get 0.
List<List<int>> _groupToMatrix(List<int> group, Puzzle puzzle) {
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
  final matrix = List.generate(h, (_) => List.filled(w, 0));
  for (final idx in group) {
    matrix[idx ~/ puzzle.width - minRow][idx % puzzle.width - minCol] = color;
  }
  return matrix;
}

/// Deep-compare two 2D int matrices.
bool _matricesEqual(List<List<int>> a, List<List<int>> b) {
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
  List<List<int>> variant,
  int groupH,
  int groupW,
) {
  final varH = variant.length;
  final varW = variant[0].length;
  // Try every valid translation (dr, dc).
  for (int dr = 0; dr <= varH - groupH; dr++) {
    for (int dc = 0; dc <= varW - groupW; dc++) {
      final allMatch = offsets.every((o) => variant[o.$1 + dr][o.$2 + dc] != 0);
      if (allMatch) return true;
    }
  }
  return false;
}
