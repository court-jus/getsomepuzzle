import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';

const textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};
const oppositeColors = {
  0: Colors.transparent,
  1: Colors.white,
  2: Colors.black,
};

class QuantityWidget extends StatelessWidget {
  const QuantityWidget({
    super.key,
    required this.constraint,
    required this.actualCount,
    required this.oppositeActual,
    required this.oppositeTotal,
    required this.cellSize,
  });

  final QuantityConstraint constraint;
  final int actualCount;
  final int oppositeActual;
  final int oppositeTotal;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final bool shouldGrayOut = constraint.isComplete;
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange);
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : mandatoryColor;
    final smallText = "$actualCount/";
    final largeText = constraint.count.toString();
    final oppositeText = "$oppositeActual/$oppositeTotal";
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final largeFontSize = cellSize * cellSizeToFontSize;
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
            Positioned(
              bottom: 0,
              left: 8,
              child: Text(
                oppositeText,
                style: TextStyle(
                  fontSize: smallFontSize,
                  color: oppositeColors[constraint.value],
                ),
              ),
            ),
            if (actualCount > 0)
              Positioned(
                top: 0,
                left: 8,
                child: Text(
                  smallText,
                  style: TextStyle(
                    fontSize: smallFontSize,
                    color: textColors[constraint.value],
                  ),
                ),
              ),
            Center(
              child: Text(
                largeText,
                style: TextStyle(
                  fontSize: largeFontSize,
                  color: textColors[constraint.value],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
