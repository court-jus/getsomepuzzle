import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/different_from.dart';

class DifferentFromPainter extends CustomPainter {
  final List<DifferentFromConstraint> constraints;
  final double cellSize;
  final int gridWidth;
  final Color defaultColor;
  final Color highlightColor;

  DifferentFromPainter({
    required this.constraints,
    required this.cellSize,
    required this.gridWidth,
    required this.defaultColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderWidth = 1.5;
    final radius = cellSize * 0.18;

    for (final constraint in constraints) {
      final idx = constraint.indices.first;
      final row = idx ~/ gridWidth;
      final col = idx % gridWidth;

      final isRight = constraint.direction == 'right';
      final isHighlighted = constraint.isHighlighted;
      final shouldGrayOut = constraint.isComplete;

      final Color circleColor;
      if (shouldGrayOut) {
        circleColor = Colors.grey;
      } else if (isHighlighted) {
        circleColor = highlightColor;
      } else {
        circleColor = constraint.isValid ? defaultColor : Colors.red;
      }

      double centerX;
      double centerY;

      if (isRight) {
        centerX = (col + 1) * cellSize;
        centerY = (row + 0.5) * cellSize;
      } else {
        centerX = (col + 0.5) * cellSize;
        centerY = (row + 1) * cellSize;
      }

      final fillPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = circleColor
        ..strokeWidth = borderWidth
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(Offset(centerX, centerY), radius, fillPaint);
      canvas.drawCircle(Offset(centerX, centerY), radius, strokePaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '≠',
          style: TextStyle(
            color: circleColor,
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          centerX - textPainter.width / 2,
          centerY - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DifferentFromPainter oldDelegate) {
    return constraints != oldDelegate.constraints ||
        cellSize != oldDelegate.cellSize ||
        gridWidth != oldDelegate.gridWidth;
  }
}
