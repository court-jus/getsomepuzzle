import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class SolverReport {
  final List<SolveStep> steps;
  final String? impossibleBy;
  final bool solved;
  final bool aborted;
  final Set<int> propagationCells;
  final Set<int> forceCells;
  final Map<int, CellValue> cornerValues;
  final int deducedCount;
  final int bruteForceCount;
  final int totalFreeCells;

  const SolverReport({
    required this.steps,
    this.impossibleBy,
    required this.solved,
    this.aborted = false,
    required this.propagationCells,
    required this.forceCells,
    required this.cornerValues,
    required this.deducedCount,
    required this.bruteForceCount,
    required this.totalFreeCells,
  });
}
