// SH (Shape) pre-fill: seed a solved grid that contains a valid Shape
// motif so the SH constraint is satisfiable.
//
// Activated when SH is in the priority slug set (required by the user
// or pushed by the equilibrium target). Returns a [Puzzle] with the
// chosen [ShapeConstraint] already attached.

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/shape.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Puzzle preFillSh(int width, int height, List<int> domain, Random rng) {
  final solved = Puzzle.empty(width, height, domain);
  final chosenMotif = _pickShapeMotif(width, height, domain, rng);
  final sc = ShapeConstraint(chosenMotif);
  _placeInitialVariant(solved, sc, rng);
  _fillRemainingWithOpposite(solved, sc.color, domain);
  solved.addConstraint(sc);
  _placeAdditionalVariants(solved, rng);
  return solved;
}

/// Pick one motif string via weighted random sampling, where the weight
/// depends on the motif's bounding-box size (`rows × cols`).
String _pickShapeMotif(int width, int height, List<int> domain, Random rng) {
  final possibleMotifs = ShapeConstraint.generateAllParameters(
    width,
    height,
    domain,
    null,
  );
  possibleMotifs.shuffle(rng);
  final puzzleSize = width * height;
  // Weight candidate motifs by bounding-box size. Exponent `puzzleSize / 20`
  // scales the size preference with the grid's area:
  //   - small grid  (size≈5):  exp≈0.25, sizes stay roughly equal
  //   - medium grid (size=20): exp=1, linear in motifSize
  //   - large grid  (size≈40): exp≈2, big motifs dominate — they fit and
  //     stay visually interesting, small motifs feel trivial.
  // `base` is a per-size hand-tuned bias (see ShapeConstraint.baseWeights).
  final weights = possibleMotifs.map((m) {
    final motifSize = ShapeConstraint.motifGridSizeOf(m);
    final base = ShapeConstraint.baseWeights[motifSize] ?? 1;
    return base * pow(motifSize, puzzleSize * 0.05);
  }).toList();

  final totalWeight = weights.reduce((a, b) => a + b);
  final r = rng.nextDouble() * totalWeight;
  double cumulative = 0;
  for (int i = 0; i < possibleMotifs.length; i++) {
    cumulative += weights[i];
    if (r <= cumulative) return possibleMotifs[i];
  }
  return possibleMotifs.last;
}

/// Paint one variant of [sc] onto [solved] at a random position that fits.
void _placeInitialVariant(Puzzle solved, ShapeConstraint sc, Random rng) {
  sc.variants.shuffle();
  final variant = sc.variants
      .where((v) => v.length <= solved.height && v[0].length <= solved.width)
      .first;
  final maxRowOffset = solved.height - variant.length;
  final maxColOffset = solved.width - variant[0].length;
  final rowOffset = maxRowOffset > 0 ? rng.nextInt(maxRowOffset) : 0;
  final colOffset = maxColOffset > 0 ? rng.nextInt(maxColOffset) : 0;
  _paintVariant(solved, variant, rowOffset, colOffset);
}

/// Fill every still-free cell of [solved] with the color opposite [color].
void _fillRemainingWithOpposite(Puzzle solved, int color, List<int> domain) {
  final opposite = domain.whereNot((i) => i == color).first;
  for (int i = 0; i < solved.width * solved.height; i++) {
    if (!solved.cells[i].isFree) continue;
    solved.cells[i].setForSolver(opposite);
  }
}

/// Repeatedly attempt to paint additional valid variant positions onto
/// [solved]. Each candidate position has a 50% chance of being accepted.
void _placeAdditionalVariants(Puzzle solved, Random rng) {
  var possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
  while (possiblePositions.isNotEmpty) {
    final position = possiblePositions[rng.nextInt(possiblePositions.length)];
    if (rng.nextDouble() > 0.5) {
      final (rowOffset, colOffset) = position.$1;
      _paintVariant(solved, position.$2, rowOffset, colOffset);
      possiblePositions = ShapeConstraint.findAdditionalPositions(solved);
    }
  }
}

/// Write non-zero cells of [variant] onto [solved] at (rowOffset, colOffset).
void _paintVariant(
  Puzzle solved,
  List<List<int>> variant,
  int rowOffset,
  int colOffset,
) {
  for (final (ridx, row) in variant.indexed) {
    for (final (cidx, value) in row.indexed) {
      if (value == 0) continue;
      solved.cells[(ridx + rowOffset) * solved.width + (cidx + colOffset)]
          .setForSolver(value);
    }
  }
}
