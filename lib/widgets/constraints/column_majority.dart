import 'package:flutter/material.dart';
import 'package:getsomepuzzle/getsomepuzzle/constraints/base_line_constraint.dart';
import 'package:getsomepuzzle/widgets/constraints/base.dart';
import 'package:getsomepuzzle/getsomepuzzle/model/app_theme.dart';

/// Renders concentric circles for a column or row majority constraint.
/// Outer circle = most present colour, inner circles = less present colours.
class MajorityIndicatorWidget extends StatelessWidget {
  const MajorityIndicatorWidget({
    super.key,
    required this.constraint,
    required this.cellSize,
  });

  final JRCConstraint constraint;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final pc = Theme.of(context).extension<PuzzleColors>()!;
    final circleSize = cellSize * 0.7;

    return SizedBox(
      width: circleSize,
      height: cellSize,
      child: Center(
        child: SizedBox(
          width: circleSize,
          height: circleSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 1; i <= constraint.colorOrder.length; i++)
                _ring(circleSize, i, pc, constraint),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _ring(
  double circleSize,
  int i,
  PuzzleColors pc,
  JRCConstraint constraint,
) {
  final ringSize =
      circleSize * (1.0 - (1 / constraint.colorOrder.length) * (i - 1));
  final value = constraint.colorOrder[i - 1];
  final color = pc.constraintColors[value] ?? pc.constraintInvalid;
  final opposite = pc.oppositeColors[value] ?? pc.constraintInvalid;
  return Container(
    width: ringSize,
    height: ringSize,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: constraint.isGrayedOut ? color.withValues(alpha: 0.3) : color,
      border: Border.all(
        color: constraint.isGrayedOut
            ? opposite.withValues(alpha: 0.3)
            : opposite,
        width: constraint.borderWidth,
      ),
    ),
  );
}
