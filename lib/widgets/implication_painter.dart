import 'dart:math';
import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/implication.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';

class ImplicationPainter extends CustomPainter {
  final List<ImplicationConstraint> constraints;
  final double cellSize;
  final int gridWidth;
  final Color highlightColor;

  ImplicationPainter({
    required this.constraints,
    required this.cellSize,
    required this.gridWidth,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final constraint in constraints) {
      final srcIdx = constraint.indices.first;
      final tgtIdx = constraint.targetIdx;

      final srcRow = srcIdx ~/ gridWidth;
      final srcCol = srcIdx % gridWidth;
      final tgtRow = tgtIdx ~/ gridWidth;
      final tgtCol = tgtIdx % gridWidth;

      final srcCenter = Offset(
        (srcCol + 0.5) * cellSize,
        (srcRow + 0.5) * cellSize,
      );
      final tgtCenter = Offset(
        (tgtCol + 0.5) * cellSize,
        (tgtRow + 0.5) * cellSize,
      );

      final isHighlighted = constraint.isHighlighted;
      final shouldGrayOut = constraint.isComplete;

      final Color arrowColor;
      double strokeWidth;
      if (!constraint.isValid) {
        arrowColor = const Color(0xFFDC322F); // solarized red
        strokeWidth = 4.0;
      } else if (isHighlighted) {
        arrowColor = highlightColor;
        strokeWidth = 5.0;
      } else if (shouldGrayOut) {
        arrowColor = Colors.grey.withValues(alpha: 0.25);
        strokeWidth = 2.0;
      } else {
        // Arrow colour reflects the constraint's colour for quick
        // visual identification.
        arrowColor = switch (constraint.color) {
          CellValue.black => const Color(0xFFB58900), // jaune
          CellValue.purple => const Color(0xFF2AA198), // cyan
          _ => const Color(0xFFD33682), // magenta
        };
        strokeWidth = 4.0;
      }

      final paint = Paint()
        ..color = arrowColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      final mid = Offset(
        (srcCenter.dx + tgtCenter.dx) / 2,
        (srcCenter.dy + tgtCenter.dy) / 2,
      );

      // Pick a control-point offset perpendicular to the line direction.
      // If the two cells are on the same row, curve upward; if on the same
      // column, curve left; otherwise pick the direction that bends the
      // arrow toward the interior of the grid.
      final dx = tgtCenter.dx - srcCenter.dx;
      final dy = tgtCenter.dy - srcCenter.dy;
      final dist = sqrt(dx * dx + dy * dy);

      // Scale the curve amplitude with the distance.
      final amplitude = max(cellSize * 0.5, dist * 0.25);
      final perpX = -dy / dist;
      final perpY = dx / dist;

      // Pick the perpendicular direction that keeps the curve inside the grid.
      // Default: bend away from the nearest grid edge.
      final centerX = size.width / 2;
      final centerY = size.height / 2;
      final bendTowardCenterX = (mid.dx < centerX) ? 1.0 : -1.0;
      final bendTowardCenterY = (mid.dy < centerY) ? 1.0 : -1.0;
      final signX = perpX.abs() > 0.01 ? (perpX > 0 ? 1.0 : -1.0) : 0.0;
      final signY = perpY.abs() > 0.01 ? (perpY > 0 ? 1.0 : -1.0) : 0.0;
      final bend = (signX * bendTowardCenterX + signY * bendTowardCenterY) >= 0
          ? 1.0
          : -1.0;

      final ctrl1 = Offset(
        srcCenter.dx + dx * 0.25 + perpX * amplitude * bend,
        srcCenter.dy + dy * 0.25 + perpY * amplitude * bend,
      );
      final ctrl2 = Offset(
        srcCenter.dx + dx * 0.75 + perpX * amplitude * bend,
        srcCenter.dy + dy * 0.75 + perpY * amplitude * bend,
      );

      final path = Path()
        ..moveTo(srcCenter.dx, srcCenter.dy)
        ..cubicTo(
          ctrl1.dx,
          ctrl1.dy,
          ctrl2.dx,
          ctrl2.dy,
          tgtCenter.dx,
          tgtCenter.dy,
        );
      canvas.drawPath(path, paint);

      // Arrowhead: tangent at the endpoint (roughly direction from ctrl2 to tgt)
      final arrowSize = cellSize * 0.22;
      final angle = atan2(tgtCenter.dy - ctrl2.dy, tgtCenter.dx - ctrl2.dx);

      final p1 = Offset(
        tgtCenter.dx - arrowSize * cos(angle - 0.5),
        tgtCenter.dy - arrowSize * sin(angle - 0.5),
      );
      final p2 = Offset(
        tgtCenter.dx - arrowSize * cos(angle + 0.5),
        tgtCenter.dy - arrowSize * sin(angle + 0.5),
      );
      final headPath = Path()
        ..moveTo(tgtCenter.dx, tgtCenter.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(
        headPath,
        Paint()
          ..color = arrowColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..color = arrowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ImplicationPainter oldDelegate) {
    return constraints != oldDelegate.constraints ||
        cellSize != oldDelegate.cellSize ||
        gridWidth != oldDelegate.gridWidth ||
        highlightColor != oldDelegate.highlightColor;
  }
}
