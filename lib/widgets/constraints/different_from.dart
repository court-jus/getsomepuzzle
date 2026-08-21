import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Preview glyph for the DF constraint: the "≠" inside a filled circle
/// straddling the shared edge of the two cells, framed by the readonly-cell
/// border on the icon's top, bottom and middle — as if seeing the right part
/// of the left cell and the left part of the right cell with the constraint
/// between them. The circle mirrors [DifferentFromPainter]'s circle on the
/// board. Only used by the UI registry for previews.
class DifferentFromPreview extends StatelessWidget {
  const DifferentFromPreview({
    super.key,
    required this.color,
    required this.cellSize,
  });

  /// Foreground colour: the circle stroke and the "≠" glyph.
  final Color color;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    return CustomPaint(
      size: Size.square(cellSize),
      painter: _DifferentFromPreviewPainter(
        cellSize: cellSize,
        fgColor: color,
        borderColor: pc.cellFgReadonly,
        fillColor: pc.mandatory,
      ),
    );
  }
}

class _DifferentFromPreviewPainter extends CustomPainter {
  _DifferentFromPreviewPainter({
    required this.cellSize,
    required this.fgColor,
    required this.borderColor,
    required this.fillColor,
  });

  final double cellSize;
  final Color fgColor;
  final Color borderColor;
  final Color fillColor;

  static const _borderWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = _borderWidth
      ..style = PaintingStyle.stroke;

    // Top and bottom edges plus the vertical divider on the shared edge
    // between the two cells. There are no left/right edges: the icon shows
    // the right part of the left cell and the left part of the right cell.
    final inset = _borderWidth / 2;
    canvas.drawLine(Offset(0, inset), Offset(cellSize, inset), borderPaint);
    canvas.drawLine(
      Offset(0, cellSize - inset),
      Offset(cellSize, cellSize - inset),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cellSize / 2, 0),
      Offset(cellSize / 2, cellSize),
      borderPaint,
    );

    // The "≠" circle sits on the shared edge, exactly like
    // DifferentFromPainter, and covers the divider where it passes.
    final center = Offset(cellSize / 2, cellSize / 2);
    final radius = cellSize * 0.18;
    canvas.drawCircle(center, radius, Paint()..color = fillColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = fgColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: '≠',
        style: TextStyle(
          color: fgColor,
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
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _DifferentFromPreviewPainter oldDelegate) {
    return cellSize != oldDelegate.cellSize ||
        fgColor != oldDelegate.fgColor ||
        borderColor != oldDelegate.borderColor ||
        fillColor != oldDelegate.fillColor;
  }
}
