import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/column_count.dart';

const _textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

class ColumnCountWidget extends StatelessWidget {
  const ColumnCountWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final ColumnCountConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final bool shouldGrayOut = constraint.isComplete;
    final borderColor = shouldGrayOut
        ? Colors.grey
        : (constraint.isHighlighted
              ? highlightColor
              : (constraint.isValid ? Colors.grey : Colors.redAccent));
    final textColor = shouldGrayOut
        ? Colors.grey
        : (_textColors[constraint.color] ?? Colors.black);
    final fontSize = cellSize * cellSizeToFontSize * 0.6;
    final circleSize = cellSize * 0.7;

    return SizedBox(
      width: cellSize,
      height: circleSize,
      child: Center(
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
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
