import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/cell.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';

final textColors = {
  CellValue.free: Colors.transparent,
  CellValue.black: Colors.black,
  CellValue.white: Colors.white,
  CellValue.purple: Colors.purple[100],
};

class GroupCountWidget extends StatelessWidget {
  const GroupCountWidget({
    super.key,
    required this.constraint,
    required this.actualGroupCount,
    required this.cellSize,
  });

  final GroupCountConstraint constraint;
  final int actualGroupCount;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange);
    final bool shouldGrayOut = constraint.isComplete;
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : mandatoryColor;
    final largeText = constraint.count.toString();
    final largeFontSize = cellSize * cellSizeToFontSize;
    final color = textColors[constraint.color];
    final compact = cellSize < 28;

    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          border: BoxBorder.all(color: borderColor, width: 2),
        ),
        child: Center(
          child: Text(
            largeText,
            style: TextStyle(fontSize: largeFontSize * 0.6, color: color),
          ),
        ),
      );
    }

    final smallText = "$actualGroupCount/";
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final iconSize = cellSize * 0.4;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(color: borderColor, width: 4),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (actualGroupCount > 0)
              Positioned(
                top: 0,
                left: 8,
                child: Text(
                  smallText,
                  style: TextStyle(fontSize: smallFontSize, color: color),
                ),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link, size: iconSize, color: color),
                  Text(
                    largeText,
                    style: TextStyle(
                      fontSize: largeFontSize * 0.6,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
