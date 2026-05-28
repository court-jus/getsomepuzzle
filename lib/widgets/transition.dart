import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';

class TransitionWidget extends StatelessWidget {
  const TransitionWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final LineCentricConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final bool shouldGrayOut = constraint.isComplete;
    final borderColor = shouldGrayOut
        ? Colors.grey
        : (constraint.isHighlighted
              ? highlightColor
              : (constraint.isValid ? Colors.grey : Colors.redAccent));
    final textColor = shouldGrayOut ? Colors.grey : Colors.black;
    final fontSize = cellSize * cellSizeToFontSize * 0.6;
    final squareSize = cellSize * 0.7;

    return SizedBox(
      width: squareSize,
      height: cellSize,
      child: Center(
        child: Container(
          width: squareSize,
          height: squareSize,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Center(
            child: Text(
              '~${constraint.count}',
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
