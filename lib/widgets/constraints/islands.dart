import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/islands.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Fixed 6×6 mini-grid island cells (row-major, 0–35), drawn in the
/// constraint colour over neutral-grey unfilled cells.
///
/// Single fixed pattern: island A (top-left L-triomino), island B
/// (top-right L-triomino), island C (centre domino) and island D (a
/// snaking hexomino along the bottom edge, rows `010010`/`011110`). Every
/// pair is separated by at least one full row/column of grey — the icon
/// itself demonstrates the diagonal-isolation rule, so it must never
/// corner-touch.
const _islandCells = {
  0, 1, 6, // A
  4, 5, 11, // B
  14, 15, // C
  25, 28, 31, 32, 33, 34, // D
};

class IslandsWidget extends StatelessWidget {
  const IslandsWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
    this.fgcolor,
  });

  final IslandsConstraint constraint;
  final double cellSize;
  final Color? fgcolor;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final borderColor = constraint.borderColor(pc);
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : pc.mandatory;

    final islandColor = shouldGrayOut
        ? pc.constraintGrayed
        : (constraint.isHighlighted
              ? pc.highlight
              : (fgcolor ??
                    pc.constraintColors[constraint.color] ??
                    pc.constraintInvalid));

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
        child: Padding(
          padding: EdgeInsets.all(cellSize * 0.08),
          child: CustomPaint(
            size: Size.fromRadius(cellSize * 0.42),
            painter: _IslandsMiniGridPainter(
              islandCells: _islandCells,
              color: islandColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _IslandsMiniGridPainter extends CustomPainter {
  _IslandsMiniGridPainter({required this.islandCells, required this.color});

  final Set<int> islandCells;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 6;
    final cellH = size.height / 6;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < 6; r++) {
      for (int c = 0; c < 6; c++) {
        final idx = r * 6 + c;
        final x = c * cellW;
        final y = r * cellH;
        final rect = Rect.fromLTWH(x, y, cellW, cellH);

        if (islandCells.contains(idx)) {
          fillPaint.color = color;
        } else {
          fillPaint.color = Colors.grey.withValues(alpha: 0.15);
        }
        canvas.drawRect(rect, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IslandsMiniGridPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.islandCells != islandCells;
  }
}
