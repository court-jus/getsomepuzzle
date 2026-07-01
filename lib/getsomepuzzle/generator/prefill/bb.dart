// BB (Bounding Box) pre-fill: seed a solved grid whose colour-`c` groups all
// share one bounding-box extent `W×H`, so the `BB:c.W.H` constraint is
// satisfiable. A random grid almost never survives the candidate `verify`
// filter for BB (heterogeneous extents), hence this dedicated pre-fill.
//
// Activated when BB is in the priority slug set (required by the user or
// pushed by the equilibrium target). Returns a [Puzzle] with the chosen
// [BoundingBoxConstraint](s) already attached. See `docs/dev/prefill_bb.md`.

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/bounding_box.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Puzzle preFillBB(int width, int height, List<CellValue> domain, Random rng) {
  final solved = Puzzle.empty(width, height, domain);

  // Phase 0: choose colours and their bounding boxes. A second BB colour is
  // drawn with p=0.35 only when the domain has room for a background colour.
  final color1 = domain[rng.nextInt(domain.length)];
  final w1 = _drawExtent(width, rng);
  final h1 = _drawExtent(height, rng);

  CellValue? color2;
  int w2 = 0, h2 = 0;
  if (domain.length > 2 && rng.nextDouble() < 0.35) {
    final others = domain.whereNot((c) => c == color1).toList();
    color2 = others[rng.nextInt(others.length)];
    w2 = _drawExtent(width, rng);
    h2 = _drawExtent(height, rng);
  }

  // Phases 1 & 2: grow the islands of each BB colour independently. A colour
  // may fail to place a single island (no window left after the other colour
  // saturated the grid); its constraint is then skipped — attaching a BB with
  // no group would forbid the player from ever forming one, a degenerate rule.
  final placed1 = _placeColorIslands(solved, color1, w1, h1, rng);
  final placed2 =
      color2 != null && _placeColorIslands(solved, color2, w2, h2, rng);

  // Phase 3: background — fill every remaining cell with a colour that is
  // not a BB colour, so no new group of either BB colour is introduced.
  final bbColors = {color1, ?color2};
  final others = domain.whereNot((c) => bbColors.contains(c)).toList();
  for (int i = 0; i < width * height; i++) {
    if (!solved.cells[i].isFree) continue;
    solved.cells[i].setForSolver(others[rng.nextInt(others.length)]);
  }

  // Phase 4: attach one BB constraint per colour that actually got an island.
  if (placed1) {
    solved.addConstraint(
      BoundingBoxConstraint('${cellValueToString(color1)}.$w1.$h1'),
    );
  }
  if (placed2) {
    solved.addConstraint(
      BoundingBoxConstraint('${cellValueToString(color2)}.$w2.$h2'),
    );
  }

  return solved;
}

/// Draw a box extent in `[2, dim - 1]` — a box never spans a full grid
/// dimension (a full-span dimension is a weak BB rule), matching the space
/// `BoundingBoxConstraint.generateAllParameters` enumerates. The minimum of two
/// uniform draws biases the mass toward small extents while letting larger
/// boxes appear in a thinning tail that widens with the grid. A grid dimension
/// below 3 has no valid interior extent and clamps to 2.
int _drawExtent(int dim, Random rng) {
  if (dim < 3) return 2;
  final span = dim - 2; // uniform indices 0..span-1 map to extents 2..dim-1
  return 2 + min(rng.nextInt(span), rng.nextInt(span));
}

/// Place all islands of [color] with bounding box [boxW]×[boxH] onto [solved].
/// The first island is always painted; further islands follow the ~50 %-accept
/// place-then-find loop (mirror of SH's `_placeAdditionalVariants`), each
/// regrown from scratch so islands sharing the extent never share a shape.
/// Returns whether at least one island was painted (false → no window left).
bool _placeColorIslands(
  Puzzle solved,
  CellValue color,
  int boxW,
  int boxH,
  Random rng,
) {
  var positions = findAdditionalBoxPositions(solved, color, boxW, boxH, rng);
  if (positions.isEmpty) return false;
  // First island: forbidden set is empty (no colour cell yet), so every
  // window is viable — paint one outright.
  _paintCells(solved, positions[rng.nextInt(positions.length)], color);

  positions = findAdditionalBoxPositions(solved, color, boxW, boxH, rng);
  while (positions.isNotEmpty) {
    final pick = positions[rng.nextInt(positions.length)];
    if (rng.nextDouble() > 0.5) {
      _paintCells(solved, pick, color);
      positions = findAdditionalBoxPositions(solved, color, boxW, boxH, rng);
    }
  }
  return true;
}

/// Scan every `boxH×boxW` window that fits the grid and, for each, grow a
/// fresh shape touching all four sides (extent exactly `boxW×boxH`). Returns
/// the grown cell sets for the windows where growth succeeded.
///
/// Windows may overlap (interlocking). Growth is per-colour separated: a
/// shape is never orthogonally adjacent to an existing [color] cell, so each
/// island stays a distinct group while boxes are free to overlap. The scan is
/// randomized — a viable window may fail on a given seed; density is emergent.
List<Set<int>> findAdditionalBoxPositions(
  Puzzle solved,
  CellValue color,
  int boxW,
  int boxH,
  Random rng,
) {
  final results = <Set<int>>[];
  for (int r0 = 0; r0 + boxH <= solved.height; r0++) {
    for (int c0 = 0; c0 + boxW <= solved.width; c0++) {
      final shape = _growBox(solved, color, r0, c0, boxW, boxH, rng);
      if (shape != null) results.add(shape);
    }
  }
  return results;
}

/// Grow a connected, hollow shape inside the window at (`r0`,`c0`) of size
/// `boxH×boxW`, touching all four sides. Returns the cell set, or null when
/// growth got stuck or the window has no usable anchor.
///
/// Strategy (skeleton → sides, then thicken): drop a random anchor, then while
/// a side is unreached, random-walk from a random already-coloured cell toward
/// that side (biased ~0.75 toward it), stopping as soon as the side is hit.
/// Finally thicken at p=0.2, keeping holes.
Set<int>? _growBox(
  Puzzle solved,
  CellValue color,
  int r0,
  int c0,
  int boxW,
  int boxH,
  Random rng,
) {
  final width = solved.width;
  final height = solved.height;
  final rMax = r0 + boxH - 1;
  final cMax = c0 + boxW - 1;

  // Forbidden = same-colour cells already placed + their orthogonal halo.
  // Cells of a *different* colour are not forbidden (different colours may be
  // adjacent) but are not free, so `usable` skips them anyway.
  final forbidden = <int>{};
  for (int i = 0; i < solved.cellValues.length; i++) {
    if (solved.cellValues[i] != color) continue;
    forbidden.add(i);
    for (final n in _neighbors4(i, width, height)) {
      forbidden.add(n);
    }
  }

  bool usable(int idx) {
    final r = idx ~/ width;
    final c = idx % width;
    if (r < r0 || r > rMax || c < c0 || c > cMax) return false;
    if (forbidden.contains(idx)) return false;
    return solved.cells[idx].isFree;
  }

  // Anchor: a random usable cell in the window.
  final usableAnchors = <int>[
    for (int r = r0; r <= rMax; r++)
      for (int c = c0; c <= cMax; c++)
        if (usable(r * width + c)) r * width + c,
  ];
  if (usableAnchors.isEmpty) return null;
  final cells = <int>{usableAnchors[rng.nextInt(usableAnchors.length)]};

  // Reach every side via a biased random walk.
  final maxSteps = 4 * boxW * boxH;
  while (true) {
    final untouched = _untouchedSides(cells, r0, rMax, c0, cMax, width);
    if (untouched.isEmpty) break;
    final target = untouched[rng.nextInt(untouched.length)];
    if (!_walkToSide(
      cells,
      target,
      usable,
      r0,
      rMax,
      c0,
      cMax,
      width,
      maxSteps,
      rng,
    )) {
      return null; // stuck or step cap exceeded → window fails
    }
  }

  // Thicken: each skeleton cell has a 0.2 chance to grab one usable neighbour.
  for (final cell in cells.toList()) {
    if (rng.nextDouble() >= 0.2) continue;
    final nbrs = _neighbors4(
      cell,
      width,
      height,
    ).where((n) => usable(n) && !cells.contains(n)).toList();
    if (nbrs.isNotEmpty) cells.add(nbrs[rng.nextInt(nbrs.length)]);
  }

  return cells;
}

/// Sides of the window not yet touched by [cells]: 0=top, 1=bottom, 2=left,
/// 3=right.
List<int> _untouchedSides(
  Set<int> cells,
  int r0,
  int rMax,
  int c0,
  int cMax,
  int width,
) {
  bool top = false, bot = false, lft = false, rgt = false;
  for (final i in cells) {
    final r = i ~/ width;
    final c = i % width;
    if (r == r0) top = true;
    if (r == rMax) bot = true;
    if (c == c0) lft = true;
    if (c == cMax) rgt = true;
  }
  return [if (!top) 0, if (!bot) 1, if (!lft) 2, if (!rgt) 3];
}

/// Random-walk from a random already-coloured cell toward [side], colouring
/// cells along the way, stopping as soon as the side is reached. Stepping onto
/// an own cell is allowed (lets the walk traverse the island). Returns true if
/// the side was reached within [maxSteps].
bool _walkToSide(
  Set<int> cells,
  int side,
  bool Function(int) usable,
  int r0,
  int rMax,
  int c0,
  int cMax,
  int width,
  int maxSteps,
  Random rng,
) {
  final start = cells.toList();
  int cur = start[rng.nextInt(start.length)];
  for (int step = 0; step < maxSteps; step++) {
    if (_onSide(cur, side, r0, rMax, c0, cMax, width)) return true;
    final r = cur ~/ width;
    final c = cur % width;
    final nbrs = <int>[];
    if (r > r0) nbrs.add(cur - width);
    if (r < rMax) nbrs.add(cur + width);
    if (c > c0) nbrs.add(cur - 1);
    if (c < cMax) nbrs.add(cur + 1);
    final valid = nbrs.where((n) => cells.contains(n) || usable(n)).toList();
    if (valid.isEmpty) return false; // stuck
    final preferred = valid
        .where((n) => _closerToSide(n, cur, side, width))
        .toList();
    final next = (preferred.isNotEmpty && rng.nextDouble() < 0.75)
        ? preferred[rng.nextInt(preferred.length)]
        : valid[rng.nextInt(valid.length)];
    cells.add(next);
    cur = next;
  }
  return _onSide(cur, side, r0, rMax, c0, cMax, width);
}

bool _onSide(int idx, int side, int r0, int rMax, int c0, int cMax, int width) {
  final r = idx ~/ width;
  final c = idx % width;
  switch (side) {
    case 0:
      return r == r0;
    case 1:
      return r == rMax;
    case 2:
      return c == c0;
    default:
      return c == cMax;
  }
}

/// True iff [next] is one step closer than [cur] to [side].
bool _closerToSide(int next, int cur, int side, int width) {
  final nr = next ~/ width, nc = next % width;
  final cr = cur ~/ width, cc = cur % width;
  switch (side) {
    case 0:
      return nr < cr;
    case 1:
      return nr > cr;
    case 2:
      return nc < cc;
    default:
      return nc > cc;
  }
}

void _paintCells(Puzzle solved, Set<int> cells, CellValue color) {
  for (final i in cells) {
    solved.cells[i].setForSolver(color);
  }
}

Iterable<int> _neighbors4(int idx, int width, int height) sync* {
  final x = idx % width;
  final y = idx ~/ width;
  if (x > 0) yield idx - 1;
  if (x < width - 1) yield idx + 1;
  if (y > 0) yield idx - width;
  if (y < height - 1) yield idx + width;
}
