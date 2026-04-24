import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/widgets/cell.dart';

class NeighborCountWidget extends StatelessWidget {
  const NeighborCountWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final NeighborCountConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: cellSize,
      height: cellSize,
      child: CustomPaint(
        painter: _CrossPainter(constraint: constraint, cellSize: cellSize),
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

class _CrossPainter extends CustomPainter {
  final NeighborCountConstraint constraint;
  final double cellSize;
  // Snapshots at construction time. The `constraint` reference is stable
  // across builds (it is mutated in place), so comparing flags through
  // `constraint.*` in `shouldRepaint` would always be a no-op.
  final bool isValid;
  final bool isHighlighted;
  final int color;
  final int count;

  _CrossPainter({required this.constraint, required this.cellSize})
    : isValid = constraint.isValid,
      isHighlighted = constraint.isHighlighted,
      color = constraint.color,
      count = constraint.count;

  @override
  void paint(Canvas canvas, Size size) {
    // Cross is centered inside the cell and capped at 2/3 of the cell size,
    // leaving a margin around it so it never bleeds into neighbouring visuals.
    const crossRatio = 2 / 3;
    const armRatio = 0.55;
    final s = cellSize * crossRatio;
    final inset = (cellSize - s) / 2;
    final w = s * armRatio;
    final h = (s - w) / 2;

    final path = Path()
      ..moveTo(inset + h, inset + 0)
      ..lineTo(inset + h + w, inset + 0)
      ..lineTo(inset + h + w, inset + h)
      ..lineTo(inset + s, inset + h)
      ..lineTo(inset + s, inset + h + w)
      ..lineTo(inset + h + w, inset + h + w)
      ..lineTo(inset + h + w, inset + s)
      ..lineTo(inset + h, inset + s)
      ..lineTo(inset + h, inset + h + w)
      ..lineTo(inset + 0, inset + h + w)
      ..lineTo(inset + 0, inset + h)
      ..lineTo(inset + h, inset + h)
      ..close();

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
          fontSize: w * 0.7,
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
        inset + (s - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _CrossPainter old) =>
      old.cellSize != cellSize ||
      old.isValid != isValid ||
      old.isHighlighted != isHighlighted ||
      old.color != color ||
      old.count != count;
}
