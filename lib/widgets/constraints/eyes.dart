import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/eyes_constraint.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
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
  final CellValue color;
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
    final oppositeColor =
        bgColors[color == CellValue.black
            ? CellValue.white
            : CellValue.black] ??
        Colors.white;
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

    final fontSize = cellSize * cellSizeToFontSize;
    // The digit takes the eye's color (= constraint color), so it visually
    // matches the eye it belongs to. Inside the eye, the digit blends with the
    // fill, so we draw an outline in the opposite color to keep it readable
    // (effectively a hollowed-out digit). Outside the eye, the colored digit
    // shows directly and the outline stays subtle.
    final outlineWidth = (cellSize * 0.04).clamp(1.0, 2.5);
    final strokePainter = TextPainter(
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outlineWidth
            ..strokeJoin = StrokeJoin.round
            ..color = textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    final fillTextPainter = TextPainter(
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          fontSize: fontSize,
          color: fillColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    strokePainter.layout();
    fillTextPainter.layout();
    final textOffset = Offset(
      (cellSize - fillTextPainter.width) / 2,
      (cellSize - fillTextPainter.height) / 2,
    );
    strokePainter.paint(canvas, textOffset);
    fillTextPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant _EyesPainter old) =>
      old.cellSize != cellSize ||
      old.isValid != isValid ||
      old.isHighlighted != isHighlighted ||
      old.color != color ||
      old.count != count;
}
