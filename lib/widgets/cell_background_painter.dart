import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/puzzle.dart';

class CellBackgroundPainter extends CustomPainter {
  final Puzzle puzzle;
  final double cellSize;
  final PuzzleColors puzzleColors;

  CellBackgroundPainter({
    required this.puzzle,
    required this.cellSize,
    required this.puzzleColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = puzzle.width;
    for (int idx = 0; idx < puzzle.cells.length; idx++) {
      final col = idx % w;
      final row = idx ~/ w;
      final value = puzzle.cellValues[idx];
      final Color color;
      switch (value) {
        case CellValue.free:
          color = puzzleColors.cellBgUndecided;
        case CellValue.black:
          color = puzzleColors.cellBgBlack;
        case CellValue.white:
          color = puzzleColors.cellBgWhite;
        case CellValue.purple:
          color = puzzleColors.cellBgWhite;
      }
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
