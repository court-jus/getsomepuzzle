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

  ui.Path _buildArrowPath(Size size) {
    final s = size.width;
    final path = ui.Path();
    // Tip at (0, 0) pointing up-right
    path.moveTo(0, 0);
    path.lineTo(s, s * 0.35);
    path.lineTo(s * 0.6, s * 0.5);
    path.lineTo(s * 0.85, s);
    path.lineTo(s * 0.6, s * 0.85);
    path.lineTo(s * 0.35, s * 0.45);
    path.lineTo(0, s * 0.6);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) => false;
}
