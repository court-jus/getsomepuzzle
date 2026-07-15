import 'package:flutter/material.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/constants.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/quantity.dart';

class QuantityWidget extends StatelessWidget {
  const QuantityWidget({
    super.key,
    required this.constraint,
    required this.actualCount,
    required this.oppositeActual,
    required this.oppositeTotal,
    required this.cellSize,
    this.domainLength = 2,
  });

  final QuantityConstraint constraint;
  final int actualCount;
  final int oppositeActual;
  final int oppositeTotal;
  final double cellSize;
  final int domainLength;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final shouldGrayOut = constraint.isGrayedOut;
    final borderColor = constraint.borderColor(pc);
    final bgColor = shouldGrayOut
        ? Colors.grey.withValues(alpha: 0.3)
        : pc.mandatory;
    final smallText = "$actualCount/";
    final largeText = constraint.count.toString();
    final oppositeText = "$oppositeActual/$oppositeTotal";
    final smallFontSize = cellSize * cellSizeToFontSize / 3.5;
    final largeFontSize = cellSize * cellSizeToFontSize;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: BoxBorder.all(
          color: borderColor,
          width: constraint.borderWidth,
        ),
      ),
      child: SizedBox(
        width: cellSize,
        height: cellSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (domainLength == 2)
              Positioned(
                bottom: 0,
                left: 8,
                child: Text(
                  oppositeText,
                  style: TextStyle(
                    fontSize: smallFontSize,
                    color:
                        pc.oppositeColors[constraint.color] ??
                        pc.constraintInvalid,
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
                    color:
                        pc.constraintColors[constraint.color] ??
                        pc.constraintInvalid,
                  ),
                ),
              ),
            Center(
              child: Text(
                largeText,
                style: TextStyle(
                  fontSize: largeFontSize,
                  color:
                      pc.constraintColors[constraint.color] ??
                      pc.constraintInvalid,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
