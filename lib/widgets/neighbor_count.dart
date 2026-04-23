import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/neighbor_count.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';

class NeighborCountWidget extends StatelessWidget {
  const NeighborCountWidget({
    super.key,
    required this.constraint,
    required this.fgcolor,
    required this.cellSize,
  });

  final NeighborCountConstraint constraint;
  final Color fgcolor;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.transparent : Colors.deepOrange);
    final smallText = "${constraint.color}:";
    final largeText = constraint.count.toString();
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
