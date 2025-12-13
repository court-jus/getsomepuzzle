import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constants.dart';

const textColors = {0: Colors.transparent, 1: Colors.black, 2: Colors.white};

class QuantityWidget extends StatelessWidget {
  // Constructor
  const QuantityWidget({
    super.key,
    required this.value,
    required this.count,
    required this.actualCount,
    required this.bgColor,
    required this.borderColor,
    required this.cellSize,
  });

  // Attributes
  final int value;
  final int count;
  final int actualCount;
  final Color bgColor;
  final Color borderColor;
  final double cellSize;

  // Build UI
  @override
  Widget build(BuildContext context) {
    final smallText = "$actualCount/";
    final largeText = count.toString();
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
            if (actualCount > 0)
              Positioned(
                top: 0,
                left: 8,
                child: Text(
                  smallText,
                  style: TextStyle(
                    fontSize: smallFontSize,
                    color: textColors[value],
                  ),
                ),
              ),
            Center(
              child: Text(
                largeText,
                style: TextStyle(
                  fontSize: largeFontSize,
                  color: textColors[value],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
