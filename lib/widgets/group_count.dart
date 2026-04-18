import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';

const textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

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
    final smallText = "$actualGroupCount/";
    final largeText = constraint.count.toString();
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final largeFontSize = cellSize * cellSizeToFontSize;
    final iconSize = cellSize * 0.4;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mandatoryColor,
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
                  style: TextStyle(
                    fontSize: smallFontSize,
                    color: textColors[constraint.color],
                  ),
                ),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.link,
                    size: iconSize,
                    color: textColors[constraint.color],
                  ),
                  Text(
                    largeText,
                    style: TextStyle(
                      fontSize: largeFontSize * 0.6,
                      color: textColors[constraint.color],
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
