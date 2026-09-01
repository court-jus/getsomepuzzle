import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/mirror.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';

/// Icon for the Mirror constraint (`MI`): a mini-grid of the `01100011`
/// pattern (4 rows × 2 cols) split by a mirror line.
///
/// The base form is portrait (4 rows × 2 cols) and is the `H` (horizontal)
/// mirror: the line runs horizontally between rows 2 and 3. The `V` (vertical)
/// form is the same widget rotated 90° clockwise, so the line renders
/// vertically and the icon reads landscape (2 rows × 4 cols).
///
/// Rendered on the constraint chip background (mandatory colour, like the
/// islands widget): a [cellSize]-sized square filled with the mandatory
/// colour and bordered by the constraint state colour.
class MirrorWidget extends StatelessWidget {
  const MirrorWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
    this.fgcolor,
  });

  final MirrorConstraint constraint;
  final double cellSize;
  final Color? fgcolor;

  /// The 8 bits of `01100011` laid out row-major over 4 rows × 2 cols.
  static const _mirrorPattern = ['01', '10', '00', '11'];

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : pc.mandatory;
    final borderColor = constraint.borderColor(pc);
    final fillColor = shouldGrayOut
        ? Colors.grey
        : (pc.constraintColors[constraint.color] ?? pc.constraintInvalid);
    final lineColor = shouldGrayOut
        ? Colors.grey
        : (fgcolor ?? constraint.borderColor(pc));
    final s = cellSize / 5;
    final grid = SizedBox(
      width: 2 * s,
      height: 4 * s,
      child: CustomPaint(
        painter: MirrorPainter(
          pattern: _mirrorPattern,
          fillColor: fillColor,
          lineColor: lineColor,
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(
          color: borderColor,
          width: constraint.borderWidth,
        ),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Center(
          child: constraint.direction == 'V'
              ? RotatedBox(quarterTurns: 1, child: grid)
              : grid,
        ),
      ),
    );
  }
}

class MirrorPainter extends CustomPainter {
  MirrorPainter({
    required this.pattern,
    required this.fillColor,
    required this.lineColor,
  });

  final List<String> pattern;
  final Color fillColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = pattern.length;
    final cols = pattern.first.length;
    final s = size.width / cols;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..color = Colors.grey.withValues(alpha: 0.4);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final rect = Rect.fromLTWH(c * s, r * s, s, s);
        if (pattern[r][c] == '1') {
          fillPaint.color = fillColor;
          canvas.drawRect(rect, fillPaint);
        }
        // Hairline outline per sub-cell for readability.
        canvas.drawRect(rect, outlinePaint);
      }
    }
    // Mirror line: horizontal between rows 2 and 3, extending half a cell
    // beyond each side so it crosses the grid border. The V form rotates the
    // whole widget, so this line renders vertically there.
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.15
      ..color = lineColor;
    final y = 2 * s;
    canvas.drawLine(
      Offset(-s / 2, y),
      Offset(size.width + s / 2, y),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant MirrorPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pattern != pattern;
  }
}
