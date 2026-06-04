import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/row_count.dart';

const _textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

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
    final bool shouldGrayOut = constraint.isComplete;
    final borderColor = shouldGrayOut
        ? Colors.grey
        : (constraint.isHighlighted
              ? highlightColor
              : (constraint.isValid ? Colors.grey : Colors.redAccent));
    final textColor = _textColors[constraint.color] ?? Colors.black;
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : mandatoryColor;
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
            border: Border.all(color: borderColor, width: 2),
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
