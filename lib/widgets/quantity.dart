import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';
import 'package:getsomepuzzle/widgets/motif.dart';

const textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

class QuantityWidget extends StatelessWidget {
  const QuantityWidget({
    super.key,
    required this.constraint,
    required this.actualCount,
    required this.cellSize,
  });

  final QuantityConstraint constraint;
  final int actualCount;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final borderColor = constraint.isHighlighted
        ? highlightColor
        : (constraint.isValid ? Colors.green : Colors.deepOrange);
    final smallText = "$actualCount/";
    final largeText = constraint.count.toString();
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final largeFontSize = cellSize * cellSizeToFontSize;
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
