import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';

class RowCountWidget extends StatelessWidget {
  const RowCountWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final RowCountConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final borderColor = constraint.borderColor(pc);
    final textColor =
        pc.constraintColors[constraint.color] ?? pc.constraintInvalid;
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : pc.mandatory;
    final fontSize = cellSize * cellSizeToFontSize * 0.6;
    final circleSize = cellSize * 0.7;

    return SizedBox(
      width: circleSize,
      height: cellSize,
      child: Center(
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(
              color: borderColor,
              width: constraint.borderWidth,
            ),
          ),
          child: Center(
            child: Text(
              constraint.count.toString(),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
