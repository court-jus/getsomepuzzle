import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/majority.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/widgets/dashed_painter.dart';

const Color _mjBorderBlackTarget = Color(0xFF3A4A6B);
const Color _mjBorderWhiteTarget = Color(0xFFC8D4E8);

Color _mjBorderColor(int targetColor) {
  if (targetColor == 1) return _mjBorderBlackTarget;
  if (targetColor == 2) return _mjBorderWhiteTarget;
  return Colors.grey;
}

class MajorityZonePainter extends CustomPainter {
  final List<MajorityConstraint> constraints;
  final double cellSize;
  final int gridWidth;

  MajorityZonePainter({
    required this.constraints,
    required this.cellSize,
    required this.gridWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const baseInset = 6.0;
    final step = (cellSize * 0.12).clamp(3.0, 5.0);
    // Cap so a nested inset never collapses a zone (MJ zones are >= 2 cells
    // per side, so 2 * maxInset stays below one cell).
    final maxInset = cellSize * 0.45;
    final borderWidth = (cellSize * 0.09).clamp(2.0, 4.0);

    // Assign each zone a nesting level via greedy graph coloring of the
    // conflict graph (zones whose borders would overlap — see
    // MajorityConstraint.conflictsWith). Conflicting zones get distinct levels
    // so their borders nest at different insets instead of coinciding.
    final levels = List<int>.filled(constraints.length, 0);
    for (int i = 0; i < constraints.length; i++) {
      final used = <int>{};
      for (int j = 0; j < i; j++) {
        if (constraints[i].conflictsWith(constraints[j])) used.add(levels[j]);
      }
      int lvl = 0;
      while (used.contains(lvl)) {
        lvl++;
      }
      levels[i] = lvl;
    }

    for (int idx = 0; idx < constraints.length; idx++) {
      final constraint = constraints[idx];
      final inset = (baseInset + levels[idx] * step).clamp(baseInset, maxInset);

      final left = constraint.c0 * cellSize + inset;
      final top = constraint.r0 * cellSize + inset;
      final width = (constraint.c1 - constraint.c0 + 1) * cellSize - 2 * inset;
      final height = (constraint.r1 - constraint.r0 + 1) * cellSize - 2 * inset;

      final rect = Rect.fromLTWH(left, top, width, height);

      final shouldGrayOut = constraint.isComplete && constraint.isValid;
      final isHighlighted = constraint.isHighlighted;

      final Color borderColor;
      if (shouldGrayOut) {
        borderColor = Colors.grey.withValues(alpha: 0.5);
      } else if (!constraint.isValid) {
        borderColor = Colors.red;
      } else if (isHighlighted) {
        borderColor = highlightColor;
      } else {
        borderColor = _mjBorderColor(constraint.targetColor);
      }

      if (isHighlighted) {
        final fillPaint = Paint()
          ..color = highlightColor.withValues(alpha: 0.1)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, fillPaint);
      }

      final borderPaint = Paint()
        ..color = borderColor
        ..strokeWidth = borderWidth
        ..style = PaintingStyle.stroke;

      final dashLength = borderWidth * 2;
      final gapLength = borderWidth * 1.5;

      drawDashedRect(canvas, rect, borderPaint, dashLength, gapLength);
    }
  }

  @override
  bool shouldRepaint(covariant MajorityZonePainter oldDelegate) {
    return !listEquals(constraints, oldDelegate.constraints) ||
        cellSize != oldDelegate.cellSize ||
        gridWidth != oldDelegate.gridWidth;
  }
}
