import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/symmetry.dart';

class SymmetryWidget extends StatelessWidget {
  const SymmetryWidget({
    super.key,
    required this.fgcolor,
    required this.constraint,
    required this.cellSize,
  });

  final SymmetryConstraint constraint;
  final double cellSize;
  final Color fgcolor;

  @override
  Widget build(BuildContext context) {
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.transparent : Colors.deepOrange);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: borderColor,
          width: constraint.isHighlighted ? 8 : 4,
        ),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: CustomPaint(
            size: Size(cellSize * 0.6, cellSize * 0.6),
            painter: SymmetryPainter(axis: constraint.axis, color: fgcolor),
          ),
        ),
      ),
    );
  }
}

class SymmetryPainter extends CustomPainter {
  SymmetryPainter({required this.axis, required this.color});

  final int axis;
  final Color color;
  // 1: "⟍",
  // 2: "|",
  // 3: "⟋",
  // 4: "―",
  // 5: "🞋",

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width / 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final margin = size.width / 100;

    switch (axis) {
      case 0:
        break;
      case 1:
        canvas.drawLine(
          Offset(margin, margin),
          Offset(size.width - margin, size.height - margin),
          paint,
        );
        break;
      case 2:
        canvas.drawLine(
          Offset(center.dx, margin),
          Offset(center.dx, size.height - margin),
          paint,
        );
        break;
      case 3:
        canvas.drawLine(
          Offset(margin, size.height - margin),
          Offset(size.width - margin, margin),
          paint,
        );
        break;
      case 4:
        canvas.drawLine(
          Offset(margin, center.dy),
          Offset(size.width - margin, center.dy),
          paint,
        );
        break;
      case 5:
        final r1 = size.width / 2;
        final r2 = size.width / 3;
        final r3 = size.width / 8;
        canvas.drawCircle(center, r1, paint);
        canvas.drawCircle(center, r2, paint);
        canvas.drawCircle(center, r3, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant SymmetryPainter oldDelegate) {
    return oldDelegate.axis != axis;
  }
}
