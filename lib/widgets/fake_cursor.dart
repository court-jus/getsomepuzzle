import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A fake mouse cursor rendered as an arrow pointer with a red shadow.
///
/// The widget is wrapped in [IgnorePointer] so it never intercepts real input.
/// It paints a small right-upward arrow whose tip approximates the cursor point.
class FakeCursor extends StatelessWidget {
  /// Size of the cursor in logical pixels.
  static const double cursorSize = 24.0;

  const FakeCursor({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: cursorSize,
        height: cursorSize,
        child: CustomPaint(painter: _ArrowPainter()),
      ),
    );
  }
}

/// Custom painter that draws a small arrow similar to a desktop mouse cursor.
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Shadow
    canvas.drawShadow(_buildArrowPath(size), Colors.red.shade900, 4.0, false);

    // Arrow body (white fill with red border)
    canvas.drawPath(_buildArrowPath(size), paint);

    final borderPaint = Paint()
      ..color = Colors.red.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(_buildArrowPath(size), borderPaint);
  }

  /// Builds the SVG-derived cursor path.
  ///
  /// Coordinates are from [subpath 1 of /tmp/cursor.svg]
  /// (viewBox 100×100), offset so the tip is at (0, 0), then scaled to
  /// [size.width] via factor `s = size.width / 100.0`.
  ui.Path _buildArrowPath(Size size) {
    final s = size.width / 100.0;
    final path = ui.Path();

    path.moveTo(73.253 * s, 59.840 * s);
    path.lineTo(52.223 * s, 38.810 * s);
    path.lineTo(74.474 * s, 27.684 * s);
    path.cubicTo(
      76.345 * s,
      26.748 * s,
      77.436 * s,
      24.746 * s,
      77.207 * s,
      22.666 * s,
    );
    path.cubicTo(
      76.979 * s,
      20.586 * s,
      75.479 * s,
      18.869 * s,
      73.450 * s,
      18.361 * s,
    );
    path.lineTo(0.000 * s, 0.000 * s);
    path.cubicTo(
      -1.707 * s,
      -0.429 * s,
      -3.506 * s,
      0.072 * s,
      -4.748 * s,
      1.315 * s,
    );
    path.cubicTo(
      -5.990 * s,
      2.556 * s,
      -6.489 * s,
      4.359 * s,
      -6.063 * s,
      6.063 * s,
    );
    path.lineTo(12.299 * s, 79.513 * s);
    path.cubicTo(
      12.807 * s,
      81.542 * s,
      14.524 * s,
      83.042 * s,
      16.604 * s,
      83.270 * s,
    );
    path.cubicTo(
      16.788 * s,
      83.291 * s,
      16.970 * s,
      83.300 * s,
      17.152 * s,
      83.300 * s,
    );
    path.cubicTo(
      19.029 * s,
      83.300 * s,
      20.769 * s,
      82.242 * s,
      21.622 * s,
      80.536 * s,
    );
    path.lineTo(32.748 * s, 58.285 * s);
    path.lineTo(53.778 * s, 79.315 * s);
    path.cubicTo(
      56.466 * s,
      82.004 * s,
      59.991 * s,
      83.349 * s,
      63.516 * s,
      83.349 * s,
    );
    path.cubicTo(
      67.040 * s,
      83.349 * s,
      70.565 * s,
      82.004 * s,
      73.253 * s,
      79.315 * s,
    );
    path.cubicTo(
      78.632 * s,
      73.938 * s,
      78.632 * s,
      65.218 * s,
      73.253 * s,
      59.840 * s,
    );
    path.close();

    return path;
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => false;
}
