// Regular pre-fill: a uniformly random solved grid.
//
// The default pre-fill mode. Each cell gets a domain value drawn
// uniformly at random. Used when neither SH nor path-based scenarios
// are active.

import 'dart:math';

import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

Puzzle preFillRegular(int width, int height, List<int> domain, Random rng) {
  final solved = Puzzle.empty(width, height, domain);
  final size = solved.width * solved.height;
  for (int i = 0; i < size; i++) {
    solved.cells[i].setForSolver(domain[rng.nextInt(domain.length)]);
  }
  return solved;
}
