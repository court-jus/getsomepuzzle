import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/chain.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';

const _textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

/// Fixed 6×6 path cells for vertical (top→bottom) chain.
const _chainPathCells = {1, 7, 8, 14, 15, 21, 22, 28, 34};

/// Rotated 90° CW for horizontal (left→right) chain.
const _chainPathCellsHorizontal = {10, 11, 15, 16, 20, 21, 24, 25, 26};

class ChainWidget extends StatelessWidget {
  const ChainWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
    this.fgcolor,
  });

  final ChainConstraint constraint;
  final double cellSize;
  final Color? fgcolor;

  @override
  Widget build(BuildContext context) {
    final bool shouldGrayOut = constraint.isComplete && constraint.isValid;
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange);
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : mandatoryColor;

    final pathColor = shouldGrayOut
        ? Colors.grey
        : (constraint.isHighlighted
              ? highlightColor
              : (fgcolor ?? _textColors[constraint.color]!));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(color: borderColor, width: 4),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Padding(
          padding: EdgeInsets.all(cellSize * 0.08),
          child: CustomPaint(
            size: Size.fromRadius(cellSize * 0.42),
            painter: _ChainMiniGridPainter(
              pathCells:
                  (constraint.fromSide == 'left' ||
                      constraint.fromSide == 'right')
                  ? _chainPathCellsHorizontal
                  : _chainPathCells,
              color: pathColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChainMiniGridPainter extends CustomPainter {
  _ChainMiniGridPainter({required this.pathCells, required this.color});

  final Set<int> pathCells;
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

        if (pathCells.contains(idx)) {
          fillPaint.color = color;
        } else {
          fillPaint.color = Colors.grey.withValues(alpha: 0.15);
        }
        canvas.drawRect(rect, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChainMiniGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pathCells != pathCells;
  }
}
