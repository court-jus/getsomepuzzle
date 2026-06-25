import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';
import 'package:getsomepuzzle/widgets/cell.dart' show bgColors;

class CellBackgroundPainter extends CustomPainter {
  final Puzzle puzzle;
  final double cellSize;

  CellBackgroundPainter({required this.puzzle, required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final w = puzzle.width;
    for (int idx = 0; idx < puzzle.cells.length; idx++) {
      final col = idx % w;
      final row = idx ~/ w;
      final color = bgColors[puzzle.cellValues[idx]] ?? Colors.transparent;
      final rect = Rect.fromLTWH(
        col * cellSize,
        row * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant CellBackgroundPainter oldDelegate) {
    return puzzle != oldDelegate.puzzle || cellSize != oldDelegate.cellSize;
  }
}
