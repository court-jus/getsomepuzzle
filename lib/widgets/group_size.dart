import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/groups.dart';

class GroupSizeWidget extends StatelessWidget {
  const GroupSizeWidget({
    super.key,
    required this.constraint,
    required this.actualGroupSize,
    required this.fgcolor,
    required this.cellSize,
  });

  final GroupSize constraint;
  final int actualGroupSize;
  final Color fgcolor;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.transparent : Colors.deepOrange);
    final smallText = "$actualGroupSize/";
    final largeText = constraint.size.toString();
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final largeFontSize = cellSize * cellSizeToFontSize;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: BoxBorder.all(color: borderColor, width: 4),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (actualGroupSize > 0)
              Positioned(
                top: 0,
                left: 8,
                child: Text(
                  smallText,
                  style: TextStyle(fontSize: smallFontSize, color: fgcolor),
                ),
              ),
            Center(
              child: Text(
                largeText,
                style: TextStyle(fontSize: largeFontSize, color: fgcolor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
