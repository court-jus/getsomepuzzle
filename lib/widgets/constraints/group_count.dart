import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/group_count.dart';

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
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final borderColor = constraint.borderColor(pc);
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : pc.mandatory;
    final largeText = constraint.count.toString();
    final largeFontSize = cellSize * cellSizeToFontSize;
    final color = pc.constraintColors[constraint.color] ?? pc.constraintInvalid;
    final compact = cellSize < 28;

    final borderWidth = constraint.borderWidth;
    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          border: BoxBorder.all(color: borderColor, width: borderWidth),
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
        border: BoxBorder.all(color: borderColor, width: borderWidth),
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
