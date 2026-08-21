import 'dart:math';

import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Preview glyph for the IM constraint: a 2×2 mini-grid that occupies the
/// same footprint as the single-cell previews (`cellSize²`), whose four
/// cells carry the readonly-cell border, with the implication arrow drawn
/// from the top-left cell to the bottom-right cell — mirroring the on-board
/// [ImplicationPainter] arrow (source cell → target cell). Only used by the
/// UI registry for previews.
class ImplicationWidget extends StatelessWidget {
  final Color fgcolor;
  final double cellSize;

  const ImplicationWidget({
    super.key,
    required this.fgcolor,
    required this.cellSize,
  });

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return CustomPaint(
      size: Size.square(cellSize),
      painter: _ImplicationPreviewPainter(
        cellSize: cellSize,
        arrowColor: fgcolor,
        borderColor: pc.cellFgReadonly,
      ),
    );
  }
}

class _ImplicationPreviewPainter extends CustomPainter {
  _ImplicationPreviewPainter({
    required this.cellSize,
    required this.arrowColor,
    required this.borderColor,
  });

  final double cellSize;
  final Color arrowColor;
  final Color borderColor;

  static const _borderWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final half = cellSize / 2;

    // 2×2 cell grid; the outer stroke is inset by half its width so it stays
    // fully inside the box (the same look as the single-cell previews).
    final inset = _borderWidth / 2;
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = _borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(inset, inset, cellSize - 2 * inset, cellSize - 2 * inset),
      borderPaint,
    );
    canvas.drawLine(Offset(half, 0), Offset(half, cellSize), borderPaint);
    canvas.drawLine(Offset(0, half), Offset(cellSize, half), borderPaint);

    // Arrow from the top-left cell centre to the bottom-right cell centre
    // (the logical destination stays on the cell centre), curved like
    // ImplicationPainter's cubic bezier: control points offset perpendicular
    // to the line (scaled off the mini-cell size, the arrow's "board cell"
    // equivalent), bending toward the top-right.
    final src = Offset(half / 2, half / 2);
    final tgt = Offset(half + half / 2, half + half / 2);
    final dx = tgt.dx - src.dx;
    final dy = tgt.dy - src.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final amplitude = max(half * 0.5, dist * 0.25);
    final perpX = -dy / dist;
    final perpY = dx / dist;
    final ctrl1 = Offset(
      src.dx + dx * 0.25 + perpX * amplitude,
      src.dy + dy * 0.25 + perpY * amplitude,
    );
    final ctrl2 = Offset(
      src.dx + dx * 0.75 + perpX * amplitude,
      src.dy + dy * 0.75 + perpY * amplitude,
    );
    final strokeWidth = (cellSize * 0.06).clamp(2.0, 4.0);
    final arrowPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(src.dx, src.dy)
      ..cubicTo(ctrl1.dx, ctrl1.dy, ctrl2.dx, ctrl2.dy, tgt.dx, tgt.dy);
    canvas.drawPath(path, arrowPaint);

    // Arrowhead drawing pushed to the right by about half its own length:
    // the logical arrow still ends on the target cell centre; only the
    // filled triangle (tip + base) is drawn half a head-length further right.
    final arrowSize = (cellSize * 0.26).clamp(6.0, 20.0);
    final headTip = Offset(tgt.dx + arrowSize / 2, tgt.dy);
    final angle = atan2(tgt.dy - ctrl2.dy, tgt.dx - ctrl2.dx);
    final p1 = Offset(
      headTip.dx - arrowSize * cos(angle - 0.5),
      headTip.dy - arrowSize * sin(angle - 0.5),
    );
    final p2 = Offset(
      headTip.dx - arrowSize * cos(angle + 0.5),
      headTip.dy - arrowSize * sin(angle + 0.5),
    );
    final headPath = Path()
      ..moveTo(headTip.dx, headTip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(headPath, Paint()..color = arrowColor);
  }

  @override
  bool shouldRepaint(covariant _ImplicationPreviewPainter oldDelegate) {
    return cellSize != oldDelegate.cellSize ||
        arrowColor != oldDelegate.arrowColor ||
        borderColor != oldDelegate.borderColor;
  }
}
