import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/widgets/cell.dart';

class EyesWidget extends StatelessWidget {
  const EyesWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final EyesConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: cellSize,
      height: cellSize,
      child: CustomPaint(
        painter: _EyesPainter(constraint: constraint, cellSize: cellSize),
      ),
    );
    // Complete-and-valid fades the whole widget via opacity rather than
    // lerping the fill toward grey: that preserves the black/white polarity
    // (which encodes *which* color the constraint is counting) while still
    // making "done" clearly distinct from an active constraint.
    if (constraint.isComplete && constraint.isValid) {
      return Opacity(opacity: 0.45, child: content);
    }
    return content;
  }
}

class _EyesPainter extends CustomPainter {
  final EyesConstraint constraint;
  final double cellSize;
  // Snapshots at construction time. The `constraint` reference is stable
  // across builds (it is mutated in place), so comparing flags through
  // `constraint.*` in `shouldRepaint` would always be a no-op.
  final bool isValid;
  final bool isHighlighted;
  final int color;
  final int count;

  _EyesPainter({required this.constraint, required this.cellSize})
    : isValid = constraint.isValid,
      isHighlighted = constraint.isHighlighted,
      color = constraint.color,
      count = constraint.count;

  @override
  void paint(Canvas canvas, Size size) {
    // Eye shape using two arcs: top arc from left to right, bottom arc from left to right.
    // Sized at 2/3 of the cell, centered with a margin.
    const eyeRatio = 2 / 3;
    final s = cellSize * eyeRatio;
    final inset = (cellSize - s) / 2;
    final ovalHeight = s * 0.55;
    final ovalTop = inset + (s - ovalHeight) / 2;

    final rect = Rect.fromLTWH(inset, ovalTop, s, ovalHeight);

    // Eye shape: top arc left→right curving up, bottom arc right→left curving down
    final path = Path()
      ..moveTo(inset, ovalTop + ovalHeight / 2)
      ..arcTo(rect, -3.14159, -3.14159, true)
      ..arcTo(rect, 3.14159, 3.14159, true);

    final fillColor = bgColors[color] ?? Colors.grey;
    final oppositeColor = bgColors[3 - color] ?? Colors.white;
    final textColor = fgColors[color] ?? Colors.black;

    final Color strokeColor;
    if (!isValid) {
      strokeColor = Colors.deepOrange;
    } else if (isHighlighted) {
      strokeColor = highlightColor;
    } else {
      strokeColor = oppositeColor;
    }

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = (s * 0.05).clamp(1.0, 3.0)
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          fontSize: ovalHeight * 0.45,
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        inset + (s - textPainter.width) / 2,
        ovalTop + (ovalHeight - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _EyesPainter old) =>
      old.cellSize != cellSize ||
      old.isValid != isValid ||
      old.isHighlighted != isHighlighted ||
      old.color != color ||
      old.count != count;
}
